# Async FIFO 仿真工作流

验收清单（挂哪些线）见：`async_fifo/sim.md`  
原理备忘见：`AI文本/async_fifo_仿真注意事项.md`

---

## 目录

```
async_fifo/
  async_fifo.v          # DUT
  Makefile
  sim.md                # Wave1/Wave2 挂线任务
  tb/
    wave_probes.v       # u_wave 探针（单一 VCD scope）
    tb_wave1.v          # 空满时序
    tb_wave2.v          # 读写传输
  sim/                  # 产物（gitignore，不提交）
    wave1.vcd
    wave2.vcd
```

---

## 命令

```bash
cd async_fifo

make sim1      # 空满 → sim/wave1.vcd
make sim2      # 传输 → sim/wave2.vcd
make sim       # 两个都跑
make wave1     # sim1 + GTKWave 开 wave1
make wave2     # sim2 + GTKWave 开 wave2
make clean
```

Cursor / VS Code 任务：

| 任务名 | 作用 |
|--------|------|
| FIFO: Wave1 empty/full | `make sim1` |
| FIFO: Wave2 xfer | `make sim2` |
| FIFO: Sim both | `make sim` |
| FIFO: Clean | `make clean` |

---

## 看波形

1. 跑对应 `make sim1` / `sim2`
2. 用 **Surfer**（或 GTKWave）打开：
   - 空满：`async_fifo/sim/wave1.vcd`
   - 传输：`async_fifo/sim/wave2.vcd`
3. 展开 **`tb_wave1.u_wave`** / **`tb_wave2.u_wave`**
4. 按 `sim.md` 挂线

**注意：** 必须从 `u_wave` 加信号。Icarus 多参数 `$dumpvars` 会拆碎 scope，Add to Wave 会没反应。

---

## TB 各自在干什么

| TB | VCD | 激励 |
|----|-----|------|
| `tb_wave1` | `wave1.vcd` | 写满 → HOLD → 读空，×2 轮 |
| `tb_wave2` | `wave2.vcd` | 连写 8 拍 → 连读 8 拍，核对 scoreboard |

通过标准：终端出现 `[PASS] tb_wave1` / `[PASS] tb_wave2`。

---

## 改 TB / 重跑

1. 改 `tb/tb_wave1.v` 或 `tb/tb_wave2.v`
2. `make sim1` 或 `make sim2`（会重编）
3. **重新打开**对应 VCD（旧标签可能是缓存）

探针端口改了 → 同步改 `tb/wave_probes.v` 和两个 TB 的例化。

---

## 提交 Git 时

- 提交：`async_fifo/` 源码、`sim.md`、`Makefile`、`tb/*`
- 不提交：`sim/`（已在 `.gitignore` 的 `**/sim/`）
