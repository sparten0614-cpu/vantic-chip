// =============================================================================
// Load/Store Queue (LSQ) — Memory Ordering for OoO Execution
// =============================================================================
// Ensures correct memory ordering despite out-of-order execution:
//   - Stores commit in program order (via ROB)
//   - Loads can execute early if no older store has unknown address
//   - Address computed when base operand ready
//
// 8-entry queue, FIFO allocation (program order preserved)
// ENTRIES must be power-of-2
// =============================================================================

module load_store_queue #(
    parameter ENTRIES   = 8,
    parameter IDX_W     = 3,
    parameter ROB_TAG_W = 4
) (
    input  wire        clk,
    input  wire        rst_n,

    // Dispatch (from Decode — allocates entry in program order)
    input  wire        dispatch_valid,
    input  wire        dispatch_is_load,   // 1=load, 0=store
    input  wire [2:0]  dispatch_funct3,    // LB/LH/LW/LBU/LHU / SB/SH/SW
    input  wire [ROB_TAG_W-1:0] dispatch_rob_tag, // Associated ROB entry
    input  wire [31:0] dispatch_base_val,  // rs1 value (if ready)
    input  wire [ROB_TAG_W-1:0] dispatch_base_tag, // rs1 ROB tag (if pending)
    input  wire        dispatch_base_ready,
    input  wire [31:0] dispatch_data_val,  // rs2 value for stores (if ready)
    input  wire [ROB_TAG_W-1:0] dispatch_data_tag, // rs2 ROB tag for stores
    input  wire        dispatch_data_ready, // Loads ignore this
    input  wire [31:0] dispatch_offset,    // Immediate offset
    output wire        dispatch_ready,     // LSQ has space

    // CDB snoop (for operand wakeup)
    input  wire        cdb_valid,
    input  wire [ROB_TAG_W-1:0] cdb_tag,
    input  wire [31:0] cdb_value,

    // Memory interface (matches dcache)
    output reg         mem_req,
    output reg         mem_we,
    output reg  [31:0] mem_addr,
    output reg  [31:0] mem_wdata,
    output reg  [1:0]  mem_size,       // 00=byte, 01=half, 10=word
    input  wire [31:0] mem_rdata,
    input  wire        mem_valid,      // Memory response valid
    input  wire        mem_ready,      // Memory can accept request

    // CDB write (load result broadcast)
    output reg         result_valid,
    output reg  [ROB_TAG_W-1:0] result_tag,
    output reg  [31:0] result_value,

    // Commit (from ROB — allows stores to write to memory)
    input  wire        commit_store,       // ROB says oldest store can commit
    input  wire [ROB_TAG_W-1:0] commit_tag,

    // Flush
    input  wire        flush
);

// =============================================================================
// Entry Storage
// =============================================================================
reg        entry_valid    [0:ENTRIES-1];
reg        entry_is_load  [0:ENTRIES-1];
reg [2:0]  entry_funct3   [0:ENTRIES-1];
reg [ROB_TAG_W-1:0] entry_rob_tag[0:ENTRIES-1];

// Address computation
reg [31:0] entry_base_val [0:ENTRIES-1];
reg [ROB_TAG_W-1:0] entry_base_tag[0:ENTRIES-1];
reg        entry_base_rdy [0:ENTRIES-1];
reg [31:0] entry_offset   [0:ENTRIES-1];
reg        entry_addr_done[0:ENTRIES-1];
reg [31:0] entry_addr     [0:ENTRIES-1];

// Store data
reg [31:0] entry_data_val [0:ENTRIES-1];
reg [ROB_TAG_W-1:0] entry_data_tag[0:ENTRIES-1];
reg        entry_data_rdy [0:ENTRIES-1];

// Execution state
reg        entry_issued    [0:ENTRIES-1]; // Memory request sent
reg        entry_completed [0:ENTRIES-1]; // Result received
reg        entry_committed [0:ENTRIES-1]; // Store committed from ROB (can write to memory)

// FIFO pointers
reg [IDX_W-1:0] head;
reg [IDX_W-1:0] tail;
reg [IDX_W:0]   count;

assign dispatch_ready = (count < ENTRIES);

