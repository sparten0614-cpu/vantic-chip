// =============================================================================
// RISC-V SV32 MMU — Memory Management Unit with TLB
// =============================================================================
// Implements Sv32 virtual memory translation for RV32:
//   - 32-bit virtual address → 34-bit physical address (4GB VA, 16GB PA)
//   - 2-level page table (10-bit VPN[1] + 10-bit VPN[0] + 12-bit offset)
//   - 4KB page size
//   - Page table entries: 32-bit (PPN + flags: V/R/W/X/U/G/A/D)
//   - 32-entry fully-associative TLB (Translation Lookaside Buffer)
//   - Page table walker (hardware, 2 memory accesses per miss)
//
// Interface:
//   - CPU sends virtual address + access type
//   - MMU returns physical address or page fault
//   - On TLB miss: MMU walks page table via memory interface
// =============================================================================

module mmu_sv32 (
    input  wire        clk,
    input  wire        rst_n,

    // CPU interface
    input  wire [31:0] vaddr,         // Virtual address
    input  wire        req_valid,     // Address translation request
    input  wire        req_read,
    input  wire        req_write,
    input  wire        req_exec,
    output reg  [33:0] paddr,         // Physical address (34-bit Sv32)
    output reg         resp_valid,    // Translation complete
    output reg         page_fault,    // Access violation

    // Page table base register
    input  wire [31:0] satp,          // satp CSR: [31]=MODE(1=Sv32), [21:0]=PPN

    // Memory interface (for page table walk)
    output reg  [31:0] ptw_addr,      // Page table walk address
    output reg         ptw_req,       // Walk memory request
    input  wire [31:0] ptw_data,      // Walk memory data
    input  wire        ptw_valid,     // Walk data valid

    // Control
    input  wire        tlb_flush,     // Flush all TLB entries (SFENCE.VMA)
    input  wire        mmu_enable     // 0=bare mode (VA=PA), 1=Sv32
);

// =============================================================================
// Virtual Address Decomposition (Sv32)
// =============================================================================
wire [9:0]  vpn1   = vaddr[31:22];  // Level-1 VPN
wire [9:0]  vpn0   = vaddr[21:12];  // Level-0 VPN
wire [11:0] offset = vaddr[11:0];   // Page offset (4KB)

// =============================================================================
// TLB: 32-entry Fully-Associative
// =============================================================================
localparam TLB_ENTRIES = 32;

reg [19:0] tlb_vpn   [0:TLB_ENTRIES-1]; // VPN[1:0] = {vpn1, vpn0}
reg [21:0] tlb_ppn   [0:TLB_ENTRIES-1]; // Physical page number
reg [7:0]  tlb_flags [0:TLB_ENTRIES-1]; // V/R/W/X/U/G/A/D
reg        tlb_valid [0:TLB_ENTRIES-1];
reg [4:0]  tlb_lru;                      // Simple counter for replacement

// TLB lookup (combinational)
wire [19:0] lookup_vpn = {vpn1, vpn0};
reg         tlb_hit;
reg [4:0]   tlb_hit_idx;
reg [21:0]  tlb_hit_ppn;
reg [7:0]   tlb_hit_flags;

integer j;
always @(*) begin
    tlb_hit = 1'b0;
    tlb_hit_idx = 5'd0;
    tlb_hit_ppn = 22'd0;
    tlb_hit_flags = 8'd0;
    for (j = 0; j < TLB_ENTRIES; j = j + 1) begin
        if (tlb_valid[j] && tlb_vpn[j] == lookup_vpn) begin
            tlb_hit = 1'b1;
            tlb_hit_idx = j[4:0];
            tlb_hit_ppn = tlb_ppn[j];
            tlb_hit_flags = tlb_flags[j];
        end
    end
end

// Permission check
wire pte_v = tlb_hit_flags[0]; // Valid
wire pte_r = tlb_hit_flags[1]; // Read
wire pte_w = tlb_hit_flags[2]; // Write
wire pte_x = tlb_hit_flags[3]; // Execute

wire permission_ok = pte_v &&
                     (!req_read  || pte_r) &&
                     (!req_write || pte_w) &&
                     (!req_exec  || pte_x);

