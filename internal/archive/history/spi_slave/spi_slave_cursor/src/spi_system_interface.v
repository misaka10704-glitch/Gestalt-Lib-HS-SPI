// System-side parallel interface: RX valid pulse and TX load handshake.
module spi_system_interface #(
    parameter DATA_WIDTH = 8
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     cs_active,
    input  wire                     cs_start,
    input  wire                     cs_end,
    input  wire                     byte_done,
    input  wire [DATA_WIDTH-1:0]    rx_byte,

    output reg                      tx_load,
    output reg  [DATA_WIDTH-1:0]    tx_byte,

    output reg                      rx_valid,
    output reg  [DATA_WIDTH-1:0]    rx_data,
    input  wire                     tx_ready,
    input  wire [DATA_WIDTH-1:0]    tx_data,
    output reg                      tx_valid
);

    wire do_tx_load = tx_ready && (cs_start || (byte_done && cs_active));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_load  <= 1'b0;
            tx_byte  <= {DATA_WIDTH{1'b0}};
            tx_valid <= 1'b0;
        end else begin
            tx_load <= do_tx_load;
            if (do_tx_load) begin
                tx_byte <= tx_data;
            end

            if (cs_end) begin
                tx_valid <= 1'b0;
            end else if (cs_start || (byte_done && cs_active)) begin
                tx_valid <= ~do_tx_load;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_valid <= 1'b0;
            rx_data  <= {DATA_WIDTH{1'b0}};
        end else begin
            rx_valid <= byte_done;
            if (byte_done) begin
                rx_data <= rx_byte;
            end
        end
    end

endmodule
