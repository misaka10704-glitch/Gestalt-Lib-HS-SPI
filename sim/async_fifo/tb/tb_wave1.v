`timescale 1ns / 1ps

// Wave1: empty / full timing — FILL→HOLD→DRAIN x2
module tb_wave1;

    localparam DATA_WIDTH = 8;
    localparam DEPTH      = 8;
    localparam N_ROUND    = 2;
    localparam HOLD_CLKS  = 8;
    localparam ADDR_W     = $clog2(DEPTH);

    localparam PHASE_IDLE  = 0;
    localparam PHASE_FILL  = 1;
    localparam PHASE_HOLD  = 2;
    localparam PHASE_DRAIN = 3;

    reg wclk, rclk, rst_n, wr_en, rd_en;
    reg [DATA_WIDTH-1:0] wdata;
    wire [DATA_WIDTH-1:0] rdata;
    wire full, empty;

    integer err, wr_cnt, rd_cnt, phase, round, fill_target, saw_full;
    reg rd_fire_d;
    reg [DATA_WIDTH-1:0] scoreboard [0:DEPTH*N_ROUND];

    async_fifo #(
        .DATA_WIDTH  (DATA_WIDTH),
        .DATA_DEEPTH (DEPTH)
    ) dut (
        .wclk(wclk), .rclk(rclk), .rst_n(rst_n),
        .wr_en(wr_en), .rd_en(rd_en),
        .wdata(wdata), .rdata(rdata),
        .full(full), .empty(empty)
    );

    initial wclk = 0;
    always #2.5 wclk = ~wclk;
    initial rclk = 0;
    always #5.0 rclk = ~rclk;

    wave_probes #(.DATA_WIDTH(DATA_WIDTH), .ADDR_W(ADDR_W)) u_wave (
        .w_clk(wclk), .w_en(wr_en), .w_data(wdata), .w_full(full),
        .w_addr(dut.wptr[ADDR_W-1:0]), .w_ptr(dut.wptr), .w_gray(dut.wgray),
        .r_gray_w1(dut.rgray_w1), .r_gray_wq(dut.rgray_wq),
        .r_clk(rclk), .r_en(rd_en), .r_data(rdata), .r_empty(empty),
        .r_addr(dut.rptr[ADDR_W-1:0]), .r_ptr(dut.rptr), .r_gray(dut.rgray),
        .w_gray_r1(dut.wgray_r1), .w_gray_rq(dut.wgray_rq),
        .s_rst(rst_n),
        .s_mem0(dut.memory[0]), .s_mem1(dut.memory[1]),
        .s_mem2(dut.memory[2]), .s_mem3(dut.memory[3]),
        .s_mem4(dut.memory[4]), .s_mem5(dut.memory[5]),
        .s_mem6(dut.memory[6]), .s_mem7(dut.memory[7])
    );

    initial begin
        $dumpfile("wave1.vcd");
        $dumpvars(0, u_wave);
    end

    always @(negedge wclk or negedge rst_n) begin
        if (!rst_n) begin wr_en <= 0; wdata <= 0; end
        else if (phase == PHASE_FILL && (wr_cnt < fill_target) && !full) begin
            wr_en <= 1; wdata <= 8'hA0 + wr_cnt[7:0];
        end else wr_en <= 0;
    end

    always @(posedge wclk) begin
        if (rst_n && wr_en && !full && phase == PHASE_FILL && wr_cnt < fill_target) begin
            scoreboard[wr_cnt] <= wdata;
            wr_cnt = wr_cnt + 1;
        end
        if (full) saw_full = saw_full + 1;
    end

    always @(negedge rclk or negedge rst_n) begin
        if (!rst_n) rd_en <= 0;
        else if (phase == PHASE_DRAIN && !empty && ((rd_cnt + rd_fire_d) < wr_cnt))
            rd_en <= 1;
        else rd_en <= 0;
    end

    always @(posedge rclk or negedge rst_n) begin
        if (!rst_n) rd_fire_d <= 0;
        else begin
            rd_fire_d <= (rd_en && !empty && (rd_cnt < wr_cnt));
            if (rd_fire_d && (rd_cnt < wr_cnt)) begin
                if (rdata !== scoreboard[rd_cnt]) err = err + 1;
                rd_cnt = rd_cnt + 1;
            end
        end
    end

    initial begin
        err = 0; wr_cnt = 0; rd_cnt = 0; phase = PHASE_IDLE;
        saw_full = 0; fill_target = 0; rst_n = 0;
        #20; rst_n = 1;
        repeat (4) @(posedge wclk);

        for (round = 1; round <= N_ROUND; round = round + 1) begin
            fill_target = round * DEPTH;
            phase = PHASE_FILL;
            wait (wr_cnt == fill_target);
            @(posedge wclk);
            wait (full === 1'b1);
            $display("[W1] full round %0d @%0t", round, $time);

            phase = PHASE_HOLD;
            repeat (HOLD_CLKS) @(posedge wclk);
            if (!full) err = err + 1;

            phase = PHASE_DRAIN;
            wait (rd_cnt == wr_cnt);
            repeat (6) @(posedge rclk);
            if (!empty) err = err + 1;
            else $display("[W1] empty round %0d @%0t", round, $time);

            phase = PHASE_IDLE;
            repeat (4) @(posedge wclk);
        end

        if (err == 0 && saw_full >= N_ROUND)
            $display("[PASS] tb_wave1 empty/full");
        else
            $display("[FAIL] tb_wave1 err=%0d", err);
        $finish;
    end

    initial begin #30000; $display("[FAIL] timeout"); $finish; end
endmodule
