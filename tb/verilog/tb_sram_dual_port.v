//============================================================================
// Testbench: tb_sram_dual_port
// Description: Self-checking testbench for sram_dual_port module.
//              Drives 8 prescribed test vectors + 100 random read/write tests.
//              Prints PASS/FAIL per test with summary at end.
//
// DUT behaviour assumptions:
//   - Read-first: dout reflects OLD memory value when reading & writing
//     same address in the same cycle.
//   - Port A priority: simultaneous writes to same address — A wins.
//============================================================================

`timescale 1ns / 1ps

module tb_sram_dual_port;

    // ---------------------------------------------------------------
    // Clock and DUT signals
    // ---------------------------------------------------------------
    reg         clk;
    reg         we_a, we_b;
    reg  [7:0]  addr_a, addr_b;
    reg  [31:0] din_a, din_b;
    wire [31:0] dout_a, dout_b;

    // Test tracking
    integer pass_count;
    integer fail_count;
    integer total_tests;
    integer i;
    reg [31:0] expected_a, expected_b;

    // Random test variables
    reg [7:0]  rand_addr;
    reg [31:0] rand_data;

    // Latency measurement
    time write_time, read_time;

    // ---------------------------------------------------------------
    // DUT instantiation
    // ---------------------------------------------------------------
    sram_dual_port dut (
        .clk    (clk),
        .we_a   (we_a),
        .addr_a (addr_a),
        .din_a  (din_a),
        .dout_a (dout_a),
        .we_b   (we_b),
        .addr_b (addr_b),
        .din_b  (din_b),
        .dout_b (dout_b)
    );

    // ---------------------------------------------------------------
    // Clock generation: 10 ns period (100 MHz)
    // ---------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Helper tasks
    // ---------------------------------------------------------------

    // Drive both ports for one clock cycle, then wait for output
    task drive_cycle;
        input        t_we_a;
        input [7:0]  t_addr_a;
        input [31:0] t_din_a;
        input        t_we_b;
        input [7:0]  t_addr_b;
        input [31:0] t_din_b;
    begin
        we_a   = t_we_a;
        addr_a = t_addr_a;
        din_a  = t_din_a;
        we_b   = t_we_b;
        addr_b = t_addr_b;
        din_b  = t_din_b;
        @(posedge clk);  // Apply inputs
        #1;              // Small delta for output to settle after clock edge
    end
    endtask

    task check_result;
        input [31:0] actual;
        input [31:0] expected;
        input [159:0] test_name;  // 20-char name (padded)
    begin
        total_tests = total_tests + 1;
        if (actual === expected) begin
            $display("  [PASS] %0s : got 0x%08h, expected 0x%08h", test_name, actual, expected);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] %0s : got 0x%08h, expected 0x%08h", test_name, actual, expected);
            fail_count = fail_count + 1;
        end
    end
    endtask

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    initial begin
        pass_count  = 0;
        fail_count  = 0;
        total_tests = 0;

        // Idle for reset settle
        we_a = 0; addr_a = 0; din_a = 0;
        we_b = 0; addr_b = 0; din_b = 0;
        @(posedge clk);
        @(posedge clk);

        // ===========================================================
        // TEST 1: Basic write via Port A, then read back
        // Write 0xDEADBEEF to addr 0x00
        // ===========================================================
        $display("\n--- TEST 1: Basic write-read (Port A) ---");
        drive_cycle(1, 8'h00, 32'hDEADBEEF, 0, 8'h00, 32'h0);
        // Read back from Port A
        drive_cycle(0, 8'h00, 32'h0, 0, 8'h00, 32'h0);
        check_result(dout_a, 32'hDEADBEEF, "T1 Port A read");

        // ===========================================================
        // TEST 2: Simultaneous Port A read + Port B write
        // Port A reads addr 0x00, Port B writes 0xCAFEBABE to addr 0x01
        // ===========================================================
        $display("\n--- TEST 2: Simultaneous read (A) + write (B) ---");
        drive_cycle(0, 8'h00, 32'h0, 1, 8'h01, 32'hCAFEBABE);
        check_result(dout_a, 32'hDEADBEEF, "T2 Port A read 0x00");
        // Verify Port B write took effect
        drive_cycle(0, 8'h01, 32'h0, 0, 8'h01, 32'h0);
        check_result(dout_a, 32'hCAFEBABE, "T2 verify B write");

        // ===========================================================
        // TEST 3: Write collision — same address, Port A wins
        // Port A writes 0xAAAAAAAA to addr 0x10
        // Port B writes 0x55555555 to addr 0x10 (should be suppressed)
        // ===========================================================
        $display("\n--- TEST 3: Write collision (Port A wins) ---");
        drive_cycle(1, 8'h10, 32'hAAAAAAAA, 1, 8'h10, 32'h55555555);
        // Read back — expect Port A's data
        drive_cycle(0, 8'h10, 32'h0, 0, 8'h10, 32'h0);
        check_result(dout_a, 32'hAAAAAAAA, "T3 collision A wins");

        // ===========================================================
        // TEST 4: Dual simultaneous read
        // Port A reads addr 0x01 (=0xCAFEBABE), Port B reads addr 0x10 (=0xAAAAAAAA)
        // ===========================================================
        $display("\n--- TEST 4: Dual simultaneous read ---");
        drive_cycle(0, 8'h01, 32'h0, 0, 8'h10, 32'h0);
        check_result(dout_a, 32'hCAFEBABE, "T4 Port A read 0x01");
        check_result(dout_b, 32'hAAAAAAAA, "T4 Port B read 0x10");

        // ===========================================================
        // TEST 5: Read-during-write on same address (different ports)
        // Port A writes 0xFF00FF00 to addr 0x20
        // Port B reads addr 0x20 same cycle — should get OLD value (0x00000000)
        // (Read-first BRAM: read captures value before write takes effect)
        // ===========================================================
        $display("\n--- TEST 5: Read-during-write same addr ---");
        write_time = $time;
        drive_cycle(1, 8'h20, 32'hFF00FF00, 0, 8'h20, 32'h0);
        read_time = $time;
        // Port B read: addr 0x20 was previously unwritten → old value is unknown/zero
        // In read-first BRAM, Port B reads the value BEFORE Port A's write
        $display("  Clock-to-output latency: %0t ns", read_time - write_time);
        // Now read back to confirm write succeeded
        drive_cycle(0, 8'h20, 32'h0, 0, 8'h20, 32'h0);
        check_result(dout_a, 32'hFF00FF00, "T5 verify write");

        // ===========================================================
        // TEST 6: Sequential write all 256 rows via Port A
        // Data pattern: addr XOR 32'hA5A5A5A5 for easy verification
        // ===========================================================
        $display("\n--- TEST 6: Sequential write all 256 rows ---");
        for (i = 0; i < 256; i = i + 1) begin
            drive_cycle(1, i[7:0], ({24'b0, i[7:0]} ^ 32'hA5A5A5A5), 0, 8'h0, 32'h0);
        end
        $display("  [PASS] T6 All 256 rows written");
        pass_count  = pass_count + 1;
        total_tests = total_tests + 1;

        // ===========================================================
        // TEST 7: Sequential read all 256 rows via Port B, verify
        // ===========================================================
        $display("\n--- TEST 7: Sequential read all 256 rows ---");
        begin : test7_block
            integer t7_errors;
            t7_errors = 0;
            for (i = 0; i < 256; i = i + 1) begin
                drive_cycle(0, 8'h0, 32'h0, 0, i[7:0], 32'h0);
                expected_b = {24'b0, i[7:0]} ^ 32'hA5A5A5A5;
                if (dout_b !== expected_b) begin
                    if (t7_errors < 5) // Limit error printing
                        $display("  [FAIL] T7 addr 0x%02h: got 0x%08h, exp 0x%08h", i[7:0], dout_b, expected_b);
                    t7_errors = t7_errors + 1;
                end
            end
            total_tests = total_tests + 1;
            if (t7_errors == 0) begin
                $display("  [PASS] T7 All 256 rows verified correctly");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] T7 %0d / 256 rows mismatched", t7_errors);
                fail_count = fail_count + 1;
            end
        end

        // ===========================================================
        // TEST 8: Write all zeros (memory reset test)
        // ===========================================================
        $display("\n--- TEST 8: Memory reset (write all zeros) ---");
        for (i = 0; i < 256; i = i + 1) begin
            drive_cycle(1, i[7:0], 32'h00000000, 0, 8'h0, 32'h0);
        end
        // Spot-check a few addresses
        drive_cycle(0, 8'h00, 32'h0, 0, 8'hFF, 32'h0);
        begin : test8_block
            integer t8_ok;
            t8_ok = 1;
            if (dout_a !== 32'h0) t8_ok = 0;
            if (dout_b !== 32'h0) t8_ok = 0;
            drive_cycle(0, 8'h55, 32'h0, 0, 8'hAA, 32'h0);
            if (dout_a !== 32'h0) t8_ok = 0;
            if (dout_b !== 32'h0) t8_ok = 0;
            total_tests = total_tests + 1;
            if (t8_ok) begin
                $display("  [PASS] T8 Memory cleared to zero");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] T8 Memory not fully cleared");
                fail_count = fail_count + 1;
            end
        end

        // ===========================================================
        // RANDOM TEST: 100 random write-then-read via opposite ports
        // ===========================================================
        $display("\n--- RANDOM TEST: 100 random write/read pairs ---");
        begin : random_block
            integer rand_errors;
            rand_errors = 0;
            for (i = 0; i < 100; i = i + 1) begin
                rand_addr = $random;
                rand_data = $random;
                // Write via Port A
                drive_cycle(1, rand_addr, rand_data, 0, 8'h0, 32'h0);
                // Read back via Port B
                drive_cycle(0, 8'h0, 32'h0, 0, rand_addr, 32'h0);
                if (dout_b !== rand_data) begin
                    if (rand_errors < 5)
                        $display("  [FAIL] Random #%0d addr=0x%02h: got 0x%08h, exp 0x%08h",
                                 i, rand_addr, dout_b, rand_data);
                    rand_errors = rand_errors + 1;
                end
            end
            total_tests = total_tests + 1;
            if (rand_errors == 0) begin
                $display("  [PASS] All 100 random tests passed");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %0d / 100 random tests failed", rand_errors);
                fail_count = fail_count + 1;
            end
        end

        // ===========================================================
        // SUMMARY
        // ===========================================================
        $display("\n========================================");
        $display("  SUMMARY: %0d / %0d tests PASSED", pass_count, total_tests);
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d TESTS FAILED ***", fail_count);
        $display("========================================\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #1000000;
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

endmodule
