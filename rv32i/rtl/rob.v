// =============================================================================
// Reorder Buffer (ROB) — Out-of-Order Execution Core
// =============================================================================
// The ROB enables out-of-order completion with in-order commit.
// Instructions are allocated in program order, can complete out-of-order,
// and commit (write to architectural state) in order.
//
// 16-entry circular buffer. Each entry:
//   - Instruction info (rd, opcode)
//   - Result value (written when execution completes)
//   - Status: allocated → executing → completed → committed
//   - PC (for exception/branch recovery)
//
// Interface:
//   Allocate: Decode stage reserves an entry (returns ROB tag)
//   Complete: Execution unit writes result (by ROB tag)
//   Commit: Head entry retires to architectural register file
//   Flush: Branch misprediction → flush all entries after mispredicted branch
// =============================================================================

module rob #(
    parameter DEPTH = 16,
    parameter TAG_W = 4    // log2(DEPTH)
) (
    input  wire        clk,
    input  wire        rst_n,

    // Allocate (from Decode)
    input  wire        alloc_valid,
    input  wire [4:0]  alloc_rd,       // Destination register
    input  wire [31:0] alloc_pc,       // Instruction PC
    input  wire        alloc_is_branch,
    input  wire        alloc_is_store,
    input  wire [31:0] alloc_branch_target, // Pre-computed branch target (PC + B-imm)
    input  wire        alloc_predicted_taken, // BP prediction at fetch time
    output wire [TAG_W-1:0] alloc_tag, // Assigned ROB tag
    output wire        alloc_ready,    // ROB has space

    // Complete (from Execution Units)
    input  wire        complete_valid,
    input  wire [TAG_W-1:0] complete_tag,
    input  wire [31:0] complete_value,
    input  wire        complete_exception,  // Exception during execution
    // Branch resolution
    input  wire        complete_branch_taken,
    input  wire [31:0] complete_branch_target,

    // Commit (to Architectural Register File)
    output reg         commit_valid,
    output reg  [4:0]  commit_rd,
    output reg  [31:0] commit_value,
    output reg  [31:0] commit_pc,
    output reg  [TAG_W-1:0] commit_tag,  // Tag of committing entry (head)
    output reg         commit_is_store,  // Is store (for LSQ commit)

    // Flush (branch misprediction)
    output reg         flush,
    output reg  [31:0] flush_target,   // Correct branch target

    // Read port (for dispatch bypass — read completed-but-not-committed values)
    input  wire [TAG_W-1:0] read_tag1,
    output wire [31:0] read_value1,
    output wire        read_complete1,  // 1 if entry is complete (value valid)
    output wire        read_valid1,     // 1 if entry exists (not yet committed)
    input  wire [TAG_W-1:0] read_tag2,
    output wire [31:0] read_value2,
    output wire        read_complete2,
    output wire        read_valid2,

    // Misprediction output (for Spec Recovery)
    output reg         misprediction,     // Misprediction detected this cycle
    output reg  [TAG_W-1:0] mispred_tag,  // Tag of mispredicted branch

    // Status
    output wire        empty,
    output wire        full
);

// =============================================================================
// ROB Entry Storage
// =============================================================================
reg [4:0]  entry_rd      [0:DEPTH-1];
reg [31:0] entry_value   [0:DEPTH-1];
reg [31:0] entry_pc      [0:DEPTH-1];
reg        entry_valid    [0:DEPTH-1]; // Allocated
reg        entry_complete [0:DEPTH-1]; // Execution done
reg        entry_exception[0:DEPTH-1];
reg        entry_is_branch[0:DEPTH-1];
reg        entry_is_store [0:DEPTH-1];
reg        entry_br_taken [0:DEPTH-1];     // Actual outcome (from ALU)
reg        entry_predicted [0:DEPTH-1];   // Predicted outcome (from BP at fetch)
reg [31:0] entry_br_target[0:DEPTH-1];

// Head and tail pointers (circular buffer)
reg [TAG_W-1:0] head;  // Commit point (oldest)
reg [TAG_W-1:0] tail;  // Allocate point (newest+1)
reg [TAG_W:0]   count; // Number of entries

assign empty = (count == 0);
assign full  = (count == DEPTH);
assign alloc_ready = !full;
assign alloc_tag = tail;
// commit_tag and commit_is_store are registered in the commit always block