// =============================================================================
// Find oldest ready load (combinational)
// =============================================================================
reg [IDX_W-1:0] load_slot;
reg             load_found;
reg             store_blocks;
reg [IDX_W:0]   lf;
reg [IDX_W-1:0] lf_idx;

always @(*) begin
    load_found = 1'b0;
    load_slot = 0;
    store_blocks = 1'b0;

    for (lf = 0; lf < ENTRIES; lf = lf + 1) begin
        lf_idx = head + lf[IDX_W-1:0]; // Wraps naturally (power-of-2)
        if (entry_valid[lf_idx]) begin
            if (entry_is_load[lf_idx] && entry_addr_done[lf_idx] &&
                !entry_issued[lf_idx] && !store_blocks && !load_found) begin
                load_slot = lf_idx;
                load_found = 1'b1;
            end
            // Older uncommitted store blocks younger loads
            // (conservative: no store-to-load forwarding, so wait for store to issue)
            if (!entry_is_load[lf_idx] && !entry_issued[lf_idx] && !load_found) begin
                store_blocks = 1'b1;
            end
        end
    end
end

// =============================================================================
// Store at head ready to commit?
// =============================================================================
wire store_head_ready = entry_valid[head] && !entry_is_load[head] &&
                        entry_addr_done[head] && entry_data_rdy[head] &&
                        entry_committed[head] && !entry_issued[head];

// =============================================================================
// Pending load waiting for memory response
// =============================================================================
reg [IDX_W-1:0] pending_load_slot;
reg             pending_load_valid;
reg [IDX_W:0]   pl;

always @(*) begin
    pending_load_valid = 1'b0;
    pending_load_slot = 0;
    for (pl = 0; pl < ENTRIES; pl = pl + 1) begin
        if (entry_valid[pl] && entry_is_load[pl] &&
            entry_issued[pl] && !entry_completed[pl] && !pending_load_valid) begin
            pending_load_slot = pl[IDX_W-1:0];
            pending_load_valid = 1'b1;
        end
    end
end

// =============================================================================
// funct3 → size conversion
// =============================================================================
function [1:0] funct3_to_size;
    input [2:0] f3;
    case (f3)
        3'b000, 3'b100: funct3_to_size = 2'b00; // LB/LBU/SB
        3'b001, 3'b101: funct3_to_size = 2'b01; // LH/LHU/SH
        default:        funct3_to_size = 2'b10; // LW/SW
    endcase
endfunction

