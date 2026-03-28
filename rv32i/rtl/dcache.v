// =============================================================================
// Direct-Mapped Data Cache — 2KB, Write-Through
// =============================================================================
// 512 lines × 4 bytes (1 word per line), direct-mapped
// Write-through policy: all writes go to both cache and memory
// Write-allocate: on write miss, fetch line then write
//
// Address: [31:11]=tag(21-bit), [10:2]=index(9-bit), [1:0]=byte offset
// =============================================================================

module dcache (
    input  wire        clk,
    input  wire        rst_n,

    // CPU interface
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,        // Byte write strobes
    input  wire        ren,           // Read enable
    input  wire        wen,           // Write enable
    output reg  [31:0] rdata,
    output reg         hit,           // Cache hit
    output reg         stall,         // Stall CPU (on miss)

    // Main memory interface
    output reg  [31:0] mem_addr,
    output reg  [31:0] mem_wdata,
    output reg  [3:0]  mem_wstrb,
    output reg         mem_ren,
    output reg         mem_wen,
    input  wire [31:0] mem_rdata,
    input  wire        mem_valid
);

localparam LINES = 512;
localparam TAG_W = 21;
localparam IDX_W = 9;

// Cache storage
reg [31:0]    data_mem [0:LINES-1];
reg [TAG_W-1:0] tag_mem [0:LINES-1];
reg             valid_mem [0:LINES-1];

// Address decomposition
wire [TAG_W-1:0] addr_tag = addr[31:11];
wire [IDX_W-1:0] addr_idx = addr[10:2];

// Lookup
wire tag_match = valid_mem[addr_idx] && (tag_mem[addr_idx] == addr_tag);

// State machine
localparam [1:0] IDLE = 2'd0, FETCH = 2'd1, WRITEBACK = 2'd2;
reg [1:0] state;

// Apply byte strobes to cache data
wire [31:0] merged_data;
assign merged_data[7:0]   = wstrb[0] ? wdata[7:0]   : data_mem[addr_idx][7:0];
assign merged_data[15:8]  = wstrb[1] ? wdata[15:8]  : data_mem[addr_idx][15:8];
assign merged_data[23:16] = wstrb[2] ? wdata[23:16] : data_mem[addr_idx][23:16];
assign merged_data[31:24] = wstrb[3] ? wdata[31:24] : data_mem[addr_idx][31:24];

integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state    <= IDLE;
        hit      <= 1'b0;
        stall    <= 1'b0;
        rdata    <= 32'd0;
        mem_ren  <= 1'b0;
        mem_wen  <= 1'b0;
        mem_addr <= 32'd0;
        mem_wdata <= 32'd0;
        mem_wstrb <= 4'd0;
        for (i = 0; i < LINES; i = i + 1)
            valid_mem[i] <= 1'b0;
    end else begin
        hit   <= 1'b0;
        stall <= 1'b0;
        mem_ren <= 1'b0;
        mem_wen <= 1'b0;

        case (state)
        IDLE: begin
            if (ren) begin
                if (tag_match) begin
                    // Read hit
                    rdata <= data_mem[addr_idx];
                    hit   <= 1'b1;
                end else begin
                    // Read miss — fetch from memory
                    stall    <= 1'b1;
                    mem_addr <= addr;
                    mem_ren  <= 1'b1;
                    state    <= FETCH;
                end
            end else if (wen) begin
                // Write-through: always write to memory
                mem_addr  <= addr;
                mem_wdata <= wdata;
                mem_wstrb <= wstrb;
                mem_wen   <= 1'b1;

                if (tag_match) begin
                    // Write hit: update cache too
                    data_mem[addr_idx] <= merged_data;
                    hit <= 1'b1;
                end else begin
                    // Write miss: write-through only (no allocate on write-miss for simplicity)
                    hit <= 1'b1; // Don't stall on write miss
                end
            end
        end

        FETCH: begin
            stall <= 1'b1;
            if (mem_valid) begin
                // Fill cache line
                data_mem[addr_idx]  <= mem_rdata;
                tag_mem[addr_idx]   <= addr_tag;
                valid_mem[addr_idx] <= 1'b1;
                rdata <= mem_rdata;
                hit   <= 1'b1;
                stall <= 1'b0;
                state <= IDLE;
            end
        end

        default: state <= IDLE;
        endcase
    end
end

endmodule
