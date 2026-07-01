#ifndef BOARD_H
#define BOARD_H

/*
 * GD32F303C8T6 board pin placeholders.
 * Wire these to the FPGA SPI slave and USB-UART bridge when hardware is ready.
 */

#include "gd32f30x.h"

/* ---- UART console (USART0) ---- */
#define UART_PERIPH       USART0
#define UART_CLK          RCU_USART0
#define UART_BAUDRATE     115200U

#define UART_TX_PORT      GPIOA
#define UART_TX_PIN       GPIO_PIN_9
#define UART_TX_CLK       RCU_GPIOA

#define UART_RX_PORT      GPIOA
#define UART_RX_PIN       GPIO_PIN_10
#define UART_RX_CLK       RCU_GPIOA

/* ---- SPI master (SPI0, Mode 0) ---- */
#define SPI_PERIPH        SPI0
#define SPI_CLK           RCU_SPI0

#define SPI_SCK_PORT      GPIOA
#define SPI_SCK_PIN       GPIO_PIN_5
#define SPI_SCK_CLK       RCU_GPIOA

#define SPI_MISO_PORT     GPIOA
#define SPI_MISO_PIN      GPIO_PIN_6

#define SPI_MOSI_PORT     GPIOA
#define SPI_MOSI_PIN      GPIO_PIN_7

#define SPI_CS_PORT       GPIOA
#define SPI_CS_PIN        GPIO_PIN_4

/* Initial SPI clock: 1 MHz (APB2 / prescaler). Adjust after link-up. */
#define SPI_PRESCALER     SPI_PSC_64

#endif /* BOARD_H */
