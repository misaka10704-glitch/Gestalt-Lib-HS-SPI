`timescale 1ns / 1ps

module spi_fifo_interface#(
    parameter DATA_WIDTH = 8, //字节位宽，对接shift的DATA_DEEPTH
    parameter DATA_DEEPTH = 8 //fifo深度，与async_fifo同名参数
)
(
    input wire clk, //spi侧：与controller/shift同域
    input wire sys_clk, //业务侧；可与clk相同
    input wire rst_n,

    //spi字节侧（主从通用：slave接cs_*，master接传输start/busy/end）
    input wire cs_active,//正在传输flag
    input wire cs_start,//传输开始脉冲
    input wire cs_end,//传输结束脉冲
    input wire byte_done,//整字节就绪，单周期
    input wire [DATA_WIDTH-1:0] rx_data,

    output reg tx_load,//装载脉冲 → shift
    output reg [DATA_WIDTH-1:0] tx_data,
    output reg rx_overflow,//byte_done时rx fifo已满
    output reg tx_underrun,//需要发送时hold为空

    //业务侧：rx读 / tx写（对接async_fifo对外口）
    input wire sys_rd_en,
    output wire [DATA_WIDTH-1:0] sys_rdata,
    output wire sys_empty,

    input wire sys_wr_en,
    input wire [DATA_WIDTH-1:0] sys_wdata,
    output wire sys_full
);

/*
字节层 ↔ 双async_fifo：
  RX：byte_done写入（clk→sys_clk）
  TX：预取到hold，cs_start/字节边界tx_load给shift
不管bit、CPOL/CPHA；master复用时只改cs_*的接法
*/

//fifo例化：rx写在clk、读在sys；tx写在sys、读在clk
wire rx_full;
wire tx_empty;
wire tx_rd_en;
wire [DATA_WIDTH-1:0] tx_rdata;

async_fifo#(
    .DATA_WIDTH(DATA_WIDTH),
    .DATA_DEEPTH(DATA_DEEPTH)
) rx_fifo (
    .full(rx_full),
    .empty(sys_empty),
    .wclk(clk),
    .rclk(sys_clk),
    .wdata(rx_data),
    .rdata(sys_rdata),
    .rst_n(rst_n),
    .wr_en(byte_done & ~rx_full),
    .rd_en(sys_rd_en)
);

async_fifo#(
    .DATA_WIDTH(DATA_WIDTH),
    .DATA_DEEPTH(DATA_DEEPTH)
) tx_fifo (
    .full(sys_full),
    .empty(tx_empty),
    .wclk(sys_clk),
    .rclk(clk),
    .wdata(sys_wdata),
    .rdata(tx_rdata),
    .rst_n(rst_n),
    .wr_en(sys_wr_en),
    .rd_en(tx_rd_en)
);

//1. rx端：脉冲写入；满则打溢出（从机侧通常只能告警）
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        rx_overflow<=0;
    end
    else if(cs_end)begin
        rx_overflow<=0;
    end
    else if(byte_done & rx_full)begin
        rx_overflow<=1;
    end
end

//2. tx端：fifo读为rd_en下一拍才出数，故hold预取
//思路：next/rdata照常来，hold有条件采纳；need时再交给shift
reg hold_valid;
reg [DATA_WIDTH-1:0] tx_hold;
reg rd_pending; //已发rd_en，等下一拍rdata

//要装下一发：帧开始，或帧内刚收完一字节（全双工边界）
wire need_tx = cs_start | (byte_done & cs_active);

//空闲预取：hold空且fifo非空且无在途读；need当拍优先load
wire do_prefetch = ~hold_valid & ~rd_pending & ~tx_empty & ~need_tx;
//need且hold有数：本拍load掉hold，顺带预取下一字（若还有）
assign tx_rd_en = do_prefetch | (need_tx & hold_valid & ~tx_empty);

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        hold_valid<=0;
        tx_hold<=0;
        rd_pending<=0;
        tx_load<=0;
        tx_data<=0;
        tx_underrun<=0;
    end
    else begin
        tx_load<=0;
        tx_underrun<=0;

        if(cs_end)begin
            hold_valid<=0;
            rd_pending<=0;
        end
        else if(need_tx)begin
            //边界装载：优先hold；其次本拍刚到的rdata
            if(hold_valid)begin
                tx_load<=1;
                tx_data<=tx_hold;
                hold_valid<=0;
                if(tx_rd_en)
                    rd_pending<=1;
            end
            else if(rd_pending)begin
                tx_load<=1;
                tx_data<=tx_rdata;
                rd_pending<=0;
            end
            else begin
                tx_underrun<=1;
                tx_load<=1;
                tx_data<=0;
            end
        end
        else begin
            //非边界：空闲预取填hold
            if(rd_pending)begin
                tx_hold<=tx_rdata;
                hold_valid<=1;
                rd_pending<=0;
            end
            else if(tx_rd_en)begin
                rd_pending<=1;
            end
        end
    end
end

endmodule
