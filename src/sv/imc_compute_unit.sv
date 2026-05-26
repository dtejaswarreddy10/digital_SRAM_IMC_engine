//============================================================================
// Module: imc_compute_unit
// Description: In-Memory Compute Boolean logic unit — purely combinational.
//              SystemVerilog version with always_comb and logic types.
//              8 bitwise operations, zero flag, popcount.
//============================================================================

module imc_compute_unit (
    input  logic [31:0] operand_a,   // Data from SRAM row A
    input  logic [31:0] operand_b,   // Data from SRAM row B
    input  logic [2:0]  op_sel,      // Operation select
    output logic [31:0] result,      // Bitwise compute result
    output logic        zero_flag,   // 1 if result is all zeros
    output logic [5:0]  ones_count   // Popcount: number of 1s (0–32)
);

    // --- 8-way operation MUX ---
    always_comb begin
        unique case (op_sel)
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

    // --- Zero flag ---
    assign zero_flag = ~|result;

    // --- Popcount via adder tree ---
    always_comb begin
        ones_count = 6'd0;
        for (int i = 0; i < 32; i++) begin
            ones_count = ones_count + 6'(result[i]);
        end
    end

endmodule