// ROB read ports (combinational — for dispatch operand bypass)
assign read_value1    = entry_value[read_tag1];
assign read_complete1 = entry_valid[read_tag1] && entry_complete[read_tag1];
assign read_valid1    = entry_valid[read_tag1];
assign read_value2    = entry_value[read_tag2];
assign read_complete2 = entry_valid[read_tag2] && entry_complete[read_tag2];
assign read_valid2    = entry_valid[read_tag2];

// =============================================================================
// Allocate
// =============================================================================
always @(posedge clk) begin
    if (!rst_n) begin
        tail  <= 0;
        count <= 0;
    end else if (flush) begin
        // On flush: reset tail to head (discard all pending)
        tail  <= head;
        count <= 0;
    end else begin
        if (alloc_valid && alloc_ready) begin
            entry_rd[tail]       <= alloc_rd;
            entry_pc[tail]       <= alloc_pc;
            entry_valid[tail]    <= 1'b1;
            entry_complete[tail] <= alloc_is_store; // Stores complete immediately (no rd value)
            entry_exception[tail] <= 1'b0;
            entry_is_branch[tail] <= alloc_is_branch;
            entry_is_store[tail]  <= alloc_is_store;
            entry_br_target[tail] <= alloc_branch_target;
            entry_predicted[tail] <= alloc_predicted_taken;
            tail  <= tail + 1; // Wraps naturally
        end
        // Count update: handle simultaneous alloc + commit
        if (alloc_valid && alloc_ready && commit_valid)
            count <= count;      // +1 -1 = net zero
        else if (alloc_valid && alloc_ready)
            count <= count + 1;
        else if (commit_valid)
            count <= count - 1;
    end
end

// Complete logic merged into commit always block below

// =============================================================================
// Commit (in-order, from head)
// =============================================================================
always @(posedge clk) begin
    if (!rst_n) begin
        head         <= 0;
        commit_valid <= 1'b0;
        commit_rd    <= 5'd0;
        commit_value <= 32'd0;
        commit_pc    <= 32'd0;
        commit_tag   <= 0;
        commit_is_store <= 1'b0;
        flush        <= 1'b0;
        flush_target <= 32'd0;
        misprediction <= 1'b0;
        mispred_tag   <= 0;
    end else begin
        commit_valid    <= 1'b0;
        commit_tag      <= 0;
        commit_is_store <= 1'b0;
        flush           <= 1'b0;
        misprediction   <= 1'b0;

        // Complete: execution unit writes result
        if (complete_valid && entry_valid[complete_tag]) begin
            entry_value[complete_tag]     <= complete_value;
            entry_complete[complete_tag]  <= 1'b1;
            entry_exception[complete_tag] <= complete_exception;
            entry_br_taken[complete_tag]  <= complete_branch_taken;
            // Update branch target if ALU computed one (JALR target)
            if (complete_branch_target != 32'd0)
                entry_br_target[complete_tag] <= complete_branch_target;
        end

        if (!empty && !flush && entry_valid[head] && entry_complete[head]) begin
            // Record commit tag BEFORE head advances
            commit_tag      <= head;
            commit_is_store <= entry_is_store[head];
            if (entry_exception[head]) begin
                flush        <= 1'b1;
                flush_target <= entry_pc[head];
                entry_valid[head] <= 1'b0;
                head <= head + 1;
            end else if (entry_is_branch[head] &&
                         entry_br_taken[head] != entry_predicted[head]) begin
                // Misprediction: actual outcome != predicted outcome
                misprediction <= 1'b1;
                mispred_tag   <= head;
                commit_valid  <= 1'b1;
                commit_rd    <= entry_rd[head];
                commit_value <= entry_value[head];
                commit_pc    <= entry_pc[head];
                flush        <= 1'b1;
                // Correct target: if actually taken → branch target, else PC+4
                flush_target <= entry_br_taken[head] ? entry_br_target[head]
                                                     : (entry_pc[head] + 32'd4);
                entry_valid[head] <= 1'b0;
                head <= head + 1;
            end else begin
                // Normal commit (including not-taken branches)
                commit_valid <= 1'b1;
                commit_rd    <= entry_rd[head];
                commit_value <= entry_value[head];
                commit_pc    <= entry_pc[head];
                entry_valid[head] <= 1'b0;
                head <= head + 1;
            end
        end
    end
end

endmodule
