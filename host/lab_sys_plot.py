#!/usr/bin/env python3
"""lab_sys 示波：样点时间轴（非主机 RX 墙钟）。

时间轴 t = 绝对样点下标 / fs（µs），不是窗内相对 0..xlen：
  - Live：历史摊平后右对齐取 xlen
  - Pause：a/d 以 ±1/4 帧（样点数）细移；红线 = 帧界绝对位置，随窗移动

按 e =「相位密度图」：
  多帧峰值对齐后，按一个周期折叠，画 (相位 × 样点值) 出现次数热力图。
  亮带细 = 对齐后各帧差不多；亮带胖/散 = 帧间差得大。

禁止用 host RX 的 ~20ms 间隙当「连续时间」。
"""

from __future__ import annotations

import argparse
import collections
import math
import sys
import threading
import time
from typing import Any

try:
    import serial
except ImportError:
    print("need: pip install pyserial", file=sys.stderr)
    sys.exit(1)

import matplotlib.pyplot as plt
import matplotlib.animation as animation
from matplotlib import font_manager


def _setup_chinese_font() -> str | None:
    """macOS/常见中文字体；解决标题方框（tofu）。"""
    prefer = (
        "Songti SC",
        "Hiragino Sans GB",
        "STHeiti",
        "Heiti TC",
        "Arial Unicode MS",
        "PingFang SC",
        "Noto Sans CJK SC",
    )
    available = {f.name for f in font_manager.fontManager.ttflist}
    chosen = None
    for name in prefer:
        if name in available:
            chosen = name
            break
    if chosen is None:
        for f in font_manager.fontManager.ttflist:
            n = f.name
            if any(k in n for k in ("Song", "Hei", "CJK", "PingFang", "Hiragino")):
                chosen = n
                break
    if chosen:
        plt.rcParams["font.sans-serif"] = [chosen, "DejaVu Sans"]
        plt.rcParams["font.family"] = "sans-serif"
        plt.rcParams["axes.unicode_minus"] = False
    return chosen


_CJK_FONT = _setup_chinese_font()

from uart_wave_plot import list_serial_ports, open_serial, pick_default_port

SYNC0, SYNC1 = 0xAA, 0x55
XLEN_PRESETS = {
    ord("1"): 64,
    ord("2"): 128,
    ord("3"): 256,
    ord("4"): 512,
    ord("5"): 1024,
    ord("6"): 2048,
}
XLEN_MIN, XLEN_MAX = 32, 8192
HIST_MAX = 512
DEFAULT_FS = 1_000_000.0


def clamp_xlen(n: int) -> int:
    return max(XLEN_MIN, min(XLEN_MAX, int(n)))


def nonzero_prefix_len(ys: list[int]) -> int:
    if not ys:
        return 0
    i = len(ys)
    while i > 0 and ys[i - 1] == 0:
        i -= 1
    return i


def estimate_wave_hz(ys: list[int], fs: float) -> float | None:
    if fs <= 0 or len(ys) < 16:
        return None
    n = nonzero_prefix_len(ys)
    if n < 16:
        n = len(ys)
    xs = ys[:n]
    peaks: list[int] = []
    for i in range(1, len(xs) - 1):
        if xs[i] >= 240 and xs[i] >= xs[i - 1] and xs[i] >= xs[i + 1]:
            if not peaks or i - peaks[-1] >= 8:
                peaks.append(i)
    if len(peaks) >= 2:
        period = (peaks[-1] - peaks[0]) / (len(peaks) - 1)
        if period > 1:
            return fs / period
    return None


def frame_corr(a: list[int], b: list[int]) -> float:
    """相邻快照样点相同比例。"""
    if not a or not b:
        return 0.0
    n = min(len(a), len(b))
    if n <= 0:
        return 0.0
    return sum(1 for i in range(n) if a[i] == b[i]) / n


def estimate_period_samp(ys: list[int], default: int = 64) -> int:
    """从峰间距估周期（样点数）；失败则 default（sine_gen LUT=64）。"""
    if len(ys) < 16:
        return default
    peaks: list[int] = []
    for i in range(1, len(ys) - 1):
        if ys[i] >= 240 and ys[i] >= ys[i - 1] and ys[i] >= ys[i + 1]:
            if not peaks or i - peaks[-1] >= 8:
                peaks.append(i)
    if len(peaks) >= 2:
        period = int(round((peaks[-1] - peaks[0]) / (len(peaks) - 1)))
        if 16 <= period <= 256:
            return period
    return default


