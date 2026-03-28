// =============================================================================
// Reservation Station — Out-of-Order Issue Queue
// =============================================================================
// 8-entry reservation station for out-of-order execution.
// Instructions wait here until all operands are ready, then issue to ALU.
//
// Each entry stores:
//   - Operation (funct3, funct7, opcode)
//   - Source operand 1: value (if ready) or ROB tag (if pending)
//   - Source operand 2: same
//   - Destination ROB tag
//   - Ready bits for each source
//
// When an execution unit broadcasts a result (via CDB - Common Data Bus),
// waiting entries snoop the tag and capture the value.
//
// Issue policy: oldest-ready-first (in-order among ready instructions)
// =============================================================================

module reservation_station #(
    parameter ENTRIES = 8,
    parameter IDX_W = 3,
    parameter ROB_TAG_W = 4
) (
    input  wire        clk,
    input  wire        rst_n,

    // Dispatch (from Decode/Rename)
    input  wire        dispatch_valid,
    input  wire [6:0]  dispatch_opcode,
    input  wire [2:0]  dispatch_funct3,
    input  wire [6:0]  dispatch_funct7,
    input  wire [31:0] dispatch_src1_val,    // Source 1 value (if ready)
    input  wire [ROB_TAG_W-1:0] dispatch_src1_tag, // Source 1 ROB tag (if not ready)
    input  wire        dispatch_src1_ready,  // 1=value valid, 0=waiting for tag
    input  wire [31:0] dispatch_src2_val,
    input  wire [ROB_TAG_W-1:0] dispatch_src2_tag,
    input  wire        dispatch_src2_ready,
    input  wire [ROB_TAG_W-1:0] dispatch_dst_tag,  // Destination ROB tag
    input  wire [31:0] dispatch_imm,         // Immediate value
    input  wire        dispatch_use_imm,     // Use immediate for src2
    output wire        dispatch_ready,       // RS has space

    // Issue (to execution unit)
    output reg         issue_valid,
    output reg  [6:0]  issue_opcode,
    output reg  [2:0]  issue_funct3,
    output reg  [6:0]  issue_funct7,
    output reg  [31:0] issue_src1,
    output reg  [31:0] issue_src2,
    output reg  [ROB_TAG_W-1:0] issue_dst_tag,

    // Common Data Bus (CDB) — snoop for operand forwarding
    input  wire        cdb_valid,
    input  wire [ROB_TAG_W-1:0] cdb_tag,
    input  wire [31:0] cdb_value,

    // Flush
    input  wire        flush
);

// =============================================================================
// Entry Storage
// =============================================================================
reg        entry_valid   [0:ENTRIES-1];
reg [6:0]  entry_opcode  [0:ENTRIES-1];
reg [2:0]  entry_funct3  [0:ENTRIES-1];
reg [6:0]  entry_funct7  [0:ENTRIES-1];
reg [31:0] entry_src1_val[0:ENTRIES-1];
reg [ROB_TAG_W-1:0] entry_src1_tag[0:ENTRIES-1];
reg        entry_src1_rdy[0:ENTRIES-1];
reg [31:0] entry_src2_val[0:ENTRIES-1];
reg [ROB_TAG_W-1:0] entry_src2_tag[0:ENTRIES-1];
reg        entry_src2_rdy[0:ENTRIES-1];
reg [ROB_TAG_W-1:0] entry_dst_tag[0:ENTRIES-1];

// Count valid entries
reg [IDX_W:0] count;
assign dispatch_ready = (count < ENTRIES);

// =============================================================================
// Find first free slot (for dispatch)
// =============================================================================
reg [IDX_W-1:0] free_slot;
reg             free_found;
integer f;
always @(*) begin
    free_found = 1'b0;
    free_slot = 0;
    for (f = 0; f < ENTRIES; f = f + 1) begin
        if (!entry_valid[f] && !free_found) begin
            free_slot = f[IDX_W-1:0];
            free_found = 1'b1;
        end
    end
end

