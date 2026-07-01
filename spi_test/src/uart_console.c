#include "uart_console.h"
#include "board.h"

#include <stdio.h>

void uart_console_init(void)
{
    rcu_periph_clock_enable(UART_TX_CLK);
    rcu_periph_clock_enable(UART_CLK);

    gpio_init(UART_TX_PORT, GPIO_MODE_AF_PP, GPIO_OSPEED_50MHZ, UART_TX_PIN);
    gpio_init(UART_RX_PORT, GPIO_MODE_IN_FLOATING, GPIO_OSPEED_50MHZ, UART_RX_PIN);

    usart_deinit(UART_PERIPH);
    usart_baudrate_set(UART_PERIPH, UART_BAUDRATE);
    usart_word_length_set(UART_PERIPH, USART_WL_8BIT);
    usart_stop_bit_set(UART_PERIPH, USART_STB_1BIT);
    usart_parity_config(UART_PERIPH, USART_PM_NONE);
    usart_hardware_flow_rts_config(UART_PERIPH, USART_RTS_DISABLE);
    usart_hardware_flow_cts_config(UART_PERIPH, USART_CTS_DISABLE);
    usart_receive_config(UART_PERIPH, USART_RECEIVE_ENABLE);
    usart_transmit_config(UART_PERIPH, USART_TRANSMIT_ENABLE);
    usart_enable(UART_PERIPH);
}

void uart_putc(char c)
{
    usart_data_transmit(UART_PERIPH, (uint8_t)c);
    while (RESET == usart_flag_get(UART_PERIPH, USART_FLAG_TBE)) {
    }
}

void uart_puts(const char *s)
{
    while (*s != '\0') {
        uart_putc(*s++);
    }
}

static const char hex_digits[] = "0123456789ABCDEF";

void uart_put_hex8(uint8_t value)
{
    uart_putc(hex_digits[(value >> 4) & 0x0FU]);
    uart_putc(hex_digits[value & 0x0FU]);
}

void uart_put_hex_buf(const uint8_t *buf, uint32_t len)
{
    for (uint32_t i = 0; i < len; i++) {
        uart_put_hex8(buf[i]);
        if (i + 1U < len) {
            uart_putc(' ');
        }
    }
}
