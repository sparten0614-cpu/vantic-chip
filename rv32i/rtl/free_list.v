// =============================================================================
// Free List — Physical Register Allocation for OoO PRF
// =============================================================================
// FIFO circular buffer tracking available physical registers.
// At reset: preloaded with pregs [ARCH_REGS .. PHYS_REGS-1]
// (pregs 0..ARCH_REGS-1 are initially mapped to architectural registers)
//
// Dispatch: dequeue a free preg for the destination register
// Commit: enqueue the old preg (freed by the committing instruction)
// Flush: restore head pointer from checkpoint
// =============================================================================

module free_list #(
    parameter PHYS_REGS = 64,
    parameter ARCH_REGS = 32,
    parameter PREG_W    = 6,    // log2(PHYS_REGS)
    parameter DEPTH     = PHYS_REGS - ARCH_REGS,  // 32 free entries
    parameter PTR_W     = 5     // log2(DEPTH)
) (
    input  wire        clk,
    input  wire        rst_n,

    // Allocate (dispatch — dequeue)
    input  wire        alloc_req,       // Request a free preg
    output wire [PREG_W-1:0] alloc_preg, // Allocated preg ID
    output wire        alloc_valid,     // Free list not empty

    // Release (commit — enqueue)
    input  wire        release_req,     // Release a preg
    input  wire [PREG_W-1:0] release_preg, // Preg to return to free list

    // Checkpoint (for speculative recovery)
    input  wire        checkpoint_req,  // Save current head
    input  wire [1:0]  checkpoint_id,   // Which checkpoint slot
    output wire [PTR_W-1:0] checkpoint_head, // Current head (for external storage)

    // Restore (flush — rewind head to checkpoint)
    input  wire        restore_req,
    input  wire [PTR_W-1:0] restore_head, // Head pointer to restore to

    // Status
    output wire        empty,
    output wire        full
);

// =============================================================================
// Storage
// =============================================================================
reg [PREG_W-1:0] fifo [0:DEPTH-1];
reg [PTR_W-1:0]  head;  // Dequeue (allocate) pointer
reg [PTR_W-1:0]  tail;  // Enqueue (release) pointer
reg [PTR_W:0]    count; // Number of entries (extra bit for full detection)

assign empty = (count == 0);
assign full  = (count == DEPTH);
assign alloc_valid = !empty;
assign alloc_preg  = fifo[head];
assign checkpoint_head = head;

// =============================================================================
// Initialize: preload with pregs ARCH_REGS .. PHYS_REGS-1
// =============================================================================
integer init_i;

always @(posedge clk) begin
    if (!rst_n) begin
        head  <= {PTR_W{1'b0}};
        tail  <= {PTR_W{1'b0}};
        count <= DEPTH[PTR_W:0];
        for (init_i = 0; init_i < DEPTH; init_i = init_i + 1)
            fifo[init_i] <= ARCH_REGS[PREG_W-1:0] + init_i[PREG_W-1:0];
    end else if (restore_req) begin
        // Flush: rewind head to checkpoint
        head  <= restore_head;
        // Count adjustment: entries between restore_head and tail
        // Since tail may have advanced (commits during speculative window),
        // count = tail - restore_head (modular)
        if (tail >= restore_head)
            count <= {1'b0, tail} - {1'b0, restore_head};
        else
            count <= DEPTH[PTR_W:0] - ({1'b0, restore_head} - {1'b0, tail});
    end else begin
        // Simultaneous alloc + release
        if (alloc_req && alloc_valid && release_req) begin
            // Net zero change in count
            fifo[tail] <= release_preg;
            head <= head + 1'b1;
            tail <= tail + 1'b1;
        end else if (alloc_req && alloc_valid) begin
            head  <= head + 1'b1;
            count <= count - 1'b1;
        end else if (release_req && !full) begin
            fifo[tail] <= release_preg;
            tail  <= tail + 1'b1;
            count <= count + 1'b1;
        end
    end
end

endmodule
