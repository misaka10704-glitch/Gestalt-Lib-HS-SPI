# Async FIFO sim (Icarus + optional GTKWave)
#   make sim1 / wave1   — empty/full  → sim/wave1.vcd
#   make sim2 / wave2   — read/write  → sim/wave2.vcd
#   make sim            — both
#   make clean

SIM_DIR  := sim
IVERILOG := iverilog
VVP      := vvp
GTKWAVE  := gtkwave
IVFLAGS  := -g2012 -Wall

RTL := async_fifo.v tb/wave_probes.v

.PHONY: all sim sim1 sim2 wave1 wave2 compile1 compile2 clean dirs

all: sim

dirs:
	@mkdir -p $(SIM_DIR)

$(SIM_DIR)/tb_wave1.out: async_fifo.v tb/wave_probes.v tb/tb_wave1.v | dirs
	$(IVERILOG) $(IVFLAGS) -o $@ async_fifo.v tb/wave_probes.v tb/tb_wave1.v

$(SIM_DIR)/tb_wave2.out: async_fifo.v tb/wave_probes.v tb/tb_wave2.v | dirs
	$(IVERILOG) $(IVFLAGS) -o $@ async_fifo.v tb/wave_probes.v tb/tb_wave2.v

sim1: $(SIM_DIR)/tb_wave1.out
	cd $(SIM_DIR) && $(VVP) ../$(SIM_DIR)/tb_wave1.out

sim2: $(SIM_DIR)/tb_wave2.out
	cd $(SIM_DIR) && $(VVP) ../$(SIM_DIR)/tb_wave2.out

sim: sim1 sim2

wave1: sim1
	$(GTKWAVE) $(SIM_DIR)/wave1.vcd &

wave2: sim2
	$(GTKWAVE) $(SIM_DIR)/wave2.vcd &

clean:
	rm -rf $(SIM_DIR)
