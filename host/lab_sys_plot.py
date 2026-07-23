#!/usr/bin/env python3
"""lab_sys 示波：单帧铺满；xlen>N 时横排多帧（样点时间轴，不是主机时刻）。

时间轴始终是「示波显示时间」t = sample_index / fs（µs）：
  - xlen≤N：当前一帧前 xlen 点，铺满窗口
  - xlen>N：往前取 ceil(xlen/N) 帧，按样点顺序横排，帧间 NaN 断开
    （轴变长到 ~xlen·µs，每帧仍清晰可见；禁止用 host RX 的 20ms 间隙）

a/d：换锚点快照；多帧模式以该帧为右端往前排。
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
    """相邻快照样点相同比例；PLL 杂波应接近 0，干净正弦通常也因相位差偏低。"""
    if not a or not b:
        return 0.0
    n = min(len(a), len(b))
    if n <= 0:
        return 0.0
    return sum(1 for i in range(n) if a[i] == b[i]) / n


def prep_frame_ys(samples: list[int], auto_crop: bool) -> list[int]:
    ys = list(samples)
    if auto_crop:
        pref = nonzero_prefix_len(ys)
        if 8 <= pref < len(ys):
            ys = ys[:pref]
    return ys


def build_view(
    frames: list[dict[str, Any]],
    end_i: int,
    xlen: int,
    fs: float,
    auto_crop: bool,
) -> tuple[list[float], list[float], int, str, list[float]]:
    """构造显示用 (t_us, y, n_frames, note, boundary_t_us)。

    boundary_t_us：帧与帧之间的红色竖线位置（显示时间 µs）。
    """
    if not frames:
        return [], [], 0, "", []
    end_i = max(0, min(end_i, len(frames) - 1))
    dt = 1e6 / fs
    one = prep_frame_ys(frames[end_i]["samples"], auto_crop)
    n0 = max(len(one), int(frames[end_i].get("n") or 128), 1)

    if xlen <= n0:
        ys = one[: min(xlen, len(one))]
        ts = [i * dt for i in range(len(ys))]
        return ts, [float(v) for v in ys], 1, "1-snap", []

    nfr = max(2, (xlen + n0 - 1) // n0)
    start = max(0, end_i - nfr + 1)
    chunk = frames[start : end_i + 1]
    ts: list[float] = []
    ys: list[float] = []
    bounds: list[float] = []
    k = 0
    for fi, fr in enumerate(chunk):
        part = prep_frame_ys(fr["samples"], auto_crop)
        for v in part:
            ts.append(k * dt)
            ys.append(float(v))
            k += 1
            if k >= xlen:
                break
        if k >= xlen:
            break
        if fi != len(chunk) - 1:
            # 帧边界：竖线画在两帧之间
            bounds.append(k * dt)
            ts.append(math.nan)
            ys.append(math.nan)
    return ts, ys, len(chunk), f"{len(chunk)}-strip", bounds


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
        "keys: p pause | a/d other snap | l live | [ ] 1-6 r xlen | c crop",
        flush=True,
    )

    def _prep(s: serial.Serial) -> None:
        try:
            s.dtr = False
            s.rts = False
        except Exception:
            pass
        time.sleep(0.05)
        try:
            s.reset_input_buffer()
        except Exception:
            pass

    ser = open_serial(port, args.baud)
    _prep(ser)
    ser.close()
    time.sleep(0.08)
    ser = open_serial(port, args.baud)
    _prep(ser)
    time.sleep(0.05)
    try:
        ser.reset_input_buffer()
    except Exception:
        pass

    parser = LabSysParser(hist_max=max(32, args.hist))
    stop = threading.Event()
    th = threading.Thread(target=reader_loop, args=(ser, parser, stop), daemon=True)
    th.start()

    ui: dict[str, Any] = {"paused": False, "view_i": 0, "freeze": []}
    boundary_artists: list[Any] = []

    fig, ax = plt.subplots(figsize=(9, 5))
    (line,) = ax.plot([], [], lw=1.2, color="#1f77b4", zorder=2)
    ax.set_ylim(-5, 260)
    ax.set_xlabel(f"time (µs)  ·  sample-index display  ·  fs={args.fs:g} Hz")
    ax.set_ylabel("value")
    ax.set_title("lab_sys  ·  red lines = UART frame boundaries")
    ax.grid(True, alpha=0.25)
    status = ax.text(0.02, 0.95, "", transform=ax.transAxes, va="top", zorder=5)
    frame_tag = ax.text(
        0.98,
        0.95,
        "",
        transform=ax.transAxes,
        va="top",
        ha="right",
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
        ui["freeze"] = snapshot()
        ui["paused"] = True
        ui["view_i"] = max(0, len(ui["freeze"]) - 1)
        print(
            f"[Pause] {len(ui['freeze'])} snapshots — a/d switches capture (not pan)",
            flush=True,
        )

    def toggle_pause() -> None:
        if ui["paused"]:
            ui["paused"] = False
            ui["freeze"] = []
            print("[Live]", flush=True)
        else:
            enter_pause()

    def step(delta: int) -> None:
        if not ui["paused"] or not ui["freeze"]:
            enter_pause()
        n = len(ui["freeze"])
        if n <= 0:
            print("[Scrub] empty", flush=True)
            return
        ui["view_i"] = max(0, min(n - 1, ui["view_i"] + delta))
        fr = ui["freeze"][ui["view_i"]]
        mode = "PLL" if fr["fast"] else "SYS"
        print(
            f"[Snapshot] {ui['view_i']+1}/{n} seq={fr['seq']} err={fr['err']} {mode}",
            flush=True,
        )

    def apply_xlen(n: int) -> None:
        state["xlen"] = clamp_xlen(n)
        nfr = max(1, (state["xlen"] + 127) // 128)
        if nfr == 1:
            print(
                f"[xlen]={state['xlen']} → one snapshot (~{state['xlen'] * dt_us():.0f} µs)",
                flush=True,
            )
        else:
            print(
                f"[xlen]={state['xlen']} → {nfr} snapshots side-by-side "
                f"(~{state['xlen'] * dt_us():.0f} µs display; NaN between frames)",
                flush=True,
            )

    def on_key(event) -> None:
        key = (event.key or "").lower()
        if key in (" ", "space", "p"):
            toggle_pause()
        elif key in ("left", "a"):
            step(-1)
        elif key in ("right", "d"):
            step(1)
        elif key in ("l",):
            ui["paused"] = False
            ui["freeze"] = []
            print("[Live]", flush=True)
        elif key in ("c",):
            state["auto_crop"] = not state["auto_crop"]
            print(f"[auto-crop] {'on' if state['auto_crop'] else 'off'}", flush=True)
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

        auto = bool(state.get("auto_crop", True))
        win = state["xlen"]

        if ui["paused"] and ui["freeze"]:
            src = ui["freeze"]
            i = max(0, min(len(src) - 1, ui["view_i"]))
            fr = src[i]
            view_err, view_n, seq = fr["err"], fr["n"], fr["seq"]
            mode = "PLL" if fr["fast"] else "SYS"
            ts, ys, nfr, note, bounds = build_view(src, i, win, args.fs, auto)
            corr = 0.0
            if i > 0:
                corr = frame_corr(src[i - 1]["samples"], fr["samples"])
            tag = f" PAUSED {i+1}/{len(src)} seq={seq} mode={mode} corr={corr:.2f}"
            frame_tag.set_text(f"seq {seq}")
        elif hist:
            i = len(hist) - 1
            fr = hist[i]
            view_err, view_n, seq = live_err, live_n, live_seq
            mode = "PLL" if live_fast else "SYS"
            ts, ys, nfr, note, bounds = build_view(hist, i, win, args.fs, auto)
            corr = frame_corr(hist[i - 1]["samples"], fr["samples"]) if i > 0 else 0.0
            tag = f" LIVE seq={seq} mode={mode} corr={corr:.2f}"
            frame_tag.set_text(f"{nfr}fr" if nfr > 1 else "")
        else:
            ts, ys, nfr, note, bounds = [], [], 0, "", []
            view_err, view_n, seq = 0, 0, 0
            mode = "?"
            corr = 0.0
            tag = ""
            frame_tag.set_text("")

        line.set_data(ts, ys)
        draw_boundaries(bounds)
        finite_t = [t for t in ts if t == t]
        tmax = finite_t[-1] if finite_t else max(win * dt_us(), dt_us())
        ax.set_xlim(0, max(tmax, dt_us()))
        if nfr > 1:
            ax.set_xlabel(
                f"time (µs)  ·  {nfr} UART frames  ·  red = frame boundary  ·  fs={args.fs:g}"
            )
        else:
            ax.set_xlabel(f"time (µs)  ·  one UART/SPI snapshot  ·  fs={args.fs:g}")

        y_for_f = [int(v) for v in ys if v == v]
        wave_hz = estimate_wave_hz(y_for_f, args.fs)
        expect = args.fs / 64.0
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

        status.set_text(
            f"ok={ok} bad={bad} spi_err={view_err} err_frames={err_frames} "
            f"N={view_n} xlen={win} {note} t=0..{tmax:.0f}µs fps={frame_hz:.1f} "
            f"{f_txt}(exp≈{expect/1000:.2f}k){tag}{indep}"
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
