// SPI controller: pin sync, CS frame detect, mode-dependent sample/shift strobes, MISO drive.
// Runs in system clock domain; shift register logic stays mode-agnostic via strobes.
module spi_controller #(
    parameter CPOL = 1'b0,
    parameter CPHA = 1'b0
) (
    input  wire clk,
    input  wire rst_n,

    input  wire sclk,
    input  wire cs_n,
    input  wire mosi,
    output wire miso,

    output wire cs_active,
    output wire cs_start,
    output wire cs_end,
    output wire sample_stb,
    output wire shift_stb,
    output wire mosi_s,

    input  wire tx_bit
);

    reg [1:0] sclk_sync;
    reg [1:0] cs_sync;
    reg [1:0] mosi_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync  <= 2'b00;
            cs_sync    <= 2'b11;
            mosi_sync  <= 2'b00;
        end else begin
            sclk_sync <= {sclk_sync[0], sclk};
            cs_sync   <= {cs_sync[0], cs_n};
            mosi_sync <= {mosi_sync[0], mosi};
        end
    end

    wire sclk_s = sclk_sync[1];
    wire cs_n_s = cs_sync[1];
    assign mosi_s = mosi_sync[1];

    reg cs_n_prev;
    reg sclk_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs_n_prev <= 1'b1;
            sclk_prev <= 1'b0;
        end else begin
            cs_n_prev <= cs_n_s;
            sclk_prev <= sclk_s;
        end
    end

    assign cs_active = ~cs_n_s;
    assign cs_start  = cs_n_prev & ~cs_n_s;
    assign cs_end    = ~cs_n_prev & cs_n_s;

    wire sclk_rise =  sclk_s & ~sclk_prev;
    wire sclk_fall = ~sclk_s &  sclk_prev;

    wire leading_edge  = CPOL ? sclk_fall : sclk_rise;
    wire trailing_edge = CPOL ? sclk_rise : sclk_fall;

    wire sample_edge = CPHA ? trailing_edge : leading_edge;
    wire shift_edge  = CPHA ? leading_edge  : trailing_edge;

    assign sample_stb = cs_active & sample_edge;
    assign shift_stb  = cs_active & shift_edge;

    // Combinational MISO: first bit visible as soon as tx_shift is loaded.
    assign miso = cs_active ? tx_bit : 1'b0;

endmodule
