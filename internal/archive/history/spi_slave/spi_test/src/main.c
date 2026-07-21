#include "board.h"
#include "spi_master.h"
#include "uart_console.h"

#include <stdio.h>
#include <string.h>

static void systick_config(void);
static void delay_ms(uint32_t ms);
static bool run_spi_case(const char *name, const uint8_t *tx, uint8_t *rx, uint32_t len);

static volatile uint32_t systick_ms = 0;

int main(void)
{
    systick_config();
    uart_console_init();
    spi_master_init();

    printf("\r\n=== GD32F303C8 SPI Test (Master, Mode 0) ===\r\n");
    printf("UART: %u baud | SPI: soft-CS, prescaler PSC_64\r\n", (unsigned)UART_BAUDRATE);
    printf("Purpose: exchange bytes with FPGA SPI slave, report via UART\r\n\r\n");

    uint8_t rx[8];
    const uint8_t single_55[] = {0x55U};
    const uint8_t single_aa[] = {0xAAU};
    const uint8_t burst[]     = {0x01U, 0x02U, 0x03U, 0x04U};

    run_spi_case("T1 single 0x55", single_55, rx, 1U);
    delay_ms(100U);

    run_spi_case("T2 single 0xAA", single_aa, rx, 1U);
    delay_ms(100U);

    run_spi_case("T3 burst 4 bytes", burst, rx, 4U);
    delay_ms(100U);

    printf("\r\nEntering periodic echo poll (1 Hz)...\r\n");

    uint8_t counter = 0U;
    while (1) {
        uint8_t tx_byte = counter++;
        uint8_t rx_byte = 0U;

        if (run_spi_case("poll", &tx_byte, &rx_byte, 1U)) {
            printf("  poll TX=%02X RX=%02X %s\r\n",
                   tx_byte,
                   rx_byte,
                   (tx_byte == rx_byte) ? "[match]" : "[diff]");
        }
        delay_ms(1000U);
    }
}

static bool run_spi_case(const char *name, const uint8_t *tx, uint8_t *rx, uint32_t len)
{
    uint8_t local_rx[8];

    if (len > sizeof(local_rx)) {
        printf("[ERR] %s: len=%lu too large\r\n", name, (unsigned long)len);
        return false;
    }

    memset(local_rx, 0, len);
    if (!spi_transfer(tx, local_rx, len)) {
        printf("[ERR] %s: spi_transfer failed\r\n", name);
        return false;
    }

    if (rx != NULL) {
        memcpy(rx, local_rx, len);
    }

    printf("[%s] TX: ", name);
    uart_put_hex_buf(tx, len);
    printf(" | RX: ");
    uart_put_hex_buf(local_rx, len);
    printf("\r\n");
    return true;
}

static void systick_config(void)
{
    if (SysTick_Config(SystemCoreClock / 1000U)) {
        while (1) {
        }
    }
    nvic_priority_group_set(NVIC_PRIGROUP_PRE4_SUB0);
}

static void delay_ms(uint32_t ms)
{
    uint32_t start = systick_ms;
    while ((systick_ms - start) < ms) {
    }
}

void SysTick_Handler(void)
{
    systick_ms++;
}

void NMI_Handler(void) {}
void HardFault_Handler(void) { while (1) {} }
void MemManage_Handler(void) { while (1) {} }
void BusFault_Handler(void) { while (1) {} }
void UsageFault_Handler(void) { while (1) {} }
void SVC_Handler(void) {}
void DebugMon_Handler(void) {}
void PendSV_Handler(void) {}
