module spi_shift#(
    parameter DATA_WIDTH = 8,
    parameter LSB_FIRST  = 1'b0
)
(
    input wire sample_stb,//面向rx
    input wire shift_stb,//面向tx
    input wire cs_active,
    input wire cs_start,
    input wire cs_end,
    input wire mosi,
    output wire miso,
    
    output reg byte_done,

    input wire clk,
    input wire rst_n

    //tx部分待会再写

);

reg [DATA_WIDTH-1:0] rx_register_fluent;
reg [DATA_WIDTH-1:0] rx_register_solid;
reg [3:0] rx_cnt; //计数，待优化

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) rx_cnt<=0;
    else if(sample_stb & cs_active &(rx_cnt<DATA_WIDTH-1)) rx_cnt<=rx_cnt+1;
    else if(sample_stb & cs_active &(rx_cnt==DATA_WIDTH-1)) rx_cnt<=0;
end
//计数

/*
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) rx_register_fluent<=0;
    else if(sample_stb & cs_active & ~LSB_FIRST) rx_register_fluent[0] <= mosi;
    else if(sample_stb & cs_active & LSB_FIRST) rx_register_fluent[DATA_WIDTH-1] <= mosi;
end
//采样


always @(posedge clk) begin
    if(shift_stb & cs_active) rx_register_fluent <= rx_register_fluent>>1;
end
//移位
*/



always @(posedge clk or negedge rst_n) begin
    if(!rst_n) rx_register_fluent<=0;
    else if(sample_stb & cs_active & ~LSB_FIRST) rx_register_fluent <= {rx_register_fluent[DATA_WIDTH-2:0],mosi};
    else if(sample_stb & cs_active & LSB_FIRST) rx_register_fluent <= {mosi,rx_register_fluent[DATA_WIDTH-1:1]};
end
//采样+移位;同时进行 (这里都是fluent)


always @(posedge clk or negedge rst_n) begin
    if(!rst_n)rx_register_solid<=0;
    else if((rx_cnt==0) & (sample_stb ==0) & cs_active)begin
        rx_register_solid<=rx_register_fluent;
        byte_done <=1;
    end
    else if((rx_cnt==0) & (sample_stb ==1) & cs_active)begin
        rx_register_solid<=rx_register_solid;
        byte_done <=0;
    end
end
//固化register;改cnt可以延长byte_done存在的时间















/*
always@(posedge sclk or negedge rst_n)begin
    if(!rst_n) rx_register <= 8'b0;
    else rx_register <= {rx_register[DATA_WIDTH-2:0],mosi};
end

always@(posedge sclk or negedge rst_n)begin
    if(!rst_n) rx_cnt <= 0;
    else if(rx_cnt < DATA_WIDTH-1) rx_cnt <= rx_cnt + 1;
    else rx_cnt <=0;
end
*/






endmodule