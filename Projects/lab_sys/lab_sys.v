`timescale 1ns / 1ps

/*
理想版：片内短接 Master→Slave（SCLK/MOSI）
*/
module lab_sys#(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD = 115200
)
(
    input wire sys_clk,
    input wire [1:0] key,
    output wire [3:0] led,
    output wire uart_tx
);

wire core_busy;
wire pulse_frame;
wire enable = key[1];
wire adc_clk;
wire spi_err_flag;
wire [7:0] spi_err_cnt;
wire spi_sclk_o, spi_mosi_o, spi_cs_n, spi_miso;
wire spi_sclk_i = spi_sclk_o;
wire spi_mosi_i = spi_mosi_o;

lab_sys_core#(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(BAUD),
    .ADC_CLK_HZ(1_000_000),
    .FRAME_N(128),
    .SPI_CLK_DIV(4),
    .AFIFO_DEPTH(512),
    .WAVE_SEL(1)
) u_core (
    .clk(sys_clk),
    .rst_n(key[0]),
    .enable(enable),
    .uart_tx(uart_tx),
    .busy(core_busy),
    .pulse_frame(pulse_frame),
    .adc_clk(adc_clk),
    .spi_err_flag(spi_err_flag),
    .spi_err_cnt(spi_err_cnt),
    .spi_sclk_o(spi_sclk_o),
    .spi_mosi_o(spi_mosi_o),
    .spi_cs_n(spi_cs_n),
    .spi_sclk_i(spi_sclk_i),
    .spi_mosi_i(spi_mosi_i),
    .spi_miso(spi_miso)
);

reg [25:0] hb_cnt;
reg heartbeat;

always@(posedge sys_clk or negedge key[0])begin
    if(!key[0])begin
        hb_cnt<=0;
        heartbeat<=0;
    end
    else begin
        if(hb_cnt == CLK_FREQ/2-1)begin
            hb_cnt<=0;
            heartbeat<=~heartbeat;
        end
        else
            hb_cnt<=hb_cnt+1'b1;
    end
end

assign led[0] = core_busy;
assign led[1] = heartbeat;
assign led[2] = spi_err_flag;
assign led[3] = |spi_err_cnt;

endmodule
