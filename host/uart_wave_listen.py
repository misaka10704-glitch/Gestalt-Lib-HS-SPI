#!/usr/bin/env python3
"""仅串口收帧监视（无 GUI），便于下载后先确认有数据。"""

from __future__ import annotations

import argparse
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    print("需要: pip install pyserial", file=sys.stderr)
    sys.exit(1)

# 复用 plot 脚本的解析逻辑（同目录）
from uart_wave_plot import FrameParser, list_serial_ports, pick_default_port  # type: ignore


def main() -> None:
    ap = argparse.ArgumentParser(description="UART 波形帧监视（终端）")
    ap.add_argument("--port", "-p")
    ap.add_argument("--baud", "-b", type=int, default=115200)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--hex", action="store_true", help="同时打印原始 hex")
    args = ap.parse_args()

    if args.list:
        list_serial_ports()
        return

    port = args.port or pick_default_port()
    if not port:
        print("请指定 --port")
        list_serial_ports()
        return

    print(f"监听 {port} @ {args.baud}，Ctrl+C 退出")
    ser = serial.Serial(port, args.baud, timeout=0.05)
    parser = FrameParser()
    last_ok = last_bad = 0
    idle = 0
    try:
        while True:
            n = ser.in_waiting
            if n:
                idle = 0
                chunk = ser.read(n)
                if args.hex:
                    print(chunk.hex(" "))
                parser.feed(chunk)
            else:
                idle += 1
                if idle == 100:  # ~2s 无字节
                    print("(仍无字节…检查：已下载 uart_wave？LED 心跳在闪？端口是否正确？)")
            if parser.ok != last_ok or parser.bad != last_bad:
                print(f"ok={parser.ok} bad_xor={parser.bad} samples={len(parser.samples)}")
                last_ok, last_bad = parser.ok, parser.bad
            time.sleep(0.02)
    except KeyboardInterrupt:
        print("\n退出")
    finally:
        ser.close()


if __name__ == "__main__":
    main()
