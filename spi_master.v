`timescale 1ns / 1ps

module spi_master#(
    parameter CPOL = 1'b0,
    parameter CPHA = 1'b0,
    parameter DATA_DEEPTH = 8,
    parameter LSB_First = 0, //0=MSB first，1=LSB first
    parameter CLK_DIV = 4, //eng_clk半周期计数，sclk周期=2*CLK_DIV；建议>=2
    parameter USE_PLL = 0 //0：用clk；1：用pll_clk（须pll_locked）
)
(
    input wire clk, //系统时钟；USE_PLL=0时作引擎时钟
    input wire rst_n,

    //PLL预留：高速位时钟源；无PLL仿真时pll_clk可接clk、pll_locked拉1
    input wire pll_clk,
    input wire pll_locked,

    //spi引脚（相对master）
    output reg sclk,
    output reg mosi,
    input wire miso,
    output reg cs_n, //低有效

    //启动：start脉冲启动一帧；xfer_bytes为本帧字节数（0视为1）
    input wire start,
    input wire [7:0] xfer_bytes,
    output wire busy,

    //字节侧：可直接接spi_fifo_interface的cs_*/byte_done/rx/tx
    output wire cs_active,
    output reg cs_start,//传输开始脉冲
    output reg cs_end,//传输结束脉冲
    output reg byte_done,
    output reg [DATA_DEEPTH-1:0] rx_data,
    input wire [DATA_DEEPTH-1:0] tx_data
);

/*
主机：自产sclk/cs，移位收发。
时序与slave对称——对外仍给cs_start/byte_done，便于复用fifo_interface。
引擎时钟 eng_clk：USE_PLL时切到pll；未锁定则忽略start、保持空闲。
*/

wire eng_clk = USE_PLL ? pll_clk : clk;
wire eng_ok  = USE_PLL ? pll_locked : 1'b1;

localparam CNT_W = $clog2(CLK_DIV);
localparam BIT_W = $clog2(DATA_DEEPTH);

localparam ST_IDLE  = 3'd0;
localparam ST_LOAD  = 3'd1; //拉cs、打cs_start（给fifo一拍取数）
localparam ST_SETUP = 3'd2; //采tx_data，mosi摆首bit
localparam ST_WAIT  = 3'd3; //半周期等待
localparam ST_EDGE  = 3'd4; //翻转sclk并sample/shift
localparam ST_GAP   = 3'd5; //字节间/结束前收尾
localparam ST_END   = 3'd6; //拉高cs、打cs_end

reg [2:0] state;
reg [CNT_W-1:0] div_cnt;
reg [BIT_W-1:0] bit_cnt;
reg [7:0] byte_cnt; //剩余待发字节（含当前）
reg [7:0] byte_total;
reg [DATA_DEEPTH-1:0] tx_shift;
reg [DATA_DEEPTH-1:0] rx_shift;
reg sclk_phase; //0=本半周后出leading沿，1=后出trailing沿
reg leading_is_sample; //由CPHA决定

assign busy = (state != ST_IDLE);
assign cs_active = ~cs_n;

//CPHA=0：leading沿采样；CPHA=1：trailing沿采样（与常见mode表一致）
wire sample_now = (sclk_phase == 1'b0) ? leading_is_sample : ~leading_is_sample;

wire [DATA_DEEPTH-1:0] rx_next = LSB_First
    ? {miso, rx_shift[DATA_DEEPTH-1:1]}
    : {rx_shift[DATA_DEEPTH-2:0], miso};

wire [DATA_DEEPTH-1:0] tx_next = LSB_First
    ? {1'b0, tx_shift[DATA_DEEPTH-1:1]}
    : {tx_shift[DATA_DEEPTH-2:0], 1'b0};

wire tx_bit = LSB_First ? tx_shift[0] : tx_shift[DATA_DEEPTH-1];

//1. 主状态机：分频 + 边沿上sample/shift
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
    end
    else begin
        cs_start<=0;
        cs_end<=0;
        byte_done<=0;

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
            //帧开始：只拉cs并打cs_start；tx_data与fifo同拍更新，下一拍再采
            cs_n<=0;
            cs_start<=1;
            rx_shift<=0;
            bit_cnt<=0;
            div_cnt<=0;
            sclk_phase<=0;
            state<=ST_SETUP;
        end

        ST_SETUP:begin
            //mosi在第一sampling沿前稳定
            tx_shift<=tx_data;
            mosi<=LSB_First ? tx_data[0] : tx_data[DATA_DEEPTH-1];
            state<=ST_WAIT;
        end

        ST_WAIT:begin
            //半周期延时
            if(div_cnt == CLK_DIV-1)begin
                div_cnt<=0;
                state<=ST_EDGE;
            end
            else begin
                div_cnt<=div_cnt+1'b1;
            end
        end

        ST_EDGE:begin
            //翻转sclk；本沿按mode做sample或shift
            sclk<=~sclk;

            if(sample_now)begin
                rx_shift<=rx_next;
                if(bit_cnt == DATA_DEEPTH-1)begin
                    rx_data<=rx_next;
                    byte_done<=1;
                end
            end
            else begin
                //shift沿：更新下一位mosi
                tx_shift<=tx_next;
                mosi<=LSB_First ? tx_next[0] : tx_next[DATA_DEEPTH-1];
            end

            //一对leading+trailing算完1bit
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
            //一字节结束：byte_done已过一拍，tx_data为fifo新数
            sclk<=CPOL;
            if(byte_cnt <= 8'd1)begin
                state<=ST_END;
            end
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
            cs_end<=1;
            sclk<=CPOL;
            state<=ST_IDLE;
        end

        default:state<=ST_IDLE;
        endcase
    end
end

endmodule
