# spi_slave = controller + shift
#   make sim / wave / clean

OUT_DIR  := out
RTL_CTRL := ../../spi_slave_controller.v
RTL_SHFT := ../../spi_slave_shift.v
IVERILOG := iverilog
VVP      := vvp
GTKWAVE  := gtkwave
IVFLAGS  := -g2012 -Wall

.PHONY: all sim wave clean dirs

all: sim

dirs:
	@mkdir -p $(OUT_DIR)

$(OUT_DIR)/tb.out: $(RTL_CTRL) $(RTL_SHFT) tb/tb_spi_slave.v | dirs
	$(IVERILOG) $(IVFLAGS) -o $@ $(RTL_CTRL) $(RTL_SHFT) tb/tb_spi_slave.v

sim: $(OUT_DIR)/tb.out
	cd $(OUT_DIR) && $(VVP) tb.out

wave: sim
	$(GTKWAVE) $(OUT_DIR)/wave.vcd &

clean:
	rm -rf $(OUT_DIR)
