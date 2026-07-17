module async_fifo#(
    parameter DATA_WIDTH = 1, //数据宽度，一个地址的数据位有多少bit
    parameter DATA_DEEPTH = 8//移位上限
)
(
    output reg full,
    output reg empty,

    input wire wclk,
    input wire rclk,

    input wire [DATA_WIDTH-1 : 0] wdata,
    output reg [DATA_WIDTH-1 : 0] rdata,

    input wire rst_n,
    input wire wr_en, //写，提示是否有有效数据
    input wire rd_en //读
);

//memory[地址，即DEEPTH]，memory[地址][某一位]
reg [DATA_WIDTH-1:0] memory [0:DATA_DEEPTH-1];

//log2(7)-1=3，说明需要[3:0]
localparam addr_width = $clog2(DATA_DEEPTH);
//这里的addr_width会直接使用，而非addr_width-1
//111-000会导致空满一致，因此需要0111-1000来区分空和满
//无论是gray还是binary都如此
reg [addr_width:0] wptr;
reg [addr_width:0] rptr;

//1. 读写控制

integer  i;
//非满时，memory正常写；不过之后要做个预警位（内部）
//由于两个都在rst_n=0时激活，因此只在一处写memory复位
always@(posedge wclk or negedge rst_n)begin
    if(!rst_n) begin
        for (i = 0; i < DATA_DEEPTH; i = i + 1)begin
            memory[i] <= {DATA_WIDTH{1'b0}};end 
            //for循环清理fifo
        wptr<=0;
    end
    else if(!full && wr_en) begin
        memory[wptr[addr_width-1:0]]<=wdata;
        //这里不能直接用ptr，因为为了适配gray，ptr比真实要求多一个bit
        wptr<=wptr+1;
    end
end

//非空时，memory正常读，也要加个预警位
always@(posedge rclk or negedge rst_n)begin
    if(!rst_n) begin
        rptr<=0;
    end
    else if(!empty && rd_en) begin
        rdata<=memory[rptr[addr_width-1:0]];
        rptr<=rptr+1;
    end
end

//2. 双稳态&空满判定
//gray双稳态
/*这里的gray仍然在自己的域内，我们需要他们被
对面域的FF2采样，然后在对面域转为二进制，进行比对；
*/
//转为gray，恰恰就是为了在对面域采样时，减少多翻
wire [addr_width:0] wgray = wptr ^ (wptr >> 1); 
wire [addr_width:0] rgray = rptr ^ (rptr >> 1);

//先进入rclk域的双稳态
reg [addr_width:0] wgray_r1;
reg [addr_width:0] wgray_r2;

always@(posedge rclk or negedge rst_n)begin
    if(!rst_n)begin
        wgray_r1<=0;
        wgray_r2<=0;
    end
    else begin
        wgray_r1 <= wgray;   // 整个 Gray 总线进第 1 级
        wgray_r2 <= wgray_r1;
    end
end
//从双稳态取出稳态gray
wire [addr_width:0] wgray_rq = wgray_r2;

//空判断，不用二进制，直接比对即可
always@(posedge rclk or negedge rst_n)begin
    if(!rst_n)empty<=1;
    else empty <= (wgray_rq == rgray);
end

//然后进入wclk域的双稳态
reg [addr_width:0] rgray_w1;
reg [addr_width:0] rgray_w2;

always@(posedge wclk or negedge rst_n)begin
    if(!rst_n)begin
        rgray_w1<=0;
        rgray_w2<=0;
    end
    else begin
        rgray_w1 <= rgray;   // 整个 Gray 总线进第 1 级
        rgray_w2 <= rgray_w1;
    end
end
//从双稳态取出稳态gray
wire [addr_width:0] rgray_wq = rgray_w2;

//满判断，用格雷码比对（格雷码转二进制较为复杂）
//满就是最高两位反相，其余相等
always@(posedge wclk or negedge rst_n)begin
    if(!rst_n)full<=0;
    else full <= (wgray == {~rgray_wq[addr_width:addr_width-1],
                             rgray_wq[addr_width-2:0]});
    //高两位反相，其余等于
end

endmodule
