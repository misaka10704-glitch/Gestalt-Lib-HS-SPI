# Gestalt-Lib-HS-SPI

| 路径 | 内容 |
|------|------|
| `async_fifo.v` | RTL（仓库根路径） |
| `sim/` | 统一仿真中心（各 IP 子目录 + Makefile） |
| `internal/docs/` | SPI / Slave / 寄存器笔记、仿真说明 |
| `internal/Research/` | 参考 PDF |
| `internal/archive/` | 历史工程 |
| `internal/README.md` | 本文件（项目说明） |
| `internal/.gitignore` | 忽略规则正文（改后执行 `cp internal/.gitignore .gitignore` 同步根目录副本） |

## 1. 项目背景

本项目面向课题组实际需求，旨在构建 FPGA 与 ADC 之间的高速数据传输链路。

在系统架构中，模拟前端（AFE）与 ADC 负责信号采集，FPGA 负责数据接收、缓存与处理，并经由高速 SPI 将数据分别传输至 MCU 与上位机。鉴于 ADC 输出数据量巨大，链路须采用高带宽的高速 SPI 接口。

```
AFE / ADC
    |
    |
 FPGA
    |
 FIFO / Data Processing
    |
 High-Speed SPI
    |
 MCU
    |
 UART / USB
    |
 PC Visualization
```

在脑机接口系统中，模拟前端（AFE）负责微弱生物信号采集与模拟处理，而 FPGA 负责高速数字数据接收、缓存、处理和传输。

本项目重点关注：

* FPGA 数据采集链路
* 高速 SPI 通信
* 数据缓存与传输
* 上位机实时显示
* 硬件验证流程

---

# 2. 项目目标

搭建一个可扩展的数据采集框架：

```
FPGA
 |
 SPI
 |
 MCU
 |
 PC
```

实现：

* FPGA 产生/采集数据
* SPI 稳定传输
* MCU 接收数据
* 上位机实时显示波形

后续可扩展：

```
ADC
 |
 FPGA
 |
 SPI
 |
 MCU
 |
 PC
```

形成完整的数据采集验证平台。

---

# 3. 硬件平台

## FPGA

当前优先使用：

* Gowin FPGA 开发板（MCU + FPGA）

原因：

* 集成 MCU
* 方便搭建 SPI 通信
* 降低硬件连接复杂度

后续可扩展：

* Altera FPGA 开发板

---

# 4. 开发路线

## Phase 1：SPI 基础 IP

目标：

完成可复用 SPI Controller。

实现：

### SPI Slave

重点：

* FPGA 作为数据接收端
* 支持 MCU 主机访问

功能：

* CPOL
* CPHA
* Shift Register
* CS 控制
* 数据收发

### SPI Master

实现：

* SCLK 生成
* CS 控制
* 数据发送

验证：

仿真波形：

```
CS
SCLK
MOSI
MISO
```

---

# 5. Phase 2：数据链路打通

首先不接真实 ADC。

使用 FPGA 内部数据源：

例如：

* Counter
* ROM 波形
* 测试序列

数据流：

```
FPGA Test Data

↓

SPI

↓

MCU

↓

UART/USB

↓

PC
```

目标：

验证：

* 数据正确性
* 通信稳定性
* 端到端链路

---

# 6. Phase 3：上位机波形显示

替代原 OLED 显示方案（课设项目）。

旧方案：

```
ADC
 |
FPGA
 |
I2C OLED
 |
Waveform Display
```

新方案：

```
FPGA
 |
SPI
 |
MCU
 |
PC
 |
Python Visualization
```

上位机功能：

* 实时波形显示
* 数据保存
* 数据分析
* 通信测试

---

# 7. 与 AD9288 项目的衔接

此前完成过：

```
AD9288
 |
FPGA
 |
数字处理
 |
OLED 波形显示
```

该项目验证了：

* ADC 数据采集
* FPGA 数据处理
* 实时显示流程

但由于：

* 缺少实验仪器
* 高速 ADC 飞线连接存在信号完整性问题

因此新的项目先采用 FPGA 内部数据源，优先完成数字链路。

后续替换：

```
FPGA Test Data

↓

AD9288 ADC Data
```

形成：

```
AD9288
 |
FPGA
 |
FIFO
 |
High-Speed SPI
 |
MCU
 |
PC
```

---

# 8. 技术重点

## SPI 本身

基础：

* SPI Mode
* CPOL/CPHA
* 时序控制
* 数据移位

## 高速数据链路

重点：

* FIFO
* Burst Transfer
* 数据缓存
* 时钟域处理
* 数据完整性验证

## FPGA 工程能力

训练：

* Verilog RTL
* FSM
* 时序分析
* 模块化设计
* 硬件验证

---

# 9. 后续扩展方向

可能扩展：

* Multi-channel ADC interface
* FIFO buffering
* DMA-like data transfer
* QSPI
* AXI interface
* 高速数字接口

---

# 10. 项目意义

本项目目标是建立一个 FPGA + MCU 的实时数据采集与传输框架。

应用方向：

* 生物信号采集
* ADC 验证
* FPGA 原型验证

核心能力：

```
Signal Acquisition

↓

Digital Processing

↓

High-Speed Data Transfer

↓

Visualization
```

通过该项目建立从硬件采集到上位机分析的完整工程闭环。
