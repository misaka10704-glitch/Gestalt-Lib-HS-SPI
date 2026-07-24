`timescale 1ns / 1ps

module spi_slave_shift#(
    parameter DATA_DEEPTH = 8,
    parameter LSB_First = 0 //要考虑哪边进：0=MSB first，1=LSB first
)
(
    input wire clk,
    input wire rst_n,
    input wire mosi,
    input wire cs_n, //端口保留；门控用 cs_active（勿 & cs_n，选中时cs_n=0会把门控反掉）
    output wire miso,

    input wire cs_active,
    //都在controller经过双稳态了
    input wire cs_start,
    input wire cs_end,

    input wire sample_stb,
    input wire shift_stb,

    //对内系统
    output reg byte_done, //整字节就绪，单周期脉冲
    output reg [DATA_DEEPTH-1:0] rx_data,

    input wire [DATA_DEEPTH-1:0] tx_data,
    output reg sending_done //一字节发完（末次shift装下一字节），单周期
);

/*
时序（对接controller的sample/shift脉冲，Mode0为例）：
  cs_start → 预装tx，miso已是首bit（早于第一次sample）
  sample_stb → 采mosi、累加rx
  shift_stb  → 移tx下一位；第DATA_DEEPTH次则装下一字节
cs_end清计数，避免半帧残留
*/

reg [DATA_DEEPTH-1:0] rx_register;
reg [DATA_DEEPTH-1:0] tx_register;
reg [$clog2(DATA_DEEPTH)-1:0] rx_cnt;
reg [$clog2(DATA_DEEPTH)-1:0] tx_cnt;

//miso跟当前待发位；CS无效拉低。wire连续驱动，避免always里给wire赋值
//LSB相关，直接wire赋值，内部buffer和外部引脚刷新则立即赋值
assign miso = cs_active
    ? (LSB_First ? tx_register[0] : tx_register[DATA_DEEPTH-1])
    : 1'b0;

//移位下一拍（不允许拼接裸0）
wire [DATA_DEEPTH-1:0] rx_next = LSB_First
    ? {mosi, rx_register[DATA_DEEPTH-1:1]}
    : {rx_register[DATA_DEEPTH-2:0], mosi};

wire [DATA_DEEPTH-1:0] tx_next = LSB_First
    ? {1'b0, tx_register[DATA_DEEPTH-1:1]}
    : {tx_register[DATA_DEEPTH-2:0], 1'b0};



//1. rx端：只跟sample_stb；与tx_cnt无关
//思路：next照常读，register有条件赋值（拆成组合和时序层）
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        rx_register<=0;
        rx_data<=0;
        rx_cnt<=0;
        byte_done<=0;
    end
    else begin
        byte_done<=0; //默认清掉，仅末bit那拍为1

        if(cs_end)begin
            rx_cnt<=0;
            rx_register<=0;
        end
        else if(cs_start)begin
            rx_cnt<=0;
        end
        else if(sample_stb & cs_active)begin
            rx_register<=rx_next;
            //实际上，rx_next会无视门，进行赋值
            //因此register在门内可以直接读next
            if(rx_cnt == DATA_DEEPTH-1)begin
                rx_cnt<=0;
                rx_data<=rx_next;
                byte_done<=1;
            end
            else begin
                rx_cnt<=rx_cnt+1'b1;
            end
        end
    end
end

//2. tx端：cs_start预装；shift只动tx_cnt（勿再用rx_cnt）
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        tx_register<=0;
        tx_cnt<=0;
        sending_done<=0;
    end
    else begin
        sending_done<=0;

        if(cs_end)begin
            tx_cnt<=0;
        end
        else if(cs_start)begin
            //首bit在第一次sample前就要稳定在miso上
            tx_cnt<=0;
            tx_register<=tx_data;
        end
        else if(shift_stb & cs_active)begin
            if(tx_cnt == DATA_DEEPTH-1)begin
                //一字节的shift用尽：装下一字节（CS保持可连传）
                tx_cnt<=0;
                tx_register<=tx_data;
                sending_done<=1;
            end
            else begin
                tx_cnt<=tx_cnt+1'b1;
                tx_register<=tx_next;
            end
        end
    end
end

endmodule
