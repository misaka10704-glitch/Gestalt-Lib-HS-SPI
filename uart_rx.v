`timescale 1ns / 1ps

module uart_rx#(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD = 115200
)
(
    input wire clk,
    input wire rst_n,
    input wire uart_rx,
    output reg rx_valid, //单周期：收到一字节
    output reg [7:0] rx_data
);

localparam integer DIV = CLK_FREQ / BAUD;
localparam integer HALF = DIV / 2;
localparam CNT_W = $clog2(DIV);

reg [1:0] rx_sync;
reg rx_d;
reg [CNT_W-1:0] baud_cnt;
reg [3:0] bit_idx; //0=等中点验起始，1..8=data，9=stop
reg [7:0] shifter;
reg busy;

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        rx_sync<=2'b11;
        rx_d<=1;
        baud_cnt<=0;
        bit_idx<=0;
        shifter<=0;
        busy<=0;
        rx_valid<=0;
        rx_data<=0;
    end
    else begin
        rx_sync <= {rx_sync[0], uart_rx};
        rx_d <= rx_sync[1];
        rx_valid <= 0;

        if(!busy)begin
            if(rx_d & ~rx_sync[1])begin //同步后下降沿 → 起始位
                busy <= 1;
                baud_cnt <= HALF[CNT_W-1:0];
                bit_idx <= 0;
            end
        end
        else if(baud_cnt == DIV-1)begin
            baud_cnt <= 0;
            if(bit_idx == 0)begin
                if(rx_sync[1] == 1'b0)begin
                    bit_idx <= 1; //确认起始，下一拍采 data0
                end
                else begin
                    busy <= 0;
                end
            end
            else if(bit_idx >= 1 && bit_idx <= 8)begin
                shifter <= {rx_sync[1], shifter[7:1]};
                bit_idx <= bit_idx + 4'd1;
            end
            else begin
                //停止位采样点：交出数据
                rx_data <= shifter;
                rx_valid <= 1;
                busy <= 0;
                bit_idx <= 0;
            end
        end
        else begin
            baud_cnt <= baud_cnt + 1'b1;
        end
    end
end

endmodule
