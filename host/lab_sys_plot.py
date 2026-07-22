#!/usr/bin/env python3
"""lab_sys：连续快照帧画图（默认只显示最新一帧，不跨帧拼接）。

帧：AA 55 | SEQ | N | ERR | DATA[N] | XOR
XOR = SEQ ^ N ^ ERR ^ DATA[…]

X 轴：--xlen / 键盘 [ ] 1-6 r
"""

from __future__ import annotations

import argparse
import collections
import sys
import threading
import time

try:
    import serial
except ImportError:
    print("需要: pip install pyserial", file=sys.stderr)
    sys.exit(1)

try:
    import matplotlib.pyplot as plt
    import matplotlib.animation as animation
except ImportError:
    print("需要: pip install matplotlib", file=sys.stderr)
    sys.exit(1)

from uart_wave_plot import list_serial_ports, open_serial, pick_default_port

SYNC0, SYNC1 = 0xAA, 0x55
XLEN_PRESETS = {ord("1"): 64, ord("2"): 128, ord("3"): 256, ord("4"): 512, ord("5"): 1024, ord("6"): 2048}
XLEN_MIN, XLEN_MAX = 32, 8192


def clamp_xlen(n: int) -> int:
    return max(XLEN_MIN, min(XLEN_MAX, int(n)))


class LabSysParser:
    """解析带 ERR 的 lab_sys 帧；默认每帧覆盖样点（不拼接）。"""

    def __init__(self, replace: bool = True) -> None:
        self.buf = bytearray()
        self.ok = 0
        self.bad = 0
        self.last_err = 0
        self.err_frames = 0
        self.lock = threading.Lock()
        self.replace = replace
        self.samples: collections.deque[int] = collections.deque(maxlen=4096)
        self.last_n = 0

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
            # AA55 SEQ N ERR + need N data + XOR → 最少 6 字节头尾
            if len(self.buf) < 5:
                return
            seq = self.buf[2]
            n = self.buf[3]
            err = self.buf[4]
            need = 5 + n + 1
            if len(self.buf) < need:
                return
            payload = self.buf[2 : 5 + n]  # seq,n,err,data…
            xor_rx = self.buf[5 + n]
            xor_calc = 0
            for b in payload:
                xor_calc ^= b
            frame = bytes(self.buf[:need])
            del self.buf[:need]
            if xor_calc != xor_rx:
                self.bad += 1
                if self.bad <= 3:
                    print(
                        f"[bad_xor #{self.bad}] n={n} err={err} "
                        f"calc=0x{xor_calc:02x} rx=0x{xor_rx:02x} "
                        f"head={frame[:min(10, len(frame))].hex(' ')}",
                        flush=True,
                    )
                continue
            data_pts = list(payload[3:])  # skip seq,n,err
            self.ok += 1
            self.last_err = err
            self.last_n = n
            if err:
                self.err_frames += 1
            with self.lock:
                if self.replace:
                    self.samples = collections.deque(data_pts, maxlen=max(4096, n))
                else:
                    self.samples.extend(data_pts)
            _ = seq
            _ = frame


def reader_loop(ser: serial.Serial, parser: LabSysParser, stop: threading.Event) -> None:
    while not stop.is_set():
        try:
            n = ser.in_waiting
            if n:
                parser.feed(ser.read(n))
            else:
                time.sleep(0.005)
        except serial.SerialException as e:
            print(f"串口读失败: {e}", file=sys.stderr)
            stop.set()
            return


def main() -> None:
    ap = argparse.ArgumentParser(description="lab_sys 连续快照 / SPI 差错观察")
    ap.add_argument("--port", "-p")
    ap.add_argument("--baud", "-b", type=int, default=115200)
    ap.add_argument("--xlen", "-x", type=int, default=128, help="X 可见点数（默认=一帧 128）")
    ap.add_argument(
        "--concat",
        action="store_true",
        help="跨帧拼接（旧行为，会有帧缝假毛刺；默认关闭）",
    )
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    if args.list:
        list_serial_ports()
        return
    port = args.port or pick_default_port()
    if not port:
        print("请指定 --port")
        list_serial_ports()
        sys.exit(1)

    xlen0 = clamp_xlen(args.xlen)
    state = {"xlen": xlen0}
    replace = not args.concat

    mode = "最新一帧(推荐看SPI)" if replace else "跨帧拼接(有假毛刺)"
    print(f"打开 {port} @ {args.baud}  mode={mode}")
    print(f"X={state['xlen']}  键:[ ]缩放 1-6快捷 r复位")

    ser = open_serial(port, args.baud)
    parser = LabSysParser(replace=replace)
    stop = threading.Event()
    th = threading.Thread(target=reader_loop, args=(ser, parser, stop), daemon=True)
    th.start()

    fig, ax = plt.subplots()
    (line,) = ax.plot([], [], lw=1.0)
    ax.set_ylim(-5, 260)
    ax.set_xlim(0, state["xlen"])
    ax.set_xlabel("sample (one continuous shot)" if replace else "sample (concat)")
    ax.set_ylabel("value")
    ax.set_title("lab_sys: continuous capture → SPI → UART")
    status = ax.text(0.02, 0.95, "", transform=ax.transAxes, va="top")

    def apply_xlen(n: int) -> None:
        state["xlen"] = clamp_xlen(n)
        ax.set_xlim(0, state["xlen"])
        fig.canvas.draw_idle()

    def on_key(event) -> None:
        if event.key in ("[", "-"):
            apply_xlen(state["xlen"] // 2)
        elif event.key in ("]", "=", "+"):
            apply_xlen(state["xlen"] * 2)
        elif event.key == "r":
            apply_xlen(xlen0)
        else:
            ch = event.key
            if ch and len(ch) == 1 and ord(ch) in XLEN_PRESETS:
                apply_xlen(XLEN_PRESETS[ord(ch)])

    fig.canvas.mpl_connect("key_press_event", on_key)

    def update(_frame):
        with parser.lock:
            ys_all = list(parser.samples)
        n = state["xlen"]
        ys = ys_all[-n:] if len(ys_all) > n else ys_all
        line.set_data(list(range(len(ys))), ys)
        ax.set_xlim(0, max(n, 1))
        status.set_text(
            f"ok={parser.ok} bad={parser.bad}  "
            f"spi_err={parser.last_err} err_frames={parser.err_frames}  "
            f"N={parser.last_n} xlen={n}"
        )
        return line, status

    _ani = animation.FuncAnimation(fig, update, interval=50, blit=False, cache_frame_data=False)
    try:
        plt.show()
    finally:
        stop.set()
        th.join(timeout=1.0)
        ser.close()


if __name__ == "__main__":
    main()
