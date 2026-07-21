#ifndef SPI_MASTER_H
#define SPI_MASTER_H

#include <stdint.h>
#include <stdbool.h>

void spi_master_init(void);
void spi_cs_low(void);
void spi_cs_high(void);
uint8_t spi_transfer_byte(uint8_t tx);
bool spi_transfer(const uint8_t *tx, uint8_t *rx, uint32_t len);

#endif /* SPI_MASTER_H */
