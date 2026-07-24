`timescale 1ns / 1ps

module triangle_gen#(
    parameter CLK_FREQ = 50_000_000,
    parameter SAMPLE_HZ = 2000 //约2kHz采样
)
(
    input wire clk,
    input wire rst_n,
    input wire enable, //0：停采
    output reg [7:0] sample,
    output reg sample_stb //单周期
);

localparam integer DIV = CLK_FREQ / SAMPLE_HZ;
localparam CNT_W = $clog2(DIV);

reg [CNT_W-1:0] div_cnt;
reg dir; //0：递增，1：递减

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        div_cnt<=0;
        sample<=0;
        sample_stb<=0;
        dir<=0;
    end
    else begin
        sample_stb<=0;
        if(!enable)begin
            div_cnt<=0;
        end
        else if(div_cnt == DIV-1)begin
            div_cnt<=0;
            sample_stb<=1;
            if(!dir)begin
                if(sample == 8'hFF)begin
                    dir<=1;
                    sample<=8'hFE;
                end
                else begin
                    sample<=sample+8'd1;
                end
            end
            else begin
                if(sample == 8'h00)begin
                    dir<=0;
                    sample<=8'h01;
                end
                else begin
                    sample<=sample-8'd1;
                end
            end
        end
        else begin
            div_cnt<=div_cnt+1'b1;
        end
    end
end

endmodule
