`timescale 1ns / 1ps

/*
lab_sys_core：连续捕捉 → SPI 整段回环比对 → UART 上送「单次快照」

SPI 主从引脚分离，便于：
  - 理想版：顶层 o→i 短接
  - 非理想版：o/i 引出飞线（SCLK、MOSI 两对）

帧：AA 55 | SEQ | N | ERR | DATA[N] | XOR
*/
module lab_sys_core#(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD = 115200,
    parameter ADC_CLK_HZ = 1_000_000,
    parameter FRAME_N = 128,
    parameter SPI_CLK_DIV = 4,
    parameter AFIFO_DEPTH = 512,
    parameter WAVE_SEL = 1
)
(
    input wire clk,
    input wire rst_n,
    input wire enable,
    output wire uart_tx,
    output wire busy,
    output wire pulse_frame,
    output wire adc_clk,
    output wire spi_err_flag,
    output wire [7:0] spi_err_cnt,
    // Master 侧输出（可引出）
    output wire spi_sclk_o,
    output wire spi_mosi_o,
    output wire spi_cs_n,
    // Slave 侧输入（可从飞线回来）
    input wire spi_sclk_i,
    input wire spi_mosi_i,
    // Slave MISO（片内可接 Master.miso；外环可不接）
    output wire spi_miso
);

localparam N = FRAME_N;
localparam integer HALF = CLK_FREQ / (2 * ADC_CLK_HZ);
localparam FRAME_LEN = 2 + 1 + 1 + 1 + N + 1; // AA55 SEQ N ERR DATA XOR

// -------- adc_clk（分频+相移）--------
reg [31:0] adc_div;
reg adc_clk_r;

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        adc_div <= HALF[31:0] >> 1;
        adc_clk_r <= 1'b0;
    end
    else if(adc_div >= HALF[31:0]-1)begin
        adc_div <= 0;
        adc_clk_r <= ~adc_clk_r;
    end
    else
        adc_div <= adc_div + 1'b1;
end

assign adc_clk = adc_clk_r;

reg rst_a1, rst_a2;
always@(posedge adc_clk or negedge rst_n)begin
    if(!rst_n)begin
        rst_a1<=0;
        rst_a2<=0;
    end
    else begin
        rst_a1<=1'b1;
        rst_a2<=rst_a1;
    end
end
wire rst_n_adc = rst_a2;

reg adc_run;
reg [1:0] en_a;
always@(posedge adc_clk or negedge rst_n_adc)begin
    if(!rst_n_adc)
        en_a<=0;
    else
        en_a<={en_a[0], adc_run};
end
wire adc_en = en_a[1];

wire [7:0] adc_sample;
wire adc_stb;

generate
if(WAVE_SEL == 0)begin : g_tri
    triangle_gen#(
        .CLK_FREQ(ADC_CLK_HZ),
        .SAMPLE_HZ(ADC_CLK_HZ)
    ) u_tri (
        .clk(adc_clk),
        .rst_n(rst_n_adc),
        .enable(adc_en),
        .sample(adc_sample),
        .sample_stb(adc_stb)
    );
end
else begin : g_sin
    sine_gen#(
        .CLK_FREQ(ADC_CLK_HZ),
        .SAMPLE_HZ(ADC_CLK_HZ),
        .PHASE_INC(1)
    ) u_sin (
        .clk(adc_clk),
        .rst_n(rst_n_adc),
        .enable(adc_en),
        .sample(adc_sample),
        .sample_stb(adc_stb)
    );
end
endgenerate

wire af_full, af_empty;
wire [7:0] af_rdata;
reg af_wr_en;
reg [7:0] af_wdata;
reg af_rd_en;

async_fifo#(
    .DATA_WIDTH(8),
    .DATA_DEEPTH(AFIFO_DEPTH)
) u_afifo (
    .full(af_full),
    .empty(af_empty),
    .wclk(adc_clk),
    .rclk(clk),
    .wdata(af_wdata),
    .rdata(af_rdata),
    .rst_n(rst_n),
    .wr_en(af_wr_en),
    .rd_en(af_rd_en)
);

always@(posedge adc_clk or negedge rst_n_adc)begin
    if(!rst_n_adc)begin
        af_wr_en<=0;
        af_wdata<=0;
    end
    else begin
        af_wr_en<=0;
        if(adc_en && adc_stb && !af_full)begin
            af_wr_en<=1;
            af_wdata<=adc_sample;
        end
    end
end

reg [7:0] adc_buf [0:N-1];
reg [7:0] adc_cnt;
reg af_rd_pend;

wire m_busy;
wire m_cs_active, m_cs_start, m_cs_end, m_byte_done;
wire [7:0] m_rx_data;
wire [7:0] m_tx_data;
reg m_start;

wire s_cs_active, s_cs_start, s_cs_end;
wire s_sample_stb, s_shift_stb, s_mosi_s;
wire s_byte_done;
wire s_sending_done;
wire s_ctrl_miso_nc;
wire [7:0] s_rx_data;

reg [7:0] spi_tx_idx;
reg [7:0] spi_rx_buf [0:N-1];
reg [7:0] spi_rx_cnt;
reg spi_rx_full;

assign m_tx_data = adc_buf[spi_tx_idx];

spi_master#(
    .CPOL(1'b0),
    .CPHA(1'b0),
    .DATA_DEEPTH(8),
    .LSB_First(0),
    .CLK_DIV(SPI_CLK_DIV),
    .USE_PLL(0)
) u_mst (
    .clk(clk),
    .rst_n(rst_n),
    .pll_clk(clk),
    .pll_locked(1'b1),
    .sclk(spi_sclk_o),
    .mosi(spi_mosi_o),
    .miso(spi_miso),
    .cs_n(spi_cs_n),
    .start(m_start),
    .xfer_bytes(N[7:0]),
    .busy(m_busy),
    .cs_active(m_cs_active),
    .cs_start(m_cs_start),
    .cs_end(m_cs_end),
    .byte_done(m_byte_done),
    .rx_data(m_rx_data),
    .tx_data(m_tx_data)
);

spi_slave_controller#(
    .CPOL(1'b0),
    .CPHA(1'b0)
) u_slv_ctrl (
    .clk(clk),
    .sclk(spi_sclk_i),
    .rst_n(rst_n),
    .mosi(spi_mosi_i),
    .cs_n(spi_cs_n),
    .miso(s_ctrl_miso_nc),
    .cs_active(s_cs_active),
    .cs_start(s_cs_start),
    .cs_end(s_cs_end),
    .sample_stb(s_sample_stb),
    .shift_stb(s_shift_stb),
    .mosi_s(s_mosi_s),
    .tx_bit(1'b0)
);

spi_slave_shift#(
    .DATA_DEEPTH(8),
    .LSB_First(0)
) u_slv_shift (
    .clk(clk),
    .rst_n(rst_n),
    .mosi(s_mosi_s),
    .cs_n(spi_cs_n),
    .miso(spi_miso),
    .cs_active(s_cs_active),
    .cs_start(s_cs_start),
    .cs_end(s_cs_end),
    .sample_stb(s_sample_stb),
    .shift_stb(s_shift_stb),
    .byte_done(s_byte_done),
    .rx_data(s_rx_data),
    .tx_data(8'h00),
    .sending_done(s_sending_done)
);

wire tx_busy;
reg tx_start;
reg [7:0] tx_data;

uart_tx#(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(BAUD)
) u_uart (
    .clk(clk),
    .rst_n(rst_n),
    .tx_start(tx_start),
    .tx_data(tx_data),
    .tx_busy(tx_busy),
    .uart_tx(uart_tx)
);

reg [7:0] frame_mem [0:FRAME_LEN-1];
reg [8:0] frame_idx; // FRAME_LEN 最大约 262
reg [7:0] xor_acc;
reg [7:0] seq;
reg [7:0] seq_latch;
reg frame_pulse_r;

reg [7:0] cmp_i;
reg [7:0] err_byte;
reg err_sticky;

assign spi_err_flag = err_sticky;
assign spi_err_cnt = err_byte;

localparam S_IDLE  = 4'd0;
localparam S_FLUSH = 4'd1;
localparam S_SAMP  = 4'd2;
localparam S_SPI   = 4'd3;
localparam S_CMP   = 4'd4;
localparam S_BUILD = 4'd5;
localparam S_ISSUE = 4'd6;
localparam S_WBUSY = 4'd7;
localparam S_WIDLE = 4'd8;

reg [3:0] state;
reg [7:0] build_i;

assign busy = (state != S_IDLE) || m_busy || tx_busy || adc_run;
assign pulse_frame = frame_pulse_r;

integer i;
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        state<=S_IDLE;
        adc_run<=0;
        adc_cnt<=0;
        af_rd_en<=0;
        af_rd_pend<=0;
        m_start<=0;
        spi_tx_idx<=0;
        spi_rx_cnt<=0;
        spi_rx_full<=0;
        seq<=0;
        seq_latch<=0;
        xor_acc<=0;
        frame_idx<=0;
        build_i<=0;
        cmp_i<=0;
        err_byte<=0;
        err_sticky<=0;
        tx_start<=0;
        tx_data<=0;
        frame_pulse_r<=0;
        for(i=0;i<N;i=i+1)begin
            adc_buf[i]<=0;
            spi_rx_buf[i]<=0;
        end
        for(i=0;i<FRAME_LEN;i=i+1)
            frame_mem[i]<=0;
    end
    else begin
        m_start<=0;
        tx_start<=0;
        frame_pulse_r<=0;
        af_rd_en<=0;

        if(m_cs_start)
            spi_tx_idx<=0;
        else if(m_byte_done && m_busy && spi_tx_idx != N-1)
            spi_tx_idx<=spi_tx_idx+8'd1;

        if(s_cs_start)
            spi_rx_cnt<=0;
        else if(s_byte_done)begin
            spi_rx_buf[spi_rx_cnt]<=s_rx_data;
            if(spi_rx_cnt == N-1)
                spi_rx_full<=1;
            else
                spi_rx_cnt<=spi_rx_cnt+8'd1;
        end

        case(state)
        S_IDLE:begin
            if(enable)begin
                adc_run<=0;
                af_rd_pend<=0;
                state<=S_FLUSH;
            end
        end

        S_FLUSH:begin
            if(af_rd_pend)
                af_rd_pend<=0;
            else if(!af_empty)begin
                af_rd_en<=1;
                af_rd_pend<=1;
            end
            else begin
                adc_cnt<=0;
                spi_rx_full<=0;
                adc_run<=1;
                state<=S_SAMP;
            end
        end

        S_SAMP:begin
            //连续采满 N 点（同一时间轴，无 UART 间隔）
            if(af_rd_pend)begin
                af_rd_pend<=0;
                adc_buf[adc_cnt]<=af_rdata;
                if(adc_cnt == N-1)begin
                    adc_run<=0;
                    spi_rx_full<=0;
                    spi_rx_cnt<=0;
                    m_start<=1;
                    state<=S_SPI;
                end
                else
                    adc_cnt<=adc_cnt+8'd1;
            end
            else if(!af_empty)begin
                af_rd_en<=1;
                af_rd_pend<=1;
            end
        end

        S_SPI:begin
            if(!m_busy && !m_start && spi_rx_full)begin
                cmp_i<=0;
                err_byte<=0;
                state<=S_CMP;
            end
        end

        S_CMP:begin
            //逐字节比对：真 SPI/移位错误会出现在这里
            if(adc_buf[cmp_i] != spi_rx_buf[cmp_i])begin
                if(err_byte != 8'hFF)
                    err_byte<=err_byte+8'd1;
                err_sticky<=1;
            end
            if(cmp_i == N-1)begin
                seq_latch<=seq+8'd1;
                seq<=seq+8'd1;
                build_i<=0;
                xor_acc<=0;
                frame_pulse_r<=1;
                state<=S_BUILD;
            end
            else
                cmp_i<=cmp_i+8'd1;
        end

        S_BUILD:begin
            // [0]=AA [1]=55 [2]=SEQ [3]=N [4]=ERR [5..]=DATA [5+N]=XOR
            if(build_i == 8'd0)begin
                frame_mem[0]<=8'hAA;
                frame_mem[1]<=8'h55;
                frame_mem[2]<=seq_latch;
                frame_mem[3]<=N[7:0];
                frame_mem[4]<=err_byte;
                xor_acc<=seq_latch ^ N[7:0] ^ err_byte;
                build_i<=8'd1;
            end
            else if(build_i <= N[7:0])begin
                frame_mem[8'd4 + build_i]<=spi_rx_buf[build_i - 8'd1]; // 5+(i-1)
                xor_acc<=xor_acc ^ spi_rx_buf[build_i - 8'd1];
                build_i<=build_i+8'd1;
            end
            else begin
                frame_mem[8'd5 + N[7:0]]<=xor_acc;
                frame_idx<=0;
                state<=S_ISSUE;
            end
        end

        S_ISSUE:begin
            if(!tx_busy)begin
                tx_data<=frame_mem[frame_idx];
                tx_start<=1;
                state<=S_WBUSY;
            end
        end

        S_WBUSY:begin
            if(tx_busy)
                state<=S_WIDLE;
        end

        S_WIDLE:begin
            if(!tx_busy)begin
                if(frame_idx == FRAME_LEN[8:0]-9'd1)begin
                    if(enable)begin
                        adc_run<=0;
                        af_rd_pend<=0;
                        state<=S_FLUSH;
                    end
                    else
                        state<=S_IDLE;
                end
                else begin
                    frame_idx<=frame_idx+9'd1;
                    state<=S_ISSUE;
                end
            end
        end

        default:state<=S_IDLE;
        endcase
    end
end

endmodule
