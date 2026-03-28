// =============================================================================
// Rename Table with Physical Register File Support (Dual RAT)
// =============================================================================
// Speculative RAT: updated at dispatch, used for operand resolution
// Committed RAT:   updated at commit, used for flush recovery
//
// Each entry maps an architectural register (x0-x31) to a physical register ID.
// On dispatch: SpecRAT[rd] = new_preg (from free list)
// On commit:   CommRAT[rd] = preg being committed
// On flush:    SpecRAT ← CommRAT (copy committed state)
// =============================================================================

module rename_prf #(
    parameter PREG_W    = 6,    // Physical register ID width
    parameter ARCH_REGS = 32
) (
    input  wire        clk,
    input  wire        rst_n,

    // Lookup (Decode — resolve source operands to physical regs)
    input  wire [4:0]  lookup_rs1,
    input  wire [4:0]  lookup_rs2,
    output wire [PREG_W-1:0] rs1_preg,   // Physical reg for rs1
    output wire [PREG_W-1:0] rs2_preg,   // Physical reg for rs2

    // Rename (Dispatch — assign new physical reg to rd)
    input  wire        rename_valid,
    input  wire [4:0]  rename_rd,
    input  wire [PREG_W-1:0] rename_new_preg,  // From free list
    output wire [PREG_W-1:0] rename_old_preg,  // Previous mapping (for ROB to track)

    // Commit (Retire — update committed mapping)
    input  wire        commit_valid,
    input  wire [4:0]  commit_rd,
    input  wire [PREG_W-1:0] commit_preg,  // Physical reg to commit

    // Flush (Misprediction — restore speculative to committed state)
    input  wire        flush,

    // Snapshot (for checkpoint — read full speculative RAT)
    output wire [PREG_W*ARCH_REGS-1:0] spec_rat_snapshot
);

// =============================================================================
// Dual RAT Storage
// =============================================================================
reg [PREG_W-1:0] spec_rat  [0:ARCH_REGS-1];  // Speculative mapping
reg [PREG_W-1:0] comm_rat  [0:ARCH_REGS-1];  // Committed mapping

// =============================================================================
// Lookup (combinational)
// =============================================================================
// x0 always maps to p0 (hardwired zero)
assign rs1_preg = (lookup_rs1 == 5'd0) ? {PREG_W{1'b0}} : spec_rat[lookup_rs1];
assign rs2_preg = (lookup_rs2 == 5'd0) ? {PREG_W{1'b0}} : spec_rat[lookup_rs2];

// Old preg for rd (before rename — needed by ROB for free list release at commit)
assign rename_old_preg = (rename_rd == 5'd0) ? {PREG_W{1'b0}} : spec_rat[rename_rd];

// =============================================================================
// Snapshot (pack all 32 entries for checkpoint)
// =============================================================================
genvar gi;
generate
    for (gi = 0; gi < ARCH_REGS; gi = gi + 1) begin : gen_snap
        assign spec_rat_snapshot[gi*PREG_W +: PREG_W] = spec_rat[gi];
    end
endgenerate

// =============================================================================
// Update Logic
// =============================================================================
integer i;
always @(posedge clk) begin
    if (!rst_n) begin
        // At reset: arch reg i maps to physical reg i (identity mapping)
        for (i = 0; i < ARCH_REGS; i = i + 1) begin
            spec_rat[i] <= i[PREG_W-1:0];
            comm_rat[i] <= i[PREG_W-1:0];
        end
    end else if (flush) begin
        // Restore speculative RAT from committed RAT
        for (i = 0; i < ARCH_REGS; i = i + 1)
            spec_rat[i] <= comm_rat[i];
    end else begin
        // Speculative rename at dispatch
        if (rename_valid && rename_rd != 5'd0)
            spec_rat[rename_rd] <= rename_new_preg;

        // Committed update at retire
        if (commit_valid && commit_rd != 5'd0)
            comm_rat[commit_rd] <= commit_preg;
    end
end

endmodule
