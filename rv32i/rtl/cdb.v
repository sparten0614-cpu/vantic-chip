// =============================================================================
// Common Data Bus (CDB) — Result Broadcast Network
// =============================================================================
// Arbitrates between multiple execution units wanting to broadcast results.
// Priority: ALU0 > ALU1 > MEM > MUL/DIV
// Winner broadcasts {tag, value} to all Reservation Stations + ROB.
// =============================================================================

module cdb #(
    parameter ROB_TAG_W = 4,
    parameter NUM_EU = 3       // Number of execution units
) (
    input  wire        clk,
    input  wire        rst_n,

    // Execution unit result inputs
    input  wire        eu0_valid,     // ALU result ready
    input  wire [ROB_TAG_W-1:0] eu0_tag,
    input  wire [31:0] eu0_value,
    input  wire        eu0_exception,

    input  wire        eu1_valid,     // MEM result ready
    input  wire [ROB_TAG_W-1:0] eu1_tag,
    input  wire [31:0] eu1_value,
    input  wire        eu1_exception,

    input  wire        eu2_valid,     // MUL/DIV result ready
    input  wire [ROB_TAG_W-1:0] eu2_tag,
    input  wire [31:0] eu2_value,
    input  wire        eu2_exception,

    // Broadcast output (to all RS entries + ROB)
    output reg         cdb_valid,
    output reg  [ROB_TAG_W-1:0] cdb_tag,
    output reg  [31:0] cdb_value,
    output reg         cdb_exception,

    // Stall signals (EU must hold result if not granted)
    output wire        eu0_stall,
    output wire        eu1_stall,
    output wire        eu2_stall
);

// Priority arbiter: EU0 > EU1 > EU2
wire eu0_grant = eu0_valid;
wire eu1_grant = eu1_valid && !eu0_valid;
wire eu2_grant = eu2_valid && !eu0_valid && !eu1_valid;

// Stall = valid but not granted
assign eu0_stall = 1'b0;  // EU0 always wins
assign eu1_stall = eu1_valid && eu0_valid;
assign eu2_stall = eu2_valid && (eu0_valid || eu1_valid);

always @(posedge clk) begin
    if (!rst_n) begin
        cdb_valid     <= 1'b0;
        cdb_tag       <= 0;
        cdb_value     <= 32'd0;
        cdb_exception <= 1'b0;
    end else begin
        if (eu0_grant) begin
            cdb_valid     <= 1'b1;
            cdb_tag       <= eu0_tag;
            cdb_value     <= eu0_value;
            cdb_exception <= eu0_exception;
        end else if (eu1_grant) begin
            cdb_valid     <= 1'b1;
            cdb_tag       <= eu1_tag;
            cdb_value     <= eu1_value;
            cdb_exception <= eu1_exception;
        end else if (eu2_grant) begin
            cdb_valid     <= 1'b1;
            cdb_tag       <= eu2_tag;
            cdb_value     <= eu2_value;
            cdb_exception <= eu2_exception;
        end else begin
            cdb_valid <= 1'b0;
        end
    end
end

endmodule
