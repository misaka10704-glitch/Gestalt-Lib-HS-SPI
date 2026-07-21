# Gestalt-Lib-HS-SPI · unified simulation
#   make -C async_fifo sim1|sim2|sim|clean
#   make async_fifo-sim

.PHONY: all clean async_fifo-sim async_fifo-sim1 async_fifo-sim2 async_fifo-clean

all: async_fifo-sim

async_fifo-sim:
	$(MAKE) -C async_fifo sim

async_fifo-sim1:
	$(MAKE) -C async_fifo sim1

async_fifo-sim2:
	$(MAKE) -C async_fifo sim2

async_fifo-clean:
	$(MAKE) -C async_fifo clean

clean: async_fifo-clean
