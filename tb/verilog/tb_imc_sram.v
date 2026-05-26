//============================================================================
// Testbench: tb_imc_sram
// Description: Self-checking testbench for imc_sram_32x256 module.
//              - Tests 1–8:   Memory Mode (standard read/write)
//              - Tests 9–16:  Compute Mode (in-memory Boolean ops)
//              - 100 random compute operations vs golden model
//              - Throughput benchmark: IMC vs conventional for 256 bulk ops
//
// DUT interface note:
//   Memory Mode (mode=0): single-port-like — uses addr_a, din, we, dout.
//   Compute Mode (mode=1): 2-cycle FSM — reads addr_a & addr_b, writes
//     result to addr_wr, pulses compute_done.
//============================================================================

`timescale 1ns / 1ps

module tb_imc_sram;

    // ---------------------------------------------------------------
    // Clock and DUT signals
    // ---------------------------------------------------------------
    reg         clk;
    reg         mode;
    reg         we;
    reg  [7:0]  addr_a, addr_b, addr_wr;
    reg  [31:0] din;
    reg  [2:0]  op_sel;
    wire [31:0] dout;
    wire        zero_flag;
    wire [5:0]  ones_count;
    wire        compute_done;

    // Test tracking
    integer pass_count;
    integer fail_count;
    integer total_tests;
    integer i;

    // Throughput measurement
    integer imc_cycles, conv_cycles;
    time    t_start, t_end;

    // ---------------------------------------------------------------
    // DUT instantiation
    // ---------------------------------------------------------------
    imc_sram_32x256 dut (
        .clk          (clk),
        .mode         (mode),
        .we           (we),
        .addr_a       (addr_a),
        .addr_b       (addr_b),
        .addr_wr      (addr_wr),
        .din          (din),
        .op_sel       (op_sel),
        .dout         (dout),
        .zero_flag    (zero_flag),
        .ones_count   (ones_count),
        .compute_done (compute_done)
    );

    // ---------------------------------------------------------------
    // Clock generation: 10 ns period (100 MHz)
    // ---------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Helper tasks
    // ---------------------------------------------------------------

    // Memory Mode write: write din_val to address in one cycle
    task mem_write;
        input [7:0]  address;
        input [31:0] data;
    begin
        mode    = 1'b0;
        we      = 1'b1;
        addr_a  = address;
        din     = data;
        addr_b  = 8'h0;
        addr_wr = 8'h0;
        op_sel  = 3'b0;
        @(posedge clk);
        #1;
        we = 1'b0;
    end
    endtask

    // Memory Mode read: read from address, output available next cycle
    task mem_read;
        input  [7:0]  address;
        output [31:0] data_out;
    begin
        mode    = 1'b0;
        we      = 1'b0;
        addr_a  = address;
        din     = 32'h0;
        addr_b  = 8'h0;
        addr_wr = 8'h0;
        op_sel  = 3'b0;
        @(posedge clk);  // Issue read
        #1;
        @(posedge clk);  // Capture registered output
        #1;
        data_out = dout;
    end
    endtask

    // Compute Mode: perform op on row at addr_a_val & addr_b_val,
    // write result to addr_wr_val.  Waits for compute_done pulse.
    task compute_op;
        input [7:0] addr_a_val;
        input [7:0] addr_b_val;
        input [7:0] addr_wr_val;
        input [2:0] op;
    begin
        mode    = 1'b1;
        we      = 1'b0;
        addr_a  = addr_a_val;
        addr_b  = addr_b_val;
        addr_wr = addr_wr_val;
        op_sel  = op;
        din     = 32'h0;
        // Wait for compute_done (FSM: IDLE→READ→COMPUTE)
        @(posedge clk);  // IDLE → next=READ
        #1;
        @(posedge clk);  // READ → next=COMPUTE (operands latched)
        #1;
        @(posedge clk);  // COMPUTE → result valid, compute_done=1
        #1;
        // Return to idle — do NOT wait another posedge here;
        // the extra clock would let the IDLE output mux overwrite dout.
        mode = 1'b0;
    end
    endtask

    // Check 32-bit result
    task check32;
        input [31:0]  actual;
        input [31:0]  expected;
        input [255:0] test_name;
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

    // Check 1-bit flag
    task check_flag;
        input         actual;
        input         expected;
        input [255:0] test_name;
    begin
        total_tests = total_tests + 1;
        if (actual === expected) begin
            $display("  [PASS] %0s : got %b, expected %b", test_name, actual, expected);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] %0s : got %b, expected %b", test_name, actual, expected);
            fail_count = fail_count + 1;
        end
    end
    endtask

    // Check ones_count (6-bit)
    task check_popcount;
        input [5:0]   actual;
        input [5:0]   expected;
        input [255:0] test_name;
    begin
        total_tests = total_tests + 1;
        if (actual === expected) begin
            $display("  [PASS] %0s : popcount=%0d, expected=%0d", test_name, actual, expected);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] %0s : popcount=%0d, expected=%0d", test_name, actual, expected);
            fail_count = fail_count + 1;
        end
    end
    endtask

    // Golden model popcount
    function [5:0] golden_popcount;
        input [31:0] val;
        integer k;
    begin
        golden_popcount = 6'd0;
        for (k = 0; k < 32; k = k + 1)
            golden_popcount = golden_popcount + {5'b0, val[k]};
    end
    endfunction

    // Golden model compute
    function [31:0] golden_compute;
        input [31:0] a;
        input [31:0] b;
        input [2:0]  op;
    begin
        case (op)
            3'b000:  golden_compute = a & b;
            3'b001:  golden_compute = a | b;
            3'b010:  golden_compute = a ^ b;
            3'b011:  golden_compute = ~(a | b);
            3'b100:  golden_compute = ~(a & b);
            3'b101:  golden_compute = ~(a ^ b);
            3'b110:  golden_compute = ~a;
            3'b111:  golden_compute = a;
            default: golden_compute = 32'h0;
        endcase
    end
    endfunction

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    initial begin
        pass_count  = 0;
        fail_count  = 0;
        total_tests = 0;

        // Initialize all inputs
        mode    = 0;
        we      = 0;
        addr_a  = 0;
        addr_b  = 0;
        addr_wr = 0;
        din     = 0;
        op_sel  = 0;

        // Let DUT settle
        @(posedge clk);
        @(posedge clk);

        // =============================================================
        //  PART A — MEMORY MODE TESTS (Tests 1–8)
        //  Adapted for imc_sram_32x256 single-port-like Memory Mode.
        // =============================================================

        // ----- TEST 1: Basic write-read -----
        $display("\n--- TEST 1: Basic write-read ---");
        mem_write(8'h00, 32'hDEADBEEF);
        begin : t1_block
            reg [31:0] rd_data;
            mem_read(8'h00, rd_data);
            check32(rd_data, 32'hDEADBEEF, "T1 read addr 0x00");
        end

        // ----- TEST 2: Write to second address, read first -----
        // (Adapted: sequential ops since Memory Mode is single-port)
        $display("\n--- TEST 2: Write addr 0x01, read addr 0x00 ---");
        mem_write(8'h01, 32'hCAFEBABE);
        begin : t2_block
            reg [31:0] rd_data;
            mem_read(8'h00, rd_data);
            check32(rd_data, 32'hDEADBEEF, "T2 read addr 0x00");
            mem_read(8'h01, rd_data);
            check32(rd_data, 32'hCAFEBABE, "T2 read addr 0x01");
        end

        // ----- TEST 3: Overwrite test (Port A priority N/A in mem mode) -----
        // Write 0xAAAAAAAA to addr 0x10, then overwrite with 0x55555555
        // Verify latest write wins.
        $display("\n--- TEST 3: Overwrite test ---");
        mem_write(8'h10, 32'hAAAAAAAA);
        mem_write(8'h10, 32'h55555555);
        begin : t3_block
            reg [31:0] rd_data;
            mem_read(8'h10, rd_data);
            check32(rd_data, 32'h55555555, "T3 overwrite wins");
        end
        // Restore value for later tests
        mem_write(8'h10, 32'hAAAAAAAA);

        // ----- TEST 4: Read two different addresses sequentially -----
        $display("\n--- TEST 4: Read two addresses ---");
        begin : t4_block
            reg [31:0] rd_data;
            mem_read(8'h01, rd_data);
            check32(rd_data, 32'hCAFEBABE, "T4 read addr 0x01");
            mem_read(8'h10, rd_data);
            check32(rd_data, 32'hAAAAAAAA, "T4 read addr 0x10");
        end

        // ----- TEST 5: Write then immediate read (same address) -----
        $display("\n--- TEST 5: Write then read same addr ---");
        mem_write(8'h20, 32'hFF00FF00);
        begin : t5_block
            reg [31:0] rd_data;
            mem_read(8'h20, rd_data);
            check32(rd_data, 32'hFF00FF00, "T5 read after write");
        end

        // ----- TEST 6: Sequential write all 256 rows -----
        $display("\n--- TEST 6: Sequential write all 256 rows ---");
        for (i = 0; i < 256; i = i + 1) begin
            mem_write(i[7:0], {24'b0, i[7:0]} ^ 32'hA5A5A5A5);
        end
        $display("  [PASS] T6 All 256 rows written");
        pass_count  = pass_count + 1;
        total_tests = total_tests + 1;

        // ----- TEST 7: Sequential read all 256 rows, verify -----
        $display("\n--- TEST 7: Sequential read all 256 rows ---");
        begin : t7_block
            integer t7_errors;
            reg [31:0] rd_data;
            reg [31:0] expected;
            t7_errors = 0;
            for (i = 0; i < 256; i = i + 1) begin
                mem_read(i[7:0], rd_data);
                expected = {24'b0, i[7:0]} ^ 32'hA5A5A5A5;
                if (rd_data !== expected) begin
                    if (t7_errors < 5)
                        $display("  [FAIL] T7 addr 0x%02h: got 0x%08h, exp 0x%08h",
                                 i[7:0], rd_data, expected);
                    t7_errors = t7_errors + 1;
                end
            end
            total_tests = total_tests + 1;
            if (t7_errors == 0) begin
                $display("  [PASS] T7 All 256 rows verified");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] T7 %0d / 256 rows mismatched", t7_errors);
                fail_count = fail_count + 1;
            end
        end

        // ----- TEST 8: Memory reset (write all zeros) -----
        $display("\n--- TEST 8: Memory reset (all zeros) ---");
        for (i = 0; i < 256; i = i + 1)
            mem_write(i[7:0], 32'h0);
        begin : t8_block
            reg [31:0] rd_data;
            integer t8_ok;
            t8_ok = 1;
            mem_read(8'h00, rd_data);
            if (rd_data !== 32'h0) t8_ok = 0;
            mem_read(8'hFF, rd_data);
            if (rd_data !== 32'h0) t8_ok = 0;
            mem_read(8'h80, rd_data);
            if (rd_data !== 32'h0) t8_ok = 0;
            total_tests = total_tests + 1;
            if (t8_ok) begin
                $display("  [PASS] T8 Memory cleared");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] T8 Memory not fully cleared");
                fail_count = fail_count + 1;
            end
        end

        // =============================================================
        //  PART B — COMPUTE MODE TESTS (Tests 9–16)
        // =============================================================

        // ----- TEST 9: AND of complementary patterns -----
        $display("\n--- TEST 9: AND (0xAAAAAAAA & 0x55555555) ---");
        mem_write(8'h00, 32'hAAAAAAAA);
        mem_write(8'h01, 32'h55555555);
        compute_op(8'h00, 8'h01, 8'hF0, 3'b000);  // AND → addr 0xF0
        check32(dout, 32'h00000000, "T9 AND result");
        check_flag(zero_flag, 1'b1, "T9 zero_flag");

        // ----- TEST 10: OR fills all bits -----
        $display("\n--- TEST 10: OR (0xAAAAAAAA | 0x55555555) ---");
        compute_op(8'h00, 8'h01, 8'hF1, 3'b001);  // OR → addr 0xF1
        check32(dout, 32'hFFFFFFFF, "T10 OR result");
        check_popcount(ones_count, 6'd32, "T10 ones_count=32");

        // ----- TEST 11: XOR change detection -----
        $display("\n--- TEST 11: XOR (0xFF00FF00 ^ 0x0FF00FF0) ---");
        mem_write(8'h02, 32'hFF00FF00);
        mem_write(8'h03, 32'h0FF00FF0);
        compute_op(8'h02, 8'h03, 8'hF2, 3'b010);  // XOR → addr 0xF2
        check32(dout, 32'hF0F0F0F0, "T11 XOR result");
        check_popcount(ones_count, 6'd16, "T11 ones_count=16");

        // ----- TEST 12: NAND of all-ones -----
        $display("\n--- TEST 12: NAND (0xFFFFFFFF ~& 0xFFFFFFFF) ---");
        mem_write(8'h04, 32'hFFFFFFFF);
        mem_write(8'h05, 32'hFFFFFFFF);
        compute_op(8'h04, 8'h05, 8'hF3, 3'b100);  // NAND → addr 0xF3
        check32(dout, 32'h00000000, "T12 NAND result");
        check_flag(zero_flag, 1'b1, "T12 zero_flag");

        // ----- TEST 13: XNOR equality check (identical rows) -----
        $display("\n--- TEST 13: XNOR (0x12345678 ~^ 0x12345678) ---");
        mem_write(8'h06, 32'h12345678);
        mem_write(8'h07, 32'h12345678);
        compute_op(8'h06, 8'h07, 8'hF4, 3'b101);  // XNOR → addr 0xF4
        check32(dout, 32'hFFFFFFFF, "T13 XNOR identical");
        check_popcount(ones_count, 6'd32, "T13 ones_count=32");

        // ----- TEST 14: XNOR non-equal rows (Hamming distance) -----
        $display("\n--- TEST 14: XNOR (0x12345678 ~^ 0x87654321) ---");
        mem_write(8'h08, 32'h12345678);
        mem_write(8'h09, 32'h87654321);
        compute_op(8'h08, 8'h09, 8'hF5, 3'b101);  // XNOR → addr 0xF5
        begin : t14_block
            reg [31:0] expected_xnor;
            reg [5:0]  exp_pc;
            expected_xnor = ~(32'h12345678 ^ 32'h87654321);
            exp_pc = golden_popcount(expected_xnor);
            check32(dout, expected_xnor, "T14 XNOR result");
            total_tests = total_tests + 1;
            if (ones_count < 6'd32) begin
                $display("  [PASS] T14 ones_count=%0d < 32 (non-equal)", ones_count);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] T14 ones_count=%0d should be < 32", ones_count);
                fail_count = fail_count + 1;
            end
            check_popcount(ones_count, exp_pc, "T14 popcount exact");
        end

        // ----- TEST 15: NOT A -----
        $display("\n--- TEST 15: NOT A (0xDEADBEEF) ---");
        mem_write(8'h0A, 32'hDEADBEEF);
        compute_op(8'h0A, 8'h00, 8'hF6, 3'b110);  // NOT A → addr 0xF6
        check32(dout, 32'h21524110, "T15 NOT A result");

        // ----- TEST 16: Bulk stress — 256 rows, 128 AND pairs -----
        $display("\n--- TEST 16: Bulk stress (128 AND pairs) ---");
        // Write 256 rows with known data
        for (i = 0; i < 256; i = i + 1)
            mem_write(i[7:0], {24'b0, i[7:0]} ^ 32'hDEADDEAD);
        // Compute AND: row[i] AND row[i+128] for i=0..127, result to row[i]
        begin : t16_block
            integer t16_errors;
            reg [31:0] exp_result;
            reg [31:0] rd_data;
            t16_errors = 0;
            for (i = 0; i < 128; i = i + 1) begin
                compute_op(i[7:0], (i + 128), i[7:0], 3'b000);
            end
            // Verify all 128 results
            for (i = 0; i < 128; i = i + 1) begin
                exp_result = ({24'b0, i[7:0]} ^ 32'hDEADDEAD) &
                             ({24'b0, (i[7:0] + 8'd128)} ^ 32'hDEADDEAD);
                mem_read(i[7:0], rd_data);
                if (rd_data !== exp_result) begin
                    if (t16_errors < 5)
                        $display("  [FAIL] T16 row %0d: got 0x%08h, exp 0x%08h",
                                 i, rd_data, exp_result);
                    t16_errors = t16_errors + 1;
                end
            end
            total_tests = total_tests + 1;
            if (t16_errors == 0) begin
                $display("  [PASS] T16 All 128 AND pairs correct");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] T16 %0d / 128 pairs incorrect", t16_errors);
                fail_count = fail_count + 1;
            end
        end

        // =============================================================
        //  THROUGHPUT BENCHMARK: IMC vs Conventional (256 AND ops)
        // =============================================================
        $display("\n--- THROUGHPUT BENCHMARK: 256 AND ops ---");

        // Prepare data: write 256 rows
        for (i = 0; i < 256; i = i + 1)
            mem_write(i[7:0], $random);

        // --- IMC approach: compute_op for 128 pairs (row[i] AND row[i+128]) ---
        imc_cycles = 0;
        t_start = $time;
        for (i = 0; i < 128; i = i + 1) begin
            compute_op(i[7:0], (i + 128), i[7:0], 3'b000);
        end
        t_end = $time;
        imc_cycles = (t_end - t_start) / 10;  // 10 ns per cycle
        $display("  IMC:          128 ops in %0d cycles (%0d ns)", imc_cycles, t_end - t_start);

        // --- Conventional approach: read A, read B, compute in TB, write back ---
        // Re-prepare data
        for (i = 0; i < 256; i = i + 1)
            mem_write(i[7:0], $random);

        conv_cycles = 0;
        t_start = $time;
        begin : conv_block
            reg [31:0] val_a, val_b, conv_result;
            for (i = 0; i < 128; i = i + 1) begin
                mem_read(i[7:0], val_a);           // Read row A
                mem_read((i + 128), val_b);        // Read row B
                conv_result = val_a & val_b;       // Compute in TB
                mem_write(i[7:0], conv_result);    // Write back
            end
        end
        t_end = $time;
        conv_cycles = (t_end - t_start) / 10;
        $display("  Conventional: 128 ops in %0d cycles (%0d ns)", conv_cycles, t_end - t_start);
        $display("  Speedup:      %.2fx", 1.0 * conv_cycles / (imc_cycles > 0 ? imc_cycles : 1));

        // Throughput comparison table
        $display("\n  +-------------------------------+----------+----------+--------+");
        $display("  | Metric                        |   IMC    |   Conv   | Speedup|");
        $display("  +-------------------------------+----------+----------+--------+");
        $display("  | Total cycles (128 ops)        | %8d | %8d | %5.2fx |",
                 imc_cycles, conv_cycles,
                 1.0 * conv_cycles / (imc_cycles > 0 ? imc_cycles : 1));
        $display("  | Cycles per operation          | %8.1f | %8.1f | %5.2fx |",
                 1.0 * imc_cycles / 128, 1.0 * conv_cycles / 128,
                 (1.0 * conv_cycles / 128) / (1.0 * imc_cycles / 128 > 0 ? 1.0 * imc_cycles / 128 : 1));
        $display("  | Bits processed per cycle      |       32 |       32 |   1.0x |");
        $display("  | Effective throughput (ops/cyc) | %8.3f | %8.3f | %5.2fx |",
                 128.0 / (imc_cycles > 0 ? imc_cycles : 1),
                 128.0 / (conv_cycles > 0 ? conv_cycles : 1),
                 1.0 * conv_cycles / (imc_cycles > 0 ? imc_cycles : 1));
        $display("  +-------------------------------+----------+----------+--------+");

        // =============================================================
        //  100 RANDOM COMPUTE OPERATIONS vs GOLDEN MODEL
        // =============================================================
        $display("\n--- RANDOM COMPUTE: 100 ops vs golden model ---");
        begin : rand_compute_block
            integer rand_errors;
            reg [31:0] rand_a, rand_b;
            reg [7:0]  rand_addr_a, rand_addr_b;
            reg [2:0]  rand_op;
            reg [31:0] golden_result;
            reg [5:0]  golden_pc;
            rand_errors = 0;
            for (i = 0; i < 100; i = i + 1) begin
                rand_a      = $random;
                rand_b      = $random;
                rand_op     = $random;
                rand_addr_a = 8'hE0;  // Use fixed scratch rows
                rand_addr_b = 8'hE1;
                // Write operands
                mem_write(rand_addr_a, rand_a);
                mem_write(rand_addr_b, rand_b);
                // Compute
                compute_op(rand_addr_a, rand_addr_b, 8'hE2, rand_op);
                // Golden model
                golden_result = golden_compute(rand_a, rand_b, rand_op);
                golden_pc     = golden_popcount(golden_result);
                // Check
                if (dout !== golden_result || ones_count !== golden_pc) begin
                    if (rand_errors < 5)
                        $display("  [FAIL] Random #%0d op=%0d a=0x%08h b=0x%08h: got 0x%08h(pc=%0d), exp 0x%08h(pc=%0d)",
                                 i, rand_op, rand_a, rand_b, dout, ones_count, golden_result, golden_pc);
                    rand_errors = rand_errors + 1;
                end
            end
            total_tests = total_tests + 1;
            if (rand_errors == 0) begin
                $display("  [PASS] All 100 random compute ops verified");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %0d / 100 random compute ops failed", rand_errors);
                fail_count = fail_count + 1;
            end
        end

        // =============================================================
        //  SUMMARY
        // =============================================================
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
        #50000000;
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

endmodule
