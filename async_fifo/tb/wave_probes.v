`timescale 1ns / 1ps

// Shared VCD probe shell (single scope for Surfer Add-to-Wave)
module wave_probes #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_W     = 3
) (
    input wire                 w_clk,
    input wire                 w_en,
    input wire [DATA_WIDTH-1:0] w_data,
    input wire                 w_full,
    input wire [ADDR_W-1:0]    w_addr,
    input wire [ADDR_W:0]      w_ptr,
    input wire [ADDR_W:0]      w_gray,
    input wire [ADDR_W:0]      r_gray_w1,
    input wire [ADDR_W:0]      r_gray_wq,
    input wire                 r_clk,
    input wire                 r_en,
    input wire [DATA_WIDTH-1:0] r_data,
    input wire                 r_empty,
    input wire [ADDR_W-1:0]    r_addr,
    input wire [ADDR_W:0]      r_ptr,
    input wire [ADDR_W:0]      r_gray,
    input wire [ADDR_W:0]      w_gray_r1,
    input wire [ADDR_W:0]      w_gray_rq,
    input wire                 s_rst,
    input wire [DATA_WIDTH-1:0] s_mem0,
    input wire [DATA_WIDTH-1:0] s_mem1,
    input wire [DATA_WIDTH-1:0] s_mem2,
    input wire [DATA_WIDTH-1:0] s_mem3,
    input wire [DATA_WIDTH-1:0] s_mem4,
    input wire [DATA_WIDTH-1:0] s_mem5,
    input wire [DATA_WIDTH-1:0] s_mem6,
    input wire [DATA_WIDTH-1:0] s_mem7
);
endmodule
