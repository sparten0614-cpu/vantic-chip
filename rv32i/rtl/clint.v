// =============================================================================
// RISC-V Core Local Interruptor (CLINT)
// =============================================================================
// Simplified CLINT for single-core RV32I:
//   - Machine timer (mtime/mtimecmp) for periodic interrupts
//   - Software interrupt (MSIP)
//   - 8 external interrupt inputs
//   - Interrupt pending/enable registers
//   - Memory-mapped (base address configurable)
// =============================================================================

module clint (
    input  wire        clk,
    input  wire        rst_n,

    // External interrupt inputs
    input  wire [7:0]  ext_irq,       // External interrupt lines

    // Timer
    input  wire        timer_tick,    // 1-cycle pulse every timer period (e.g., 1MHz)

    // CPU interface (memory-mapped register access)
    input  wire [7:0]  reg_addr,      // Register address (byte offset)
    input  wire [31:0] reg_wdata,
    input  wire        reg_wen,
    output reg  [31:0] reg_rdata,

    // Interrupt output to CPU
    output wire        irq_timer,     // Machine timer interrupt
    output wire        irq_software,  // Machine software interrupt
    output wire        irq_external,  // External interrupt (any enabled & pending)
    output wire        irq_any        // Any interrupt active
);

// =============================================================================
// Registers
// =============================================================================
// 0x00: MSIP        — Software interrupt pending (bit 0)
// 0x04: MTIMECMP_LO — Timer compare low 32 bits
// 0x08: MTIMECMP_HI — Timer compare high 32 bits
// 0x0C: MTIME_LO    — Timer counter low 32 bits (read-only, clears on write)
// 0x10: MTIME_HI    — Timer counter high 32 bits
// 0x14: MIE         — Interrupt enable (bit per source)
// 0x18: MIP         — Interrupt pending (read-only for external, W1C for software)

reg        msip;
reg [63:0] mtime;
reg [63:0] mtimecmp;
reg [7:0]  mie;          // Interrupt enable per external line
reg        mie_timer;    // Timer interrupt enable
reg        mie_sw;       // Software interrupt enable

// =============================================================================
// Timer
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        mtime <= 64'd0;
    else if (timer_tick)
        mtime <= mtime + 64'd1;
end

assign irq_timer = mie_timer && (mtime >= mtimecmp);

// =============================================================================
// Software Interrupt
// =============================================================================
assign irq_software = mie_sw && msip;

// =============================================================================
// External Interrupts
// =============================================================================
wire [7:0] ext_pending = ext_irq & mie;
assign irq_external = |ext_pending;

// =============================================================================
// Aggregate
// =============================================================================
assign irq_any = irq_timer | irq_software | irq_external;

// =============================================================================
// Register Read/Write
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        msip     <= 1'b0;
        mtimecmp <= 64'hFFFFFFFFFFFFFFFF; // Max value (never triggers initially)
        mie      <= 8'd0;
        mie_timer <= 1'b0;
        mie_sw   <= 1'b0;
    end else if (reg_wen) begin
        case (reg_addr)
            8'h00: msip <= reg_wdata[0];
            8'h04: mtimecmp[31:0]  <= reg_wdata;
            8'h08: mtimecmp[63:32] <= reg_wdata;
            8'h14: {mie_timer, mie_sw, mie} <= reg_wdata[9:0];
            default: ;
        endcase
    end
end

always @(*) begin
    case (reg_addr)
        8'h00: reg_rdata = {31'd0, msip};
        8'h04: reg_rdata = mtimecmp[31:0];
        8'h08: reg_rdata = mtimecmp[63:32];
        8'h0C: reg_rdata = mtime[31:0];
        8'h10: reg_rdata = mtime[63:32];
        8'h14: reg_rdata = {22'd0, mie_timer, mie_sw, mie};
        8'h18: reg_rdata = {22'd0, irq_timer, irq_software, ext_irq & mie};
        default: reg_rdata = 32'd0;
    endcase
end

endmodule
