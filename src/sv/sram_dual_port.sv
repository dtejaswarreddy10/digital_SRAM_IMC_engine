//============================================================================
// Module: sram_dual_port
// Description: True dual-port SRAM — 256 rows x 32-bit words.
//              SystemVerilog version with logic types and always_ff.
//              Port A priority on write collision.
//              Synchronous read-first for BRAM inference.
//============================================================================

module sram_dual_port (
    input  logic        clk,
    // Port A
    input  logic        we_a,
    input  logic [7:0]  addr_a,
    input  logic [31:0] din_a,
    output logic [31:0] dout_a,
    // Port B
    input  logic        we_b,
    input  logic [7:0]  addr_b,
    input  logic [31:0] din_b,
    output logic [31:0] dout_b
);

    logic [31:0] mem [0:255];

    // Port A — read-first, unconditional write when we_a=1
    always_ff @(posedge clk) begin
        if (we_a) begin
            mem[addr_a] <= din_a;
        end
        dout_a <= mem[addr_a];
    end

    // Port B — read-first, write suppressed on collision with Port A
    always_ff @(posedge clk) begin
        if (we_b && !(we_a && (addr_a == addr_b))) begin
            mem[addr_b] <= din_b;
        end
        dout_b <= mem[addr_b];
    end

endmodule
