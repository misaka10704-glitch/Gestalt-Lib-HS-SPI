`timescale 1ns / 1ps

/*
逻辑派 G1 · UART 回波工程顶层
上位机下发复杂波形 → FPGA 收帧 → 回传同帧格式
*/
module uart_wave#(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD = 115200
)
(
    input wire sys_clk,
    input wire [1:0] key, //key[0]=rst_n
    output wire [3:0] led,
    output wire uart_tx,
    input wire uart_rx
);

wire rx_active, tx_active;
wire frame_ok, frame_bad;

uart_echo_core#(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(BAUD),
    .MAX_N(128)
) u_core (
    .clk(sys_clk),
    .rst_n(key[0]),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx),
    .rx_active(rx_active),
    .tx_active(tx_active),
    .frame_ok_pulse(frame_ok),
    .frame_bad_pulse(frame_bad)
);

reg [25:0] hb_cnt;
reg heartbeat;
reg ok_sticky, bad_sticky;

always@(posedge sys_clk or negedge key[0])begin
    if(!key[0])begin
        hb_cnt<=0;
        heartbeat<=0;
        ok_sticky<=0;
        bad_sticky<=0;
    end
    else begin
        if(hb_cnt == CLK_FREQ/2-1)begin
            hb_cnt<=0;
            heartbeat<=~heartbeat;
        end
        else
            hb_cnt<=hb_cnt+1'b1;
        if(frame_ok)
            ok_sticky<=1;
        if(frame_bad)
            bad_sticky<=1;
        if(!key[1])begin //按 key1 清粘滞
            ok_sticky<=0;
            bad_sticky<=0;
        end
    end
end

assign led[0] = tx_active | rx_active; //活动
assign led[1] = heartbeat;
assign led[2] = ok_sticky;  //曾收妥
assign led[3] = bad_sticky; //曾校验失败

endmodule
