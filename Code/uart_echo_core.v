`timescale 1ns / 1ps

/*
uart_echo_core：上位机下发波形帧 → 存缓冲 → 原样回传
帧同 uart_wave：AA 55 | SEQ | N | DATA[N] | XOR
N 最大 MAX_N（默认 128）
*/
module uart_echo_core#(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD = 115200,
    parameter MAX_N = 128,
    parameter FIFO_DEPTH = 512
)
(
    input wire clk,
    input wire rst_n,
    input wire uart_rx,
    output wire uart_tx,
    output wire rx_active,
    output wire tx_active,
    output reg frame_ok_pulse, //收妥一帧
    output reg frame_bad_pulse
);

wire rx_valid;
wire [7:0] rx_byte;

uart_rx#(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(BAUD)
) u_rx (
    .clk(clk),
    .rst_n(rst_n),
    .uart_rx(uart_rx),
    .rx_valid(rx_valid),
    .rx_data(rx_byte)
);

// ---- 收帧状态机 ----
localparam R_SYNC0 = 3'd0;
localparam R_SYNC1 = 3'd1;
localparam R_SEQ   = 3'd2;
localparam R_N     = 3'd3;
localparam R_DATA  = 3'd4;
localparam R_XOR   = 3'd5;

reg [2:0] rstate;
reg [7:0] seq_rx;
reg [7:0] n_rx;
reg [7:0] idx;
reg [7:0] xor_acc;
reg [7:0] wave [0:MAX_N-1];
reg [7:0] n_store;
reg [7:0] seq_store;
reg echo_req; //收妥后请求回传

reg rx_busy_vis;
assign rx_active = rx_busy_vis | (rstate != R_SYNC0);

integer wi;
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        rstate<=R_SYNC0;
        seq_rx<=0;
        n_rx<=0;
        idx<=0;
        xor_acc<=0;
        n_store<=0;
        seq_store<=0;
        echo_req<=0;
        frame_ok_pulse<=0;
        frame_bad_pulse<=0;
        rx_busy_vis<=0;
        for(wi=0; wi<MAX_N; wi=wi+1)
            wave[wi]<=0;
    end
    else begin
        frame_ok_pulse<=0;
        frame_bad_pulse<=0;
        echo_req<=0;
        rx_busy_vis<=(rstate!=R_SYNC0);

        if(rx_valid)begin
            case(rstate)
            R_SYNC0:begin
                if(rx_byte == 8'hAA)
                    rstate<=R_SYNC1;
            end
            R_SYNC1:begin
                if(rx_byte == 8'h55)
                    rstate<=R_SEQ;
                else if(rx_byte == 8'hAA)
                    rstate<=R_SYNC1;
                else
                    rstate<=R_SYNC0;
            end
            R_SEQ:begin
                seq_rx<=rx_byte;
                xor_acc<=rx_byte;
                rstate<=R_N;
            end
            R_N:begin
                n_rx<=rx_byte;
                xor_acc<=xor_acc ^ rx_byte;
                idx<=0;
                if(rx_byte == 0 || rx_byte > MAX_N)begin
                    frame_bad_pulse<=1;
                    rstate<=R_SYNC0;
                end
                else
                    rstate<=R_DATA;
            end
            R_DATA:begin
                wave[idx]<=rx_byte;
                xor_acc<=xor_acc ^ rx_byte;
                if(idx == n_rx-1)
                    rstate<=R_XOR;
                else
                    idx<=idx+8'd1;
            end
            R_XOR:begin
                if(rx_byte == xor_acc)begin
                    n_store<=n_rx;
                    seq_store<=seq_rx;
                    echo_req<=1;
                    frame_ok_pulse<=1;
                end
                else begin
                    frame_bad_pulse<=1;
                end
                rstate<=R_SYNC0;
            end
            default:rstate<=R_SYNC0;
            endcase
        end
    end
end

// ---- 回传：组帧写入 FIFO → uart_tx ----
wire fifo_full, fifo_empty;
wire [7:0] fifo_rdata;
reg fifo_wr_en;
reg [7:0] fifo_wdata;
reg fifo_rd_en;

async_fifo#(
    .DATA_WIDTH(8),
    .DATA_DEEPTH(FIFO_DEPTH)
) u_fifo (
    .full(fifo_full),
    .empty(fifo_empty),
    .wclk(clk),
    .rclk(clk),
    .wdata(fifo_wdata),
    .rdata(fifo_rdata),
    .rst_n(rst_n),
    .wr_en(fifo_wr_en),
    .rd_en(fifo_rd_en)
);

localparam W_IDLE = 3'd0;
localparam W_HDR0 = 3'd1;
localparam W_HDR1 = 3'd2;
localparam W_SEQ  = 3'd3;
localparam W_N    = 3'd4;
localparam W_DATA = 3'd5;
localparam W_XOR  = 3'd6;

reg [2:0] wstate;
reg [7:0] w_idx;
reg [7:0] xor_tx;
reg [7:0] n_tx;
reg [7:0] seq_tx;
reg echo_hold;

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        wstate<=W_IDLE;
        w_idx<=0;
        xor_tx<=0;
        n_tx<=0;
        seq_tx<=0;
        echo_hold<=0;
        fifo_wr_en<=0;
        fifo_wdata<=0;
    end
    else begin
        fifo_wr_en<=0;
        if(echo_req)
            echo_hold<=1;

        case(wstate)
        W_IDLE:begin
            if(echo_hold)begin
                echo_hold<=0;
                n_tx<=n_store;
                seq_tx<=seq_store;
                xor_tx<=0;
                w_idx<=0;
                wstate<=W_HDR0;
            end
        end
        W_HDR0:begin
            if(!fifo_full)begin
                fifo_wr_en<=1;
                fifo_wdata<=8'hAA;
                wstate<=W_HDR1;
            end
        end
        W_HDR1:begin
            if(!fifo_full)begin
                fifo_wr_en<=1;
                fifo_wdata<=8'h55;
                wstate<=W_SEQ;
            end
        end
        W_SEQ:begin
            if(!fifo_full)begin
                fifo_wr_en<=1;
                fifo_wdata<=seq_tx;
                xor_tx<=seq_tx;
                wstate<=W_N;
            end
        end
        W_N:begin
            if(!fifo_full)begin
                fifo_wr_en<=1;
                fifo_wdata<=n_tx;
                xor_tx<=xor_tx ^ n_tx;
                w_idx<=0;
                wstate<=W_DATA;
            end
        end
        W_DATA:begin
            if(!fifo_full)begin
                fifo_wr_en<=1;
                fifo_wdata<=wave[w_idx];
                xor_tx<=xor_tx ^ wave[w_idx];
                if(w_idx == n_tx-1)
                    wstate<=W_XOR;
                else
                    w_idx<=w_idx+8'd1;
            end
        end
        W_XOR:begin
            if(!fifo_full)begin
                fifo_wr_en<=1;
                fifo_wdata<=xor_tx;
                wstate<=W_IDLE;
            end
        end
        default:wstate<=W_IDLE;
        endcase
    end
end

wire tx_busy_w;
reg tx_start;
reg [7:0] tx_data;
reg rd_pend;

uart_tx#(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(BAUD)
) u_tx (
    .clk(clk),
    .rst_n(rst_n),
    .tx_start(tx_start),
    .tx_data(tx_data),
    .tx_busy(tx_busy_w),
    .uart_tx(uart_tx)
);

assign tx_active = tx_busy_w | ~fifo_empty | (wstate != W_IDLE);

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        tx_start<=0;
        tx_data<=0;
        fifo_rd_en<=0;
        rd_pend<=0;
    end
    else begin
        tx_start<=0;
        fifo_rd_en<=0;
        if(rd_pend)begin
            rd_pend<=0;
            tx_data<=fifo_rdata;
            tx_start<=1;
        end
        else if(!tx_busy_w && !fifo_empty)begin
            fifo_rd_en<=1;
            rd_pend<=1;
        end
    end
end

endmodule
