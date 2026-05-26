//============================================================================
// Module: sram_single_port
// Description: Single-port SRAM array — 256 rows x 32-bit words.
//              Synchronous read and write on rising clock edge.
//              Coded for BRAM inference (registered output, no reset on memory).
//
// BRAM Inference Requirements:
//   - Memory declared as reg array (not wire)
//   - Synchronous read (output registered in always @(posedge clk))
//   - No asynchronous read path
//   - No initial block on memory array
//   These ensure Xilinx Vivado / Intel Quartus map to Block RAM, not LUT RAM.
//============================================================================

module sram_single_port (
    input  wire        clk,   // System clock
    input  wire        we,    // Write enable: 1 = write, 0 = read
    input  wire [7:0]  addr,  // Address — 8 bits for 256 rows
    input  wire [31:0] din,   // Data input — 32-bit word
    output reg  [31:0] dout   // Data output — 32-bit word (registered)
);

    // Memory array: 256 entries of 32 bits each (8 Kbit = 1 KB)
    // Synthesizer infers this as Block RAM when read is synchronous.
    reg [31:0] mem [0:255];

    // Synchronous read-first behaviour:
    //   On rising clock edge —
    //     Write path: if we=1, store din at mem[addr]
    //     Read path:  always register mem[addr] to dout (read-first means
    //                 dout gets the OLD value at addr, even if writing same cycle)
    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;  // Write: data stored at addressed location
        end
        dout <= mem[addr];     // Read: output is always the stored value (read-first)
    end

endmodule
