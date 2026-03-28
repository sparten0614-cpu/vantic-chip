// =============================================================================
// Register Rename Table — Eliminates WAR/WAW False Dependencies
// =============================================================================
// Maps 32 architectural registers (x0-x31) to physical registers (ROB tags).
// Each architectural register points to the ROB entry that will produce its
// latest value, or is marked as "committed" (value in arch register file).
//
// On dispatch: rd → allocate new ROB tag, update rename table
// On commit: ROB tag retires, mark architectural register as committed
// On flush: restore rename table to committed state (checkpoint)
//
// 32 entries × (ROB_TAG_W + 1 valid bit) = small and fast
// =============================================================================

module reg_rename #(
    parameter ROB_TAG_W = 4
) (
    input  wire        clk,
    input  wire        rst_n,

    // Lookup (Decode stage — resolve source operands)
    input  wire [4:0]  lookup_rs1,
    input  wire [4:0]  lookup_rs2,
    output wire [ROB_TAG_W-1:0] rs1_tag,
    output wire        rs1_pending,    // 1=value in ROB (use tag), 0=value in arch regfile
    output wire [ROB_TAG_W-1:0] rs2_tag,
    output wire        rs2_pending,

    // Rename (Dispatch — assign new tag to rd)
    input  wire        rename_valid,
    input  wire [4:0]  rename_rd,
    input  wire [ROB_TAG_W-1:0] rename_tag, // New ROB tag for this rd

    // Commit (Retire — mark register as no longer pending)
    input  wire        commit_valid,
    input  wire [4:0]  commit_rd,
    input  wire [ROB_TAG_W-1:0] commit_tag, // Only clear if tag matches (avoid clearing newer mapping)

    // Flush (Branch mispredict — restore to committed state)
    input  wire        flush
);

// =============================================================================
// Rename Table: 32 entries
// =============================================================================
reg [ROB_TAG_W-1:0] table_tag [0:31];   // ROB tag for each arch register
reg                  table_pending [0:31]; // 1=waiting for ROB result

// x0 is always ready (hardwired to 0)
// =============================================================================
// Lookup (combinational)
// =============================================================================
assign rs1_tag     = table_tag[lookup_rs1];
assign rs1_pending = (lookup_rs1 != 5'd0) && table_pending[lookup_rs1];
assign rs2_tag     = table_tag[lookup_rs2];
assign rs2_pending = (lookup_rs2 != 5'd0) && table_pending[lookup_rs2];

// =============================================================================
// Update Logic
// =============================================================================
integer i;
always @(posedge clk) begin
    if (!rst_n || flush) begin
        // On reset or flush: all registers are committed (in arch regfile)
        for (i = 0; i < 32; i = i + 1)
            table_pending[i] <= 1'b0;
    end else begin
        // Rename: new instruction writes rd → mark as pending with new tag
        if (rename_valid && rename_rd != 5'd0) begin
            table_tag[rename_rd]     <= rename_tag;
            table_pending[rename_rd] <= 1'b1;
        end

        // Commit: instruction retires → mark as committed
        // Only clear pending if the tag matches (a newer instruction may have
        // already renamed this register to a different tag)
        if (commit_valid && commit_rd != 5'd0) begin
            if (table_tag[commit_rd] == commit_tag)
                table_pending[commit_rd] <= 1'b0;
        end
    end
end

endmodule