// =============================================================================
// Main Logic — single always block drives all state
// =============================================================================
integer mi; // main loop index
always @(posedge clk) begin
    if (!rst_n || flush) begin
        head  <= 0;
        tail  <= 0;
        count <= 0;
        mem_req      <= 1'b0;
        result_valid <= 1'b0;
        for (mi = 0; mi < ENTRIES; mi = mi + 1) begin
            entry_valid[mi]     <= 1'b0;
            entry_issued[mi]    <= 1'b0;
            entry_completed[mi] <= 1'b0;
            entry_committed[mi] <= 1'b0;
            entry_addr_done[mi] <= 1'b0;
        end
    end else begin
        mem_req      <= 1'b0;
        result_valid <= 1'b0;

        // --- Address computation for all entries with ready base ---
        for (mi = 0; mi < ENTRIES; mi = mi + 1) begin
            if (entry_valid[mi] && entry_base_rdy[mi] && !entry_addr_done[mi]) begin
                entry_addr[mi]      <= entry_base_val[mi] + entry_offset[mi];
                entry_addr_done[mi] <= 1'b1;
            end
        end

        // --- CDB snoop: wake up base address and store data operands ---
        if (cdb_valid) begin
            for (mi = 0; mi < ENTRIES; mi = mi + 1) begin
                if (entry_valid[mi]) begin
                    if (!entry_base_rdy[mi] && entry_base_tag[mi] == cdb_tag) begin
                        entry_base_val[mi] <= cdb_value;
                        entry_base_rdy[mi] <= 1'b1;
                    end
                    if (!entry_data_rdy[mi] && !entry_is_load[mi] &&
                        entry_data_tag[mi] == cdb_tag) begin
                        entry_data_val[mi] <= cdb_value;
                        entry_data_rdy[mi] <= 1'b1;
                    end
                end
            end
        end

        // --- Issue load to memory ---
        if (load_found && mem_ready && !mem_req) begin
            mem_req  <= 1'b1;
            mem_we   <= 1'b0;
            mem_addr <= entry_addr[load_slot];
            mem_wdata <= 32'd0;
            mem_size <= funct3_to_size(entry_funct3[load_slot]);
            entry_issued[load_slot] <= 1'b1;
        end

        // --- Latch store commit from ROB ---
        if (commit_store) begin
            for (mi = 0; mi < ENTRIES; mi = mi + 1) begin
                if (entry_valid[mi] && !entry_is_load[mi] &&
                    entry_rob_tag[mi] == commit_tag)
                    entry_committed[mi] <= 1'b1;
            end
        end

        // --- Issue committed store to memory ---
        if (store_head_ready && mem_ready && !mem_req && !load_found) begin
            mem_req  <= 1'b1;
            mem_we   <= 1'b1;
            mem_addr <= entry_addr[head];
            mem_wdata <= entry_data_val[head];
            mem_size <= funct3_to_size(entry_funct3[head]);
            entry_issued[head]    <= 1'b1;
            entry_completed[head] <= 1'b1;
            entry_valid[head]     <= 1'b0;
            head  <= head + 1;
            count <= count - 1;
        end

        // --- Load result: capture memory response and broadcast ---
        if (mem_valid && pending_load_valid) begin
            entry_completed[pending_load_slot] <= 1'b1;
            result_valid <= 1'b1;
            result_tag   <= entry_rob_tag[pending_load_slot];
            case (entry_funct3[pending_load_slot])
                3'b000:  result_value <= {{24{mem_rdata[7]}},  mem_rdata[7:0]};  // LB
                3'b001:  result_value <= {{16{mem_rdata[15]}}, mem_rdata[15:0]}; // LH
                3'b010:  result_value <= mem_rdata;                               // LW
                3'b100:  result_value <= {24'd0, mem_rdata[7:0]};                // LBU
                3'b101:  result_value <= {16'd0, mem_rdata[15:0]};               // LHU
                default: result_value <= mem_rdata;
            endcase
            entry_valid[pending_load_slot] <= 1'b0;
            if (pending_load_slot == head) begin
                head  <= head + 1;
                count <= count - 1;
            end
        end

        // --- Dispatch: allocate new entry ---
        if (dispatch_valid && dispatch_ready) begin
            entry_valid[tail]      <= 1'b1;
            entry_is_load[tail]    <= dispatch_is_load;
            entry_funct3[tail]     <= dispatch_funct3;
            entry_rob_tag[tail]    <= dispatch_rob_tag;
            entry_offset[tail]     <= dispatch_offset;
            entry_issued[tail]     <= 1'b0;
            entry_completed[tail]  <= 1'b0;
            entry_committed[tail]  <= 1'b0;
            entry_addr_done[tail]  <= 1'b0;

            // Base address
            entry_base_val[tail]  <= dispatch_base_val;
            entry_base_tag[tail]  <= dispatch_base_tag;
            entry_base_rdy[tail]  <= dispatch_base_ready;
            // CDB bypass for base
            if (!dispatch_base_ready && cdb_valid && dispatch_base_tag == cdb_tag) begin
                entry_base_val[tail] <= cdb_value;
                entry_base_rdy[tail] <= 1'b1;
            end

            // Store data
            if (!dispatch_is_load) begin
                entry_data_val[tail]  <= dispatch_data_val;
                entry_data_tag[tail]  <= dispatch_data_tag;
                entry_data_rdy[tail]  <= dispatch_data_ready;
                if (!dispatch_data_ready && cdb_valid && dispatch_data_tag == cdb_tag) begin
                    entry_data_val[tail] <= cdb_value;
                    entry_data_rdy[tail] <= 1'b1;
                end
            end else begin
                entry_data_rdy[tail] <= 1'b1;
            end

            tail  <= tail + 1;
            count <= count + 1;
        end
    end
end

endmodule
