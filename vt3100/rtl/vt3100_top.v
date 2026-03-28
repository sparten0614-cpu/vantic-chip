// =============================================================================
// VT3100 Top-Level — USB PD Fast Charging Protocol Controller
// =============================================================================
// Integrates: CC Logic + BMC PHY + PD Message + GoodCRC + PD Policy + I2C + RegFile
//
// Pad-level I/O:
//   CC1, CC2     : USB Type-C CC pins (analog interface)
//   SDA, SCL     : I2C configuration interface
//   VBUS_EN      : Power stage enable
//   GPIO[3:0]    : General purpose I/O
// =============================================================================

module vt3100_top (
    input  wire        clk,           // 12 MHz system clock
    input  wire        rst_n,         // Active-low reset

    // CC pins (analog interface — directly to comparators and BMC PHY)
    input  wire [2:0]  cc1_comp,      // CC1 comparator results {Ra, Rd, below_vOpen}
    input  wire [2:0]  cc2_comp,      // CC2 comparator results
    output wire [1:0]  rp_cc1_level,  // Rp current source level CC1
    output wire [1:0]  rp_cc2_level,  // Rp current source level CC2

    // BMC PHY CC line (muxed by orientation)
    input  wire        cc_rx_in,      // BMC receive (from active CC via analog mux)
    output wire        cc_tx_out,     // BMC transmit (to active CC via analog mux)
    output wire        cc_sel,        // CC orientation select (0=CC1, 1=CC2)

    // I2C
    input  wire        scl_in,
    input  wire        sda_in,
    output wire        sda_oe,

    // Power stage control
    output wire        vbus_en,
    output wire [7:0]  vbus_voltage,  // Target voltage (100mV units)
    output wire [9:0]  vbus_current,  // Max current (10mA units)
    input  wire        vbus_stable,   // VBUS reached target

    // Status
    output wire        pd_contract,
    output wire        vbus_present,
    output wire [3:0]  protocol_id,
    output wire        int_out        // Interrupt
);

// =============================================================================
// Internal Wires
// =============================================================================

// CC Logic outputs
wire        cc_attached;
wire        cc_orientation;
wire        cc_attach_event;
wire        cc_detach_event;
wire        cc_vconn_en;
wire        cc_vconn_cc2;
wire        cc_accessory_mode;
wire [2:0]  cc_state_out;

// BMC PHY ↔ PD Message
wire        phy_tx_valid, phy_tx_ready, phy_tx_sop, phy_tx_eop;
wire [7:0]  phy_tx_data;
wire        phy_rx_valid, phy_rx_sop, phy_rx_eop, phy_rx_crc_ok;
wire [7:0]  phy_rx_data;

// PD Message TX (shared between Policy Engine and GoodCRC)
wire        msg_tx_busy, msg_tx_done;
wire [2:0]  msg_tx_id;

// Policy Engine → TX arbiter
wire        pol_tx_start;
wire [4:0]  pol_tx_msg_type;
wire [2:0]  pol_tx_num_do;
wire        pol_tx_extended;
wire [31:0] pol_tx_do0, pol_tx_do1, pol_tx_do2, pol_tx_do3;
wire        pol_msg_id_inc, pol_msg_id_rst;

// GoodCRC → TX arbiter
wire        gc_tx_start;
wire [4:0]  gc_tx_msg_type;
wire [2:0]  gc_tx_num_do;

// PD Message RX (raw from parser)
wire        raw_rx_valid;
wire [4:0]  raw_rx_msg_type;
wire [2:0]  raw_rx_num_do, raw_rx_msg_id;
wire        raw_rx_ppr, raw_rx_pdr, raw_rx_ext;
wire [1:0]  raw_rx_spec_rev;
wire [31:0] raw_rx_do0, raw_rx_do1, raw_rx_do2, raw_rx_do3;
wire [31:0] raw_rx_do4, raw_rx_do5, raw_rx_do6;
wire        raw_rx_error;

// GoodCRC → Policy Engine (filtered)
wire        filtered_rx_valid;
wire [4:0]  filtered_rx_type;
wire [2:0]  filtered_rx_num_do;
wire        goodcrc_received;
wire [2:0]  gc_rx_expected_id;

// I2C ↔ Register File
wire [7:0]  i2c_reg_addr, i2c_wdata, i2c_rdata;
wire        i2c_wstrobe, i2c_busy;