// =============================================================================
// Find oldest ready entry (for issue)
// =============================================================================
reg [IDX_W-1:0] ready_slot;
reg             ready_found;
integer r;
always @(*) begin
    ready_found = 1'b0;
    ready_slot = 0;
    for (r = 0; r < ENTRIES; r = r + 1) begin
        if (entry_valid[r] && entry_src1_rdy[r] && entry_src2_rdy[r] && !ready_found) begin
            ready_slot = r[IDX_W-1:0];
            ready_found = 1'b1;
        end
    end
end

// =============================================================================
// Main Logic
// =============================================================================
integer i;
always @(posedge clk) begin
    if (!rst_n || flush) begin
        count <= 0;
        issue_valid <= 1'b0;
        for (i = 0; i < ENTRIES; i = i + 1)
            entry_valid[i] <= 1'b0;
    end else begin
        issue_valid <= 1'b0;

        // CDB snoop: update waiting operands
        if (cdb_valid) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                if (entry_valid[i]) begin
                    if (!entry_src1_rdy[i] && entry_src1_tag[i] == cdb_tag) begin
                        entry_src1_val[i] <= cdb_value;
                        entry_src1_rdy[i] <= 1'b1;
                    end
                    if (!entry_src2_rdy[i] && entry_src2_tag[i] == cdb_tag) begin
                        entry_src2_val[i] <= cdb_value;
                        entry_src2_rdy[i] <= 1'b1;
                    end
                end
            end
        end

        // Issue: send oldest ready to execution unit
        if (ready_found) begin
            issue_valid   <= 1'b1;
            issue_opcode  <= entry_opcode[ready_slot];
            issue_funct3  <= entry_funct3[ready_slot];
            issue_funct7  <= entry_funct7[ready_slot];
            issue_src1    <= entry_src1_val[ready_slot];
            issue_src2    <= entry_src2_val[ready_slot];
            issue_dst_tag <= entry_dst_tag[ready_slot];
            entry_valid[ready_slot] <= 1'b0;
        end

        // Dispatch: accept new instruction
        if (dispatch_valid && dispatch_ready && free_found) begin
            entry_valid[free_slot]    <= 1'b1;
            entry_opcode[free_slot]   <= dispatch_opcode;
            entry_funct3[free_slot]   <= dispatch_funct3;
            entry_funct7[free_slot]   <= dispatch_funct7;
            entry_src1_val[free_slot] <= dispatch_src1_val;
            entry_src1_tag[free_slot] <= dispatch_src1_tag;
            entry_src1_rdy[free_slot] <= dispatch_src1_ready;
            entry_dst_tag[free_slot]  <= dispatch_dst_tag;

            // Source 1: CDB bypass — if dispatching src is pending and CDB has the tag
            if (!dispatch_src1_ready && cdb_valid && dispatch_src1_tag == cdb_tag) begin
                entry_src1_val[free_slot] <= cdb_value;
                entry_src1_rdy[free_slot] <= 1'b1;
            end

            // Source 2: use immediate if flagged, else check CDB bypass
            if (dispatch_use_imm) begin
                entry_src2_val[free_slot] <= dispatch_imm;
                entry_src2_rdy[free_slot] <= 1'b1;
            end else if (!dispatch_src2_ready && cdb_valid && dispatch_src2_tag == cdb_tag) begin
                entry_src2_val[free_slot] <= cdb_value;
                entry_src2_rdy[free_slot] <= 1'b1;
            end else begin
                entry_src2_val[free_slot] <= dispatch_src2_val;
                entry_src2_tag[free_slot] <= dispatch_src2_tag;
                entry_src2_rdy[free_slot] <= dispatch_src2_ready;
            end

        end

        // Count update: handle simultaneous issue + dispatch
        if (ready_found && dispatch_valid && dispatch_ready && free_found)
            count <= count;       // +1 -1 = net zero
        else if (ready_found)
            count <= count - 1;
        else if (dispatch_valid && dispatch_ready && free_found)
            count <= count + 1;
    end
end

endmodule
