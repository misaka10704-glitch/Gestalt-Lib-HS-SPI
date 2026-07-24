# SPI-ADC

本文意图阐述一种，无实体ADC情况下，测试FPGA-SPI系统的方法，主要用于验证/理解以下情况：

1. ADC内部+SPI从机的发送逻辑，如AD7380
2. SPI-ADC与SPI-Master的通讯（飞线与片内）；50MHz情况下的现象
3. SPI—Master尾部的Async-fifo，以及uart->上位机逻辑
4. DDR控制器->DDR3，大数据量吞吐
5. 并行输出ADC+转换器+SPI从机设计，如AD9288->SPI

除此之外，期望SPI-Master部分可以直接复用在SPI-ADC上，只需经过一点调试，而非推翻重来；

## SPI—Master行为->上位机

与伪ADC对称：采样率看`cs_n`帧率，SCLK只负责本帧移位。主机须**Mode1**（旧`spi_master`若是Mode0要改）。

### 主链路

```
scheduler → spi_master(2-wire) → frame_pack → [async_fifo] → uart_tx → PC
```

每得到一个样点 = 一次CS帧：

1. `cs_n`↓
2. 16×SCLK，并行收SDOA(A)、SDOB(B)；MOSI可固定`0x0000`
3. `cs_n`↑；`bit_cnt≠15`则本帧作废
4. `{A,B}`打包UART发出；再采下一帧（或先入FIFO）

首样丢弃，与从机一致。

> UART固定帧（一点一帧）：`AA 55 | A_hi A_lo | B_hi B_lo | xor`（7B）；省带宽可只发4B，批量时帧头发一次`AA55+N`。

> 节奏：首版**停等**——发完7B再拉下一次CS，最稳。连续采须`f_cs×bytes×10 < baud`，否则FIFO满/空。

> 板子：逻辑派G1，CH340→`uart_tx` F12。115200约1.6k点/s(7B)；921600约11k；2M约23k。不够再提波特率或减字节；**本阶段不用DDR3**。

主机侧不做寄存器controller；可选`sample_proc`（丢首样、只发A、抽取）放在pack前。

## 第一种伪ADC（模仿AD7380）

### 真实行为模式

```
cs_n 输入片选
sclk 输入时钟
SDI  输入指令；主机->ADC，写寄存器
SDOA 输出数据；ADC->主机：通道A结果，或1-wire时A+B
SDOB 输出数据；2-wire时通道B；也可配成超限告警
```

> t_sclk的最小值为12.5ns，对应最大sclk为80MHz，这个频率由FPGA给；

> SDI用于设定模式寄存器（SPI传输16bit指令）：
>
> 命令帧结构(MSB_first) -> {WR , REGADDR[14:12] , DATA[11:0]}
>
> WR=1写，WR=0读；
>
> REGADDR为寄存器地址0-5；
>
> DATA为写入值，读的时候忽略；
>
> 2-wire命令：0xA000
>
> 1-wire命令：0xA100

> SDO用于发送数据：
>
> 2-wire模式，SDO输出16bits
>
> 1-wire模式，SDOA先输出16bits的ADCA数据，再输出16bits的ADCB数据，跑满32bits

AD7380比较特殊，是一种CPOL=0，CPHA=1的SPI mode1的SPI ADC，因此需要对应修改模式；并且AD7380每读一帧，cs_n都要下拉一次，因此伪装需要按着这个写；

### 伪装方案

主链路：

1. wave在adc_clk上跑，sample_reg每拍并行更新（深度1，宽16bit;不移位）
2. cs_n↓（同一沿）:

sample_cdc <- sample_reg;

tx_hold <- prev;

prev <- sample_cdc;

**第2次cs_n↓起为有效输出；**

3. cs_n=0:sclk驱动bit_cnt，发送数据直至bit_cnt=15
4. cs_n↑:帧结束；（bit_cnt若未到15，无效帧）
5. 下一帧，仍然需要cs_n↓

默认2-wire，不留controller；但是wave_sel保留，以选取triangle/sine；其余做prev A/B（也可以将B做成A的移相版本）
