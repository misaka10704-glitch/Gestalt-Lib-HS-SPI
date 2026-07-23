# spi_master sim
#   make sim / wave / clean

OUT_DIR  := out
RTL      := ../../spi_master.v
IVERILOG := iverilog
VVP      := vvp
GTKWAVE  := gtkwave
IVFLAGS  := -g2012 -Wall

.PHONY: all sim wave clean dirs

all: sim

dirs:
	@mkdir -p $(OUT_DIR)

$(OUT_DIR)/tb.out: $(RTL) tb/tb_spi_master.v | dirs
	$(IVERILOG) $(IVFLAGS) -o $@ $(RTL) tb/tb_spi_master.v

sim: $(OUT_DIR)/tb.out
	cd $(OUT_DIR) && $(VVP) tb.out

wave: sim
	$(GTKWAVE) $(OUT_DIR)/wave.vcd &

clean:
	rm -rf $(OUT_DIR)