// =============================================================================
// Page Table Walker State Machine
// =============================================================================
localparam [2:0] IDLE   = 3'd0,
                 WALK_L1 = 3'd1,  // Fetch level-1 PTE
                 WAIT_L1 = 3'd2,
                 WALK_L0 = 3'd3,  // Fetch level-0 PTE
                 WAIT_L0 = 3'd4,
                 DONE    = 3'd5,
                 FAULT   = 3'd6;

reg [2:0]  walk_state;
reg [31:0] pte_l1;  // Level-1 PTE

// Page table base physical address
wire [31:0] pt_base = {satp[21:0], 12'd0}; // PPN × 4096

integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        walk_state  <= IDLE;
        resp_valid  <= 1'b0;
        page_fault  <= 1'b0;
        paddr       <= 34'd0;
        ptw_req     <= 1'b0;
        ptw_addr    <= 32'd0;
        tlb_lru     <= 5'd0;
        for (i = 0; i < TLB_ENTRIES; i = i + 1)
            tlb_valid[i] <= 1'b0;
    end else begin
        resp_valid <= 1'b0;
        page_fault <= 1'b0;
        ptw_req    <= 1'b0;

        // TLB flush
        if (tlb_flush) begin
            for (i = 0; i < TLB_ENTRIES; i = i + 1)
                tlb_valid[i] <= 1'b0;
        end

        case (walk_state)
        IDLE: begin
            if (req_valid) begin
                if (!mmu_enable || !satp[31]) begin
                    // Bare mode: VA = PA
                    paddr      <= {2'b0, vaddr};
                    resp_valid <= 1'b1;
                end else if (tlb_hit) begin
                    // TLB hit
                    if (permission_ok) begin
                        paddr      <= {tlb_hit_ppn, offset};
                        resp_valid <= 1'b1;
                    end else begin
                        page_fault <= 1'b1;
                        resp_valid <= 1'b1;
                    end
                end else begin
                    // TLB miss — start page table walk
                    // Level-1: PTE addr = pt_base + vpn1 * 4
                    ptw_addr   <= pt_base + {20'd0, vpn1, 2'b00};
                    ptw_req    <= 1'b1;
                    walk_state <= WAIT_L1;
                end
            end
        end

        WAIT_L1: begin
            if (ptw_valid) begin
                pte_l1 <= ptw_data;
                if (!ptw_data[0]) begin
                    // PTE not valid → page fault
                    walk_state <= FAULT;
                end else if (ptw_data[1] || ptw_data[3]) begin
                    // Leaf PTE at level 1 (superpage, 4MB)
                    // PPN = PTE[31:10], offset includes vpn0+page_offset
                    tlb_vpn[tlb_lru]   <= lookup_vpn;
                    tlb_ppn[tlb_lru]   <= ptw_data[31:10];
                    tlb_flags[tlb_lru] <= ptw_data[7:0];
                    tlb_valid[tlb_lru] <= 1'b1;
                    tlb_lru            <= tlb_lru + 5'd1;
                    paddr      <= {ptw_data[31:10], offset};
                    resp_valid <= 1'b1;
                    walk_state <= IDLE;
                end else begin
                    // Non-leaf PTE → walk level 0
                    ptw_addr   <= {ptw_data[29:10], vpn0, 2'b00};
                    ptw_req    <= 1'b1;
                    walk_state <= WAIT_L0;
                end
            end
        end

        WAIT_L0: begin
            if (ptw_valid) begin
                if (!ptw_data[0] || (!ptw_data[1] && !ptw_data[3])) begin
                    // Invalid or non-leaf at level 0 → fault
                    walk_state <= FAULT;
                end else begin
                    // Valid leaf PTE
                    tlb_vpn[tlb_lru]   <= lookup_vpn;
                    tlb_ppn[tlb_lru]   <= ptw_data[31:10];
                    tlb_flags[tlb_lru] <= ptw_data[7:0];
                    tlb_valid[tlb_lru] <= 1'b1;
                    tlb_lru            <= tlb_lru + 5'd1;
                    paddr      <= {ptw_data[31:10], offset};
                    resp_valid <= 1'b1;
                    walk_state <= IDLE;
                end
            end
        end

        FAULT: begin
            page_fault <= 1'b1;
            resp_valid <= 1'b1;
            walk_state <= IDLE;
        end

        default: walk_state <= IDLE;
        endcase
    end
end

endmodule
