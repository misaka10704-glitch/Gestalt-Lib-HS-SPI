`timescale 1ns / 1ps

/*
lab_sys_ext：飞线 SPI + PLL 加压对比

  key[0] = 复位
  key[1] 短按 = 慢/快分频切换（下一帧生效；Master IDLE 才改 DIV）

  eng 固定 rPLL 200M（不在 sys↔pll 间切钟）：
    关加压：DIV=16 → SCLK=6.25M（基线）
    开加压：DIV=2  → SCLK=50M

  USE_FLYWIRE=0：片内短接，不依赖飞线，用于确认 UART 仍活着
  USE_FLYWIRE=1：飞线（G15→G14 SCLK，G16→H15 MOSI）

  LED0：加压时闪
  LED1：请求加压
  LED2：err
  LED3：pll lock
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
    output wire spi_sclk_o,
    output wire spi_mosi_o,
    input wire spi_sclk_i,
    input wire spi_mosi_i
);

localparam USE_FLYWIRE = 1'b0;

wire core_busy;
wire pulse_frame;
wire adc_clk;
wire spi_err_flag;
wire [7:0] spi_err_cnt;
wire spi_cs_n;
wire spi_miso;
wire pll_on;

wire pll_clk_200;
wire pll_clk_200_p;
wire pll_locked;

wire sclk_to_slv = USE_FLYWIRE ? spi_sclk_i : spi_sclk_o;
wire mosi_to_slv = USE_FLYWIRE ? spi_mosi_i : spi_mosi_o;

gowin_rpll_200m u_pll (
    .clkin(sys_clk),
    .clkout(pll_clk_200),
    .clkoutp(pll_clk_200_p),
    .lock(pll_locked)
);

localparam integer DEB_CYC = CLK_FREQ / 1000 * 20;

reg use_fast_req;
reg [2:0] key1_sync;
reg key1_f;
reg [31:0] deb_cnt;

always@(posedge sys_clk or negedge key[0])begin
    if(!key[0])begin
        key1_sync<=3'b111;
        key1_f<=1'b1;
        deb_cnt<=0;
    end
    else begin
        key1_sync<={key1_sync[1:0], key[1]};
        if(key1_sync[2] == key1_f)
            deb_cnt<=0;
        else if(deb_cnt >= DEB_CYC[31:0])begin
            key1_f<=key1_sync[2];
            deb_cnt<=0;
        end
        else
            deb_cnt<=deb_cnt+32'd1;
    end
end

reg key1_f_d;
wire key1_fall = key1_f_d & ~key1_f;

always@(posedge sys_clk or negedge key[0])begin
    if(!key[0])begin
        use_fast_req<=1'b0;
        key1_f_d<=1'b1;
    end
    else begin
        key1_f_d<=key1_f;
        if(key1_fall)
            use_fast_req<=~use_fast_req;
    end
end

reg [24:0] blink_cnt;
reg blink;
always@(posedge sys_clk or negedge key[0])begin
    if(!key[0])begin
        blink_cnt<=0;
        blink<=0;
    end
    else if(blink_cnt == CLK_FREQ/4-1)begin
        blink_cnt<=0;
        blink<=~blink;
    end
    else
        blink_cnt<=blink_cnt+25'd1;
end

lab_sys_core#(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(BAUD),
    .ADC_CLK_HZ(1_000_000),
    .FRAME_N(128),
    .SPI_CLK_DIV(16),      // eng=200M → SCLK=6.25M
    .SPI_CLK_DIV_FAST(2),  // eng=200M → SCLK=50M
    .SPI_PULSE_HOLD(16),
    .SPI_TIMEOUT_CYCLES(500_000),
    .AFIFO_DEPTH(512),
    .WAVE_SEL(1)
) u_core (
    .clk(sys_clk),
    .rst_n(key[0]),
    .enable(1'b1),
    .use_fast(use_fast_req),
    .pll_clk(pll_clk_200),
    .pll_locked(pll_locked),
    .fast_on(pll_on),
    .uart_tx(uart_tx),
    .busy(core_busy),
    .pulse_frame(pulse_frame),
    .adc_clk(adc_clk),
    .spi_err_flag(spi_err_flag),
    .spi_err_cnt(spi_err_cnt),
    .spi_sclk_o(spi_sclk_o),
    .spi_mosi_o(spi_mosi_o),
    .spi_cs_n(spi_cs_n),
    .spi_sclk_i(sclk_to_slv),
    .spi_mosi_i(mosi_to_slv),
    .spi_miso(spi_miso)
);

assign led[0] = pll_on ? blink : 1'b0;
assign led[1] = use_fast_req;
assign led[2] = spi_err_flag;
assign led[3] = pll_locked;

endmodule
