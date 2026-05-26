//============================================================================
// Module: imc_sram_32x256
// Description: Top-level IMC-SRAM integrating dual-port SRAM + compute unit.
//              256 rows x 32-bit words with in-memory Boolean compute.
//
// Modes:
//   Memory Mode (mode=0): Standard SRAM read/write via addr_a.
//     we=1 → write din to addr_a.  we=0 → read addr_a to dout.
//
//   Compute Mode (mode=1): 2-cycle in-memory compute pipeline.
//     Cycle 1 (READ):          Read row addr_a (Port A) and row addr_b (Port B).
//     Cycle 2 (COMPUTE+WRITE): Compute unit result → written to addr_wr,
//                               dout shows result, compute_done pulses high.
//
// Pipeline FSM States:  IDLE → READ → COMPUTE → IDLE
//============================================================================

module imc_sram_32x256 (
    input  wire        clk,           // System clock
    input  wire        mode,          // 0 = Memory Mode, 1 = Compute Mode
    input  wire        we,            // Write enable (Memory Mode only)
    input  wire [7:0]  addr_a,        // Row address A
    input  wire [7:0]  addr_b,        // Row address B (operand B in Compute Mode)
    input  wire [7:0]  addr_wr,       // Write-back address (Compute Mode result dest)
    input  wire [31:0] din,           // Data input (Memory Mode write)
    input  wire [2:0]  op_sel,        // Boolean operation select (Compute Mode)
    output reg  [31:0] dout,          // Data output (read or compute result)
    output wire        zero_flag,     // Zero flag from compute unit
    output wire [5:0]  ones_count,    // Popcount from compute unit
    output reg         compute_done   // Pulses high for 1 cycle when result valid
);

    // ---------------------------------------------------------------
    // FSM state encoding
    // ---------------------------------------------------------------
    localparam S_IDLE    = 2'b00;
    localparam S_READ    = 2'b01;
    localparam S_COMPUTE = 2'b10;

    reg [1:0] state, next_state;

    // ---------------------------------------------------------------
    // Internal signals — SRAM ports
    // ---------------------------------------------------------------
    reg         sram_we_a;
    reg  [7:0]  sram_addr_a;
    reg  [31:0] sram_din_a;
    wire [31:0] sram_dout_a;

    reg         sram_we_b;
    reg  [7:0]  sram_addr_b;
    reg  [31:0] sram_din_b;
    wire [31:0] sram_dout_b;

    // ---------------------------------------------------------------
    // Internal signals — Compute unit
    // ---------------------------------------------------------------
    wire [31:0] compute_result;
    // Latched operands from read cycle
    reg  [31:0] operand_a_reg;
    reg  [31:0] operand_b_reg;
    // Latched op_sel and write address for compute cycle
    reg  [2:0]  op_sel_reg;
    reg  [7:0]  addr_wr_reg;

    // ---------------------------------------------------------------
    // Sub-module instantiations
    // ---------------------------------------------------------------
    sram_dual_port u_sram (
        .clk    (clk),
        .we_a   (sram_we_a),
        .addr_a (sram_addr_a),
        .din_a  (sram_din_a),
        .dout_a (sram_dout_a),
        .we_b   (sram_we_b),
        .addr_b (sram_addr_b),
        .din_b  (sram_din_b),
        .dout_b (sram_dout_b)
    );

    imc_compute_unit u_compute (
        .operand_a  (operand_a_reg),
        .operand_b  (operand_b_reg),
        .op_sel     (op_sel_reg),
        .result     (compute_result),
        .zero_flag  (zero_flag),
        .ones_count (ones_count)
    );

    // ---------------------------------------------------------------
    // FSM — next state logic
    // ---------------------------------------------------------------
    always @(*) begin
        case (state)
            S_IDLE: begin
                if (mode)
                    next_state = S_READ;
                else
                    next_state = S_IDLE;
            end
            S_READ:    next_state = S_COMPUTE;
            S_COMPUTE: next_state = S_IDLE;
            default:   next_state = S_IDLE;
        endcase
    end

    // ---------------------------------------------------------------
    // FSM — state register
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        state <= next_state;
    end

    // ---------------------------------------------------------------
    // Operand latch + op_sel/addr_wr capture on READ cycle
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (state == S_READ) begin
            operand_a_reg <= sram_dout_a;
            operand_b_reg <= sram_dout_b;
            op_sel_reg    <= op_sel;
            addr_wr_reg   <= addr_wr;
        end
    end

    // ---------------------------------------------------------------
    // SRAM port mux — combinational
    // ---------------------------------------------------------------
    always @(*) begin
        // Defaults — no writes, idle addresses
        sram_we_a   = 1'b0;
        sram_addr_a = addr_a;
        sram_din_a  = 32'h0;
        sram_we_b   = 1'b0;
        sram_addr_b = addr_b;
        sram_din_b  = 32'h0;

        case (state)
            S_IDLE: begin
                if (!mode) begin
                    // Memory Mode: Port A used for standard read/write
                    sram_we_a   = we;
                    sram_addr_a = addr_a;
                    sram_din_a  = din;
                    // Port B idle
                end else begin
                    // Compute Mode starting: set up read addresses
                    sram_addr_a = addr_a;
                    sram_addr_b = addr_b;
                end
            end
            S_READ: begin
                // Second cycle of read — data appears on dout_a/dout_b
                // Addresses stable from previous cycle
                sram_addr_a = addr_a;
                sram_addr_b = addr_b;
            end
            S_COMPUTE: begin
                // Write compute result to addr_wr via Port A
                sram_we_a   = 1'b1;
                sram_addr_a = addr_wr_reg;
                sram_din_a  = compute_result;
            end
            default: begin
                // Keep defaults
            end
        endcase
    end

    // ---------------------------------------------------------------
    // Output mux + compute_done
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        compute_done <= 1'b0;  // Default: de-assert

        case (state)
            S_IDLE: begin
                if (!mode && !we) begin
                    // Memory Mode read: dout follows Port A read
                    // Guard with !we so write-only cycles don't clobber dout
                    dout <= sram_dout_a;
                end
            end
            S_COMPUTE: begin
                // Compute Mode: output the compute result
                dout         <= compute_result;
                compute_done <= 1'b1;
            end
            default: begin
                // S_READ: hold previous dout, compute_done stays low
            end
        endcase
    end

endmodule
