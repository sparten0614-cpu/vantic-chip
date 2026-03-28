// =============================================================================
// Direct-Mapped Instruction Cache
// =============================================================================
// 1KB cache (256 words × 4 bytes), direct-mapped, read-only
// Line size: 1 word (32 bits) — simplest possible cache
// Tag + valid bit per line
//
// Address mapping (32-bit):
//   [31:10] = tag (22 bits)
//   [9:2]   = index (8 bits → 256 lines)
//   [1:0]   = byte offset (always 0 for word-aligned instruction fetch)
//
// On miss: stall pipeline, fetch from main memory (1-cycle assumed)
// =============================================================================

module icache (
    input  wire        clk,
    input  wire        rst_n,

    // CPU interface
    input  wire [31:0] addr,          // Instruction address from CPU
    output reg  [31:0] data,          // Instruction data to CPU
    output reg         hit,           // Cache hit (data valid this cycle)

    // Main memory interface (on miss)
    output reg  [31:0] mem_addr,
    input  wire [31:0] mem_data,
    output reg         mem_req,       // Memory request
    input  wire        mem_valid      // Memory data valid
);

localparam LINES = 256;
localparam TAG_W = 22;
localparam IDX_W = 8;

// Cache storage
reg [31:0]    cache_data [0:LINES-1];
reg [TAG_W-1:0] cache_tag [0:LINES-1];
reg             cache_valid [0:LINES-1];

// Address decomposition
wire [TAG_W-1:0] addr_tag = addr[31:10];
wire [IDX_W-1:0] addr_idx = addr[9:2];

// Lookup
wire tag_match = cache_valid[addr_idx] && (cache_tag[addr_idx] == addr_tag);

// State machine
localparam IDLE = 1'b0, FETCH = 1'b1;
reg state;

integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state   <= IDLE;
        hit     <= 1'b0;
        mem_req <= 1'b0;
        data    <= 32'd0;
        mem_addr <= 32'd0;
        for (i = 0; i < LINES; i = i + 1)
            cache_valid[i] <= 1'b0;
    end else begin
        case (state)
        IDLE: begin
            if (tag_match) begin
                // Cache hit
                data <= cache_data[addr_idx];
                hit  <= 1'b1;
                mem_req <= 1'b0;
            end else begin
                // Cache miss — fetch from memory
                hit      <= 1'b0;
                mem_addr <= addr;
                mem_req  <= 1'b1;
                state    <= FETCH;
            end
        end

        FETCH: begin
            if (mem_valid) begin
                // Fill cache line
                cache_data[addr_idx]  <= mem_data;
                cache_tag[addr_idx]   <= addr_tag;
                cache_valid[addr_idx] <= 1'b1;
                data    <= mem_data;
                hit     <= 1'b1;
                mem_req <= 1'b0;
                state   <= IDLE;
            end
        end

        default: state <= IDLE;
        endcase
    end
end

endmodule
