#!/usr/bin/env python3
"""生成复杂波形 → UART 下发 → 等 FPGA 回传 → 对比绘图。

帧：AA 55 | SEQ | N | DATA[N] | XOR
"""

from __future__ import annotations

import argparse
import sys
import time

import numpy as np

try:
    import serial
except ImportError:
    print("需要: pip install pyserial", file=sys.stderr)
    sys.exit(1)

try:
    import matplotlib.pyplot as plt
except ImportError:
    print("需要: pip install matplotlib", file=sys.stderr)
    sys.exit(1)

from uart_wave_plot import list_serial_ports, pick_default_port

SYNC0, SYNC1 = 0xAA, 0x55


def build_frame(seq: int, data: list[int]) -> bytes:
    n = len(data)
    assert 1 <= n <= 128
    body = bytes([seq & 0xFF, n] + [d & 0xFF for d in data])
    x = 0
    for b in body:
        x ^= b
    return bytes([SYNC0, SYNC1]) + body + bytes([x])


def make_complex_wave(n: int = 128) -> list[int]:
    """基波 + 三次谐波 + 缓慢包络，映射到 0..255。"""
    t = np.linspace(0, 4 * np.pi, n, endpoint=False)
    env = 0.55 + 0.45 * np.sin(t / 4)
    y = env * (np.sin(t) + 0.35 * np.sin(3 * t + 0.4))
    y = (y - y.min()) / (y.max() - y.min() + 1e-9)
    return [int(v * 255) for v in y]


def recv_one_frame(ser: serial.Serial, timeout_s: float = 2.0) -> list[int] | None:
    t0 = time.time()
    buf = bytearray()
    while time.time() - t0 < timeout_s:
        n = ser.in_waiting
        if n:
            buf.extend(ser.read(n))
        while True:
            if len(buf) < 2:
                break
            i = 0
            while i + 1 < len(buf):
                if buf[i] == SYNC0 and buf[i + 1] == SYNC1:
                    break
                i += 1
            else:
                buf[:] = buf[-1:]
                break
            if i:
                del buf[:i]
            if len(buf) < 4:
                break
            nlen = buf[3]
            need = 4 + nlen + 1
            if len(buf) < need:
                break
            payload = buf[2 : 4 + nlen]
            xor_rx = buf[4 + nlen]
            xor_calc = 0
            for b in payload:
                xor_calc ^= b
            del buf[:need]
            if xor_calc == xor_rx:
                return list(payload[2:])
        time.sleep(0.005)
    return None


def main() -> None:
    ap = argparse.ArgumentParser(description="复杂波形下发并回波显示")
    ap.add_argument("--port", "-p")
    ap.add_argument("--baud", "-b", type=int, default=115200)
    ap.add_argument("--n", type=int, default=128, help="每帧点数，<=128")
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

    n = max(8, min(128, args.n))
    wave = make_complex_wave(n)
    frame = build_frame(1, wave)

    print(f"打开 {port} @ {args.baud}，发送 {n} 点…")
    ser = serial.Serial(port, args.baud, timeout=0.05)
    time.sleep(0.05)
    ser.reset_input_buffer()
    ser.write(frame)
    ser.flush()

    echo = recv_one_frame(ser, timeout_s=3.0)
    ser.close()

    if echo is None:
        print("超时未收到回波。确认已下载 uart_echo 工程，且用对口（…131）。")
        sys.exit(2)

    print(f"回波 {len(echo)} 点，匹配={echo == wave}")

    xs = list(range(n))
    plt.figure(figsize=(9, 4))
    plt.plot(xs, wave, label="TX (host)", lw=1.5)
    plt.plot(xs[: len(echo)], echo, label="RX (FPGA echo)", lw=1.2, alpha=0.85)
    plt.ylim(-5, 260)
    plt.xlabel("sample")
    plt.ylabel("value")
    plt.title("complex wave echo")
    plt.legend()
    plt.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()