// Register File outputs
wire [7:0]  ctrl_0, ctrl_1;
wire [7:0]  pdo1_volt, pdo1_curr, pdo2_volt, pdo2_curr;
wire [7:0]  pdo3_volt, pdo3_curr, pdo4_volt, pdo4_curr;
wire [7:0]  ovp_th, ocp_th, otp_th, gpio_cfg;
wire [1:0]  rp_level;

// Policy Engine status
wire        pol_pd_contract, pol_vbus_present, pol_pd_timeout, pol_int_out;
wire [3:0]  pol_protocol_id;
wire [3:0]  pol_state_out;

// =============================================================================
// TX Arbiter: GoodCRC has priority over Policy Engine
// =============================================================================
wire arb_tx_start    = gc_tx_start ? gc_tx_start : pol_tx_start;
wire [4:0] arb_tx_type = gc_tx_start ? gc_tx_msg_type : pol_tx_msg_type;
wire [2:0] arb_tx_ndo  = gc_tx_start ? gc_tx_num_do : pol_tx_num_do;
wire arb_tx_ext      = gc_tx_start ? 1'b0 : pol_tx_extended;
wire [31:0] arb_tx_do0 = pol_tx_do0;
wire [31:0] arb_tx_do1 = pol_tx_do1;
wire [31:0] arb_tx_do2 = pol_tx_do2;
wire [31:0] arb_tx_do3 = pol_tx_do3;

