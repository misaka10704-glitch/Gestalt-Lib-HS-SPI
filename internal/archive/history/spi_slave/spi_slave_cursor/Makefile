# SPI slave timing simulation (Icarus Verilog + GTKWave)
# Usage:
#   make sim              # compile + run tb_spi_slave
#   make wave             # open waveform
#   make clean

TB      ?= tb_spi_slave
TOP     ?= $(TB)
SIM_DIR := sim
BUILD   := $(SIM_DIR)/$(TB).out

RTL_SRCS := \
	src/spi_controller.v \
	src/spi_shift_register.v \
	src/spi_system_interface.v \
	src/spi_slave_top.v
TB_SRCS  := tb/$(TB).v

IVERILOG := iverilog
IVFLAGS  := -g2012 -Wall -I src -I tb -o $(BUILD)
VVP      := vvp
GTKWAVE  := gtkwave

.PHONY: all sim wave compile run clean dirs

all: sim

dirs:
	@mkdir -p $(SIM_DIR)

compile: dirs $(BUILD)

$(BUILD): $(RTL_SRCS) $(TB_SRCS)
	$(IVERILOG) $(IVFLAGS) $(RTL_SRCS) $(TB_SRCS)

run: compile
	cd $(SIM_DIR) && $(VVP) ../$(BUILD) -l $(TB).log

sim: run

wave: sim
	$(GTKWAVE) $(SIM_DIR)/wave.vcd &

clean:
	rm -rf $(SIM_DIR)
