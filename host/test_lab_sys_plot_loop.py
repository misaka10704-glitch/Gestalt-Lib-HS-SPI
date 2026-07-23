#!/usr/bin/env python3
"""自测 lab_sys_plot 显示逻辑。"""

from __future__ import annotations

import math
import sys

import lab_sys_plot as P

FS = 1e6
SINE = [P.estimate_wave_hz.__doc__ and 0]  # placemarker


def sine(n=128, ph=0):
    lut = [
        128, 140, 152, 164, 176, 187, 198, 208, 217, 226, 233, 239, 245, 249, 252, 254,
        255, 254, 252, 249, 245, 239, 233, 226, 217, 208, 198, 187, 176, 164, 152, 140,
        128, 115, 103, 91, 79, 68, 57, 47, 38, 29, 22, 16, 10, 6, 3, 1,
        0, 1, 3, 6, 10, 16, 22, 29, 38, 47, 57, 68, 79, 91, 103, 115,
    ]
    return [lut[(ph + i) % 64] for i in range(n)]


def fail(msg):
    raise AssertionError(msg)


def main() -> int:
    frames = [
        {"seq": i, "n": 128, "err": 100, "fast": 1, "samples": sine(128, i * 17)}
        for i in range(4)
    ]
    # xlen=128 → 1 frame
    ts, ys, nfr, note, bounds = P.build_view(frames, 3, 128, FS, False)
    assert nfr == 1 and note == "1-snap" and bounds == [], (nfr, note, bounds)
    assert abs(ts[-1] - 127.0) < 1e-6, ts[-1]

    # xlen=256 → 2 frames, axis ~255µs, has NaN break + boundary
    ts2, ys2, nfr2, note2, bounds2 = P.build_view(frames, 3, 256, FS, False)
    assert nfr2 == 2 and "strip" in note2, (nfr2, note2)
    assert any(isinstance(t, float) and math.isnan(t) for t in ts2), "need NaN break"
    assert len(bounds2) == 1, f"need 1 red-line boundary, got {bounds2}"
    finite = [t for t in ts2 if t == t]
    assert finite[-1] > 200, f"axis should grow: last={finite[-1]}"

    # xlen=512 → 4 frames, still longer
    ts4, _, nfr4, _, bounds4 = P.build_view(frames, 3, 512, FS, False)
    finite4 = [t for t in ts4 if t == t]
    assert nfr4 == 4 and finite4[-1] > finite[-1], "512 must be longer than 256"
    assert len(bounds4) == 3, f"3 boundaries for 4 frames, got {bounds4}"

    a = list(range(128))
    b = list(range(128, 0, -1))
    c = P.frame_corr(a, b)
    assert c < 0.05, f"corr={c}"
    assert P.frame_corr(a, a) == 1.0

    print("OK: xlen 128/256/512 grows strip; clutter frames uncorrelated by design")
    print(f"    256 last_t={finite[-1]:.0f}µs  512 last_t={finite4[-1]:.0f}µs  corr={c:.2f}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as e:
        print("FAIL:", e)
        raise SystemExit(1)
