#ifndef UART_CONSOLE_H
#define UART_CONSOLE_H

#include <stdint.h>

void uart_console_init(void);
void uart_putc(char c);
void uart_puts(const char *s);
void uart_put_hex8(uint8_t value);
void uart_put_hex_buf(const uint8_t *buf, uint32_t len);

#endif /* UART_CONSOLE_H */
