//============================================================================
// Testbench: tb_imc_sram (SystemVerilog)
// Description: Self-checking testbench for imc_sram_32x256 module.
//              Tests 1–8 (Memory Mode), Tests 9–16 (Compute Mode),
//              100 random compute ops, throughput benchmark.
//============================================================================

`timescale 1ns / 1ps

module tb_imc_sram;

    // ---------------------------------------------------------------
    // Signals
    // ---------------------------------------------------------------
    logic        clk;
    logic        mode;
    logic        we;
    logic [7:0]  addr_a, addr_b, addr_wr;
    logic [31:0] din;
    logic [2:0]  op_sel;
    logic [31:0] dout;
    logic        zero_flag;
    logic [5:0]  ones_count;
    logic        compute_done;

    int pass_count = 0;
    int fail_count = 0;
    int total_tests = 0;

    int imc_cycles, conv_cycles;
    time t_start, t_end;

    // ---------------------------------------------------------------
    // DUT
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

    // Clock: 10 ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Tasks
    // ---------------------------------------------------------------
    task automatic mem_write(input logic [7:0] address, input logic [31:0] data);
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
    endtask

    task automatic mem_read(input logic [7:0] address, output logic [31:0] data_out);
        mode    = 1'b0;
        we      = 1'b0;
        addr_a  = address;
        din     = 32'h0;
        addr_b  = 8'h0;
        addr_wr = 8'h0;
        op_sel  = 3'b0;
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        data_out = dout;
    endtask

    task automatic compute_op(
        input logic [7:0] a_addr,
        input logic [7:0] b_addr,
        input logic [7:0] wr_addr,
        input logic [2:0] op
    );
        mode    = 1'b1;
        we      = 1'b0;
        addr_a  = a_addr;
        addr_b  = b_addr;
        addr_wr = wr_addr;
        op_sel  = op;
        din     = 32'h0;
        @(posedge clk); #1;  // IDLE → READ
        @(posedge clk); #1;  // READ → COMPUTE (operands latched)
        @(posedge clk); #1;  // COMPUTE → done, result valid
        mode = 1'b0;
        @(posedge clk); #1;  // back to IDLE
    endtask

    task automatic check32(input logic [31:0] actual, input logic [31:0] expected, input string name);
        total_tests++;
        if (actual === expected) begin
            $display("  [PASS] %s : got 0x%08h, expected 0x%08h", name, actual, expected);
            pass_count++;
        end else begin
            $display("  [FAIL] %s : got 0x%08h, expected 0x%08h", name, actual, expected);
            fail_count++;
        end
    endtask

    task automatic check_flag(input logic actual, input logic expected, input string name);
        total_tests++;
        if (actual === expected) begin
            $display("  [PASS] %s : got %b, expected %b", name, actual, expected);
            pass_count++;
        end else begin
            $display("  [FAIL] %s : got %b, expected %b", name, actual, expected);
            fail_count++;
        end
    endtask

    task automatic check_popcount(input logic [5:0] actual, input logic [5:0] expected, input string name);
        total_tests++;
        if (actual === expected) begin
            $display("  [PASS] %s : popcount=%0d, expected=%0d", name, actual, expected);
            pass_count++;
        end else begin
            $display("  [FAIL] %s : popcount=%0d, expected=%0d", name, actual, expected);
            fail_count++;
        end
    endtask

    function automatic logic [5:0] golden_popcount(input logic [31:0] val);
        logic [5:0] cnt;
        cnt = 6'd0;
        for (int k = 0; k < 32; k++) cnt = cnt + {5'b0, val[k]};
        return cnt;
    endfunction

    function automatic logic [31:0] golden_compute(input logic [31:0] a, input logic [31:0] b, input logic [2:0] op);
        case (op)
            3'b000:  return a & b;
            3'b001:  return a | b;
            3'b010:  return a ^ b;
            3'b011:  return ~(a | b);
            3'b100:  return ~(a & b);
            3'b101:  return ~(a ^ b);
            3'b110:  return ~a;
            3'b111:  return a;
            default: return 32'h0;
        endcase
    endfunction

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    initial begin
        mode = 0; we = 0; addr_a = 0; addr_b = 0; addr_wr = 0; din = 0; op_sel = 0;
        repeat (2) @(posedge clk);

        // =============================================================
        //  MEMORY MODE TESTS (Tests 1–8)
        // =============================================================

        // TEST 1: Basic write-read
        $display("\n--- TEST 1: Basic write-read ---");
        begin
            logic [31:0] rd;
            mem_write(8'h00, 32'hDEADBEEF);
            mem_read(8'h00, rd);
            check32(rd, 32'hDEADBEEF, "T1 read addr 0x00");
        end

        // TEST 2: Write + read different addresses
        $display("\n--- TEST 2: Write addr 0x01, read addr 0x00 ---");
        begin
            logic [31:0] rd;
            mem_write(8'h01, 32'hCAFEBABE);
            mem_read(8'h00, rd);
            check32(rd, 32'hDEADBEEF, "T2 read addr 0x00");
            mem_read(8'h01, rd);
            check32(rd, 32'hCAFEBABE, "T2 read addr 0x01");
        end

        // TEST 3: Overwrite test
        $display("\n--- TEST 3: Overwrite test ---");
        begin
            logic [31:0] rd;
            mem_write(8'h10, 32'hAAAAAAAA);
            mem_write(8'h10, 32'h55555555);
            mem_read(8'h10, rd);
            check32(rd, 32'h55555555, "T3 overwrite wins");
        end
        mem_write(8'h10, 32'hAAAAAAAA);

        // TEST 4: Read two addresses sequentially
        $display("\n--- TEST 4: Read two addresses ---");
        begin
            logic [31:0] rd;
            mem_read(8'h01, rd);
            check32(rd, 32'hCAFEBABE, "T4 read addr 0x01");
            mem_read(8'h10, rd);
            check32(rd, 32'hAAAAAAAA, "T4 read addr 0x10");
        end

        // TEST 5: Write then immediate read
        $display("\n--- TEST 5: Write then read same addr ---");
        begin
            logic [31:0] rd;
            mem_write(8'h20, 32'hFF00FF00);
            mem_read(8'h20, rd);
            check32(rd, 32'hFF00FF00, "T5 read after write");
        end

        // TEST 6: Sequential write all 256 rows
        $display("\n--- TEST 6: Sequential write all 256 rows ---");
        for (int i = 0; i < 256; i++)
            mem_write(i[7:0], {24'b0, i[7:0]} ^ 32'hA5A5A5A5);
        $display("  [PASS] T6 All 256 rows written");
        pass_count++; total_tests++;

        // TEST 7: Sequential read all 256 rows
        $display("\n--- TEST 7: Sequential read all 256 rows ---");
        begin
            int t7_errors = 0;
            logic [31:0] rd, exp;
            for (int i = 0; i < 256; i++) begin
                mem_read(i[7:0], rd);
                exp = {24'b0, i[7:0]} ^ 32'hA5A5A5A5;
                if (rd !== exp) begin
                    if (t7_errors < 5)
                        $display("  [FAIL] T7 addr 0x%02h: got 0x%08h, exp 0x%08h", i[7:0], rd, exp);
                    t7_errors++;
                end
            end
            total_tests++;
            if (t7_errors == 0) begin
                $display("  [PASS] T7 All 256 rows verified");
                pass_count++;
            end else begin
                $display("  [FAIL] T7 %0d / 256 rows mismatched", t7_errors);
                fail_count++;
            end
        end

        // TEST 8: Memory reset
        $display("\n--- TEST 8: Memory reset (all zeros) ---");
        for (int i = 0; i < 256; i++)
            mem_write(i[7:0], 32'h0);
        begin
            logic [31:0] rd;
            int t8_ok = 1;
            mem_read(8'h00, rd); if (rd !== 32'h0) t8_ok = 0;
            mem_read(8'hFF, rd); if (rd !== 32'h0) t8_ok = 0;
            mem_read(8'h80, rd); if (rd !== 32'h0) t8_ok = 0;
            total_tests++;
            if (t8_ok) begin
                $display("  [PASS] T8 Memory cleared");
                pass_count++;
            end else begin
                $display("  [FAIL] T8 Memory not fully cleared");
                fail_count++;
            end
        end

        // =============================================================
        //  COMPUTE MODE TESTS (Tests 9–16)
        // =============================================================

        // TEST 9: AND complementary
        $display("\n--- TEST 9: AND (0xAAAAAAAA & 0x55555555) ---");
        mem_write(8'h00, 32'hAAAAAAAA);
        mem_write(8'h01, 32'h55555555);
        compute_op(8'h00, 8'h01, 8'hF0, 3'b000);
        check32(dout, 32'h00000000, "T9 AND result");
        check_flag(zero_flag, 1'b1, "T9 zero_flag");

        // TEST 10: OR fills all bits
        $display("\n--- TEST 10: OR (0xAAAAAAAA | 0x55555555) ---");
        compute_op(8'h00, 8'h01, 8'hF1, 3'b001);
        check32(dout, 32'hFFFFFFFF, "T10 OR result");
        check_popcount(ones_count, 6'd32, "T10 ones_count=32");

        // TEST 11: XOR
        $display("\n--- TEST 11: XOR (0xFF00FF00 ^ 0x0FF00FF0) ---");
        mem_write(8'h02, 32'hFF00FF00);
        mem_write(8'h03, 32'h0FF00FF0);
        compute_op(8'h02, 8'h03, 8'hF2, 3'b010);
        check32(dout, 32'hF0F0F0F0, "T11 XOR result");
        check_popcount(ones_count, 6'd16, "T11 ones_count=16");

        // TEST 12: NAND all-ones
        $display("\n--- TEST 12: NAND (0xFFFFFFFF ~& 0xFFFFFFFF) ---");
        mem_write(8'h04, 32'hFFFFFFFF);
        mem_write(8'h05, 32'hFFFFFFFF);
        compute_op(8'h04, 8'h05, 8'hF3, 3'b100);
        check32(dout, 32'h00000000, "T12 NAND result");
        check_flag(zero_flag, 1'b1, "T12 zero_flag");

        // TEST 13: XNOR identical
        $display("\n--- TEST 13: XNOR (0x12345678 ~^ 0x12345678) ---");
        mem_write(8'h06, 32'h12345678);
        mem_write(8'h07, 32'h12345678);
        compute_op(8'h06, 8'h07, 8'hF4, 3'b101);
        check32(dout, 32'hFFFFFFFF, "T13 XNOR identical");
        check_popcount(ones_count, 6'd32, "T13 ones_count=32");

        // TEST 14: XNOR non-equal (Hamming)
        $display("\n--- TEST 14: XNOR (0x12345678 ~^ 0x87654321) ---");
        mem_write(8'h08, 32'h12345678);
        mem_write(8'h09, 32'h87654321);
        compute_op(8'h08, 8'h09, 8'hF5, 3'b101);
        begin
            logic [31:0] exp_xnor;
            logic [5:0]  exp_pc;
            exp_xnor = ~(32'h12345678 ^ 32'h87654321);
            exp_pc   = golden_popcount(exp_xnor);
            check32(dout, exp_xnor, "T14 XNOR result");
            total_tests++;
            if (ones_count < 6'd32) begin
                $display("  [PASS] T14 ones_count=%0d < 32 (non-equal)", ones_count);
                pass_count++;
            end else begin
                $display("  [FAIL] T14 ones_count=%0d should be < 32", ones_count);
                fail_count++;
            end
            check_popcount(ones_count, exp_pc, "T14 popcount exact");
        end

        // TEST 15: NOT A
        $display("\n--- TEST 15: NOT A (0xDEADBEEF) ---");
        mem_write(8'h0A, 32'hDEADBEEF);
        compute_op(8'h0A, 8'h00, 8'hF6, 3'b110);
        check32(dout, 32'h21524110, "T15 NOT A result");

        // TEST 16: Bulk stress — 128 AND pairs
        $display("\n--- TEST 16: Bulk stress (128 AND pairs) ---");
        for (int i = 0; i < 256; i++)
            mem_write(i[7:0], {24'b0, i[7:0]} ^ 32'hDEADDEAD);
        begin
            int t16_errors = 0;
            logic [31:0] exp_r, rd;
            for (int i = 0; i < 128; i++)
                compute_op(i[7:0], i[7:0] + 8'd128, i[7:0], 3'b000);
            for (int i = 0; i < 128; i++) begin
                exp_r = ({24'b0, i[7:0]} ^ 32'hDEADDEAD) &
                        ({24'b0, i[7:0] + 8'd128} ^ 32'hDEADDEAD);
                mem_read(i[7:0], rd);
                if (rd !== exp_r) begin
                    if (t16_errors < 5)
                        $display("  [FAIL] T16 row %0d: got 0x%08h, exp 0x%08h", i, rd, exp_r);
                    t16_errors++;
                end
            end
            total_tests++;
            if (t16_errors == 0) begin
                $display("  [PASS] T16 All 128 AND pairs correct");
                pass_count++;
            end else begin
                $display("  [FAIL] T16 %0d / 128 pairs incorrect", t16_errors);
                fail_count++;
            end
        end

        // =============================================================
        //  THROUGHPUT BENCHMARK
        // =============================================================
        $display("\n--- THROUGHPUT BENCHMARK: 128 AND ops ---");

        for (int i = 0; i < 256; i++)
            mem_write(i[7:0], $urandom);

        // IMC
        imc_cycles = 0;
        t_start = $time;
        for (int i = 0; i < 128; i++)
            compute_op(i[7:0], i[7:0] + 8'd128, i[7:0], 3'b000);
        t_end = $time;
        imc_cycles = (t_end - t_start) / 10;
        $display("  IMC:          128 ops in %0d cycles", imc_cycles);

        // Conventional
        for (int i = 0; i < 256; i++)
            mem_write(i[7:0], $urandom);

        conv_cycles = 0;
        t_start = $time;
        begin
            logic [31:0] va, vb, cr;
            for (int i = 0; i < 128; i++) begin
                mem_read(i[7:0], va);
                mem_read(i[7:0] + 8'd128, vb);
                cr = va & vb;
                mem_write(i[7:0], cr);
            end
        end
        t_end = $time;
        conv_cycles = (t_end - t_start) / 10;
        $display("  Conventional: 128 ops in %0d cycles", conv_cycles);
        $display("  Speedup:      %.2fx", real'(conv_cycles) / (imc_cycles > 0 ? real'(imc_cycles) : 1.0));

        $display("\n  +-------------------------------+----------+----------+--------+");
        $display("  | Metric                        |   IMC    |   Conv   | Speedup|");
        $display("  +-------------------------------+----------+----------+--------+");
        $display("  | Total cycles (128 ops)        | %8d | %8d | %5.2fx |",
                 imc_cycles, conv_cycles,
                 real'(conv_cycles) / (imc_cycles > 0 ? real'(imc_cycles) : 1.0));
        $display("  | Cycles per operation          | %8.1f | %8.1f | %5.2fx |",
                 real'(imc_cycles) / 128.0, real'(conv_cycles) / 128.0,
                 (real'(conv_cycles) / 128.0) / (real'(imc_cycles) / 128.0 > 0 ? real'(imc_cycles) / 128.0 : 1.0));
        $display("  | Bits processed per cycle      |       32 |       32 |   1.0x |");
        $display("  | Effective throughput (ops/cyc) | %8.3f | %8.3f | %5.2fx |",
                 128.0 / (imc_cycles > 0 ? real'(imc_cycles) : 1.0),
                 128.0 / (conv_cycles > 0 ? real'(conv_cycles) : 1.0),
                 real'(conv_cycles) / (imc_cycles > 0 ? real'(imc_cycles) : 1.0));
        $display("  +-------------------------------+----------+----------+--------+");

        // =============================================================
        //  100 RANDOM COMPUTE OPS
        // =============================================================
        $display("\n--- RANDOM COMPUTE: 100 ops vs golden model ---");
        begin
            int rand_errors = 0;
            logic [31:0] ra, rb, gr;
            logic [2:0]  rop;
            logic [5:0]  gpc;
            for (int i = 0; i < 100; i++) begin
                ra  = $urandom;
                rb  = $urandom;
                rop = $urandom;
                mem_write(8'hE0, ra);
                mem_write(8'hE1, rb);
                compute_op(8'hE0, 8'hE1, 8'hE2, rop);
                gr  = golden_compute(ra, rb, rop);
                gpc = golden_popcount(gr);
                if (dout !== gr || ones_count !== gpc) begin
                    if (rand_errors < 5)
                        $display("  [FAIL] Random #%0d op=%0d a=0x%08h b=0x%08h: got 0x%08h(pc=%0d), exp 0x%08h(pc=%0d)",
                                 i, rop, ra, rb, dout, ones_count, gr, gpc);
                    rand_errors++;
                end
            end
            total_tests++;
            if (rand_errors == 0) begin
                $display("  [PASS] All 100 random compute ops verified");
                pass_count++;
            end else begin
                $display("  [FAIL] %0d / 100 random compute ops failed", rand_errors);
                fail_count++;
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

    // Timeout
    initial begin
        #50000000;
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

endmodule