def align_to_peak(ys: list[int], period: int) -> list[int]:
    """把本帧最大值旋到下标 0，消掉每帧起始相位随机。"""
    if not ys or period <= 0:
        return list(ys)
    search_n = min(len(ys), max(period * 2, period + 1))
    pk = max(range(search_n), key=lambda i: ys[i])
    return ys[pk:] + ys[:pk]


def build_phase_density(
    frames: list[dict[str, Any]],
    period: int,
    auto_crop: bool,
    mode_filter: int | None,
    max_frames: int = 128,
) -> tuple[list[list[int]], int, float, list[float], list[float]]:
    """多帧峰值对齐后的 (相位 × 样点值) 出现次数 —— 密度热力图。

    横轴=一个周期内相位（峰值旋到 0）；纵轴=样点 0..255；颜色越亮出现越多。
    亮带细、贴均值线 → 帧间接近；亮带胖 → 帧间差大。
    mode_filter: None=全部, 0=慢SYS, 1=快PLL
    """
    period = max(8, int(period))
    dens = [[0 for _ in range(256)] for _ in range(period)]
    n_used = 0
    cols: list[list[int]] = [[] for _ in range(period)]

    for fr in frames[-max_frames:]:
        fast = int(fr.get("fast", 0))
        if mode_filter is not None and fast != mode_filter:
            continue
        ys = prep_frame_ys(list(fr.get("samples") or []), auto_crop)
        if len(ys) < period // 2:
            continue
        aligned = align_to_peak(ys, period)
        # 只用对齐后的第一个周期，避免同一帧后半再折回去加重某一相位
        one = aligned[:period]
        n_used += 1
        for ph, v in enumerate(one):
            vi = 0 if v < 0 else (255 if v > 255 else int(v))
            dens[ph][vi] += 1
            if len(cols[ph]) < 512:
                cols[ph].append(vi)

    means: list[float] = []
    stds: list[float] = []
    rms_acc = 0.0
    rms_n = 0
    for col in dens:
        total = sum(col)
        if total <= 0:
            means.append(float("nan"))
            stds.append(float("nan"))
            continue
        m = sum(i * c for i, c in enumerate(col)) / total
        var = sum(c * (i - m) ** 2 for i, c in enumerate(col)) / total
        s = var**0.5
        means.append(m)
        stds.append(s)
        rms_acc += s
        rms_n += 1
    rms = rms_acc / rms_n if rms_n else 0.0
    return dens, n_used, rms, means, stds


def prep_frame_ys(samples: list[int], auto_crop: bool) -> list[int]:
    ys = list(samples)
    if auto_crop:
        pref = nonzero_prefix_len(ys)
        if 8 <= pref < len(ys):
            ys = ys[:pref]
    return ys


def flatten_frames(
    frames: list[dict[str, Any]],
    auto_crop: bool,
) -> tuple[list[int], list[int], list[int]]:
    """摊成连续样点带。

    返回 (flat_ys, boundary_indices, seq_at_sample)
    boundary_indices：帧分界在 flat 中的下标（竖线位置）
    """
    flat: list[int] = []
    bounds: list[int] = []
    seqs: list[int] = []
    for fi, fr in enumerate(frames):
        if fi > 0 and flat:
            bounds.append(len(flat))
        part = prep_frame_ys(fr["samples"], auto_crop)
        seq = int(fr.get("seq", 0))
        for v in part:
            flat.append(int(v))
            seqs.append(seq)
    return flat, bounds, seqs


def window_at_offset(
    flat: list[int],
    bounds: list[int],
    offset: int,
    xlen: int,
    fs: float,
) -> tuple[list[float], list[float], list[float], int]:
    """从样点 offset 起取 xlen 点。

    时间轴用绝对样点下标（µs），这样左右细移时红线会跟着数据一起平移，
    而不是永远钉在相对窗的 128/256/… 上。

    返回 (ts, ys, boundary_t_us, used_offset)
    """
    if not flat or xlen <= 0:
        return [], [], [], 0
    off = max(0, min(int(offset), max(0, len(flat) - 1)))
    chunk = flat[off : off + xlen]
    dt = 1e6 / fs
    ts = [(off + i) * dt for i in range(len(chunk))]
    ys = [float(v) for v in chunk]
    # 含右缘：窗刚好停在帧界时也画竖线
    bt = [b * dt for b in bounds if off < b <= off + len(chunk)]
    return ts, ys, bt, off


