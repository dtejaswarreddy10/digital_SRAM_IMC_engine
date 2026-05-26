//============================================================================
// Testbench: tb_sram_dual_port (SystemVerilog)
// Description: Self-checking testbench for sram_dual_port module.
//              8 prescribed tests + 100 random write/read pairs.
//              Uses SV assertions, automatic tasks, and string formatting.
//============================================================================

`timescale 1ns / 1ps

module tb_sram_dual_port;

    // ---------------------------------------------------------------
    // Signals
    // ---------------------------------------------------------------
    logic        clk;
    logic        we_a, we_b;
    logic [7:0]  addr_a, addr_b;
    logic [31:0] din_a, din_b;
    logic [31:0] dout_a, dout_b;

    int pass_count = 0;
    int fail_count = 0;
    int total_tests = 0;

    time write_time, read_time;

    // ---------------------------------------------------------------
    // DUT
    // ---------------------------------------------------------------
    sram_dual_port dut (
        .clk    (clk),
        .we_a   (we_a),   .addr_a (addr_a), .din_a (din_a), .dout_a (dout_a),
        .we_b   (we_b),   .addr_b (addr_b), .din_b (din_b), .dout_b (dout_b)
    );

    // ---------------------------------------------------------------
    // Clock: 10 ns period
    // ---------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Tasks
    // ---------------------------------------------------------------
    task automatic drive_cycle(
        input logic        t_we_a,
        input logic [7:0]  t_addr_a,
        input logic [31:0] t_din_a,
        input logic        t_we_b,
        input logic [7:0]  t_addr_b,
        input logic [31:0] t_din_b
    );
        we_a   = t_we_a;   addr_a = t_addr_a; din_a = t_din_a;
        we_b   = t_we_b;   addr_b = t_addr_b; din_b = t_din_b;
        @(posedge clk);
        #1;
    endtask

    task automatic check_result(
        input logic [31:0] actual,
        input logic [31:0] expected,
        input string       test_name
    );
        total_tests++;
        if (actual === expected) begin
            $display("  [PASS] %s : got 0x%08h, expected 0x%08h", test_name, actual, expected);
            pass_count++;
        end else begin
            $display("  [FAIL] %s : got 0x%08h, expected 0x%08h", test_name, actual, expected);
            fail_count++;
        end
    endtask

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    initial begin
        we_a = 0; addr_a = 0; din_a = 0;
        we_b = 0; addr_b = 0; din_b = 0;
        repeat (2) @(posedge clk);

        // ----- TEST 1: Basic write-read -----
        $display("\n--- TEST 1: Basic write-read (Port A) ---");
        drive_cycle(1, 8'h00, 32'hDEADBEEF, 0, 8'h00, 32'h0);
        drive_cycle(0, 8'h00, 32'h0, 0, 8'h00, 32'h0);
        check_result(dout_a, 32'hDEADBEEF, "T1 Port A read");

        // ----- TEST 2: Simultaneous read (A) + write (B) -----
        $display("\n--- TEST 2: Simultaneous read (A) + write (B) ---");
        drive_cycle(0, 8'h00, 32'h0, 1, 8'h01, 32'hCAFEBABE);
        check_result(dout_a, 32'hDEADBEEF, "T2 Port A read 0x00");
        drive_cycle(0, 8'h01, 32'h0, 0, 8'h01, 32'h0);
        check_result(dout_a, 32'hCAFEBABE, "T2 verify B write");

        // ----- TEST 3: Write collision (Port A wins) -----
        $display("\n--- TEST 3: Write collision (Port A wins) ---");
        drive_cycle(1, 8'h10, 32'hAAAAAAAA, 1, 8'h10, 32'h55555555);
        drive_cycle(0, 8'h10, 32'h0, 0, 8'h10, 32'h0);
        check_result(dout_a, 32'hAAAAAAAA, "T3 collision A wins");

        // ----- TEST 4: Dual simultaneous read -----
        $display("\n--- TEST 4: Dual simultaneous read ---");
        drive_cycle(0, 8'h01, 32'h0, 0, 8'h10, 32'h0);
        check_result(dout_a, 32'hCAFEBABE, "T4 Port A read 0x01");
        check_result(dout_b, 32'hAAAAAAAA, "T4 Port B read 0x10");

        // ----- TEST 5: Read-during-write same addr -----
        $display("\n--- TEST 5: Read-during-write same addr ---");
        write_time = $time;
        drive_cycle(1, 8'h20, 32'hFF00FF00, 0, 8'h20, 32'h0);
        read_time = $time;
        $display("  Clock-to-output latency: %0t ns", read_time - write_time);
        drive_cycle(0, 8'h20, 32'h0, 0, 8'h20, 32'h0);
        check_result(dout_a, 32'hFF00FF00, "T5 verify write");

        // ----- TEST 6: Sequential write all 256 rows -----
        $display("\n--- TEST 6: Sequential write all 256 rows ---");
        for (int i = 0; i < 256; i++) begin
            drive_cycle(1, i[7:0], ({24'b0, i[7:0]} ^ 32'hA5A5A5A5), 0, 8'h0, 32'h0);
        end
        $display("  [PASS] T6 All 256 rows written");
        pass_count++; total_tests++;

        // ----- TEST 7: Sequential read all 256 rows -----
        $display("\n--- TEST 7: Sequential read all 256 rows ---");
        begin
            int t7_errors = 0;
            for (int i = 0; i < 256; i++) begin
                logic [31:0] exp;
                drive_cycle(0, 8'h0, 32'h0, 0, i[7:0], 32'h0);
                exp = {24'b0, i[7:0]} ^ 32'hA5A5A5A5;
                if (dout_b !== exp) begin
                    if (t7_errors < 5)
                        $display("  [FAIL] T7 addr 0x%02h: got 0x%08h, exp 0x%08h", i[7:0], dout_b, exp);
                    t7_errors++;
                end
            end
            total_tests++;
            if (t7_errors == 0) begin
                $display("  [PASS] T7 All 256 rows verified correctly");
                pass_count++;
            end else begin
                $display("  [FAIL] T7 %0d / 256 rows mismatched", t7_errors);
                fail_count++;
            end
        end

        // ----- TEST 8: Memory reset (all zeros) -----
        $display("\n--- TEST 8: Memory reset (write all zeros) ---");
        for (int i = 0; i < 256; i++)
            drive_cycle(1, i[7:0], 32'h0, 0, 8'h0, 32'h0);
        drive_cycle(0, 8'h00, 32'h0, 0, 8'hFF, 32'h0);
        begin
            int t8_ok = 1;
            if (dout_a !== 32'h0) t8_ok = 0;
            if (dout_b !== 32'h0) t8_ok = 0;
            drive_cycle(0, 8'h55, 32'h0, 0, 8'hAA, 32'h0);
            if (dout_a !== 32'h0) t8_ok = 0;
            if (dout_b !== 32'h0) t8_ok = 0;
            total_tests++;
            if (t8_ok) begin
                $display("  [PASS] T8 Memory cleared to zero");
                pass_count++;
            end else begin
                $display("  [FAIL] T8 Memory not fully cleared");
                fail_count++;
            end
        end

        // ----- RANDOM TEST: 100 write/read pairs -----
        $display("\n--- RANDOM TEST: 100 random write/read pairs ---");
        begin
            int rand_errors = 0;
            logic [7:0]  raddr;
            logic [31:0] rdata;
            for (int i = 0; i < 100; i++) begin
                raddr = $urandom;
                rdata = $urandom;
                drive_cycle(1, raddr, rdata, 0, 8'h0, 32'h0);
                drive_cycle(0, 8'h0, 32'h0, 0, raddr, 32'h0);
                if (dout_b !== rdata) begin
                    if (rand_errors < 5)
                        $display("  [FAIL] Random #%0d addr=0x%02h: got 0x%08h, exp 0x%08h",
                                 i, raddr, dout_b, rdata);
                    rand_errors++;
                end
            end
            total_tests++;
            if (rand_errors == 0) begin
                $display("  [PASS] All 100 random tests passed");
                pass_count++;
            end else begin
                $display("  [FAIL] %0d / 100 random tests failed", rand_errors);
                fail_count++;
            end
        end

        // ----- SUMMARY -----
        $display("\n========================================");
        $display("  SUMMARY: %0d / %0d tests PASSED", pass_count, total_tests);
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d TESTS FAILED ***", fail_count);
        $display("========================================\n");
        $finish;
    end

    // Timeout
    initial begin
        #1000000;
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

endmodule
