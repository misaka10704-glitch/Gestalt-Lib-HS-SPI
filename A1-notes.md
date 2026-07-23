# 高速 SPI 学习笔记

## UART 帧格式

### uart_wave

```
AA 55 | SEQ | N | DATA[0..N-1] | XOR
```

### lab_sys（多 ERR）

```
AA 55 | SEQ | N | ERR | DATA[0..N-1] | XOR
```

`XOR` 含 `ERR`；`ERR` = 本拍 SPI 错字节数（饱和到 255）。  
上位机 `lab_sys_plot.py` 默认只画**最新一帧**（勿跨帧拼接，否则像波形炸裂）。

## 实验系统参数

| 量 | 默认 |
|----|------|
| adc_clk | 1 MHz |
| FRAME_N | 128 |
| SPI sclk | `lab_sys`≈6.25 MHz；`lab_sys_ext`=**50 MHz**（rPLL 200 M ÷ DIV2） |
| AFIFO_DEPTH | 512 |
| BAUD | 115200 |

- `Projects/lab_sys/` — 片内理想（`spi_err` 应≈0）
- `Projects/lab_sys_ext/` — 飞线 + 50 MHz sclk：`G15→G14`(SCLK)、`G16→H15`(MOSI)

---

## lab_sys 架构笔记（review 用）

### 易错认知

| 错 | 对 |
|----|----|
| 伪 ADC 经 SPI 进 FPGA | 伪 ADC 在片内并行出样点；SPI 在采满之后 |
| UART 直接读 async_fifo | UART 读的是组好的 `frame_mem`（DATA 来自 `spi_rx_buf`） |
| FIFO 要扛全部采样历史 | FIFO 只做 CDC；长数据在 `adc_buf`（将来可换 DDR） |
| 曲线乱 = SPI 坏了 | 先看 `ERR`；ERR=0 仍乱多半是上位机跨帧拼接 |

### 一次拍摄在干什么

1. **FLUSH**：排空残留 FIFO，避免上拍尾巴污染。  
2. **SAMP**：`adc_run=1`，伪 ADC 写 FIFO；sys 侧读入 `adc_buf`，满 N 后 `adc_run=0` 并 `m_start`。  
3. **SPI**：master 发 `adc_buf[0..N-1]`；slave 填 `spi_rx_buf`；`spi_rx_full` 且 master 空闲 → 下一态。  
4. **CMP**：逐字节比，累计 `err_byte`，`err_sticky` 粘住。  
5. **BUILD**：组 `AA55|SEQ|N|ERR|DATA|XOR`（DATA=`spi_rx_buf`）。  
6. **ISSUE/WBUSY/WIDLE**：逐字节 UART；发完若 `enable` 再 FLUSH。

`busy` = 非 IDLE 或 master busy 或 uart busy 或 `adc_run`。

### 时钟域

| 域 | 谁 |
|----|----|
| `adc_clk` | 分频自 `sys_clk`（故意相移）；伪 ADC、FIFO 写 |
| `sys_clk` | FIFO 读、SPI 主从逻辑、比对、UART、FSM |
| SPI 线 | master 出 `sclk_o`/`mosi_o`；slave 入 `sclk_i`/`mosi_i`（可飞线） |
| `cs_n` | 主从同线；ext 版仍片内（相对外线相位更易错） |

### 各 `.v` 逻辑要点（lab_sys 相关）

**`lab_sys_core.v`**  
编排者。参数：`ADC_CLK_HZ`、`FRAME_N`、`SPI_CLK_DIV`、`AFIFO_DEPTH`、`WAVE_SEL`。  
SPI 口拆成 `*_o` / `*_i`，顶层决定短接还是飞线。  
读 FIFO 用 `af_rd_pend`：拉 `rd_en` 下一拍才采 `rdata`（匹配 async_fifo 时序）。

**`lab_sys.v` / `lab_sys_ext.v`**  
板级：`key[0]=rst_n`，`key[1]=enable`；LED：busy / 心跳 / `spi_err_flag` / `|spi_err_cnt`。  
ext 多四个 SPI 管脚；CST 顶排邻脚便于短杜邦线。

**`sine_gen.v`**  
`PHASE_INC` 步进 LUT；`f ≈ SAMPLE_HZ/64`（默认每样 +1）。`sample_stb` 单周期。

**`triangle_gen.v`**  
0↔255 折返；同上分频与 `enable` 门控。

**`async_fifo.v`**  
二进制指针 + 格雷跨域比空满；多余 1bit 区分空/满。深度须 2 的幂（当前实现按 wrap 切低位）。

**`spi_master.v`**  
状态：IDLE→LOAD(cs_start)→SETUP→WAIT/EDGE 循环→GAP→END(cs_end)。  
对外 `byte_done`/`cs_*` 可接 `spi_fifo_interface`；lab_sys 直接用索引取 `adc_buf`。

**`spi_slave_controller.v`**  
3 级同步 `sclk`/`mosi`/`cs_n`；按 CPOL/CPHA 译采样/移位沿。输出已是 `clk` 域脉冲。

**`spi_slave_shift.v`**  
MSB-first 默认；`cs_start` 预装 TX；`sample_stb` 拼 RX；满字节锁 `rx_data` 并 `byte_done`。  
lab_sys：只关心 RX 路径正确性。

**`uart_tx.v`**  
波特分频；移位 `{stop,data}`；空闲线高。

**`spi_fifo_interface.v`（对照，未接入）**  
RX：`byte_done`→FIFO→业务读；TX：业务写→hold→`tx_load` 给 shift。  
lab_sys 用数组缓冲整帧，故未例化。

**`spi_verify_top.v`（对照工程）**  
独立主从自检 + LED；无伪 ADC/UART 帧。学 SPI 时可与 lab_sys 对照。

### 缓冲 / DDR（实现顺序建议）

1. 维持「采满停 → SPI → UART」吃透现核。  
2. 加长先加大 `FRAME_N` / 片上 BRAM（仍非实时）。  
3. 再上 DDR3 作深缓冲，浅 async_fifo 只留 CDC。  
4. 真 ADC/DAC 替换伪 ADC 时，接口对齐「并行样点 + adc_clk」，下游 FSM 可复用。

### 其它

- 回波实验：`uart_echo_core` + `host/uart_wave_echo.py`  
- 加压飞线：`lab_sys_ext` 默认 rPLL→**50 MHz sclk**；仍看 `spi_err`/示波器
