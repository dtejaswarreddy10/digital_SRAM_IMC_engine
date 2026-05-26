//============================================================================
// Module: sram_single_port
// Description: Single-port SRAM array — 256 rows x 32-bit words.
//              Synchronous read and write on rising clock edge.
//              SystemVerilog version — uses logic types and always_ff.
//              Coded for BRAM inference (registered output, no reset on memory).
//============================================================================

module sram_single_port (
    input  logic        clk,   // System clock
    input  logic        we,    // Write enable: 1 = write, 0 = read
    input  logic [7:0]  addr,  // Address — 8 bits for 256 rows
    input  logic [31:0] din,   // Data input — 32-bit word
    output logic [31:0] dout   // Data output — 32-bit word (registered)
);

    // Memory array: 256 entries of 32 bits each (8 Kbit = 1 KB)
    logic [31:0] mem [0:255];

    // Synchronous read-first behaviour:
    //   Write path: if we=1, store din at mem[addr]
    //   Read path:  dout always gets mem[addr] (old value on write cycle)
    always_ff @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;
        end
        dout <= mem[addr];
    end

endmodule
