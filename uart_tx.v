`timescale 1ns / 1ps

module uart_tx#(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD = 115200
)
(
    input wire clk,
    input wire rst_n,
    input wire tx_start, //单周期脉冲启动
    input wire [7:0] tx_data,
    output reg tx_busy,
    output reg uart_tx //空闲为1
);

localparam integer DIV = CLK_FREQ / BAUD;
localparam CNT_W = $clog2(DIV);

reg [CNT_W-1:0] baud_cnt;
reg [3:0] bit_idx;
reg [8:0] shifter; //{stop, data[7:0]}，起始位单独在tx_start时拉低

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        tx_busy<=0;
        uart_tx<=1;
        baud_cnt<=0;
        bit_idx<=0;
        shifter<=9'h1FF;
    end
    else if(tx_busy)begin
        if(baud_cnt == DIV-1)begin
            baud_cnt<=0;
            if(bit_idx == 4'd9)begin
                tx_busy<=0;
                bit_idx<=0;
                uart_tx<=1;
            end
            else begin
                uart_tx<=shifter[0];
                shifter<={1'b1, shifter[8:1]};
                bit_idx<=bit_idx+4'd1;
            end
        end
        else begin
            baud_cnt<=baud_cnt+1'b1;
        end
    end
    else if(tx_start)begin
        uart_tx<=0; //起始位
        shifter<={1'b1, tx_data};
        tx_busy<=1;
        baud_cnt<=0;
        bit_idx<=0;
    end
    else begin
        uart_tx<=1;
    end
end

endmodule
