`timescale 1ns / 1ps

module spi_verify_top#(
    parameter DATA_DEEPTH = 8,
    parameter FIFO_DEPTH = 16,
    parameter XFER_N = 8, //本帧字节数
    parameter CLK_DIV = 8, //master分频；板载clk较慢时可加大
    parameter CPOL = 1'b0,
    parameter CPHA = 1'b0,
    parameter LSB_First = 0,
    parameter USE_PLL = 0, //0：引擎用clk；上板接PLL后改1
    parameter LOOPBACK = 1 //1：片内主从自环；0：miso走外部管脚
)
(
    input wire clk, //板载晶振/系统时钟
    input wire rst_n,

    //PLL预留（Gowin PLL IP：clk→pll_clk；未用时pll_clk接clk、locked=1）
    input wire pll_clk,
    input wire pll_locked,

    input wire btn_start, //启动一次自测（建议机械按键，内部做沿检测）

    output wire led_busy,
    output wire led_pass,
    output wire led_fail,
    output wire led_overflow, //fifo溢出/欠载粘滞提示

    //SPI管脚：LOOPBACK=1时仍可引出观察；=0时miso须外接回环或真从机
    output wire spi_sclk,
    output wire spi_mosi,
    input wire spi_miso_ext,
    output wire spi_cs_n
);

/*
初级验证系统（对照 README Phase2 + Theory 主从/FIFO链路）：

  按键 → 填 master TX FIFO（递增测试序列）
       → spi_master 发帧
       → [片内] sclk/mosi/cs → slave_controller → slave_shift
       → slave RX FIFO 应收递增序列
       → slave TX 固定回波 SLV_ECHO，master RX FIFO 应收全 SLV_ECHO
       → 比对 → led_pass / led_fail

后续：USE_PLL=1 接 Gowin PLL；LOOPBACK=0 接板外 MCU/从机。
*/

localparam [DATA_DEEPTH-1:0] SLV_ECHO = 8'h5A;
localparam [7:0] N_BYTES = XFER_N[7:0];

// ------------------------------------------------------------
// 按键沿：按下产生1拍start_req（默认低有效按键，可按板改）
// ------------------------------------------------------------
reg btn_d1, btn_d2;
//多数Gowin板按键低有效：按下为下降沿
wire btn_press = ~btn_d1 & btn_d2;

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        btn_d1<=1;
        btn_d2<=1;
    end
    else begin
        btn_d1<=btn_start;
        btn_d2<=btn_d1;
    end
end

// ------------------------------------------------------------
// 片内SPI互连
// ------------------------------------------------------------
wire m_sclk, m_mosi, m_cs_n;
wire s_miso;
wire m_miso = LOOPBACK ? s_miso : spi_miso_ext;

assign spi_sclk = m_sclk;
assign spi_mosi = m_mosi;
assign spi_cs_n = m_cs_n;

// ------------------------------------------------------------
// Master + 其 fifo_interface
// ------------------------------------------------------------
wire m_busy;
wire m_cs_active, m_cs_start, m_cs_end, m_byte_done;
wire [DATA_DEEPTH-1:0] m_rx_data;
wire [DATA_DEEPTH-1:0] m_tx_data;
wire m_tx_load; //fifo侧有，master靠cs_start延迟一拍采tx_data

wire m_sys_rd_en, m_sys_wr_en;
wire [DATA_DEEPTH-1:0] m_sys_rdata, m_sys_wdata;
wire m_sys_empty, m_sys_full;
wire m_rx_overflow, m_tx_underrun;

reg m_start;

spi_master#(
    .CPOL(CPOL),
    .CPHA(CPHA),
    .DATA_DEEPTH(DATA_DEEPTH),
    .LSB_First(LSB_First),
    .CLK_DIV(CLK_DIV),
    .USE_PLL(USE_PLL)
) u_master (
    .clk(clk),
    .rst_n(rst_n),
    .pll_clk(pll_clk),
    .pll_locked(pll_locked),
    .sclk(m_sclk),
    .mosi(m_mosi),
    .miso(m_miso),
    .cs_n(m_cs_n),
    .start(m_start),
    .xfer_bytes(N_BYTES),
    .busy(m_busy),
    .cs_active(m_cs_active),
    .cs_start(m_cs_start),
    .cs_end(m_cs_end),
    .byte_done(m_byte_done),
    .rx_data(m_rx_data),
    .tx_data(m_tx_data)
);

spi_fifo_interface#(
    .DATA_WIDTH(DATA_DEEPTH),
    .DATA_DEEPTH(FIFO_DEPTH)
) u_mst_fifo (
    .clk(clk),
    .sys_clk(clk),
    .rst_n(rst_n),
    .cs_active(m_cs_active),
    .cs_start(m_cs_start),
    .cs_end(m_cs_end),
    .byte_done(m_byte_done),
    .rx_data(m_rx_data),
    .tx_load(m_tx_load),
    .tx_data(m_tx_data),
    .rx_overflow(m_rx_overflow),
    .tx_underrun(m_tx_underrun),
    .sys_rd_en(m_sys_rd_en),
    .sys_rdata(m_sys_rdata),
    .sys_empty(m_sys_empty),
    .sys_wr_en(m_sys_wr_en),
    .sys_wdata(m_sys_wdata),
    .sys_full(m_sys_full)
);

// ------------------------------------------------------------
// Slave：controller(同步/选通) + shift(字节) + fifo(仅用RX侧核对)
// ------------------------------------------------------------
wire s_cs_active, s_cs_start, s_cs_end;
wire s_sample_stb, s_shift_stb, s_mosi_s;
wire s_byte_done;
wire [DATA_DEEPTH-1:0] s_rx_data;
wire s_sending_done;

wire s_sys_rd_en;
wire [DATA_DEEPTH-1:0] s_sys_rdata;
wire s_sys_empty;
wire s_rx_full;
reg  s_rx_overflow;

wire s_ctrl_miso_nc;

//从机回波：固定图案；RX 只用 async_fifo（避免空 TX fifo 被扫掉 NL0002）
wire [DATA_DEEPTH-1:0] s_tx_data = SLV_ECHO;

spi_slave_controller#(
    .CPOL(CPOL),
    .CPHA(CPHA)
) u_slv_ctrl (
    .clk(clk),
    .sclk(m_sclk),
    .rst_n(rst_n),
    .mosi(m_mosi),
    .cs_n(m_cs_n),
    .miso(s_ctrl_miso_nc), //miso由shift驱动
    .cs_active(s_cs_active),
    .cs_start(s_cs_start),
    .cs_end(s_cs_end),
    .sample_stb(s_sample_stb),
    .shift_stb(s_shift_stb),
    .mosi_s(s_mosi_s),
    .tx_bit(1'b0)
);

spi_slave_shift#(
    .DATA_DEEPTH(DATA_DEEPTH),
    .LSB_First(LSB_First)
) u_slv_shift (
    .clk(clk),
    .rst_n(rst_n),
    .mosi(s_mosi_s),
    .cs_n(m_cs_n),
    .miso(s_miso),
    .cs_active(s_cs_active),
    .cs_start(s_cs_start),
    .cs_end(s_cs_end),
    .sample_stb(s_sample_stb),
    .shift_stb(s_shift_stb),
    .byte_done(s_byte_done),
    .rx_data(s_rx_data),
    .tx_data(s_tx_data),
    .sending_done(s_sending_done)
);

async_fifo#(
    .DATA_WIDTH(DATA_DEEPTH),
    .DATA_DEEPTH(FIFO_DEPTH)
) u_slv_rx_fifo (
    .full(s_rx_full),
    .empty(s_sys_empty),
    .wclk(clk),
    .rclk(clk),
    .wdata(s_rx_data),
    .rdata(s_sys_rdata),
    .rst_n(rst_n),
    .wr_en(s_byte_done & ~s_rx_full),
    .rd_en(s_sys_rd_en)
);

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)
        s_rx_overflow<=0;
    else if(s_cs_end)
        s_rx_overflow<=0;
    else if(s_byte_done & s_rx_full)
        s_rx_overflow<=1;
end

// ------------------------------------------------------------
// 自测FSM：填TX → kick master → 等结束+FIFO同步settle → 核对RX
// async_fifo空满有Gray延迟，核对按固定N次读，不靠empty判失败
// ------------------------------------------------------------
localparam S_IDLE   = 3'd0;
localparam S_FILL   = 3'd1;
localparam S_KICK   = 3'd2;
localparam S_WAIT   = 3'd3;
localparam S_SETTLE = 3'd4; //等指针跨域稳定
localparam S_CHK_M  = 3'd5; //master RX 应为 SLV_ECHO
localparam S_CHK_S  = 3'd6; //slave  RX 应为 0x10+i
localparam S_DONE   = 3'd7; //pass/fail 由pass_r/fail_r区分

reg [2:0] state;
reg [7:0] fill_i;
reg [7:0] chk_i;
reg [3:0] settle_cnt;
reg rd_pend; //1：上一拍发了rd_en，本拍比rdata
reg pass_r, fail_r;
reg ovf_sticky;

reg m_sys_wr_r, m_sys_rd_r, s_sys_rd_r;
reg [DATA_DEEPTH-1:0] m_sys_wdata_r;

assign m_sys_wr_en = m_sys_wr_r;
assign m_sys_rd_en = m_sys_rd_r;
assign m_sys_wdata = m_sys_wdata_r;
assign s_sys_rd_en = s_sys_rd_r;

assign led_busy = m_busy | (state != S_IDLE && state != S_DONE);
assign led_pass = pass_r;
assign led_fail = fail_r;
assign led_overflow = ovf_sticky;

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        state<=S_IDLE;
        fill_i<=0;
        chk_i<=0;
        settle_cnt<=0;
        rd_pend<=0;
        pass_r<=0;
        fail_r<=0;
        ovf_sticky<=0;
        m_start<=0;
        m_sys_wr_r<=0;
        m_sys_rd_r<=0;
        s_sys_rd_r<=0;
        m_sys_wdata_r<=0;
    end
    else begin
        m_start<=0;
        m_sys_wr_r<=0;
        m_sys_rd_r<=0;
        s_sys_rd_r<=0;

        if(m_rx_overflow | m_tx_underrun | s_rx_overflow)
            ovf_sticky<=1;

        case(state)
        S_IDLE:begin
            if(btn_press)begin
                pass_r<=0;
                fail_r<=0;
                ovf_sticky<=0;
                fill_i<=0;
                state<=S_FILL;
            end
        end

        S_FILL:begin
            //写入 master TX：0x10,0x11,...
            if(!m_sys_full)begin
                m_sys_wr_r<=1;
                m_sys_wdata_r<=8'h10 + fill_i;
                if(fill_i == N_BYTES-1)begin
                    fill_i<=0;
                    state<=S_KICK;
                end
                else begin
                    fill_i<=fill_i+1'b1;
                end
            end
        end

        S_KICK:begin
            m_start<=1;
            state<=S_WAIT;
        end

        S_WAIT:begin
            if(!m_busy && !m_start)begin
                settle_cnt<=4'd8; //给Gray同步几拍
                state<=S_SETTLE;
            end
        end

        S_SETTLE:begin
            if(settle_cnt == 0)begin
                chk_i<=0;
                rd_pend<=0;
                state<=S_CHK_M;
            end
            else begin
                settle_cnt<=settle_cnt-4'd1;
            end
        end

        S_CHK_M:begin
            if(rd_pend)begin
                rd_pend<=0;
                if(m_sys_rdata != SLV_ECHO)begin
                    fail_r<=1;
                    state<=S_DONE;
                end
                else if(chk_i == N_BYTES-1)begin
                    chk_i<=0;
                    rd_pend<=0;
                    state<=S_CHK_S;
                end
                else begin
                    chk_i<=chk_i+1'b1;
                    m_sys_rd_r<=1;
                    rd_pend<=1;
                end
            end
            else begin
                m_sys_rd_r<=1;
                rd_pend<=1;
            end
        end

        S_CHK_S:begin
            if(rd_pend)begin
                rd_pend<=0;
                if(s_sys_rdata != (8'h10 + chk_i))begin
                    fail_r<=1;
                    state<=S_DONE;
                end
                else if(chk_i == N_BYTES-1)begin
                    pass_r<=1;
                    state<=S_DONE;
                end
                else begin
                    chk_i<=chk_i+1'b1;
                    s_sys_rd_r<=1;
                    rd_pend<=1;
                end
            end
            else begin
                s_sys_rd_r<=1;
                rd_pend<=1;
            end
        end

        S_DONE:begin
            if(btn_press)begin
                pass_r<=0;
                fail_r<=0;
                ovf_sticky<=0;
                fill_i<=0;
                state<=S_FILL;
            end
        end

        default:state<=S_IDLE;
        endcase
    end
end

endmodule
