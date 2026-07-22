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

`XOR` 含 `ERR`；`ERR` = 本拍 SPI 错字节数。

## 实验系统（lab_sys）

```
连续采 N=128 → SPI 整段回环 → 比对 ERR → UART 单帧上送
上位机默认只画最新一帧（不跨帧拼）
```

- `Projects/lab_sys/` — 片内理想（`spi_err` 应≈0）
- `Projects/lab_sys_ext/` — 飞线顶排邻脚：`G15→G14`(SCLK)、`G16→H15`(MOSI)

| 量 | 默认 |
|----|------|
| adc_clk | 1 MHz |
| FRAME_N | 128 |
| SPI sclk | 6.25 MHz（DIV=4） |

## 其它

- 回波：`uart_echo_core` + `host/uart_wave_echo.py`
