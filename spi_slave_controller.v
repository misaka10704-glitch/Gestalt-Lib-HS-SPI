`timescale 1ns / 1ps

module spi_slave_controller
#(
    parameter CPOL = 1'b0,
	parameter CPHA = 1'b0
)
(

 input wire clk, //系统时钟
 input wire sclk, //外部时钟
 input wire rst_n,
 input wire mosi,
 input wire cs_n, //低电平有效,选中
 output wire miso,

 output wire cs_active,//正在传输flag
 output wire cs_start,//传输开始脉冲
 output wire cs_end,//传输结束脉冲

 output wire sample_stb,//采样脉冲
 output wire shift_stb,//移位脉冲
 //用于将sclk转换为FPGA内部时钟，cs的分拆也有同样目的
 //将亚稳态的sclk转为确定名称的脉冲
 //这样分拆，使得下游shift，免除了always判断的部分

 output wire mosi_s,//同步spi输入
 //这里要用fifo缓冲，以便原mosi维持不变速度输入
 //而另一边，可以速度不变地读取、处理数据

 input  wire tx_bit //TX移位寄存器的bit

);

/*
双触发同步器：

外部时钟sclk与FPGA内部系统时钟clk无关，因此若使用clk去采集一个异步信号时，采样时刻可能正好撞上这个信号的翻转沿；此时触发器输出会进入 亚稳态（metastability）：既不是稳定的 0 也不是稳定的 1，而是在 Vih/Vil 之间悬着一个不确定的电压，并且需要一段随机时间才会"决议"到 0 或 1。

双触发同步器的原理并非消除亚稳态，而是给亚稳态留出决议时间，把它逃逸到下游的概率压到可忽略。

经过两轮之后，FF2的输出clk基本稳定；
*/
	reg [2:0] sclk_sync;
	reg [2:0] mosi_sync;
	reg [2:0] cs_n_sync;

always@(posedge clk or negedge rst_n)begin

	if(!rst_n)begin
		sclk_sync<=3'b00;
		cs_n_sync<=3'b11;
		mosi_sync<=3'b00;
	end
	else begin
		sclk_sync<={sclk_sync[1:0],sclk};
		cs_n_sync<={cs_n_sync[1:0],cs_n};
		mosi_sync<={mosi_sync[1:0],mosi};
	end
end

	assign mosi_s=mosi_sync[1];
	//取稳定值

    assign cs_active = ~cs_n_sync[1];
    assign cs_start  =  cs_n_sync[2] & ~cs_n_sync[1];
    assign cs_end    = ~cs_n_sync[2] &  cs_n_sync[1];
	//边缘检测器设计

/*
CPOL/CPHA逻辑
CPOL：空闲时sclk电平
CPHA：边沿相位，决定第一/第二个边沿采样
此处将提炼出采样信号和移位信号，以便下一级移位寄存器，可以只专注移位功能
*/

	wire rising_edge = ~sclk_sync[2] & sclk_sync[1];
	wire falling_edge = sclk_sync[2] & ~sclk_sync[1];
//上升沿脉冲信号&下降沿脉冲信号
	reg sample_internal;
	reg shift_internal;

always@(*)begin
	case({CPOL,CPHA})
		2'b00:begin
			sample_internal=rising_edge;
			shift_internal=falling_edge;
			end
		2'b01:begin
			sample_internal=falling_edge;
			shift_internal=rising_edge;
			end
		2'b10:begin
			sample_internal=rising_edge;
			shift_internal=falling_edge;
			end
		2'b11:begin
			sample_internal=falling_edge;
			shift_internal=rising_edge;
			end
		default:begin
			sample_internal=rising_edge;
			shift_internal=falling_edge;
			end
	endcase
end
//由于系统从电平系统压缩为脉冲系统，因此实际上，只有两种模式
//0-2和1-3都能归结为一种SPI模式

assign sample_stb = cs_active & sample_internal;
assign shift_stb = cs_active & shift_internal;

assign miso = cs_active ? tx_bit : 1'b0;

endmodule












