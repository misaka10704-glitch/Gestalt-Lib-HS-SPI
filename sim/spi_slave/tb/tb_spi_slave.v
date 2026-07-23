`timescale 1ns / 1ps

// 从机 = controller + shift；外部 Mode0 bit-bang，校验 RX（兼看 MISO）
module tb_spi_slave;

    localparam CPOL = 1'b0;
    localparam CPHA = 1'b0;
    localparam CLK_PERIOD = 10;
    localparam SCLK_HALF  = 50;

    reg clk, rst_n, sclk, cs_n, mosi;
    reg [7:0] tx_data;
    wire miso_ctrl_nc;
    wire miso;
    wire cs_active, cs_start, cs_end, sample_stb, shift_stb, mosi_s;
    wire byte_done, sending_done;
    wire [7:0] rx_data;

    integer err, rx_cnt;
    reg [7:0] rx_got [0:7];
    reg [7:0] miso_byte;

    spi_slave_controller #(.CPOL(CPOL), .CPHA(CPHA)) u_ctrl (
        .clk(clk), .sclk(sclk), .rst_n(rst_n),
        .mosi(mosi), .cs_n(cs_n), .miso(miso_ctrl_nc),
        .cs_active(cs_active), .cs_start(cs_start), .cs_end(cs_end),
        .sample_stb(sample_stb), .shift_stb(shift_stb),
        .mosi_s(mosi_s), .tx_bit(1'b0)
    );

    spi_slave_shift #(.DATA_DEEPTH(8), .LSB_First(0)) u_shift (
        .clk(clk), .rst_n(rst_n),
        .mosi(mosi_s), .cs_n(cs_n), .miso(miso),
        .cs_active(cs_active), .cs_start(cs_start), .cs_end(cs_end),
        .sample_stb(sample_stb), .shift_stb(shift_stb),
        .byte_done(byte_done), .rx_data(rx_data),
        .tx_data(tx_data), .sending_done(sending_done)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    always @(posedge clk) begin
        if (byte_done) begin
            rx_got[rx_cnt] = rx_data;
            rx_cnt = rx_cnt + 1;
        end
    end

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_spi_slave);
    end

    task automatic wait_sys;
        input integer n;
        integer k;
        begin for (k = 0; k < n; k = k + 1) @(posedge clk); end
    endtask

    task automatic xfer_byte_capture_miso;
        input  [7:0] mosi_b;
        output [7:0] miso_b;
        integer bit_i;
        begin
            miso_b = 8'h00;
            for (bit_i = 7; bit_i >= 0; bit_i = bit_i - 1) begin
                mosi = mosi_b[bit_i];
                #(SCLK_HALF);
                sclk = 1'b1;
                miso_b[bit_i] = miso;
                #(SCLK_HALF);
                sclk = 1'b0;
            end
        end
    endtask

    initial begin
        err = 0;
        rx_cnt = 0;
        sclk = CPOL;
        cs_n = 1'b1;
        mosi = 1'b0;
        tx_data = 8'h00;
        rst_n = 1'b0;
        wait_sys(20);
        rst_n = 1'b1;
        wait_sys(10);

        // --- 帧1：三字节 RX ---
        tx_data = 8'hF0;
        cs_n = 1'b0;
        wait_sys(12); // cs_start 预装 TX

        xfer_byte_capture_miso(8'hA5, miso_byte);
        if (miso_byte !== 8'hF0) begin
            $display("[ERR] miso0 got=%02h exp=F0", miso_byte);
            err = err + 1;
        end
        wait_sys(4);
        tx_data = 8'h0F;
        wait_sys(2);

        xfer_byte_capture_miso(8'h3C, miso_byte);
        wait_sys(4);
        tx_data = 8'h55;
        wait_sys(2);

        xfer_byte_capture_miso(8'h99, miso_byte);
        wait_sys(8);
        cs_n = 1'b1;
        wait_sys(20);

        if (rx_cnt != 3) begin
            $display("[ERR] rx_cnt=%0d expect 3", rx_cnt);
            err = err + 1;
        end
        if (rx_got[0] !== 8'hA5) begin $display("[ERR] rx0=%02h", rx_got[0]); err = err + 1; end
        if (rx_got[1] !== 8'h3C) begin $display("[ERR] rx1=%02h", rx_got[1]); err = err + 1; end
        if (rx_got[2] !== 8'h99) begin $display("[ERR] rx2=%02h", rx_got[2]); err = err + 1; end

        // --- 半帧打断后下一帧仍正确 ---
        rx_cnt = 0;
        cs_n = 1'b0;
        wait_sys(8);
        begin : partial
            integer bit_i;
            for (bit_i = 7; bit_i >= 4; bit_i = bit_i - 1) begin
                mosi = 1'b1;
                #(SCLK_HALF); sclk = 1'b1;
                #(SCLK_HALF); sclk = 1'b0;
            end
        end
        cs_n = 1'b1;
        wait_sys(15);

        tx_data = 8'h00;
        cs_n = 1'b0;
        wait_sys(12);
        xfer_byte_capture_miso(8'h81, miso_byte);
        wait_sys(10);
        cs_n = 1'b1;
        wait_sys(15);
        if (rx_cnt != 1 || rx_got[0] !== 8'h81) begin
            $display("[ERR] after abort rx_cnt=%0d rx0=%02h", rx_cnt, rx_got[0]);
            err = err + 1;
        end

        if (err == 0)
            $display("[PASS] tb_spi_slave");
        else
            $display("[FAIL] tb_spi_slave err=%0d", err);
        $finish;
    end

endmodule
