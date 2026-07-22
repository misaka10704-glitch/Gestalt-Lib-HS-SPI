`timescale 1ns / 1ps

/*
非理想版 lab_sys_ext：
  Master 的 SCLK/MOSI 从管脚打出，Slave 从另两脚收回。
  用两根飞线连接：
    飞线（顶排邻脚）：G15→G14 (SCLK), G16→H15 (MOSI)
    spi_sclk_o ──飞线──► spi_sclk_i
    spi_mosi_o ──飞线──► spi_mosi_i
  CS 仍片内直连（相对外线有相位差，更容易出建立/保持问题）。
*/
module lab_sys_ext#(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD = 115200
)
(
    input wire sys_clk,
    input wire [1:0] key,
    output wire [3:0] led,
    output wire uart_tx,
    // 飞线：两根线分别短接 o→i
    output wire spi_sclk_o,
    output wire spi_mosi_o,
    input wire spi_sclk_i,
    input wire spi_mosi_i
);

wire core_busy;
wire pulse_frame;
wire enable = key[1];
wire adc_clk;
wire spi_err_flag;
wire [7:0] spi_err_cnt;
wire spi_cs_n;
wire spi_miso;

lab_sys_core#(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(BAUD),
    .ADC_CLK_HZ(1_000_000),
    .FRAME_N(128),
    .SPI_CLK_DIV(4), // 可改 2 加压
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
assign led[2] = spi_err_flag; // 飞线松/错相时应变亮
assign led[3] = |spi_err_cnt;

endmodule
