module spi_shift_register_rx #(
    parameter DATA_WIDTH = 8,
    parameter LSB_FIRST  = 1'b0
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     spi_input,
    output wire [DATA_WIDTH-1:0]    rx_byte,
    output reg                     byte_flag

);

reg [DATA_WIDTH-1:0] rx_shift_reg;
reg [3:0] bit_count;

assign rx_byte[0]=rx_shift_reg[0];
assign rx_byte[1]=rx_shift_reg[1];
assign rx_byte[2]=rx_shift_reg[2];
assign rx_byte[3]=rx_shift_reg[3];
assign rx_byte[4]=rx_shift_reg[4];
assign rx_byte[5]=rx_shift_reg[5];
assign rx_byte[6]=rx_shift_reg[6];
assign rx_byte[7]=rx_shift_reg[7];



assign byte_flag=(bit_count==0)?1:0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bit_count <= 0;
        byte_flag <= 0;
        rx_shift_reg <= 0;
    end
    else begin 
    if(bit_count < DATA_WIDTH) begin
        bit_count <= bit_count + 1;
    end
    else begin
        bit_count <= 0;
        rx_shift_reg <= 0;
    end

    end
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        rx_shift_reg <= 0;
    end
    else rx_shift_reg[bit_count]<=spi_input;
end

/*
module spi_shift_register_rx #(
    parameter DATA_WIDTH = 8,
    parameter LSB_FIRST  = 1'b0
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     cs_active,
    input  wire                     cs_start,
    input  wire                     cs_end,
    input  wire                     sample_stb,
    input  wire                     mosi_s,
    output wire [DATA_WIDTH-1:0]    rx_byte,
    output reg                      byte_done
);

    reg [DATA_WIDTH-1:0]            shift;
    reg [$clog2(DATA_WIDTH)-1:0]    bit_cnt;

    wire [DATA_WIDTH-1:0] shift_next = LSB_FIRST
        ? {mosi_s, shift[DATA_WIDTH-1:1]}
        : {shift[DATA_WIDTH-2:0], mosi_s};

    assign rx_byte = shift;  // 或 byte_done 时锁存到 rx_byte_r

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift     <= 0;
            bit_cnt   <= 0;
            byte_done <= 0;
        end else begin
            byte_done <= 0;
            if (cs_end) begin
                shift   <= 0;
                bit_cnt <= 0;
            end else if (cs_start)
                bit_cnt <= 0;

            if (sample_stb && cs_active) begin
                shift <= shift_next;
                if (bit_cnt == DATA_WIDTH - 1) begin
                    byte_done <= 1;
                    bit_cnt   <= 0;
                end else
                    bit_cnt <= bit_cnt + 1;
            end
        end
    end
endmodule


*/


