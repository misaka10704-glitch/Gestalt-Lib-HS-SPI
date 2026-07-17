# Async FIFO 仿真注意事项

目录：`async_fifo/`  
DUT：`async_fifo.v`  
TB：`tb/tb_async_fifo.v`  
波形：`sim/wave.vcd`

---

## 1. 怎么跑

```bash
cd async_fifo
make sim      # 编译 + 仿真，生成 sim/wave.vcd
make wave     # 仿真后用 GTKWave 打开（独立窗口）
make clean
```

Cursor / VS Code：

- 推荐用 **Surfer** 扩展打开 `sim/wave.vcd`
- 或命令面板跑任务：**FIFO: Simulate** / **FIFO: Open Waveform (GTKWave)**

当前 TB 激励（短）：**满 → 短 HOLD → 读空，重复 3 次**（`DEPTH=8`）。总仿真约 1 µs 量级，不必再拉很长。

---

## 2. 波形里看什么（`u_wave`）

Icarus 对「多个 `$dumpvars` 参数」会拆成破碎 scope，Cursor 里 **Add to Wave 会没反应**。  
因此 TB 用单一实例 **`u_wave`**（`wave_probes`）集中 dump。请展开：

`tb_async_fifo` → **`u_wave`**

| 前缀 | 时钟域 | 信号 |
|------|--------|------|
| `w_*` | 写 / wclk | `w_clk, w_en, w_data, w_addr, w_ptr, w_gray, w_full` |
| `r_*` | 读 / rclk | `r_clk, r_en, r_data, r_addr, r_ptr, r_gray, r_empty` |
| CDC | 跨域 2FF | 见下表 |
| `s_*` | 共享 | `s_rst, s_mem0…7` |

### 判空（在 rclk 域）— 写指针“晚到”

看顺序：

```
w_gray → w_gray_r1 → w_gray_rq  与  r_gray  比较 → r_empty
```

- `w_gray`：写侧本域 Gray（刚变）
- `w_gray_r1` / `w_gray_rq`：打进 **rclk** 的第 1 / 第 2 级
- **empty** 用的是稳态后的 `w_gray_rq == r_gray`（再寄存一拍）

所以：写完后 `empty` 变 0，会晚大约 **2～3 个 rclk**，这是正常 CDC，不是 bug。

### 判满（在 wclk 域）— 读指针“晚到”

```
r_gray → r_gray_w1 → r_gray_wq  与  w_gray  比满 → w_full
```

满条件（Gray，DEPTH 为 2 的幂）：

```text
w_gray == {~r_gray_wq[MSB:MSB-1], r_gray_wq[MSB-2:0]}
```

即：最高两位相对读侧同步 Gray **取反**，其余位相等。

---

## 3. 指针多 1 位（和仿真强相关）

```verilog
localparam addr_width = $clog2(DEPTH);
reg [addr_width:0] wptr, rptr;   // 多 1 位
// 访存只用低位：
memory[wptr[addr_width-1:0]]
```

- 低 `addr_width` 位：memory 地址（0～DEPTH-1）
- 最高 1 位：区分「空」和「满」（同址时靠圈数不同）

**Gray 不是多 1 位的原因**；多 1 位是空/满语义，Gray 只是跨时钟传指针的编码。

---

## 4. 仿真里容易晕的几点

### 4.1 `full` / `empty` 都是寄存器输出

本拍比较结果，**下一拍**才反映到 `full`/`empty`。  
再叠加 2FF，波形上会感觉“指针已经到了，旗标还没动”——先对一下 `*_gray_*` 再看旗标。

### 4.2 写穿导致 `full` 闪一下又掉（重要）

若 TB **只看 `!full` 就狂写**：

1. 最后一拍写入使指针到“真满”
2. 本拍 `full` 仍是旧值 0 → 可能再写一笔（overshoot）
3. 指针越过满点后，Gray 满条件不再成立 → **`full` 拉高后很快掉下去**

所以：

- 看 full 时序：TB 应 **写满 DEPTH 即停**，再 `wait(full)`，再 HOLD
- 高速连续写时，量产设计常加 **almost_full**，或提前停写

当前 TB 已按「写满 DEPTH → HOLD → 读空」做，避免写穿。

### 4.3 读侧也会多读一拍

`empty` 寄存晚一拍时，若 `rd_en` 一直拉着，可能在“已经读完”的同一拍再读一次，指针超前，**empty 再也等不回来**。

TB 用类似：

```verilog
rd_en <= ... && ((rd_cnt + rd_fire_d) < wr_cnt);
```

在最后一笔前停掉 `rd_en`。自己写 TB 时要注意。

### 4.4 DEPTH 必须是 2 的幂

当前 Gray 判满公式依赖 2 的幂深度。改成 6、12 等会错。

### 4.5 参数别混

| 参数 | 含义 |
|------|------|
| `DATA_WIDTH` | 每个 entry 多少 bit |
| `DATA_DEEPTH`（DEPTH） | 有多少个 entry |

地址位宽用 `$clog2(DEPTH)`，**不要**用 `DATA_WIDTH`。

---

## 5. 建议观察顺序（满相关）

1. 只挂：`w_clk, w_en, w_ptr, w_gray, r_gray, r_gray_w1, r_gray_wq, w_full`
2. 找 FILL 末尾：`w_full` 变 1 的边沿
3. 对照：`w_gray` 是否已满足满码型，而 `r_gray_wq` 仍接近 0（读侧没动）
4. HOLD 段：`w_full` 应保持 1；`r_*` 基本不动
5. DRAIN：`r_en` 有效后，`r_ptr` 追上，`w_full` 落下，最后 `r_empty` 升起（带 CDC 延迟）

空相关则盯：`w_gray → w_gray_r1 → w_gray_rq` 与 `r_gray`、`r_empty`。

---

## 6. 工具建议

| 工具 | 用途 |
|------|------|
| **Surfer**（VS Code/Cursor 扩展） | 日常看 VCD，缩放比内置好 |
| **GTKWave** | `make wave`，独立窗口，不被 AI 侧栏挡住 |
| Cursor 内置 VCD | 能扫一眼；行高可右键 Row Height 调大 |

内置波形若 Add to Wave 无反应：确认打开的是**最新** `sim/wave.vcd`，并只从 **`u_wave`** 下加信号。

---

## 7. 文件与忽略

- `sim/` 在 `.gitignore` 中（仿真产物不提交）
- 源码：`async_fifo.v`、`tb/tb_async_fifo.v`、`Makefile`、`wave.gtkw`

---

## 8. 一句话备忘

> **跨域的是 Gray 指针（2FF）；比空/满在本域做；旗标有寄存延迟；写满要防 overshoot，读空要防多读一拍。**
