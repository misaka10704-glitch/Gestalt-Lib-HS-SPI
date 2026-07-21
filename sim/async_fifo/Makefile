# Async FIFO sim (Icarus + optional GTKWave)
# RTL: ../../async_fifo.v
#   make sim1 / wave1   — empty/full  → out/wave1.vcd
#   make sim2 / wave2   — read/write  → out/wave2.vcd
#   make sim            — both
#   make clean

OUT_DIR  := out
RTL      := ../../async_fifo.v
IVERILOG := iverilog
VVP      := vvp
GTKWAVE  := gtkwave
IVFLAGS  := -g2012 -Wall

.PHONY: all sim sim1 sim2 wave1 wave2 clean dirs

all: sim

dirs:
	@mkdir -p $(OUT_DIR)

$(OUT_DIR)/tb_wave1.out: $(RTL) tb/wave_probes.v tb/tb_wave1.v | dirs
	$(IVERILOG) $(IVFLAGS) -o $@ $(RTL) tb/wave_probes.v tb/tb_wave1.v

$(OUT_DIR)/tb_wave2.out: $(RTL) tb/wave_probes.v tb/tb_wave2.v | dirs
	$(IVERILOG) $(IVFLAGS) -o $@ $(RTL) tb/wave_probes.v tb/tb_wave2.v

sim1: $(OUT_DIR)/tb_wave1.out
	cd $(OUT_DIR) && $(VVP) ../$(OUT_DIR)/tb_wave1.out

sim2: $(OUT_DIR)/tb_wave2.out
	cd $(OUT_DIR) && $(VVP) ../$(OUT_DIR)/tb_wave2.out

sim: sim1 sim2

wave1: sim1
	$(GTKWAVE) $(OUT_DIR)/wave1.vcd wave.gtkw &

wave2: sim2
	$(GTKWAVE) $(OUT_DIR)/wave2.vcd wave.gtkw &

clean:
	rm -rf $(OUT_DIR)
