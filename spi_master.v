`timescale 1ns / 1ps

/*
SPI Master：eng 在 IDLE 锁定
  use_fast=0 → eng=clk，分频 CLK_DIV
  use_fast=1 → eng=pll_clk（需 locked），分频 CLK_DIV_FAST

lab_sys_ext 用法（同速率 PLL 前后）：
  关 PLL：sys 50M / DIV=2  → SCLK=12.5M
  开 PLL：200M / DIV=8     → SCLK=12.5M
只在 ST_IDLE 改 use_fast_d，避免传输出途切钟。
*/
module spi_master#(
    parameter CPOL = 1'b0,
    parameter CPHA = 1'b0,
    parameter DATA_DEEPTH = 8,
    parameter LSB_First = 0,
    parameter CLK_DIV = 4,
    parameter CLK_DIV_FAST = 4,
    parameter PULSE_HOLD = 1
)
(
    input wire clk,
    input wire rst_n,
    input wire use_fast,
    input wire pll_clk,
    input wire pll_locked,

    output reg sclk,
    output reg mosi,
    input wire miso,
    output reg cs_n,

    input wire start,
    input wire [7:0] xfer_bytes,
    output wire busy,

    output wire cs_active,
    output reg cs_start,
    output reg cs_end,
    output reg byte_done,
    output reg [DATA_DEEPTH-1:0] rx_data,
    input wire [DATA_DEEPTH-1:0] tx_data
);

reg use_fast_d;
wire eng_clk = use_fast_d ? pll_clk : clk;
wire eng_ok  = use_fast_d ? pll_locked : 1'b1;

localparam DIV_MAX = (CLK_DIV_FAST > CLK_DIV) ? CLK_DIV_FAST : CLK_DIV;
// 计数 0..DIV-1；勿把 DIV 塞进 $clog2(DIV)（16→截成 0）
localparam CNT_W = (DIV_MAX <= 2) ? 1 : $clog2(DIV_MAX);
localparam BIT_W = $clog2(DATA_DEEPTH);
localparam HOLD_W = (PULSE_HOLD <= 1) ? 1 : $clog2(PULSE_HOLD+1);

localparam ST_IDLE  = 3'd0;
localparam ST_LOAD  = 3'd1;
localparam ST_SETUP = 3'd2;
localparam ST_WAIT  = 3'd3;
localparam ST_EDGE  = 3'd4;
localparam ST_GAP   = 3'd5;
localparam ST_END   = 3'd6;

reg [2:0] state;
reg [CNT_W-1:0] div_cnt;
reg [BIT_W-1:0] bit_cnt;
reg [7:0] byte_cnt;
reg [7:0] byte_total;
reg [DATA_DEEPTH-1:0] tx_shift;
reg [DATA_DEEPTH-1:0] rx_shift;
reg sclk_phase;
reg leading_is_sample;
reg [HOLD_W-1:0] bd_hold;
reg [HOLD_W-1:0] css_hold;
reg [HOLD_W-1:0] cse_hold;
wire [CNT_W-1:0] div_last = use_fast_d
    ? (CLK_DIV_FAST[CNT_W:0] - 1'b1)
    : (CLK_DIV[CNT_W:0] - 1'b1);

assign busy = (state != ST_IDLE);
assign cs_active = ~cs_n;

wire sample_now = (sclk_phase == 1'b0) ? leading_is_sample : ~leading_is_sample;

wire [DATA_DEEPTH-1:0] rx_next = LSB_First
    ? {miso, rx_shift[DATA_DEEPTH-1:1]}
    : {rx_shift[DATA_DEEPTH-2:0], miso};

wire [DATA_DEEPTH-1:0] tx_next = LSB_First
    ? {1'b0, tx_shift[DATA_DEEPTH-1:1]}
    : {tx_shift[DATA_DEEPTH-2:0], 1'b0};

always@(posedge eng_clk or negedge rst_n)begin
    if(!rst_n)begin
        state<=ST_IDLE;
        div_cnt<=0;
        bit_cnt<=0;
        byte_cnt<=0;
        byte_total<=0;
        tx_shift<=0;
        rx_shift<=0;
        rx_data<=0;
        sclk<=CPOL;
        mosi<=0;
        cs_n<=1;
        cs_start<=0;
        cs_end<=0;
        byte_done<=0;
        sclk_phase<=0;
        leading_is_sample<=(CPHA == 1'b0);
        bd_hold<=0;
        css_hold<=0;
        cse_hold<=0;
        use_fast_d<=1'b0;
    end
    else begin
        if(state == ST_IDLE)
            use_fast_d<=use_fast;

        if(bd_hold != 0)begin
            byte_done<=1'b1;
            bd_hold<=bd_hold-1'b1;
        end
        else
            byte_done<=1'b0;

        if(css_hold != 0)begin
            cs_start<=1'b1;
            css_hold<=css_hold-1'b1;
        end
        else
            cs_start<=1'b0;

        if(cse_hold != 0)begin
            cs_end<=1'b1;
            cse_hold<=cse_hold-1'b1;
        end
        else
            cs_end<=1'b0;

        case(state)
        ST_IDLE:begin
            sclk<=CPOL;
            cs_n<=1;
            sclk_phase<=0;
            if(start & eng_ok)begin
                state<=ST_LOAD;
                byte_total<=(xfer_bytes == 8'd0) ? 8'd1 : xfer_bytes;
                byte_cnt<=(xfer_bytes == 8'd0) ? 8'd1 : xfer_bytes;
                leading_is_sample<=(CPHA == 1'b0);
            end
        end

        ST_LOAD:begin
            cs_n<=0;
            cs_start<=1'b1;
            css_hold<=(PULSE_HOLD <= 1) ? {HOLD_W{1'b0}} : (PULSE_HOLD - 1);
            rx_shift<=0;
            bit_cnt<=0;
            div_cnt<=0;
            sclk_phase<=0;
            state<=ST_SETUP;
        end

        ST_SETUP:begin
            tx_shift<=tx_data;
            mosi<=LSB_First ? tx_data[0] : tx_data[DATA_DEEPTH-1];
            state<=ST_WAIT;
        end

        ST_WAIT:begin
            if(div_cnt == div_last)begin
                div_cnt<=0;
                state<=ST_EDGE;
            end
            else
                div_cnt<=div_cnt+1'b1;
        end

        ST_EDGE:begin
            sclk<=~sclk;
            if(sample_now)begin
                rx_shift<=rx_next;
                if(bit_cnt == DATA_DEEPTH-1)begin
                    rx_data<=rx_next;
                    byte_done<=1'b1;
                    bd_hold<=(PULSE_HOLD <= 1) ? {HOLD_W{1'b0}} : (PULSE_HOLD - 1);
                end
            end
            else begin
                tx_shift<=tx_next;
                mosi<=LSB_First ? tx_next[0] : tx_next[DATA_DEEPTH-1];
            end

            if(sclk_phase == 1'b1)begin
                sclk_phase<=0;
                if(bit_cnt == DATA_DEEPTH-1)begin
                    bit_cnt<=0;
                    state<=ST_GAP;
                end
                else begin
                    bit_cnt<=bit_cnt+1'b1;
                    state<=ST_WAIT;
                end
            end
            else begin
                sclk_phase<=1;
                state<=ST_WAIT;
            end
        end

        ST_GAP:begin
            sclk<=CPOL;
            if(byte_cnt <= 8'd1)
                state<=ST_END;
            else begin
                byte_cnt<=byte_cnt-8'd1;
                tx_shift<=tx_data;
                mosi<=LSB_First ? tx_data[0] : tx_data[DATA_DEEPTH-1];
                rx_shift<=0;
                bit_cnt<=0;
                div_cnt<=0;
                sclk_phase<=0;
                state<=ST_WAIT;
            end
        end

        ST_END:begin
            cs_n<=1;
            cs_end<=1'b1;
            cse_hold<=(PULSE_HOLD <= 1) ? {HOLD_W{1'b0}} : (PULSE_HOLD - 1);
            sclk<=CPOL;
            state<=ST_IDLE;
        end

        default:state<=ST_IDLE;
        endcase
    end
end

endmodule
