//============================================================================
// Module: imc_compute_unit
// Description: In-Memory Compute Boolean logic unit — purely combinational.
//              Performs 8 bitwise operations on two 32-bit operands.
//              Outputs: 32-bit result, zero flag, and popcount (ones_count).
//
// Operation Encoding (op_sel[2:0]):
//   000 — AND   : A & B        (bitmasking, feature intersection)
//   001 — OR    : A | B        (feature union, flag merging)
//   010 — XOR   : A ^ B        (change detection, encryption, Hamming distance)
//   011 — NOR   : ~(A | B)     (complement of union)
//   100 — NAND  : ~(A & B)     (complement of intersection)
//   101 — XNOR  : ~(A ^ B)    (equality comparison, BNN multiply)
//   110 — NOT A : ~A           (bitwise complement of row A)
//   111 — PASS A: A            (pass-through, no compute)
//
// Popcount (ones_count):
//   Counts number of 1-bits in result (0–32). Implemented with a for-loop
//   that synthesizers map to a logarithmic-depth adder tree:
//     Level 1: 16 pairs  → 16 x 2-bit sums
//     Level 2:  8 groups →  8 x 3-bit sums
//     Level 3:  4 groups →  4 x 4-bit sums
//     Level 4:  2 groups →  2 x 5-bit sums
//     Level 5:  1 final  →  1 x 6-bit sum (max 32)
//   Used for Hamming distance (XOR + popcount) and BNN accumulation.
//============================================================================

module imc_compute_unit (
    input  wire [31:0] operand_a,   // Data from SRAM row A
    input  wire [31:0] operand_b,   // Data from SRAM row B
    input  wire [2:0]  op_sel,      // Operation select
    output reg  [31:0] result,      // Bitwise compute result
    output wire        zero_flag,   // 1 if result is all zeros
    output reg  [5:0]  ones_count   // Popcount: number of 1s in result (0–32)
);

    integer i;

    // --- 8-way operation MUX (combinational) ---
    always @(*) begin
        case (op_sel)
            3'b000:  result = operand_a & operand_b;           // AND
            3'b001:  result = operand_a | operand_b;           // OR
            3'b010:  result = operand_a ^ operand_b;           // XOR
            3'b011:  result = ~(operand_a | operand_b);        // NOR
            3'b100:  result = ~(operand_a & operand_b);        // NAND
            3'b101:  result = ~(operand_a ^ operand_b);        // XNOR
            3'b110:  result = ~operand_a;                      // NOT A
            3'b111:  result = operand_a;                       // PASS A
            default: result = 32'h00000000;
        endcase
    end

    // --- Zero flag: NOR-reduction of all result bits ---
    // Asserts when every bit of result is 0.
    assign zero_flag = ~|result;

    // --- Popcount: count number of 1-bits via adder tree ---
    // The for-loop is unrolled by synthesis into a balanced adder tree.
    always @(*) begin
        ones_count = 6'd0;
        for (i = 0; i < 32; i = i + 1) begin
            ones_count = ones_count + {5'b00000, result[i]};
        end
    end

endmodule
