# Gestalt-Lib-HS-SPI · unified simulation
#   make -C async_fifo sim
#   make -C spi_slave_controller sim
#   make -C spi_master sim
#   make -C spi_slave sim
#   make all / clean

.PHONY: all clean \
	async_fifo-sim async_fifo-clean \
	spi_ctrl-sim spi_master-sim spi_slave-sim \
	spi_ctrl-clean spi_master-clean spi_slave-clean

all: async_fifo-sim spi_ctrl-sim spi_master-sim spi_slave-sim

async_fifo-sim:
	$(MAKE) -C async_fifo sim

spi_ctrl-sim:
	$(MAKE) -C spi_slave_controller sim

spi_master-sim:
	$(MAKE) -C spi_master sim

spi_slave-sim:
	$(MAKE) -C spi_slave sim

async_fifo-clean:
	$(MAKE) -C async_fifo clean

spi_ctrl-clean:
	$(MAKE) -C spi_slave_controller clean

spi_master-clean:
	$(MAKE) -C spi_master clean

spi_slave-clean:
	$(MAKE) -C spi_slave clean

clean: async_fifo-clean spi_ctrl-clean spi_master-clean spi_slave-clean