// =============================================================================
// PDO Construction (register bytes → 32-bit PD Fixed PDO format)
// =============================================================================
// Fixed PDO format: [31:30]=00, [29]=DualRole, [28]=Suspend, [27]=ExtPowered,
//   [26]=USBCommsCapable, [25]=DRD, [24:22]=reserved, [21:20]=peak_curr,
//   [19:10]=voltage(50mV), [9:0]=current(10mA)
// Register voltage is in 100mV units, current in 50mA units
// PDO voltage = reg_volt * 2 (100mV → 50mV units)
// PDO current = reg_curr * 5 (50mA → 10mA units)
// Bit[26]=1 (USB Communications Capable) — required by some sinks
// Compute voltage and current fields as 10-bit values
wire [9:0] pdo0_v = {2'b0, pdo1_volt} * 10'd2;
wire [9:0] pdo0_i = {2'b0, pdo1_curr} * 10'd5;
wire [9:0] pdo1_v = {2'b0, pdo2_volt} * 10'd2;
wire [9:0] pdo1_i = {2'b0, pdo2_curr} * 10'd5;
wire [9:0] pdo2_v = {2'b0, pdo3_volt} * 10'd2;
wire [9:0] pdo2_i = {2'b0, pdo3_curr} * 10'd5;
wire [9:0] pdo3_v = {2'b0, pdo4_volt} * 10'd2;
wire [9:0] pdo3_i = {2'b0, pdo4_curr} * 10'd5;

wire [31:0] pdo0_w = {2'b00, 3'b000, 1'b1, 4'd0, 2'd0, pdo0_v, pdo0_i};
wire [31:0] pdo1_w = (pdo2_volt == 8'd0) ? 32'd0 :
                     {2'b00, 3'b000, 1'b1, 4'd0, 2'd0, pdo1_v, pdo1_i};
wire [31:0] pdo2_w = (pdo3_volt == 8'd0) ? 32'd0 :
                     {2'b00, 3'b000, 1'b1, 4'd0, 2'd0, pdo2_v, pdo2_i};
wire [31:0] pdo3_w = (pdo4_volt == 8'd0) ? 32'd0 :
                     {2'b00, 3'b000, 1'b1, 4'd0, 2'd0, pdo3_v, pdo3_i};

// Count active PDOs
wire [2:0] num_pdos = (pdo4_volt != 8'd0) ? 3'd4 :
                      (pdo3_volt != 8'd0) ? 3'd3 :
                      (pdo2_volt != 8'd0) ? 3'd2 : 3'd1;

// =============================================================================
// Module Instances
// =============================================================================

cc_logic u_cc_logic (
    .clk           (clk),
    .rst_n         (rst_n),
    .cc1_comp      (cc1_comp),
    .cc2_comp      (cc2_comp),
    .rp_level      (rp_level),
    .debounce_cfg  (8'd150),
    .attached      (cc_attached),
    .orientation   (cc_orientation),
    .rp_cc1_level  (rp_cc1_level),
    .rp_cc2_level  (rp_cc2_level),
    .vconn_en      (cc_vconn_en),
    .vconn_cc2     (cc_vconn_cc2),
    .attach_event  (cc_attach_event),
    .detach_event  (cc_detach_event),
    .accessory_mode(cc_accessory_mode),
    .cc_sel        (cc_sel),
    .state_out     (cc_state_out)
);

bmc_phy u_bmc_phy (
    .clk       (clk),
    .rst_n     (rst_n),
    .tx_valid  (phy_tx_valid),
    .tx_data   (phy_tx_data),
    .tx_sop    (phy_tx_sop),
    .tx_eop    (phy_tx_eop),
    .tx_ready  (phy_tx_ready),
    .tx_active (),
    .cc_tx_out (cc_tx_out),
    .cc_rx_in  (cc_rx_in),
    .rx_data   (phy_rx_data),
    .rx_valid  (phy_rx_valid),
    .rx_sop    (phy_rx_sop),
    .rx_eop    (phy_rx_eop),
    .rx_crc_ok (phy_rx_crc_ok),
    .rx_error  (),
    .crc_init  (1'b0),
    .crc_en    (1'b0),
    .crc_din   (8'd0),
    .crc_out   ()
);

pd_msg u_pd_msg (
    .clk             (clk),
    .rst_n           (rst_n),
    // TX builder
    .tx_start        (arb_tx_start),
    .tx_msg_type     (arb_tx_type),
    .tx_num_do       (arb_tx_ndo),
    .tx_extended     (arb_tx_ext),
    .tx_do0          (arb_tx_do0),
    .tx_do1          (arb_tx_do1),
    .tx_do2          (arb_tx_do2),
    .tx_do3          (arb_tx_do3),
    .tx_do4          (32'd0),
    .tx_do5          (32'd0),
    .tx_do6          (32'd0),
    .tx_busy         (msg_tx_busy),
    .tx_done         (msg_tx_done),
    .port_power_role (1'b1),  // Source
    .port_data_role  (1'b1),  // DFP
    .spec_revision   (2'b10), // PD 3.0
    .tx_msg_id       (msg_tx_id),
    .tx_msg_id_inc   (pol_msg_id_inc),
    .tx_msg_id_rst   (pol_msg_id_rst),
    // PHY TX
    .phy_tx_valid    (phy_tx_valid),
    .phy_tx_data     (phy_tx_data),
    .phy_tx_sop      (phy_tx_sop),
    .phy_tx_eop      (phy_tx_eop),
    .phy_tx_ready    (phy_tx_ready),
    // RX parser
    .rx_msg_valid    (raw_rx_valid),
    .rx_msg_type     (raw_rx_msg_type),
    .rx_num_do       (raw_rx_num_do),
    .rx_msg_id       (raw_rx_msg_id),
    .rx_port_power_role (raw_rx_ppr),
    .rx_spec_revision   (raw_rx_spec_rev),
    .rx_port_data_role  (raw_rx_pdr),
    .rx_extended     (raw_rx_ext),
    .rx_do0          (raw_rx_do0),
    .rx_do1          (raw_rx_do1),
    .rx_do2          (raw_rx_do2),
    .rx_do3          (raw_rx_do3),
    .rx_do4          (raw_rx_do4),
    .rx_do5          (raw_rx_do5),
    .rx_do6          (raw_rx_do6),
    .rx_error        (raw_rx_error),
    // PHY RX
    .phy_rx_data     (phy_rx_data),
    .phy_rx_valid    (phy_rx_valid),
    .phy_rx_sop      (phy_rx_sop),
    .phy_rx_eop      (phy_rx_eop),
    .phy_rx_crc_ok   (phy_rx_crc_ok)
);

goodcrc u_goodcrc (
    .clk             (clk),
    .rst_n           (rst_n),
    .rx_msg_valid    (raw_rx_valid),
    .rx_msg_type     (raw_rx_msg_type),
    .rx_msg_id       (raw_rx_msg_id),
    .rx_num_do       (raw_rx_num_do),
    .gc_tx_start     (gc_tx_start),
    .gc_tx_msg_type  (gc_tx_msg_type),
    .gc_tx_num_do    (gc_tx_num_do),
    .gc_tx_busy      (msg_tx_busy),
    .port_power_role (1'b1),
    .port_data_role  (1'b1),
    .filtered_rx_valid  (filtered_rx_valid),
    .filtered_rx_type   (filtered_rx_type),
    .filtered_rx_num_do (filtered_rx_num_do),
    .goodcrc_received   (goodcrc_received),
    .msg_id_rst      (pol_msg_id_rst),
    .rx_expected_id  (gc_rx_expected_id)
);

pd_policy u_pd_policy (
    .clk             (clk),
    .rst_n           (rst_n),
    .cc_attached     (cc_attached),
    .cc_attach_event (cc_attach_event),
    .cc_detach_event (cc_detach_event),
    .msg_tx_start    (pol_tx_start),
    .msg_tx_msg_type (pol_tx_msg_type),
    .msg_tx_num_do   (pol_tx_num_do),
    .msg_tx_extended (pol_tx_extended),
    .msg_tx_do0      (pol_tx_do0),
    .msg_tx_do1      (pol_tx_do1),
    .msg_tx_do2      (pol_tx_do2),
    .msg_tx_do3      (pol_tx_do3),
    .msg_tx_busy     (msg_tx_busy),
    .msg_tx_done     (msg_tx_done),
    .msg_id_inc      (pol_msg_id_inc),
    .msg_id_rst      (pol_msg_id_rst),
    .msg_rx_valid    (filtered_rx_valid),
    .msg_rx_msg_type (filtered_rx_type),
    .msg_rx_num_do   (filtered_rx_num_do),
    .msg_rx_do0      (raw_rx_do0),  // DO passed through directly
    .goodcrc_received(goodcrc_received),
    .pdo0            (pdo0_w),
    .pdo1            (pdo1_w),
    .pdo2            (pdo2_w),
    .pdo3            (pdo3_w),
    .num_pdos        (num_pdos),
    .vbus_en         (vbus_en),
    .vbus_voltage    (vbus_voltage),
    .vbus_current    (vbus_current),
    .vbus_stable     (vbus_stable),
    .pd_contract     (pol_pd_contract),
    .vbus_present    (pol_vbus_present),
    .protocol_id     (pol_protocol_id),
    .pd_timeout_flag (pol_pd_timeout),
    .int_out         (pol_int_out),
    .state_out       (pol_state_out)
);

i2c_slave #(.SLAVE_ADDR(7'h60)) u_i2c (
    .clk         (clk),
    .rst_n       (rst_n),
    .scl_in      (scl_in),
    .sda_in      (sda_in),
    .sda_oe      (sda_oe),
    .reg_addr    (i2c_reg_addr),
    .reg_wdata   (i2c_wdata),
    .reg_wstrobe (i2c_wstrobe),
    .reg_rdata   (i2c_rdata),
    .busy        (i2c_busy)
);

reg_file u_reg_file (
    .clk         (clk),
    .rst_n       (rst_n),
    .i2c_addr    (i2c_reg_addr),
    .i2c_wdata   (i2c_wdata),
    .i2c_wstrobe (i2c_wstrobe),
    .i2c_rdata   (i2c_rdata),
    .attached    (cc_attached),
    .orientation (cc_orientation),
    .pd_contract (pol_pd_contract),
    .vbus_present(pol_vbus_present),
    .protocol_id (pol_protocol_id),
    .status_1_hw (8'd0),  // TODO: connect fault logic
    .ctrl_0      (ctrl_0),
    .ctrl_1      (ctrl_1),
    .pdo1_volt   (pdo1_volt),
    .pdo1_curr   (pdo1_curr),
    .pdo2_volt   (pdo2_volt),
    .pdo2_curr   (pdo2_curr),
    .pdo3_volt   (pdo3_volt),
    .pdo3_curr   (pdo3_curr),
    .pdo4_volt   (pdo4_volt),
    .pdo4_curr   (pdo4_curr),
    .ovp_th      (ovp_th),
    .ocp_th      (ocp_th),
    .otp_th      (otp_th),
    .gpio_cfg    (gpio_cfg),
    .rp_level    (rp_level)
);

// =============================================================================
// Output Assignments
// =============================================================================
assign pd_contract = pol_pd_contract;
assign vbus_present = pol_vbus_present;
assign protocol_id = pol_protocol_id;
assign int_out = pol_int_out;

endmodule