def build_view(
    frames: list[dict[str, Any]],
    end_i: int,
    xlen: int,
    fs: float,
    auto_crop: bool,
    sample_offset: int | None = None,
) -> tuple[list[float], list[float], int, str, list[float], int]:
    """构造显示窗。

    sample_offset 非空：整条历史摊平后从该样点起取 xlen（左右键细移）。
    否则：以 end_i 为右端取最近若干帧（Live 默认）。
    返回 (ts, ys, n_frames_touched, note, bounds_t, offset_used)
    """
    if not frames:
        return [], [], 0, "", [], 0

    flat, bounds, seqs = flatten_frames(frames, auto_crop)
    if not flat:
        return [], [], 0, "", [], 0

    if sample_offset is not None:
        ts, ys, bt, off = window_at_offset(flat, bounds, sample_offset, xlen, fs)
        # 窗口内涉及多少不同 seq
        seq_set = set(seqs[off : off + len(ys)]) if ys else set()
        note = f"off={off}/{len(flat)}"
        return ts, ys, max(1, len(seq_set)), note, bt, off

    # Live：右对齐到 end_i 帧末尾
    end_i = max(0, min(end_i, len(frames) - 1))
    # 计算 end_i 帧在 flat 中的结束下标
    pos = 0
    end_pos = len(flat)
    for fi, fr in enumerate(frames):
        part = prep_frame_ys(fr["samples"], auto_crop)
        nxt = pos + len(part)
        if fi == end_i:
            end_pos = nxt
            break
        pos = nxt
    off = max(0, end_pos - xlen)
    ts, ys, bt, off = window_at_offset(flat, bounds, off, xlen, fs)
    seq_set = set(seqs[off : off + len(ys)]) if ys else set()
    note = "1-snap" if len(seq_set) <= 1 else f"{len(seq_set)}-strip"
    return ts, ys, max(1, len(seq_set)), note, bt, off


def pick_lab_sys_port() -> str | None:
    from serial.tools import list_ports

    cands: list[str] = []
    for p in list_ports.comports():
        d = p.device.lower()
        if "bluetooth" in d or "bose" in d or "redmi" in d or "debug-console" in d:
            continue
        if "usbserial" in d or "wch" in d or "usbmodem" in d:
            cands.append(p.device)
    if not cands:
        return pick_default_port()
    for pref in ("131", "uart"):
        for c in cands:
            if pref in c.lower():
                return c
    if len(cands) == 1:
        return cands[0]
    print("multiple serial ports — pass -p explicitly:", flush=True)
    for c in cands:
        print(f"  {c}", flush=True)
    return None


class LabSysParser:
    def __init__(self, hist_max: int = HIST_MAX) -> None:
        self.buf = bytearray()
        self.ok = 0
        self.bad = 0
        self.raw_bytes = 0
        self.last_err = 0
        self.last_fast = 0
        self.err_frames = 0
        self.lock = threading.Lock()
        self.samples: collections.deque[int] = collections.deque(maxlen=4096)
        self.last_n = 0
        self.last_seq = 0
        self.history: collections.deque[dict[str, Any]] = collections.deque(maxlen=hist_max)
        self._fps_t0 = time.time()
        self._fps_ok0 = 0
        self.frame_hz = 0.0

    def feed(self, data: bytes) -> None:
        if not data:
            return
        self.raw_bytes += len(data)
        self.buf.extend(data)
        while True:
            if len(self.buf) < 2:
                return
            i = 0
            while i + 1 < len(self.buf):
                if self.buf[i] == SYNC0 and self.buf[i + 1] == SYNC1:
                    break
                i += 1
            else:
                self.buf[:] = self.buf[-1:]
                return
            if i:
                del self.buf[:i]
            if len(self.buf) < 5:
                return
            seq = self.buf[2]
            n = self.buf[3]
            err_raw = self.buf[4]
            fast = (err_raw >> 7) & 1
            err = err_raw & 0x7F
            need = 5 + n + 1
            if len(self.buf) < need:
                return
            payload = self.buf[2 : 5 + n]
            xor_rx = self.buf[5 + n]
            xor_calc = 0
            for b in payload:
                xor_calc ^= b
            del self.buf[:need]
            if xor_calc != xor_rx:
                self.bad += 1
                if self.bad <= 3:
                    print(
                        f"[bad_xor #{self.bad}] n={n} err_raw=0x{err_raw:02x} "
                        f"calc=0x{xor_calc:02x} rx=0x{xor_rx:02x}",
                        flush=True,
                    )
                continue
            # 忽略过短帧（旧 beacon N=1）；正常 core 为 N=128
            if n < 8:
                continue
            data_pts = list(payload[3:])
            self.ok += 1
            self.last_err = err
            self.last_fast = fast
            self.last_n = n
            self.last_seq = seq
            if err:
                self.err_frames += 1
            now = time.time()
            dt = now - self._fps_t0
            if dt >= 0.5:
                self.frame_hz = (self.ok - self._fps_ok0) / dt
                self._fps_t0 = now
                self._fps_ok0 = self.ok
            with self.lock:
                self.history.append(
                    {
                        "seq": seq,
                        "n": n,
                        "err": err,
                        "fast": fast,
                        "samples": data_pts,
                    }
                )
                self.samples = collections.deque(data_pts, maxlen=max(4096, n))


