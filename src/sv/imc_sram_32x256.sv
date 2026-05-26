//============================================================================
// Module: imc_sram_32x256 (SystemVerilog)
// Description: Top-level IMC-SRAM — dual-port SRAM + Boolean compute unit.
//              256 rows x 32-bit. Memory Mode + Compute Mode (2-cycle FSM).
//============================================================================

module imc_sram_32x256 (
    input  logic        clk,
    input  logic        mode,          // 0 = Memory, 1 = Compute
    input  logic        we,            // Write enable (Memory Mode)
    input  logic [7:0]  addr_a,        // Row address A
    input  logic [7:0]  addr_b,        // Row address B (Compute operand B)
    input  logic [7:0]  addr_wr,       // Write-back address (Compute result)
    input  logic [31:0] din,           // Data input (Memory Mode)
    input  logic [2:0]  op_sel,        // Operation select (Compute Mode)
    output logic [31:0] dout,          // Data output
    output logic        zero_flag,     // Zero flag
    output logic [5:0]  ones_count,    // Popcount
    output logic        compute_done   // 1-cycle pulse when result valid
);

    // FSM states
    typedef enum logic [1:0] {
        S_IDLE    = 2'b00,
        S_READ    = 2'b01,
        S_COMPUTE = 2'b10
    } state_t;

    state_t state, next_state;

    // SRAM port signals
    logic        sram_we_a;
    logic [7:0]  sram_addr_a;
    logic [31:0] sram_din_a;
    logic [31:0] sram_dout_a;
    logic        sram_we_b;
    logic [7:0]  sram_addr_b;
    logic [31:0] sram_din_b;
    logic [31:0] sram_dout_b;

    // Compute unit signals
    logic [31:0] compute_result;
    logic [31:0] operand_a_reg, operand_b_reg;
    logic [2:0]  op_sel_reg;
    logic [7:0]  addr_wr_reg;

    // Sub-modules
    sram_dual_port u_sram (
        .clk    (clk),
        .we_a   (sram_we_a),   .addr_a (sram_addr_a), .din_a (sram_din_a), .dout_a (sram_dout_a),
        .we_b   (sram_we_b),   .addr_b (sram_addr_b), .din_b (sram_din_b), .dout_b (sram_dout_b)
    );

    imc_compute_unit u_compute (
        .operand_a  (operand_a_reg),
        .operand_b  (operand_b_reg),
        .op_sel     (op_sel_reg),
        .result     (compute_result),
        .zero_flag  (zero_flag),
        .ones_count (ones_count)
    );

    // FSM next state
    always_comb begin
        unique case (state)
            S_IDLE:    next_state = mode ? S_READ : S_IDLE;
            S_READ:    next_state = S_COMPUTE;
            S_COMPUTE: next_state = S_IDLE;
            default:   next_state = S_IDLE;
        endcase
    end

    // FSM register
    always_ff @(posedge clk) begin
        state <= next_state;
    end

    // Latch operands + control on READ cycle
    always_ff @(posedge clk) begin
        if (state == S_READ) begin
            operand_a_reg <= sram_dout_a;
            operand_b_reg <= sram_dout_b;
            op_sel_reg    <= op_sel;
            addr_wr_reg   <= addr_wr;
        end
    end

    // SRAM port mux
    always_comb begin
        sram_we_a   = 1'b0;
        sram_addr_a = addr_a;
        sram_din_a  = 32'h0;
        sram_we_b   = 1'b0;
        sram_addr_b = addr_b;
        sram_din_b  = 32'h0;

        unique case (state)
            S_IDLE: begin
                if (!mode) begin
                    sram_we_a   = we;
                    sram_addr_a = addr_a;
                    sram_din_a  = din;
                end else begin
                    sram_addr_a = addr_a;
                    sram_addr_b = addr_b;
                end
            end
            S_READ: begin
                sram_addr_a = addr_a;
                sram_addr_b = addr_b;
            end
            S_COMPUTE: begin
                sram_we_a   = 1'b1;
                sram_addr_a = addr_wr_reg;
                sram_din_a  = compute_result;
            end
            default: ;
        endcase
    end

    // Output + compute_done
    always_ff @(posedge clk) begin
        compute_done <= 1'b0;

        unique case (state)
            S_IDLE: begin
                if (!mode)
                    dout <= sram_dout_a;
            end
            S_COMPUTE: begin
                dout         <= compute_result;
                compute_done <= 1'b1;
            end
            default: ;
        endcase
    end

endmodule
