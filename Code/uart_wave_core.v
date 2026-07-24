`timescale 1ns / 1ps

/*
uart_wave_core：三角波采点 → 定长帧 → FIFO → uart_tx
帧：AA 55 | SEQ | N=64 | DATA[64] | XOR
XOR：自 SEQ 起至最后一个 DATA
*/
module uart_wave_core#(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD = 115200,
    parameter SAMPLE_HZ = 2000,
    parameter FRAME_N = 64,
    parameter FIFO_DEPTH = 256
)
(
    input wire clk,
    input wire rst_n,
    input wire pause_n, //0：暂停采数与组帧推送（键按下为低）
    output wire uart_tx,
    output wire tx_active //有字节在发或FIFO非空
);

wire [7:0] sample;
wire sample_stb;
wire run = pause_n;

triangle_gen#(
    .CLK_FREQ(CLK_FREQ),
    .SAMPLE_HZ(SAMPLE_HZ)
) u_tri (
    .clk(clk),
    .rst_n(rst_n),
    .enable(run),
    .sample(sample),
    .sample_stb(sample_stb)
);

//点缓冲
reg [7:0] buf_mem [0:FRAME_N-1];
reg [7:0] buf_cnt;
reg [7:0] seq;
reg frame_ready; //缓冲满，可写入FIFO

//FIFO
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

//组帧写FIFO
localparam W_IDLE = 3'd0;
localparam W_HDR0 = 3'd1;
localparam W_HDR1 = 3'd2;
localparam W_SEQ  = 3'd3;
localparam W_N    = 3'd4;
localparam W_DATA = 3'd5;
localparam W_XOR  = 3'd6;

reg [2:0] wstate;
reg [7:0] w_idx;
reg [7:0] xor_acc;
reg [7:0] seq_latch;

//1+2. 采点与组帧写FIFO（frame_ready 只在本块读写）
integer bi;
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        buf_cnt<=0;
        frame_ready<=0;
        wstate<=W_IDLE;
        w_idx<=0;
        xor_acc<=0;
        seq<=0;
        seq_latch<=0;
        fifo_wr_en<=0;
        fifo_wdata<=0;
        for(bi=0; bi<FRAME_N; bi=bi+1)
            buf_mem[bi]<=0;
    end
    else begin
        fifo_wr_en<=0;

        //采点：帧占用缓冲期间不写
        if(run && sample_stb && !frame_ready)begin
            buf_mem[buf_cnt]<=sample;
            if(buf_cnt == FRAME_N-1)begin
                buf_cnt<=0;
                frame_ready<=1;
            end
            else begin
                buf_cnt<=buf_cnt+8'd1;
            end
        end

        case(wstate)
        W_IDLE:begin
            if(frame_ready && !fifo_full)begin
                seq_latch<=seq;
                seq<=seq+8'd1;
                xor_acc<=0;
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
                fifo_wdata<=seq_latch;
                xor_acc<=seq_latch;
                wstate<=W_N;
            end
        end
        W_N:begin
            if(!fifo_full)begin
                fifo_wr_en<=1;
                fifo_wdata<=FRAME_N[7:0];
                xor_acc<=xor_acc ^ FRAME_N[7:0];
                w_idx<=0;
                wstate<=W_DATA;
            end
        end
        W_DATA:begin
            if(!fifo_full)begin
                fifo_wr_en<=1;
                fifo_wdata<=buf_mem[w_idx];
                xor_acc<=xor_acc ^ buf_mem[w_idx];
                if(w_idx == FRAME_N-1)
                    wstate<=W_XOR;
                else
                    w_idx<=w_idx+8'd1;
            end
        end
        W_XOR:begin
            if(!fifo_full)begin
                fifo_wr_en<=1;
                fifo_wdata<=xor_acc;
                frame_ready<=0;
                wstate<=W_IDLE;
            end
        end
        default:wstate<=W_IDLE;
        endcase
    end
end

//3. FIFO → uart_tx（读延迟1拍）
wire tx_busy;
reg tx_start;
reg [7:0] tx_data;
reg rd_pend;

uart_tx#(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(BAUD)
) u_uart (
    .clk(clk),
    .rst_n(rst_n),
    .tx_start(tx_start),
    .tx_data(tx_data),
    .tx_busy(tx_busy),
    .uart_tx(uart_tx)
);

assign tx_active = tx_busy | ~fifo_empty | (wstate != W_IDLE);

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
        else if(!tx_busy && !fifo_empty && !tx_start)begin
            fifo_rd_en<=1;
            rd_pend<=1;
        end
    end
end

endmodule
