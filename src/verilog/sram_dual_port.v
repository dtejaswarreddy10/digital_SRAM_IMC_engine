//============================================================================
// Module: sram_dual_port
// Description: True dual-port SRAM — 256 rows x 32-bit words.
//              Port A and Port B can independently read or write each cycle.
//              Write collision policy: Port A has priority (Port B write
//              is suppressed when both target the same address).
//              Synchronous read-first behaviour for BRAM inference.
//
// BRAM Inference Notes:
//   Xilinx UG901 "True Dual-Port RAM with Single Clock":
//     - Single always block, two read/write sections
//     - Registered outputs on both ports
//   Intel: similar pattern with single-clock dual-port template.
//============================================================================

module sram_dual_port (
    input  wire        clk,     // System clock
    // Port A
    input  wire        we_a,    // Port A write enable
    input  wire [7:0]  addr_a,  // Port A address
    input  wire [31:0] din_a,   // Port A data input
    output reg  [31:0] dout_a,  // Port A data output (registered)
    // Port B
    input  wire        we_b,    // Port B write enable
    input  wire [7:0]  addr_b,  // Port B address
    input  wire [31:0] din_b,   // Port B data input
    output reg  [31:0] dout_b   // Port B data output (registered)
);

    // Shared memory array — both ports access the same storage
    reg [31:0] mem [0:255];

    // --- Port A: synchronous read-first ---
    // Read-first: dout_a captures mem[addr_a] BEFORE any write in this cycle.
    // If we_a=1, new data is written into mem[addr_a] after the read capture.
    always @(posedge clk) begin
        if (we_a) begin
            mem[addr_a] <= din_a;
        end
        dout_a <= mem[addr_a];
    end

    // --- Port B: synchronous read-first, collision-guarded ---
    // Write collision guard: if Port A and Port B both write to the same
    // address in the same cycle, Port A wins — Port B write is suppressed.
    // This prevents undefined memory state from simultaneous dual writes.
    always @(posedge clk) begin
        if (we_b && !(we_a && (addr_a == addr_b))) begin
            mem[addr_b] <= din_b;
        end
        dout_b <= mem[addr_b];
    end

endmodule
