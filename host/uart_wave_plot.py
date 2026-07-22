#!/usr/bin/env python3
"""UART 三角波收帧并实时显示。

帧：AA 55 | SEQ | N | DATA[N] | XOR
XOR = SEQ ^ N ^ DATA[0] ^ ... ^ DATA[N-1]
"""

from __future__ import annotations

import argparse
import collections
import sys
import threading
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    print("需要: pip install pyserial", file=sys.stderr)
    sys.exit(1)

try:
    import matplotlib.pyplot as plt
    import matplotlib.animation as animation
except ImportError:
    print("需要: pip install matplotlib", file=sys.stderr)
    sys.exit(1)


SYNC0, SYNC1 = 0xAA, 0x55
PLOT_LEN = 1024


def list_serial_ports() -> None:
    ports = list(list_ports.comports())
    if not ports:
        print("未发现串口")
        return
    for p in ports:
        print(f"  {p.device}\t{p.description}")


def pick_default_port() -> str | None:
    """优先选 usbserial / wch，跳过蓝牙。"""
    cands = []
    for p in list_ports.comports():
        d = p.device.lower()
        if "bluetooth" in d or "bose" in d or "redmi" in d or "debug-console" in d:
            continue
        if "usbserial" in d or "wch" in d or "usbmodem" in d:
            cands.append(p.device)
    return cands[0] if cands else None


class FrameParser:
    def __init__(self, buf_len: int = PLOT_LEN) -> None:
        self.buf = bytearray()
        self.ok = 0
        self.bad = 0
        self.lock = threading.Lock()
        self.samples: collections.deque[int] = collections.deque(maxlen=max(64, buf_len))

    def set_buf_len(self, n: int) -> None:
        """调整样点环形缓冲长度（保留最近数据）。"""
        n = max(64, int(n))
        with self.lock:
            old = list(self.samples)
            self.samples = collections.deque(old[-n:], maxlen=n)

    def feed(self, data: bytes) -> None:
        self.buf.extend(data)
        while True:
            if len(self.buf) < 2:
                return
            # 找同步头
            i = 0
            while i + 1 < len(self.buf):
                if self.buf[i] == SYNC0 and self.buf[i + 1] == SYNC1:
                    break
                i += 1
            else:
                # 无完整头，保留最后一字节以防跨包 AA
                self.buf[:] = self.buf[-1:]
                return
            if i:
                del self.buf[:i]
            if len(self.buf) < 4:
                return
            seq = self.buf[2]
            n = self.buf[3]
            need = 4 + n + 1
            if len(self.buf) < need:
                return
            payload = self.buf[2 : 4 + n]
            xor_rx = self.buf[4 + n]
            xor_calc = 0
            for b in payload:
                xor_calc ^= b
            frame = bytes(self.buf[:need])
            del self.buf[:need]
            if xor_calc != xor_rx:
                self.bad += 1
                if self.bad <= 3:
                    print(
                        f"[bad_xor #{self.bad}] n={n} calc=0x{xor_calc:02x} rx=0x{xor_rx:02x} "
                        f"head={frame[:min(12,len(frame))].hex(' ')} "
                        f"(期望 n=64 且 head 形如 aa 55 <seq> 40 ...)",
                        flush=True,
                    )
                continue
            if n != 64 and self.ok == 0 and self.bad <= 1:
                print(f"[warn] n={n}（lab_sys 应为 64），可能仍在错位", flush=True)
            self.ok += 1
            with self.lock:
                self.samples.extend(payload[2:])  # skip seq,n → data only
            _ = seq
            _ = frame


def reader_loop(ser: serial.Serial, parser: FrameParser, stop: threading.Event) -> None:
    while not stop.is_set():
        try:
            n = ser.in_waiting
            if n:
                parser.feed(ser.read(n))
            else:
                time.sleep(0.005)
        except serial.SerialException as e:
            print(f"串口读失败: {e}", file=sys.stderr)
            print("常见原因：端口被 WCHSerial/串口助手占用，或线被拔掉。", file=sys.stderr)
            stop.set()
            return


def open_serial(port: str, baud: int) -> serial.Serial:
    """打开串口；被占用时给出可操作提示。"""
    try:
        # exclusive：尽量独占，避免 macOS 上多开静默抢读
        return serial.Serial(port, baud, timeout=0.05, exclusive=True)
    except TypeError:
        return serial.Serial(port, baud, timeout=0.05)
    except serial.SerialException as e:
        print(f"无法打开 {port}: {e}", file=sys.stderr)
        print("请关掉 WCHSerial / 串口助手 / 其它 python，再试。", file=sys.stderr)
        print(f"  查占用: lsof {port}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    ap = argparse.ArgumentParser(description="UART 三角波实时波形")
    ap.add_argument("--port", "-p", help="串口，如 /dev/cu.usbserial-xxx 或 COM3")
    ap.add_argument("--baud", "-b", type=int, default=115200)
    ap.add_argument("--list", action="store_true", help="列出串口后退出")
    args = ap.parse_args()

    if args.list:
        list_serial_ports()
        return
    port = args.port or pick_default_port()
    if not port:
        print("请指定 --port，或先 --list 查看")
        list_serial_ports()
        sys.exit(1)
    print(f"打开 {port} @ {args.baud}")

    ser = open_serial(port, args.baud)
    parser = FrameParser()
    stop = threading.Event()
    th = threading.Thread(target=reader_loop, args=(ser, parser, stop), daemon=True)
    th.start()

    fig, ax = plt.subplots()
    (line,) = ax.plot([], [], lw=1.2)
    ax.set_ylim(-5, 260)
    ax.set_xlim(0, PLOT_LEN)
    ax.set_xlabel("sample")
    ax.set_ylabel("value")
    ax.set_title("uart_wave triangle")
    status = ax.text(0.02, 0.95, "", transform=ax.transAxes, va="top")

    def update(_frame):
        with parser.lock:
            ys = list(parser.samples)
        xs = list(range(len(ys)))
        line.set_data(xs, ys)
        if ys:
            ax.set_xlim(0, max(PLOT_LEN, len(ys)))
        status.set_text(f"ok={parser.ok}  bad_xor={parser.bad}")
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
