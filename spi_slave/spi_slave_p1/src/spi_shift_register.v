// SPI shift register: RX/TX shift registers and bit counting driven by controller strobes.
module spi_shift_register #(
    parameter DATA_WIDTH = 8,
    parameter LSB_FIRST  = 1'b0
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     cs_active,
    input  wire                     cs_start,
    input  wire                     cs_end,
    input  wire                     sample_stb,
    input  wire                     shift_stb,
    input  wire                     mosi_s,

    input  wire                     tx_load,
    input  wire [DATA_WIDTH-1:0]    tx_byte,

    output wire [DATA_WIDTH-1:0]    rx_byte,
    output reg                      byte_done,
    output wire                     tx_bit
);

    reg [DATA_WIDTH-1:0] rx_shift;
    reg [DATA_WIDTH-1:0] tx_shift;
    reg [DATA_WIDTH-1:0] rx_byte_r;
    reg [$clog2(DATA_WIDTH)-1:0] bit_cnt;

    wire [DATA_WIDTH-1:0] rx_shift_next = LSB_FIRST
        ? {mosi_s, rx_shift[DATA_WIDTH-1:1]}
        : {rx_shift[DATA_WIDTH-2:0], mosi_s};

    wire [DATA_WIDTH-1:0] rx_byte_next = LSB_FIRST
        ? {mosi_s, rx_shift[DATA_WIDTH-1:1]}
        : {rx_shift[DATA_WIDTH-2:0], mosi_s};

    wire [DATA_WIDTH-1:0] tx_shift_next = LSB_FIRST
        ? {1'b0, tx_shift[DATA_WIDTH-1:1]}
        : {tx_shift[DATA_WIDTH-2:0], 1'b0};

    assign rx_byte = rx_byte_r;
    assign tx_bit  = LSB_FIRST ? tx_shift[0] : tx_shift[DATA_WIDTH-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_shift  <= {DATA_WIDTH{1'b0}};
            tx_shift  <= {DATA_WIDTH{1'b0}};
            rx_byte_r <= {DATA_WIDTH{1'b0}};
            bit_cnt   <= {$clog2(DATA_WIDTH){1'b0}};
            byte_done <= 1'b0;
        end else begin
            byte_done <= 1'b0;

            if (cs_end) begin
                bit_cnt  <= {$clog2(DATA_WIDTH){1'b0}};
                rx_shift <= {DATA_WIDTH{1'b0}};
            end else if (cs_start) begin
                bit_cnt <= {$clog2(DATA_WIDTH){1'b0}};
            end

            if (tx_load) begin
                tx_shift <= tx_byte;
            end

            if (sample_stb && cs_active) begin
                rx_shift <= rx_shift_next;

                if (bit_cnt == DATA_WIDTH - 1) begin
                    rx_byte_r <= rx_byte_next;
                    byte_done <= 1'b1;
                    bit_cnt   <= {$clog2(DATA_WIDTH){1'b0}};
                end else begin
                    bit_cnt <= bit_cnt + 1'b1;
                end
            end

            if (shift_stb && cs_active) begin
                tx_shift <= tx_shift_next;
            end
        end
    end

endmodule
