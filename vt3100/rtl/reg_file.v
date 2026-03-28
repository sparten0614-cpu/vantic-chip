// =============================================================================
// VT3100 Register File — I2C ↔ Logic Bridge
// =============================================================================
// Maps I2C register reads/writes to internal signals.
// Address space: 0x00-0x1F (32 registers), per spec Section 6.
//
// Access types:
//   R   = Read-only (hardware-driven)
//   R/W = Read-write (I2C writable, logic readable)
//   R/C = Read / Write-1-to-Clear
// =============================================================================

module reg_file (
    input  wire        clk,
    input  wire        rst_n,

    // I2C slave interface
    input  wire [7:0]  i2c_addr,
    input  wire [7:0]  i2c_wdata,
    input  wire        i2c_wstrobe,
    output reg  [7:0]  i2c_rdata,

    // --- Read-only status inputs (from logic) ---
    input  wire        attached,        // STATUS_0[7]
    input  wire        orientation,     // STATUS_0[6]
    input  wire        pd_contract,     // STATUS_0[5]
    input  wire        vbus_present,    // STATUS_0[4]
    input  wire [3:0]  protocol_id,     // STATUS_0[3:0]
    input  wire [7:0]  status_1_hw,     // STATUS_1 from fault logic

    // --- R/W control outputs (to logic) ---
    output reg  [7:0]  ctrl_0,          // 0x04: Protocol enable
    output reg  [7:0]  ctrl_1,          // 0x05: Mode and feature control
    output reg  [7:0]  pdo1_volt,       // 0x06
    output reg  [7:0]  pdo1_curr,       // 0x07
    output reg  [7:0]  pdo2_volt,       // 0x08
    output reg  [7:0]  pdo2_curr,       // 0x09
    output reg  [7:0]  pdo3_volt,       // 0x0A
    output reg  [7:0]  pdo3_curr,       // 0x0B
    output reg  [7:0]  pdo4_volt,       // 0x0C
    output reg  [7:0]  pdo4_curr,       // 0x0D
    output reg  [7:0]  ovp_th,          // 0x18
    output reg  [7:0]  ocp_th,          // 0x19
    output reg  [7:0]  otp_th,          // 0x1A
    output reg  [7:0]  gpio_cfg,        // 0x1F

    // Rp level extract (from ctrl_1[3:2])
    output wire [1:0]  rp_level
);

// =============================================================================
// Constants
// =============================================================================
localparam DEV_ID  = 8'h31;
localparam DEV_REV = 8'h10;

// =============================================================================
// Rp level from CTRL_1
// =============================================================================
assign rp_level = ctrl_1[3:2];

// =============================================================================
// Write Logic
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ctrl_0    <= 8'hFF;  // All protocols enabled
        ctrl_1    <= 8'h00;
        pdo1_volt <= 8'h32;  // 5.0V
        pdo1_curr <= 8'h1E;  // 1.5A
        pdo2_volt <= 8'h5A;  // 9.0V
        pdo2_curr <= 8'h3C;  // 3.0A
        pdo3_volt <= 8'h78;  // 12.0V
        pdo3_curr <= 8'h3C;  // 3.0A
        pdo4_volt <= 8'h96;  // 15.0V
        pdo4_curr <= 8'h3C;  // 3.0A
        ovp_th    <= 8'hDC;  // 22.0V
        ocp_th    <= 8'h46;  // 3.5A
        otp_th    <= 8'h78;  // 120°C
        gpio_cfg  <= 8'h00;
    end else if (i2c_wstrobe) begin
        case (i2c_addr)
            8'h04: ctrl_0    <= i2c_wdata;
            8'h05: ctrl_1    <= i2c_wdata;
            8'h06: pdo1_volt <= i2c_wdata;
            8'h07: pdo1_curr <= i2c_wdata;
            8'h08: pdo2_volt <= i2c_wdata;
            8'h09: pdo2_curr <= i2c_wdata;
            8'h0A: pdo3_volt <= i2c_wdata;
            8'h0B: pdo3_curr <= i2c_wdata;
            8'h0C: pdo4_volt <= i2c_wdata;
            8'h0D: pdo4_curr <= i2c_wdata;
            8'h18: ovp_th    <= i2c_wdata;
            8'h19: ocp_th    <= i2c_wdata;
            8'h1A: otp_th    <= i2c_wdata;
            8'h1F: gpio_cfg  <= i2c_wdata;
            // Read-only and R/C registers silently ignored on write
            default: ;
        endcase
    end
end

// =============================================================================
// Read Mux
// =============================================================================
always @(*) begin
    case (i2c_addr)
        8'h00: i2c_rdata = DEV_ID;
        8'h01: i2c_rdata = DEV_REV;
        8'h02: i2c_rdata = {attached, orientation, pd_contract, vbus_present, protocol_id};
        8'h03: i2c_rdata = status_1_hw;
        8'h04: i2c_rdata = ctrl_0;
        8'h05: i2c_rdata = ctrl_1;
        8'h06: i2c_rdata = pdo1_volt;
        8'h07: i2c_rdata = pdo1_curr;
        8'h08: i2c_rdata = pdo2_volt;
        8'h09: i2c_rdata = pdo2_curr;
        8'h0A: i2c_rdata = pdo3_volt;
        8'h0B: i2c_rdata = pdo3_curr;
        8'h0C: i2c_rdata = pdo4_volt;
        8'h0D: i2c_rdata = pdo4_curr;
        8'h18: i2c_rdata = ovp_th;
        8'h19: i2c_rdata = ocp_th;
        8'h1A: i2c_rdata = otp_th;
        8'h1F: i2c_rdata = gpio_cfg;
        default: i2c_rdata = 8'h00;
    endcase
end

endmodule
