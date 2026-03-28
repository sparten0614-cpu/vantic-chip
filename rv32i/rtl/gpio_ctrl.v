// =============================================================================
// Enhanced GPIO Controller — Cortex-M0+ Level
// =============================================================================
// 32 GPIO pins with:
//   - Direction control (input/output per pin)
//   - Output value register
//   - Input value register (synchronized)
//   - Set/Clear registers (atomic bit manipulation)
//   - Edge-triggered interrupts (rising/falling/both)
//
// Register Map (byte offsets):
//   0x00: DIR    — Direction (0=input, 1=output)
//   0x04: OUT    — Output value
//   0x08: IN     — Input value (read-only, synchronized)
//   0x0C: SET    — Atomic set (write 1 to set output bit, read returns OUT)
//   0x10: CLR    — Atomic clear (write 1 to clear output bit)
//   0x14: TOGGLE — Atomic toggle (write 1 to toggle output bit)
//   0x18: INTEN  — Interrupt enable per pin
//   0x1C: INTFLAG — Interrupt flags (write 1 to clear)
//   0x20: INTCFG — Interrupt config: 0=rising, 1=falling (per pin)
// =============================================================================

module gpio_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [7:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    input  wire        reg_wen,
    output reg  [31:0] reg_rdata,

    // GPIO pins
    output wire [31:0] gpio_out,
    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_dir,    // Direction (for tri-state pad control)

    // Interrupt output
    output wire        irq
);

reg [31:0] dir_reg;
reg [31:0] out_reg;
reg [31:0] inten_reg;
reg [31:0] intflag_reg;
reg [31:0] intcfg_reg;  // 0=rising, 1=falling

assign gpio_out = out_reg;
assign gpio_dir = dir_reg;

// Input synchronizer (2-stage)
reg [31:0] in_s1, in_s2, in_prev;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_s1 <= 32'd0; in_s2 <= 32'd0; in_prev <= 32'd0;
    end else begin
        in_s1   <= gpio_in;
        in_s2   <= in_s1;
        in_prev <= in_s2;
    end
end

// Edge detection
wire [31:0] rising_edge  = in_s2 & ~in_prev;
wire [31:0] falling_edge = ~in_s2 & in_prev;
wire [31:0] edge_detect  = (~intcfg_reg & rising_edge) | (intcfg_reg & falling_edge);

// Interrupt flag set (edge detected + enabled)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        intflag_reg <= 32'd0;
    else begin
        // Set on edge
        intflag_reg <= intflag_reg | (edge_detect & inten_reg);
        // Clear on write-1-to-clear
        if (reg_wen && reg_addr == 8'h1C)
            intflag_reg <= intflag_reg & ~reg_wdata;
    end
end

assign irq = |intflag_reg;

// Register write
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dir_reg    <= 32'd0;
        out_reg    <= 32'd0;
        inten_reg  <= 32'd0;
        intcfg_reg <= 32'd0;
    end else if (reg_wen) begin
        case (reg_addr)
            8'h00: dir_reg    <= reg_wdata;
            8'h04: out_reg    <= reg_wdata;
            8'h0C: out_reg    <= out_reg | reg_wdata;   // SET
            8'h10: out_reg    <= out_reg & ~reg_wdata;  // CLR
            8'h14: out_reg    <= out_reg ^ reg_wdata;   // TOGGLE
            8'h18: inten_reg  <= reg_wdata;
            8'h20: intcfg_reg <= reg_wdata;
            default: ;
        endcase
    end
end

// Register read
always @(*) begin
    case (reg_addr)
        8'h00: reg_rdata = dir_reg;
        8'h04: reg_rdata = out_reg;
        8'h08: reg_rdata = in_s2;
        8'h0C: reg_rdata = out_reg;
        8'h18: reg_rdata = inten_reg;
        8'h1C: reg_rdata = intflag_reg;
        8'h20: reg_rdata = intcfg_reg;
        default: reg_rdata = 32'd0;
    endcase
end

endmodule
