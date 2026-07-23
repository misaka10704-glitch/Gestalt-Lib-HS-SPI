`timescale 1ns / 1ps

// Master Mode0：MISO=MOSI 回环，校验多字节收发 + busy/cs 波形
module tb_spi_master;

    localparam CLK_PERIOD = 10;
    localparam CLK_DIV    = 4;
    localparam N_BYTES    = 4;

    reg clk, rst_n, start;
    reg [7:0] xfer_bytes;
    reg [7:0] tx_rom [0:15];
    reg [7:0] tx_idx;
    wire [7:0] tx_data = tx_rom[tx_idx];
    wire [7:0] rx_data;
    wire sclk, mosi, cs_n, busy;
    wire cs_active, cs_start, cs_end, byte_done;
    wire miso = mosi; // 回环

    integer err, rx_cnt, i;
    reg [7:0] rx_got [0:15];

    spi_master #(
        .CPOL(0), .CPHA(0),
        .DATA_DEEPTH(8),
        .LSB_First(0),
        .CLK_DIV(CLK_DIV),
        .CLK_DIV_FAST(CLK_DIV)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .use_fast(1'b0),
        .pll_clk(clk), .pll_locked(1'b1),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n),
        .start(start), .xfer_bytes(xfer_bytes), .busy(busy),
        .cs_active(cs_active), .cs_start(cs_start), .cs_end(cs_end),
        .byte_done(byte_done), .rx_data(rx_data), .tx_data(tx_data)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // 与 lab_sys 相同：组合取数；cs_start 清索引，byte_done 推进（最后一字节不越界）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tx_idx <= 0;
        else if (cs_start)
            tx_idx <= 0;
        else if (byte_done && busy && (tx_idx + 8'd1 < xfer_bytes))
            tx_idx <= tx_idx + 8'd1;
    end

    always @(posedge clk) begin
        if (byte_done) begin
            rx_got[rx_cnt] = rx_data;
            rx_cnt = rx_cnt + 1;
        end
    end

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_spi_master);
    end

    initial begin
        err = 0;
        rx_cnt = 0;
        start = 0;
        xfer_bytes = N_BYTES;
        for (i = 0; i < 16; i = i + 1)
            tx_rom[i] = 8'h00;
        tx_rom[0] = 8'hA1;
        tx_rom[1] = 8'hB2;
        tx_rom[2] = 8'hC3;
        tx_rom[3] = 8'hD4;
        for (i = 0; i < 16; i = i + 1)
            rx_got[i] = 8'h00;
        rst_n = 0;
        repeat (20) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        if (cs_n !== 1'b1 || busy !== 1'b0) begin
            $display("[ERR] idle cs/busy");
            err = err + 1;
        end

        tx_idx = 0;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        wait (busy == 1'b1);
        wait (busy == 1'b0);
        repeat (5) @(posedge clk);

        if (rx_cnt != N_BYTES) begin
            $display("[ERR] rx_cnt=%0d expect %0d", rx_cnt, N_BYTES);
            err = err + 1;
        end
        for (i = 0; i < N_BYTES; i = i + 1) begin
            if (rx_got[i] !== tx_rom[i]) begin
                $display("[ERR] byte%0d got=%02h exp=%02h", i, rx_got[i], tx_rom[i]);
                err = err + 1;
            end
        end
        if (cs_n !== 1'b1) begin
            $display("[ERR] cs not released");
            err = err + 1;
        end

        // 第二帧：单字节（start 前清索引，避免 cs_start 同拍晚一拍）
        rx_cnt = 0;
        rx_got[0] = 8'h00;
        xfer_bytes = 8'd1;
        tx_rom[0] = 8'h5A;
        tx_idx = 0;
        repeat (5) @(posedge clk);
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        wait (busy == 1'b1);
        wait (busy == 1'b0);
        repeat (10) @(posedge clk);
        if (rx_cnt != 1) begin
            $display("[ERR] single rx_cnt=%0d", rx_cnt);
            err = err + 1;
        end
        if (rx_got[0] !== 8'h5A) begin
            $display("[ERR] single got=%02h", rx_got[0]);
            err = err + 1;
        end

        if (err == 0)
            $display("[PASS] tb_spi_master");
        else
            $display("[FAIL] tb_spi_master err=%0d", err);
        $finish;
    end

endmodule
