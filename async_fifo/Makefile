# Async FIFO timing simulation (Icarus Verilog + GTKWave)
# Usage:
#   make sim              # compile + run tb_async_fifo
#   make wave             # open waveform
#   make clean

TB      ?= tb_async_fifo
TOP     ?= $(TB)
SIM_DIR := sim
BUILD   := $(SIM_DIR)/$(TB).out

RTL_SRCS := async_fifo.v
TB_SRCS  := tb/$(TB).v

IVERILOG := iverilog
IVFLAGS  := -g2012 -Wall -o $(BUILD)
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
	$(GTKWAVE) $(SIM_DIR)/wave.vcd wave.gtkw &

clean:
	rm -rf $(SIM_DIR)
