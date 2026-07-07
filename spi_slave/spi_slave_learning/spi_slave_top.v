module spi_slave_top
#(
    parameter CPOL = 1'b0,
	parameter CPHA = 1'b0
)
(
 input wire sclk,
 input wire rst_n,
 input wire mosi,
 input wire cs_n,
 output wire miso
);

