`timescale 1ns / 1ps

/*
立创·逻辑派 FPGA-G1 板级封装（工程目录 projects/spi_verify/）
LED 避开 SSPI 专用脚 C10/T10
*/
module spi_verify#(
    parameter USE_PLL = 0,
    parameter LOOPBACK = 1,
    parameter CLK_DIV = 8,
    parameter XFER_N = 8
)
(
    input wire sys_clk,
    input wire [1:0] key,
    output wire [3:0] led, //R9,R7,N6,P7
    output wire spi_sclk,
    output wire spi_mosi,
    input wire spi_miso_ext,
    output wire spi_cs_n
);

wire pll_clk = sys_clk;
wire pll_locked = 1'b1;

wire led_busy, led_pass, led_fail, led_overflow;

reg miso_ext_r;
always@(posedge sys_clk)begin
    miso_ext_r <= spi_miso_ext;
end

spi_verify_top#(
    .USE_PLL(USE_PLL),
    .LOOPBACK(LOOPBACK),
    .CLK_DIV(CLK_DIV),
    .XFER_N(XFER_N)
) u_core (
    .clk(sys_clk),
    .rst_n(key[0]),
    .pll_clk(pll_clk),
    .pll_locked(pll_locked),
    .btn_start(key[1]),
    .led_busy(led_busy),
    .led_pass(led_pass),
    .led_fail(led_fail),
    .led_overflow(led_overflow),
    .spi_sclk(spi_sclk),
    .spi_mosi(spi_mosi),
    .spi_miso_ext(spi_miso_ext),
    .spi_cs_n(spi_cs_n)
);

// R9忙 / R7失败 / N6溢出 / P7采样外部MISO（保脚）；pass 与 fail 挤在可视脚：用 R7 表示 fail，pass 用「非 fail 且曾完成」难；
// 四灯：busy, pass|!fail 简化为 busy / pass / fail|overflow 合并
assign led[0] = led_busy;                        // R9
assign led[1] = led_pass;                        // R7（原绿脚不可用，改蓝脚显示 pass）
assign led[2] = led_fail | led_overflow;         // N6
assign led[3] = miso_ext_r;                      // P7 保 MISO 输入

endmodule
