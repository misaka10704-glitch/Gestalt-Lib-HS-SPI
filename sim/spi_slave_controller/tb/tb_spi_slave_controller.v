`timescale 1ns / 1ps

// Mode0 controller：外部 bit-bang SPI → 查 cs_*/sample/shift 脉冲
module tb_spi_slave_controller;

    localparam CPOL = 1'b0;
    localparam CPHA = 1'b0;
    localparam CLK_PERIOD  = 10;   // 100 MHz sys
    localparam SCLK_HALF   = 50;   // 10 MHz sclk

    reg clk, rst_n, sclk, cs_n, mosi;
    wire miso;
    wire cs_active, cs_start, cs_end, sample_stb, shift_stb, mosi_s;

    integer err, i, n_sample, n_shift;
    reg [7:0] tx_byte;

    spi_slave_controller #(.CPOL(CPOL), .CPHA(CPHA)) dut (
        .clk(clk), .sclk(sclk), .rst_n(rst_n),
        .mosi(mosi), .cs_n(cs_n), .miso(miso),
        .cs_active(cs_active), .cs_start(cs_start), .cs_end(cs_end),
        .sample_stb(sample_stb), .shift_stb(shift_stb),
        .mosi_s(mosi_s), .tx_bit(1'b1)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    always @(posedge clk) begin
        if (sample_stb) n_sample = n_sample + 1;
        if (shift_stb)  n_shift  = n_shift  + 1;
    end

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_spi_slave_controller);
    end

    task automatic wait_sys;
        input integer n;
        integer k;
        begin for (k = 0; k < n; k = k + 1) @(posedge clk); end
    endtask

    // Mode0：空闲 sclk=0；下降沿后改 MOSI，上升沿采样
    task automatic xfer_byte;
        input [7:0] b;
        integer bit_i;
        begin
            for (bit_i = 7; bit_i >= 0; bit_i = bit_i - 1) begin
                mosi = b[bit_i];
                #(SCLK_HALF);
                sclk = 1'b1;
                #(SCLK_HALF);
                sclk = 1'b0;
            end
        end
    endtask

    initial begin
        err = 0;
        n_sample = 0;
        n_shift = 0;
        sclk = CPOL;
        cs_n = 1'b1;
        mosi = 1'b0;
        rst_n = 1'b0;
        wait_sys(20);
        rst_n = 1'b1;
        wait_sys(10);

        // --- 单字节 0xA5 ---
        n_sample = 0;
        n_shift = 0;
        cs_n = 1'b0;
        wait_sys(8); // 等同步出 cs_start / cs_active
        if (!cs_active) begin
            $display("[ERR] cs_active after CS low");
            err = err + 1;
        end
        xfer_byte(8'hA5);
        wait_sys(8);
        if (n_sample != 8) begin
            $display("[ERR] sample_stb count=%0d expect 8", n_sample);
            err = err + 1;
        end
        if (n_shift != 8) begin
            $display("[ERR] shift_stb count=%0d expect 8", n_shift);
            err = err + 1;
        end
        cs_n = 1'b1;
        wait_sys(12);
        if (cs_active) begin
            $display("[ERR] cs_active stuck after CS high");
            err = err + 1;
        end

        // --- 连传两字节 ---
        n_sample = 0;
        n_shift = 0;
        cs_n = 1'b0;
        wait_sys(8);
        xfer_byte(8'h12);
        xfer_byte(8'h34);
        wait_sys(8);
        if (n_sample != 16) begin
            $display("[ERR] 2B sample=%0d expect 16", n_sample);
            err = err + 1;
        end
        if (n_shift != 16) begin
            $display("[ERR] 2B shift=%0d expect 16", n_shift);
            err = err + 1;
        end
        cs_n = 1'b1;
        wait_sys(20);

        // miso 在 cs_active 时应跟 tx_bit=1
        cs_n = 1'b0;
        wait_sys(10);
        if (miso !== 1'b1) begin
            $display("[ERR] miso expect 1 while active");
            err = err + 1;
        end
        cs_n = 1'b1;
        wait_sys(10);
        if (miso !== 1'b0) begin
            $display("[ERR] miso expect 0 while idle");
            err = err + 1;
        end

        if (err == 0)
            $display("[PASS] tb_spi_slave_controller");
        else
            $display("[FAIL] tb_spi_slave_controller err=%0d", err);
        $finish;
    end

endmodule