def reader_loop(ser: serial.Serial, parser: LabSysParser, stop: threading.Event) -> None:
    while not stop.is_set():
        try:
            n = ser.in_waiting
            if n:
                parser.feed(ser.read(n))
            else:
                time.sleep(0.005)
        except serial.SerialException as e:
            print(f"serial read fail: {e}", file=sys.stderr)
            stop.set()
            return


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", "-p")
    ap.add_argument("--baud", "-b", type=int, default=115200)
    ap.add_argument("--xlen", "-x", type=int, default=128)
    ap.add_argument("--hist", type=int, default=HIST_MAX)
    ap.add_argument("--fs", type=float, default=DEFAULT_FS)
    ap.add_argument(
        "--warmup",
        action="store_true",
        help="open/close/open once (旧 CH340 癖好；默认关闭，以免 exclusive 抢口后空读)",
    )
    ap.add_argument("--list", action="store_true")
    ap.add_argument(
        "--no-crop",
        action="store_true",
        help="do not auto-crop trailing zeros (half-frame PLL)",
    )
    args = ap.parse_args()

    if args.list:
        list_serial_ports()
        return
    port = args.port or pick_lab_sys_port()
    if not port:
        print("need --port")
        list_serial_ports()
        sys.exit(1)

    xlen0 = clamp_xlen(args.xlen)
    state = {"xlen": xlen0, "auto_crop": not args.no_crop}

    print(f"open {port} @ {args.baud}  fs={args.fs:g} Hz", flush=True)
    if _CJK_FONT:
        print(f"matplotlib 中文字体: {_CJK_FONT}", flush=True)
    else:
        print("警告: 未找到中文字体，标题可能显示为方框", flush=True)
    print(
        "X=time(µs) by sample index. xlen≤N: one snap. xlen>N: strip of snaps (NaN breaks).",
        flush=True,
    )
    print(
        "NOTE: each UART frame is an independent SPI capture — PLL noise frames "
        "are NOT continuous in time; a/d jumps look unrelated by design.",
        flush=True,
    )
    print(
        "按键: p 暂停 | a/d ±¼帧 | ,/. ±1帧 | l live | e 相位密度 | [ ] xlen | c crop",
        flush=True,
    )
    print(
        "e=相位密度：多帧峰值对齐后画 (相位×数值) 出现次数。"
        "亮带细=帧间接近；胖/散=差得大。",
        flush=True,
    )

    def _open(port: str, baud: int) -> serial.Serial:
        # 不用 exclusive：macOS 上易与其它工具互斥成「打得开但读 0 / Operation not permitted」
        try:
            return serial.Serial(
                port, baud, timeout=0.05, dsrdtr=False, rtscts=False
            )
        except TypeError:
            return open_serial(port, baud)
        except serial.SerialException as e:
            print(f"无法打开 {port}: {e}", file=sys.stderr)
            sys.exit(1)

    if args.warmup:
        print("serial warm-up (open/close/open)…", flush=True)
        ser = _open(port, args.baud)
        try:
            ser.reset_input_buffer()
        except Exception:
            pass
        time.sleep(0.25)
        try:
            _ = ser.read(ser.in_waiting or 0)
        except Exception:
            pass
        ser.close()
        time.sleep(0.15)

    ser = _open(port, args.baud)
    try:
        ser.reset_input_buffer()
    except Exception:
        pass
    time.sleep(0.05)
    t_open = time.time()
    first_ok_logged = {"done": False}
    wait_note_t = {"t": t_open}

    parser = LabSysParser(hist_max=max(32, args.hist))
    # 开图前先同步收 1.2s，立刻告诉你 FPGA 有没有在发（避免空窗干等）
    t_probe = time.time()
    while time.time() - t_probe < 1.2:
        try:
            n = ser.in_waiting
            if n:
                parser.feed(ser.read(n))
            else:
                time.sleep(0.005)
        except serial.SerialException as e:
            print(f"serial read fail during probe: {e}", file=sys.stderr)
            ser.close()
            sys.exit(1)
    print(
        f"[probe] 1.2s → raw={parser.raw_bytes}B  ok={parser.ok}  bad_xor={parser.bad}  "
        f"port={port}",
        flush=True,
    )
    if parser.ok == 0:
        print(
            "[probe] 无合法帧。确认 -p 用 …131（…130 是空的）；"
            "关掉其它 py；按 KEY1；看终端 raw 是否也为 0。",
            flush=True,
        )
    else:
        fr = parser.history[-1]
        ys = fr["samples"]
        print(
            f"[probe] seq={fr['seq']} mode={'PLL' if fr['fast'] else 'SYS'} "
            f"spi_err={fr['err']} samples={len(ys)} min={min(ys)} max={max(ys)}",
            flush=True,
        )

    stop = threading.Event()
    th = threading.Thread(target=reader_loop, args=(ser, parser, stop), daemon=True)
    th.start()

    ui: dict[str, Any] = {
        "paused": False,
        "view_i": 0,
        "freeze": [],
        "samp_off": 0,  # 冻结带上的样点偏移（可非整数帧）
        "step_samp": 32,  # 默认 ±1/4·128
        # 相位密度: 0=关, 1=全部, 2=仅慢SYS, 3=仅快PLL
        "eye_mode": 0,
        "eye_period": 64,
    }
    boundary_artists: list[Any] = []

    fig, ax = plt.subplots(figsize=(9, 5))
    (line,) = ax.plot([], [], lw=1.2, color="#1f77b4", zorder=2)
    (dens_mean,) = ax.plot([], [], lw=1.5, color="#f0f0f0", zorder=4, alpha=0.95)
    (dens_hi,) = ax.plot([], [], lw=0.8, color="#cccccc", ls="--", zorder=4, alpha=0.75)
    (dens_lo,) = ax.plot([], [], lw=0.8, color="#cccccc", ls="--", zorder=4, alpha=0.75)
    dens_im = ax.imshow(
        [[0]],
        origin="lower",
        aspect="auto",
        extent=[0, 64, 0, 255],
        cmap="inferno",
        interpolation="nearest",
        zorder=1,
        visible=False,
        vmin=0,
        vmax=1,
    )
    ax.set_ylim(-5, 260)
    ax.set_xlabel(f"time (µs)  ·  样点下标  ·  fs={args.fs:g} Hz")
    ax.set_ylabel("样点值")
    ax.set_title("lab_sys  ·  红线 = UART 帧界")
    ax.grid(True, alpha=0.25)
    # 状态放左上；标签放左下，避免与右上红字重叠
    status = ax.text(0.02, 0.98, "", transform=ax.transAxes, va="top", ha="left", zorder=5, fontsize=9)
    frame_tag = ax.text(
        0.02,
        0.02,
        "",
        transform=ax.transAxes,
        va="bottom",
        ha="left",
        fontsize=11,
        color="#b00020",
        fontweight="bold",
        zorder=5,
    )

    def clear_boundaries() -> None:
        while boundary_artists:
            art = boundary_artists.pop()
            try:
                art.remove()
            except Exception:
                pass

    def set_density_mode(on: bool) -> None:
        dens_im.set_visible(on)
        dens_mean.set_visible(on)
        dens_hi.set_visible(on)
        dens_lo.set_visible(on)
        line.set_visible(not on)

    def cycle_eye() -> None:
        ui["eye_mode"] = (int(ui["eye_mode"]) + 1) % 4
        names = ["关", "全部密度", "仅慢(SYS)", "仅快(PLL)"]
        print(f"[相位密度] {names[ui['eye_mode']]}", flush=True)

    def draw_boundaries(bounds: list[float]) -> None:
        clear_boundaries()
        for t in bounds:
            art = ax.axvline(
                t,
                color="#d62728",
                lw=1.8,
                ls="-",
                alpha=0.95,
                zorder=3,
            )
            boundary_artists.append(art)

    def dt_us() -> float:
        return 1e6 / float(args.fs)

    def snapshot() -> list[dict[str, Any]]:
        with parser.lock:
            return [
                {
                    "seq": fr["seq"],
                    "n": fr["n"],
                    "err": fr["err"],
                    "fast": fr["fast"],
                    "samples": list(fr["samples"]),
                }
                for fr in parser.history
            ]

    def enter_pause() -> None:
        snap = snapshot()
        if not snap:
            print("[Pause] ignored — no frames yet (wait for first UART)", flush=True)
            return
        ui["freeze"] = snap
        ui["paused"] = True
        ui["view_i"] = max(0, len(ui["freeze"]) - 1)
        auto = bool(state.get("auto_crop", True))
        flat, _b, _s = flatten_frames(ui["freeze"], auto)
        ui["samp_off"] = max(0, len(flat) - state["xlen"])
        n_frame = max(int(ui["freeze"][-1].get("n") or 128), 1)
        ui["step_samp"] = max(1, n_frame // 4)
        print(
            f"[Pause] {len(ui['freeze'])} snaps, {len(flat)} samples — "
            f"a/d ±{ui['step_samp']} samp (1/4 fr), ,/. ±1 fr",
            flush=True,
        )

    def toggle_pause() -> None:
        if ui["paused"]:
            ui["paused"] = False
            ui["freeze"] = []
            print("[Live]", flush=True)
        else:
            enter_pause()

    def scrub_samples(delta: int) -> None:
        if not ui["paused"] or not ui["freeze"]:
            enter_pause()
        auto = bool(state.get("auto_crop", True))
        flat, _b, seqs = flatten_frames(ui["freeze"], auto)
        if not flat:
            print("[Scrub] empty", flush=True)
            return
        max_off = max(0, len(flat) - 1)
        ui["samp_off"] = max(0, min(max_off, int(ui["samp_off"]) + int(delta)))
        # 同步 view_i 到窗口中心所在帧（便于状态显示）
        mid = min(ui["samp_off"] + state["xlen"] // 2, len(seqs) - 1)
        # 找 seq 对应的 frame index
        want = seqs[mid]
        for i, fr in enumerate(ui["freeze"]):
            if fr["seq"] == want:
                ui["view_i"] = i
                break
        fr = ui["freeze"][ui["view_i"]]
        mode = "PLL" if fr["fast"] else "SYS"
        print(
            f"[Scrub] off={ui['samp_off']}/{len(flat)} "
            f"(Δ{delta:+d}) seq≈{fr['seq']} err={fr['err']} {mode}",
            flush=True,
        )
        try:
            fig.canvas.draw_idle()
        except Exception:
            pass

    def scrub_frames(delta_fr: int) -> None:
        n_frame = 128
        if ui.get("freeze"):
            n_frame = max(int(ui["freeze"][ui["view_i"]].get("n") or 128), 1)
        scrub_samples(int(delta_fr) * n_frame)

    def apply_xlen(n: int) -> None:
        state["xlen"] = clamp_xlen(n)
        nfr = max(1, (state["xlen"] + 127) // 128)
        print(
            f"[xlen]={state['xlen']} ≈ {nfr} frames wide "
            f"(~{state['xlen'] * dt_us():.0f} µs); a/d still ±1/4 frame",
            flush=True,
        )

    def on_key(event) -> None:
        key = (event.key or "").lower()
        if key in (" ", "space", "p"):
            toggle_pause()
        elif key in ("left", "a"):
            scrub_samples(-int(ui.get("step_samp") or 32))
        elif key in ("right", "d"):
            scrub_samples(int(ui.get("step_samp") or 32))
        elif key in (",",):
            scrub_frames(-1)
        elif key in (".",):
            scrub_frames(1)
        elif key in ("l",):
            ui["paused"] = False
            ui["freeze"] = []
            print("[Live]", flush=True)
        elif key in ("c",):
            state["auto_crop"] = not state["auto_crop"]
            print(f"[auto-crop] {'on' if state['auto_crop'] else 'off'}", flush=True)
        elif key in ("e",):
            cycle_eye()
        elif key in ("[", "-"):
            apply_xlen(state["xlen"] // 2)
        elif key in ("]", "=", "+"):
            apply_xlen(state["xlen"] * 2)
        elif key == "r":
            state["xlen"] = xlen0
            state["auto_crop"] = not args.no_crop
            print(f"[reset] xlen={xlen0}", flush=True)
        elif len(key) == 1 and ord(key) in XLEN_PRESETS:
            apply_xlen(XLEN_PRESETS[ord(key)])

    fig.canvas.mpl_connect("key_press_event", on_key)

    def update(_frame):
        with parser.lock:
            hist = [
                {
                    "seq": fr["seq"],
                    "n": fr["n"],
                    "err": fr["err"],
                    "fast": fr["fast"],
                    "samples": list(fr["samples"]),
                }
                for fr in parser.history
            ]
            live_err = parser.last_err
            live_fast = parser.last_fast
            live_n = parser.last_n
            live_seq = parser.last_seq
            ok = parser.ok
            bad = parser.bad
            err_frames = parser.err_frames
            frame_hz = parser.frame_hz
            raw_bytes = parser.raw_bytes

        if ok > 0 and not first_ok_logged["done"]:
            first_ok_logged["done"] = True
            print(
                f"[first frame] after {(time.time() - t_open)*1000:.0f} ms  "
                f"N={live_n} mode={'PLL' if live_fast else 'SYS'} err={live_err}",
                flush=True,
            )
        elif ok == 0 and (time.time() - wait_note_t["t"]) >= 2.0:
            wait_note_t["t"] = time.time()
            print(
                f"[wait] {(time.time()-t_open):.1f}s  raw={raw_bytes}B  "
                f"bad_xor={bad}  (raw=0=FPGA未发：按KEY1复位，看LED3=PLL lock，关其它占串口的py)",
                flush=True,
            )

        auto = bool(state.get("auto_crop", True))
        win = state["xlen"]
        eye_m = int(ui.get("eye_mode") or 0)

        if ui["paused"] and ui["freeze"]:
            src = ui["freeze"]
            i = max(0, min(len(src) - 1, ui["view_i"]))
            fr = src[i]
            view_err, view_n, seq = fr["err"], fr["n"], fr["seq"]
            mode = "PLL" if fr["fast"] else "SYS"
            corr = 0.0
            if i > 0:
                corr = frame_corr(src[i - 1]["samples"], fr["samples"])
            tag = (
                f" PAUSED off={ui.get('samp_off', 0)} seq≈{seq} mode={mode} "
                f"corr={corr:.2f}"
            )
            eye_src = src
        elif hist:
            src = hist
            i = len(hist) - 1
            fr = hist[i]
            view_err, view_n, seq = live_err, live_n, live_seq
            mode = "PLL" if live_fast else "SYS"
            corr = frame_corr(hist[i - 1]["samples"], fr["samples"]) if i > 0 else 0.0
            tag = f" LIVE seq={seq} mode={mode} corr={corr:.2f}"
            eye_src = hist
        else:
            src = []
            fr = {}
            view_err, view_n, seq = 0, 0, 0
            mode = "?"
            corr = 0.0
            tag = ""
            eye_src = []
            i = 0

        expect = args.fs / 64.0
        t0, tmax = 0.0, max(win * dt_us(), dt_us())
        nfr, note, bounds, off = 0, "", [], 0
        f_txt = "wave=?Hz"

        if eye_m > 0 and eye_src:
            # —— 相位密度热力图 ——
            set_density_mode(True)
            clear_boundaries()
            mode_filter = {1: None, 2: 0, 3: 1}.get(eye_m)
            probe = prep_frame_ys(list(fr.get("samples") or []), auto)
            period = estimate_period_samp(probe, int(ui.get("eye_period") or 64))
            ui["eye_period"] = period
            dens, n_used, rms, means, stds = build_phase_density(
                eye_src, period, auto, mode_filter, max_frames=min(256, len(eye_src))
            )
            img = [[float(dens[ph][v]) for ph in range(period)] for v in range(256)]
            peak = max((max(row) for row in img), default=1.0) or 1.0
            dens_im.set_data(img)
            dens_im.set_extent([0, period, 0, 255])
            dens_im.set_clim(0, peak)
            xs = list(range(period))
            dens_mean.set_data(xs, means)
            dens_hi.set_data(
                xs, [m + s if m == m else float("nan") for m, s in zip(means, stds)]
            )
            dens_lo.set_data(
                xs, [m - s if m == m else float("nan") for m, s in zip(means, stds)]
            )
            ax.set_xlim(0, period)
            ax.set_ylim(-5, 260)
            ax.set_ylabel("样点值 0..255")
            filt = {1: "全部", 2: "慢SYS", 3: "快PLL"}[eye_m]
            ax.set_title(f"相位密度（{filt}）· 亮=出现多 · 细带=帧间接近")
            ax.set_xlabel(
                f"相位 0..{period - 1}（峰值已旋到 0）· fs={args.fs:g}"
            )
            frame_tag.set_text(f"n={n_used}  rms={rms:.1f}")
            note = f"密度/{filt}"
            t0, tmax = 0.0, float(period)
            y_for_f = [int(m) for m in means if m == m]
            wave_hz = estimate_wave_hz(y_for_f * 3 if y_for_f else [], args.fs)
            if wave_hz is None and period > 0:
                wave_hz = args.fs / period
            if wave_hz is None:
                f_txt = "wave=?Hz"
            elif wave_hz >= 1000:
                f_txt = f"wave={wave_hz/1000:.2f}kHz"
            else:
                f_txt = f"wave={wave_hz:.1f}Hz"
            tag += f" rms={rms:.1f}"
            indep = " | 相位密度=对齐后分布"
        else:
            set_density_mode(False)
            dens_mean.set_data([], [])
            dens_hi.set_data([], [])
            dens_lo.set_data([], [])
            if ui["paused"] and ui["freeze"]:
                ts, ys, nfr, note, bounds, off = build_view(
                    src, i, win, args.fs, auto, sample_offset=int(ui["samp_off"])
                )
                frame_tag.set_text(f"off={off}")
            elif hist:
                ts, ys, nfr, note, bounds, off = build_view(
                    hist, i, win, args.fs, auto, sample_offset=None
                )
                frame_tag.set_text(f"seq:{seq}" if nfr <= 1 else f"{nfr}fr")
            else:
                ts, ys = [], []
                frame_tag.set_text("")

            line.set_data(ts, ys)
            draw_boundaries(bounds)
            finite_t = [t for t in ts if t == t]
            if finite_t:
                t0, tmax = finite_t[0], finite_t[-1]
                pad = max((tmax - t0) * 0.01, dt_us())
                ax.set_xlim(t0 - pad * 0.1, tmax + pad)
            else:
                t0, tmax = 0.0, max(win * dt_us(), dt_us())
                ax.set_xlim(0, tmax)
            ax.set_ylim(-5, 260)
            ax.set_ylabel("样点值")
            ax.set_title("lab_sys  ·  红线 = UART 帧界")
            if nfr > 1 or bounds:
                ax.set_xlabel(
                    f"time (µs)  · 红线=帧界  ·  a/d ±¼帧 · e=相位密度  ·  fs={args.fs:g}"
                )
            else:
                ax.set_xlabel(
                    f"time (µs)  · 单帧快照 · e=相位密度  ·  fs={args.fs:g}"
                )
            y_for_f = [int(v) for v in ys if v == v]
            wave_hz = estimate_wave_hz(y_for_f, args.fs)
            if wave_hz is None:
                f_txt = "wave=?Hz"
            elif wave_hz >= 1000:
                f_txt = f"wave={wave_hz/1000:.2f}kHz"
            else:
                f_txt = f"wave={wave_hz:.1f}Hz"
            indep = ""
            if mode == "PLL" and view_err > 10:
                indep = " | snaps UNRELATED (SPI fail)"
            elif corr < 0.15 and nfr >= 1 and mode != "?":
                indep = " | low corr=independent captures"

        wait_txt = ""
        if ok == 0:
            wait_txt = f" | waiting first UART… {(time.time()-t_open):.1f}s"

        status.set_text(
            f"ok={ok} bad={bad} spi_err={view_err} err_frames={err_frames} "
            f"N={view_n} xlen={win} {note} t={t0:.0f}..{tmax:.0f}µs fps={frame_hz:.1f} "
            f"{f_txt}(exp≈{expect/1000:.2f}k){tag}{indep}{wait_txt}"
        )
        return line, status, frame_tag

    ani = animation.FuncAnimation(fig, update, interval=50, blit=False, cache_frame_data=False)
    fig._ani = ani

    try:
        plt.show()
    finally:
        stop.set()
        th.join(timeout=1.0)
        ser.close()


if __name__ == "__main__":
    main()
