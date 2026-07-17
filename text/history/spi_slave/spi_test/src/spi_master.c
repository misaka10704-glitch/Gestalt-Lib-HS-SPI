#include "spi_master.h"
#include "board.h"

#include <stddef.h>

void spi_master_init(void)
{
    spi_parameter_struct spi_init_struct;

    rcu_periph_clock_enable(SPI_SCK_CLK);
    rcu_periph_clock_enable(SPI_CLK);

    gpio_init(SPI_SCK_PORT, GPIO_MODE_AF_PP, GPIO_OSPEED_50MHZ, SPI_SCK_PIN);
    gpio_init(SPI_MOSI_PORT, GPIO_MODE_AF_PP, GPIO_OSPEED_50MHZ, SPI_MOSI_PIN);
    gpio_init(SPI_MISO_PORT, GPIO_MODE_IN_FLOATING, GPIO_OSPEED_50MHZ, SPI_MISO_PIN);
    gpio_init(SPI_CS_PORT, GPIO_MODE_OUT_PP, GPIO_OSPEED_50MHZ, SPI_CS_PIN);

    spi_cs_high();

    spi_i2s_deinit(SPI_PERIPH);
    spi_init_struct.trans_mode           = SPI_TRANSMODE_FULLDUPLEX;
    spi_init_struct.device_mode          = SPI_MASTER;
    spi_init_struct.frame_size           = SPI_FRAMESIZE_8BIT;
    spi_init_struct.clock_polarity_phase = SPI_CK_PL_LOW_PH_1EDGE; /* Mode 0 */
    spi_init_struct.nss                  = SPI_NSS_SOFT;
    spi_init_struct.prescale             = SPI_PRESCALER;
    spi_init_struct.endian               = SPI_ENDIAN_MSB;
    spi_init(SPI_PERIPH, &spi_init_struct);

    spi_enable(SPI_PERIPH);
}

void spi_cs_low(void)
{
    gpio_bit_reset(SPI_CS_PORT, SPI_CS_PIN);
}

void spi_cs_high(void)
{
    gpio_bit_set(SPI_CS_PORT, SPI_CS_PIN);
}

uint8_t spi_transfer_byte(uint8_t tx)
{
    while (RESET == spi_i2s_flag_get(SPI_PERIPH, SPI_FLAG_TBE)) {
    }
    spi_i2s_data_transmit(SPI_PERIPH, tx);

    while (RESET == spi_i2s_flag_get(SPI_PERIPH, SPI_FLAG_RBNE)) {
    }
    return (uint8_t)spi_i2s_data_receive(SPI_PERIPH);
}

bool spi_transfer(const uint8_t *tx, uint8_t *rx, uint32_t len)
{
    if (tx == NULL || rx == NULL || len == 0U) {
        return false;
    }

    spi_cs_low();
    for (uint32_t i = 0; i < len; i++) {
        rx[i] = spi_transfer_byte(tx[i]);
    }
    spi_cs_high();
    return true;
}
