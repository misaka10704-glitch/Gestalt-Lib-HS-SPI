#!/usr/bin/env python3
"""听 UART：统计 beacon(N=1) vs core(N>=8)。"""
import sys, time

try:
    import serial
except ImportError:
    sys.exit("pip install pyserial")

ports = sys.argv[1:] or [
    "/dev/cu.usbserial-20230814131",
    "/dev/cu.usbserial-20230814130",
]

def parse(buf: bytes):
    n1 = n128 = bad = 0
    i = 0
    while i + 5 < len(buf):
        if buf[i] != 0xAA or buf[i + 1] != 0x55:
            i += 1
            continue
        n = buf[i + 3]
        need = 5 + n + 1
        if i + need > len(buf):
            break
        payload = buf[i + 2 : i + 5 + n]
        xor_rx = buf[i + 5 + n]
        x = 0
        for b in payload:
            x ^= b
        if x != xor_rx:
            bad += 1
        elif n == 1:
            n1 += 1
        elif n >= 8:
            n128 += 1
        i += need
    return n1, n128, bad

for p in ports:
    try:
        s = serial.Serial(p, 115200, timeout=0.2)
    except Exception as e:
        print(f"{p}: OPEN_FAIL {e}")
        continue
    s.reset_input_buffer()
    t0 = time.time()
    buf = bytearray()
    while time.time() - t0 < 2.0:
        n = s.in_waiting
        if n:
            buf.extend(s.read(n))
        else:
            time.sleep(0.01)
    s.close()
    n1, nbig, bad = parse(bytes(buf))
    print(f"{p}: {len(buf)} bytes | beacon_N1={n1} core_N>=8={nbig} bad_xor={bad}")
    if len(buf) == 0:
        print("  silence — 未下载或口错")
    elif nbig == 0 and n1 > 0:
        print("  仅 beacon → core 仍没发出波形帧")
    elif nbig > 0:
        print("  core 波形帧 OK → 可开 plot")
