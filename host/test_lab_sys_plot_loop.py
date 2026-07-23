#!/usr/bin/env python3
"""自测 lab_sys_plot：绝对时间轴 + 细移时红线平移。"""

from __future__ import annotations

import lab_sys_plot as P

FS = 1e6


def sine(n=128, ph=0):
    lut = [
        128, 140, 152, 164, 176, 187, 198, 208, 217, 226, 233, 239, 245, 249, 252, 254,
        255, 254, 252, 249, 245, 239, 233, 226, 217, 208, 198, 187, 176, 164, 152, 140,
        128, 115, 103, 91, 79, 68, 57, 47, 38, 29, 22, 16, 10, 6, 3, 1,
        0, 1, 3, 6, 10, 16, 22, 29, 38, 47, 57, 68, 79, 91, 103, 115,
    ]
    return [lut[(ph + i) % 64] for i in range(n)]


def main() -> int:
    frames = [
        {"seq": i, "n": 128, "err": 0, "fast": 0, "samples": sine(128, i * 8)}
        for i in range(4)
    ]
    flat, bounds, _ = P.flatten_frames(frames, False)
    assert len(flat) == 512 and bounds == [128, 256, 384], (len(flat), bounds)

    ts0, ys0, _, _, bt0, off0 = P.build_view(
        frames, 3, 256, FS, False, sample_offset=0
    )
    assert off0 == 0 and abs(ts0[0] - 0.0) < 1e-9
    assert [round(t) for t in bt0] == [128, 256], bt0

    # 半帧细移：红线绝对位置不变，窗起点变 → 屏上线会动
    ts1, ys1, _, _, bt1, off1 = P.build_view(
        frames, 3, 256, FS, False, sample_offset=64
    )
    assert off1 == 64 and abs(ts1[0] - 64.0) < 1e-9 and len(ys1) == 256
    assert abs(bt1[0] - 128.0) < 1e-6, bt1  # 仍在绝对 128µs
    assert abs(bt1[0] - ts1[0] - 64.0) < 1e-6  # 相对窗左缘 = 64µs

    # 再移 32：红线绝对仍在 128/256…，窗左缘 96 → 相对位置再变
    ts2, _, _, _, bt2, off2 = P.build_view(
        frames, 3, 256, FS, False, sample_offset=96
    )
    assert off2 == 96 and abs(ts2[0] - 96.0) < 1e-9
    assert abs(bt2[0] - 128.0) < 1e-6
    assert abs(bt2[0] - ts2[0] - 32.0) < 1e-6

    print("OK: abs-time axis; scrub moves window under fixed absolute red lines")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as e:
        print("FAIL:", e)
        raise SystemExit(1)
