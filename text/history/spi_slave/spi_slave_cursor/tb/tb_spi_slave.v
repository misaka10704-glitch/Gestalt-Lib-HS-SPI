`timescale 1ns / 1ps

module tb_spi_slave;

    localparam CPOL       = 1'b0;
    localparam CPHA       = 1'b0;
    localparam DATA_WIDTH = 8;

    localparam CLK_PERIOD  = 10;
    localparam SCLK_PERIOD = 100;

    reg clk;
    reg rst_n;
    reg sclk;
    reg cs_n;
    reg mosi;
    wire miso;

    wire rx_valid;
    wire [DATA_WIDTH-1:0] rx_data;
    reg  tx_ready;
    wire [DATA_WIDTH-1:0] tx_data;
    wire tx_valid;

    reg [7:0] echo_data;
    assign tx_data = echo_data;

    integer err_cnt;

    reg [7:0] rx_latched;
    reg       rx_seen;

    always @(posedge clk) begin
        if (rx_valid) begin
            rx_latched <= rx_data;
            rx_seen    <= 1'b1;
        end
    end

    spi_slave_top #(
        .CPOL       (CPOL),
        .CPHA       (CPHA),
        .DATA_WIDTH (DATA_WIDTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .sclk     (sclk),
        .cs_n     (cs_n),
        .mosi     (mosi),
        .miso     (miso),
        .rx_valid (rx_valid),
        .rx_data  (rx_data),
        .tx_ready (tx_ready),
        .tx_data  (tx_data),
        .tx_valid (tx_valid)
    );

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_spi_slave);
    end

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    initial begin
        sclk      = CPOL;
        rst_n     = 1'b0;
        cs_n      = 1'b1;
        mosi      = 1'b0;
        echo_data = 8'h00;
        tx_ready  = 1'b0;
        err_cnt   = 0;
        rx_seen   = 1'b0;

        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 10);
        tx_ready = 1'b1;

        spi_transfer(8'h55);
        spi_transfer(8'hAA);

        spi_begin();
        echo_data = 8'h00;
        repeat (1) @(posedge clk);
        spi_send_byte_check(8'h01);
        spi_send_byte_check(8'h02);
        spi_send_byte_check(8'h03);
        spi_send_byte_check(8'h04);
        spi_end();

        spi_begin();
        spi_send_byte(8'hDE);
        spi_send_n_bits(8'hAD, 4);
        spi_end();
        #(SCLK_PERIOD * 4);

        spi_begin();
        spi_send_byte(8'h12);
        spi_end();
        expect_rx(8'h12);

        #(CLK_PERIOD * 20);
        if (err_cnt == 0) begin
            $display("[PASS] tb_spi_slave");
        end else begin
            $display("[FAIL] tb_spi_slave, errors = %0d", err_cnt);
        end
        $finish;
    end

    task spi_begin;
        begin
            cs_n = 1'b0;
            #(SCLK_PERIOD / 2);
        end
    endtask

    task spi_end;
        begin
            #(SCLK_PERIOD / 2);
            cs_n = 1'b1;
            sclk = CPOL;
            #(SCLK_PERIOD);
        end
    endtask

    task spi_write_bit;
        input mosi_bit;
        begin
            mosi = mosi_bit;
            #(SCLK_PERIOD / 2);
            sclk = ~CPOL;
            #(SCLK_PERIOD / 2);
            sclk = CPOL;
        end
    endtask

    task spi_send_byte;
        input [7:0] data;
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                spi_write_bit(data[i]);
            end
        end
    endtask

    task spi_send_n_bits;
        input [7:0] data;
        input n;
        integer i;
        begin
            for (i = 7; i >= 8 - n; i = i - 1) begin
                spi_write_bit(data[i]);
            end
        end
    endtask

    task spi_transfer;
        input [7:0] data;
        reg [7:0] rx_sample;
        integer i;
        begin
            echo_data = data;
            repeat (1) @(posedge clk);
            spi_begin();
            for (i = 7; i >= 0; i = i - 1) begin
                mosi = data[i];
                #(SCLK_PERIOD / 2);
                sclk = ~CPOL;
                rx_sample[i] = miso;
                #(SCLK_PERIOD / 2);
                sclk = CPOL;
            end
            spi_end();

            if (rx_sample !== data) begin
                $display("[ERROR] echo mismatch: sent 0x%02h, got 0x%02h", data, rx_sample);
                err_cnt = err_cnt + 1;
            end else begin
                $display("[OK] echo 0x%02h", data);
            end
        end
    endtask

    task spi_send_byte_check;
        input [7:0] data;
        begin
            spi_send_byte(data);
            expect_rx(data);
        end
    endtask

    task expect_rx;
        input [7:0] expected;
        integer timeout;
        reg got;
        begin
            got = 0;
            timeout = 0;
            while (!got && timeout < 1000) begin
                @(posedge clk);
                if (rx_valid || rx_seen) begin
                    got = 1;
                    if ((rx_valid ? rx_data : rx_latched) !== expected) begin
                        $display("[ERROR] rx mismatch: expect 0x%02h, got 0x%02h",
                                 expected, rx_valid ? rx_data : rx_latched);
                        err_cnt = err_cnt + 1;
                    end else begin
                        $display("[OK] rx 0x%02h", expected);
                    end
                    rx_seen = 1'b0;
                end
                timeout = timeout + 1;
            end
            if (!got) begin
                $display("[ERROR] rx timeout, expect 0x%02h", expected);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

endmodule
