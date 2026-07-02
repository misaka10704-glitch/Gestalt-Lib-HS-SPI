# SPI 基础

本文档介绍 SPI 是什么、为什么在本项目中选用它。Slave / Master 的具体实现见各自子目录文档。

---

## 1. 什么是 SPI

**SPI**（Serial Peripheral Interface，串行外设接口）是一种**同步、全双工**的串行通信总线，由 Motorola 提出，广泛用于 MCU、FPGA、传感器、Flash、ADC 等芯片之间的短距离数据传输。

与 UART 的「发完就走、靠波特率对齐」不同，SPI 额外提供一根**时钟线**，收发双方在同一时钟边沿上移位，时序关系明确，适合对速度和可靠性有要求的场景。

### 1.1 基本信号

| 信号 | 全称 | 方向（相对 Master） | 作用 |
|------|------|---------------------|------|
| SCLK | Serial Clock | 输出 | 同步时钟，由 Master 产生 |
| MOSI | Master Out Slave In | 输出 | Master 发送、Slave 接收 |
| MISO | Master In Slave Out | 输入 | Slave 发送、Master 接收 |
| CS   | Chip Select（常写作 CS_N，低有效） | 输出 | 选中某个 Slave，一 Master 可挂多 Slave |

```
        Master                          Slave
    ┌──────────┐                   ┌──────────┐
    │          │──── SCLK ────────→│          │
    │          │──── MOSI ────────→│          │
    │          │←─── MISO ─────────│          │
    │          │──── CS_N ────────→│          │
    └──────────┘                   └──────────┘
```

一次传输以 **CS 拉低** 开始，在 **SCLK** 驱动下逐 bit 移位；**CS 拉高** 结束当前帧。Master 发 MOSI 的同时可以读 MISO，因此是**全双工**（每时钟周期交换 1 bit）。

### 1.2 Master 与 Slave

- **Master（主机）**：提供 SCLK，发起传输，控制 CS。
- **Slave（从机）**：响应 Master 的时钟，在 CS 有效期间收发数据。

系统中通常只有一个 Master，可有多个 Slave（各用独立 CS 线，或菊花链等方式扩展）。本项目中 **MCU 作 Master、FPGA 作 Slave** 是常见组合；后续高速数据链路里，角色与带宽需求可能再调整，但电气层仍是同一套 SPI 时序。

### 1.3 四种模式（CPOL / CPHA）

SPI 不规定唯一时序，而是用 **CPOL**（时钟极性）和 **CPHA**（时钟相位）组合成 4 种 Mode（0–3），约定「在哪一个 SCLK 边沿采样、哪一个边沿改变数据」。

| Mode | CPOL | CPHA | 常见用途 |
|------|------|------|----------|
| 0 | 0 | 0 | 最常见，多数 MCU / 外设默认 |
| 1 | 0 | 1 | |
| 2 | 1 | 0 | |
| 3 | 1 | 1 | |

**Master 与 Slave 必须使用相同 Mode**，否则 bit 会错位。工程上先确认对端（如 Gowin 片上 MCU 或 STM32）默认配置，再定 FPGA 侧参数；实现细节在 Slave IP 文档中展开。

### 1.4 与常见接口的对比

| 接口 | 线数 | 时钟 | 典型特点 |
|------|------|------|----------|
| UART | 2（TX/RX） | 异步，靠波特率 | 简单、距离可稍长，速度较低 |
| I2C | 2（SDA/SCL） | 同步 | 多设备、省引脚，速度中等，协议较复杂 |
| SPI | 4+（SCLK/MOSI/MISO/CS…） | 同步，Master 出时钟 | 实现简单、速度高、全双工，引脚随 Slave 数增加 |

---

## 2. 为什么需要 SPI

### 2.1 问题：模块之间如何传数据

一块板子上往往有 FPGA、MCU、ADC、存储器等多种器件。它们需要：

- 传**配置 / 状态**（寄存器读写）
- 传**采样数据**（波形、测量结果）
- 在**确定时间内**传完，并保证**bit 不错**

若每种连接各写一套自定义并行口或 GPIO  bit-bang，硬件和软件都难以复用。SPI 作为**事实标准**，芯片普遍自带 SPI 控制器，驱动与例程多，有利于快速打通链路。

### 2.2 SPI 适合本项目的理由

结合 [Readme.md](./Readme.md) 中的系统架构：

```
AFE / ADC → FPGA →（FIFO / 处理）→ SPI → MCU → UART / USB → PC
```

选用 SPI 主要基于：

1. **速度**  
   ADC 与 FPGA 侧数据量大，MCU 到 PC 之前需要一条比 UART 更宽的通路。SPI 在板级短连线上可达数 MHz 至数十 MHz（高速 / QSPI 可更高），适合批量传采样块。

2. **实现成本**  
   RTL 侧：移位寄存器 + 有限状态机即可搭出可验证的 Slave。MCU 侧：硬件 SPI 外设 + DMA 即可收 burst，无需复杂协议栈。

3. **全双工与可控时序**  
   同步时钟便于 FPGA 做时序约束和仿真；CS 帧边界清晰，利于定义「一包多少字节、何时结束」的 burst 协议。

4. **与现有平台匹配**  
   当前优先 Gowin **MCU + FPGA 一体**开发板：片间 SPI 走线短、延迟小，适合作为 Phase 1 验证平台，再扩展到独立 FPGA + 外接 MCU。

5. **可演进**  
   标准 SPI 跑通后，可沿同一套分层架构扩展 FIFO、长 burst、更高 SCLK，乃至 QSPI 等，而不必更换整条产品思路。

### 2.3 SPI 不解决什么

明确边界有助于设计时分清层次：

- **不是长距离传输**：通常限于 PCB 级、厘米级；上 PC 仍靠 MCU 的 USB / UART / 以太网等。
- **不自带高级协议**：多字节帧、校验、流控需在上层（寄存器 map、帧头、FIFO）自行定义。
- **引脚随 Slave 增加**：每个 Slave 一根 CS（或额外译码），设备很多时 I2C 可能更省脚；本项目中设备数量少，SPI 更合适。

---

## 3. 在本项目中的位置

SPI 在本工程中既是 **Phase 1 的学习与 IP 目标**，也是 **后续数据采集链路的骨干**：

| 阶段 | SPI 的作用 |
|------|------------|
| Phase 1 | 掌握 Mode、时序、移位；完成可复用 SPI IP（Slave / Master） |
| Phase 2 | FPGA 测试数据源经 SPI 稳定传到 MCU，验证端到端 |
| Phase 3 | MCU / PC 侧波形显示；SPI 承载连续数据流 |
| 后续 | 接入 AD9288 等 ADC 后，FPGA 缓存的高吞吐数据仍经 SPI（或高速变体）送出 |

数据流概念：

```
数据源（Counter / ROM / 日后 ADC）
        ↓
   FPGA 处理与缓存
        ↓
      SPI  bulk 传输
        ↓
   MCU 转发与协议
        ↓
      上位机显示
```

---

## 4. 进一步阅读

- 项目总览与阶段规划：[Readme.md](./Readme.md)
- SPI Slave IP 规格与实现：[SPI_Slave/SPI_Slave.md](./SPI_Slave/SPI_Slave.md)
