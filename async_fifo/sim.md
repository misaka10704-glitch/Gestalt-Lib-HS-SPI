# 仿真任务

```bash
cd async_fifo
make sim1    # → sim/wave1.vcd  空满
make sim2    # → sim/wave2.vcd  读写传输
make sim     # 两个都跑
```

波形从 `u_wave` 加信号。

---

## Wave1 空满时序

文件：`sim/wave1.vcd`

### 满（wclk）

```
w_full
w_clk
r_gray_wq
w_gray
```

### 空（rclk）

```
r_empty
r_clk
w_gray_rq
r_gray
```

---

## Wave2 读写传输

文件：`sim/wave2.vcd`

### 写（wclk）

```
w_full
w_clk
w_en
w_data
w_addr
s_mem0
s_mem1
s_mem2
s_mem3
```

### 读（rclk）

```
r_empty
r_clk
r_en
r_data
r_addr
s_mem0
s_mem1
s_mem2
s_mem3
```
