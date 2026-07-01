module spi_slave_top #(
    parameter CPOL       = 1'b0,
    parameter CPHA       = 1'b0,
    parameter DATA_WIDTH = 8,
    parameter LSB_FIRST  = 1'b0
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     sclk,
    input  wire                     cs_n,
    input  wire                     mosi,
    output wire                     miso,

    output wire                     rx_valid,
    output wire [DATA_WIDTH-1:0]    rx_data,
    input  wire                     tx_ready,
    input  wire [DATA_WIDTH-1:0]    tx_data,
    output wire                     tx_valid
);

    wire cs_active;
    wire cs_start;
    wire cs_end;
    wire sample_stb;
    wire shift_stb;
    wire mosi_s;
    wire tx_bit;

    wire [DATA_WIDTH-1:0] rx_byte;
    wire                  byte_done;

    wire                  tx_load;
    wire [DATA_WIDTH-1:0] tx_byte;

    spi_phy #(
        .CPOL (CPOL),
        .CPHA (CPHA)
    ) u_phy (
        .clk        (clk),
        .rst_n      (rst_n),
        .sclk       (sclk),
        .cs_n       (cs_n),
        .mosi       (mosi),
        .miso       (miso),
        .cs_active  (cs_active),
        .cs_start   (cs_start),
        .cs_end     (cs_end),
        .sample_stb (sample_stb),
        .shift_stb  (shift_stb),
        .mosi_s     (mosi_s),
        .tx_bit     (tx_bit)
    );

    spi_byte_engine #(
        .DATA_WIDTH (DATA_WIDTH),
        .LSB_FIRST  (LSB_FIRST)
    ) u_byte (
        .clk        (clk),
        .rst_n      (rst_n),
        .cs_active  (cs_active),
        .cs_start   (cs_start),
        .cs_end     (cs_end),
        .sample_stb (sample_stb),
        .shift_stb  (shift_stb),
        .mosi_s     (mosi_s),
        .tx_load    (tx_load),
        .tx_byte    (tx_byte),
        .rx_byte    (rx_byte),
        .byte_done  (byte_done),
        .tx_bit     (tx_bit)
    );

    spi_user_if #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_if (
        .clk        (clk),
        .rst_n      (rst_n),
        .cs_active  (cs_active),
        .cs_start   (cs_start),
        .cs_end     (cs_end),
        .byte_done  (byte_done),
        .rx_byte    (rx_byte),
        .tx_load    (tx_load),
        .tx_byte    (tx_byte),
        .rx_valid   (rx_valid),
        .rx_data    (rx_data),
        .tx_ready   (tx_ready),
        .tx_data    (tx_data),
        .tx_valid   (tx_valid)
    );

endmodule
