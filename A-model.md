# 高速 SPI · IP 清单（首目录）

可复用 RTL 放在仓库根路径；具体上板/仿真工程见 `Projects/`。

1. 异步 FIFO — `async_fifo.v`
2. SPI 从机 — `spi_slave_controller.v` + `spi_slave_shift.v`
3. SPI 主机 — `spi_master.v`（PLL 预留）
4. 字节 FIFO 桥 — `spi_fifo_interface.v`
5. 验证核心 — `spi_verify_top.v`
6. UART TX / RX — `uart_tx.v`、`uart_rx.v`
7. 伪 ADC — `triangle_gen.v`（三角）、`sine_gen.v`（正弦 LUT）

7b. 同步 FIFO — `sync_fifo.v`（同时钟 UART 推流用）
8. UART 波形核心 — `uart_wave_core.v`（自发推流）
9. UART 回波核心 — `uart_echo_core.v`（上位机下发再回传）
10. **实验系统核心** — `lab_sys_core.v`（adc_clk 伪 ADC → async_fifo → SPI → UART）
11. **上板工程**
   - `Projects/spi_verify/` — SPI 主从回环自检（看 LED，无上位机）
   - `Projects/uart_wave/` — UART 回波显象
   - `Projects/lab_sys/` — 片内理想回环（金参考）
   - `Projects/lab_sys_ext/` — SCLK/MOSI 飞线非理想（复现 SPI 错）
12. SDRAM 控制器
13. 仲裁器及控制电路

板卡原厂资料：`Gowin/`（引脚表、手册；非工程顶层）。

---



## Projects ↔ 上位机 Python

依赖（一次即可）：

```bash
cd host
pip3 install -r requirements.txt
```

串口：板载 WCH，常用 `**/dev/cu.usbserial-20230814131**`（先 `--list` 确认）。  
**不要**同时开 WCHSerial / 其它串口助手，否则会抢口。


| 工程                     | 已下载的顶层            | 调用                                             | 作用                         |
| ---------------------- | ----------------- | ---------------------------------------------- | -------------------------- |
| `Projects/lab_sys/`    | `lab_sys`         | `python3 lab_sys_plot.py -p <口> -b 115200`     | 收伪 ADC→SPI→UART 帧并实时画图     |
| `Projects/uart_wave/`  | `uart_wave`（echo） | `python3 uart_wave_echo.py -p <口> -b 115200`   | PC 下发复杂波，FPGA 回传，对比绘图      |
| `Projects/uart_wave/`  | 若改回自发推流           | `python3 uart_wave_plot.py -p <口> -b 115200`   | 只收帧画图（配合 `uart_wave_core`） |
| （调试）                   | 任意推流工程            | `python3 uart_wave_listen.py -p <口> -b 115200` | 只打印收字节/帧，不画图               |
| `Projects/spi_verify/` | `spi_verify`      | —                                              | 无 py；用 LED / 板级自检          |


示例（当前主实验）：

```bash
cd /Users/misaka10704/Documents/Workspace/Gestalt-Lib-HS-SPI/host
python3 lab_sys_plot.py --list
python3 lab_sys_plot.py --port /dev/cu.usbserial-20230814131 --baud 115200
python3 lab_sys_plot.py --port /dev/cu.usbserial-20230814131
```

帧格式（`lab_sys` / `uart_wave` 共用）：`AA 55 | SEQ | N | DATA[N] | XOR`。  
脚本与工程必须匹配：下了 `lab_sys` 不要跑 `uart_wave_echo.py`（无 RX 回波）。