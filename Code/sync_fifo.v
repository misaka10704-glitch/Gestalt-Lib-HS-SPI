`timescale 1ns / 1ps

// 单时钟同步 FIFO（空满用二进制指针，无 Gray 延迟）
module sync_fifo#(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 256
)
(
    input wire clk,
    input wire rst_n,
    input wire wr_en,
    input wire rd_en,
    input wire [DATA_WIDTH-1:0] wdata,
    output reg [DATA_WIDTH-1:0] rdata,
    output wire full,
    output wire empty
);

localparam AW = $clog2(DEPTH);

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
reg [AW:0] wptr, rptr; // 多 1 bit 区分空满

wire [AW:0] level = wptr - rptr;
assign empty = (level == 0);
assign full  = (level == DEPTH);

integer i;
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        wptr<=0;
        rptr<=0;
        rdata<=0;
        for(i=0;i<DEPTH;i=i+1)
            mem[i]<=0;
    end
    else begin
        if(wr_en && !full)begin
            mem[wptr[AW-1:0]]<=wdata;
            wptr<=wptr+1'b1;
        end
        if(rd_en && !empty)begin
            rdata<=mem[rptr[AW-1:0]];
            rptr<=rptr+1'b1;
        end
    end
end

endmodule
