// =============================================================================
// VT3200 Top-Level — USB PD Controller + Integrated Buck Converter
// =============================================================================
// Integrates VT3100 protocol core + Buck digital controller on single die.
//
// Clock domains:
//   clk_sys (12MHz) — protocol logic, compensator, ADC, registers
//   clk_pwm (96MHz) — PWM counter, dead time insertion
//   CDC: cycle_start pulse from clk_pwm → clk_sys via 2-stage synchronizer
// =============================================================================

module vt3200_top (
    input  wire        clk_sys,        // 12MHz system clock
    input  wire        clk_pwm,        // 96MHz PWM clock (from PLL)
    input  wire        rst_n,
    input  wire        pll_lock,       // PLL locked indicator

    // === CC Pins (analog interface) ===
    input  wire [2:0]  cc1_comp,
    input  wire [2:0]  cc2_comp,
    output wire [1:0]  rp_cc1_level,
    output wire [1:0]  rp_cc2_level,

    // === BMC PHY ===
    input  wire        cc_rx_in,
    output wire        cc_tx_out,
    output wire        cc_sel,

    // === I2C ===
    input  wire        scl_in,
    input  wire        sda_in,
    output wire        sda_oe,

    // === Buck Power Stage ===
    output wire        hg_out,         // High-side gate drive
    output wire        lg_out,         // Low-side gate drive
    input  wire        ocp_comp,       // OCP comparator from analog

    // === ADC Hardware Interface ===
    output wire [1:0]  adc_ch_sel,
    output wire        adc_start,
    input  wire        adc_busy,
    input  wire [9:0]  adc_data,
    input  wire        adc_valid,

    // === Status ===
    output wire        pgood,          // Power good (open-drain driver)
    output wire        pd_contract,
    output wire [3:0]  protocol_id,
    output wire        int_out
);

// =============================================================================
// CDC: cycle_start from clk_pwm → clk_sys
// =============================================================================
wire pwm_cycle_start_raw; // In clk_pwm domain

reg cs_sync1, cs_sync2, cs_sync3;
always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) begin
        cs_sync1 <= 0; cs_sync2 <= 0; cs_sync3 <= 0;
    end else begin
        cs_sync1 <= pwm_cycle_start_raw;
        cs_sync2 <= cs_sync1;
        cs_sync3 <= cs_sync2;
    end
end
wire cycle_start_sys = cs_sync2 & ~cs_sync3; // Rising edge in clk_sys domain

// =============================================================================
// VT3100 Protocol Core Interface Signals
// =============================================================================
wire        vt_vbus_en;
wire [7:0]  vt_vbus_voltage;
wire [9:0]  vt_vbus_current;
wire        vt_pd_contract;
wire        vt_vbus_present;
wire [3:0]  vt_protocol_id;
wire        vt_int_out;

// =============================================================================
// ADC Results
// =============================================================================
wire [9:0] adc_vbus, adc_isns, adc_vin, adc_temp;
wire       comp_update_pulse;

// =============================================================================
// Soft-Start
// =============================================================================
wire [10:0] ramped_target;
wire        ss_done, ss_active;

// Convert vt_vbus_voltage (8-bit, 100mV units) to 11-bit target (10mV units)
wire [10:0] final_target = {vt_vbus_voltage, 3'd0} + {2'd0, vt_vbus_voltage, 1'd0};
// 100mV * 10 = 10mV units: val * 8 + val * 2 = val * 10

// =============================================================================
// Compensator
// =============================================================================
wire [15:0] duty_out;
wire        comp_done;

// Default coefficients (from spec Section 5.7)
// TODO: wire to extended register file
wire signed [15:0] coeff_b0 = 16'h1EE0; // +0.4823 Q1.14
wire signed [15:0] coeff_b1 = 16'hC72C; // -0.8917 Q1.14
wire signed [15:0] coeff_b2 = 16'h1A50; // +0.4105 Q1.14

// =============================================================================
// Protection
// =============================================================================
wire       ocp_trip, ovp_active, prot_shutdown, fault_latch;
wire [3:0] fault_code;
wire       buck_pgood;

// =============================================================================
// PWM Configuration (defaults, TODO: wire to registers)
// =============================================================================
wire [1:0] freq_sel = 2'b00;      // 500kHz
wire [2:0] dead_time_cfg = 3'd3;  // 31.3ns

// =============================================================================
// Module Instances
// =============================================================================

// --- VT3100 Protocol Core ---
vt3100_top u_protocol (
    .clk          (clk_sys),
    .rst_n        (rst_n),
    .cc1_comp     (cc1_comp),
    .cc2_comp     (cc2_comp),
    .rp_cc1_level (rp_cc1_level),
    .rp_cc2_level (rp_cc2_level),
    .cc_rx_in     (cc_rx_in),
    .cc_tx_out    (cc_tx_out),
    .cc_sel       (cc_sel),
    .scl_in       (scl_in),
    .sda_in       (sda_in),
    .sda_oe       (sda_oe),
    .vbus_en      (vt_vbus_en),
    .vbus_voltage (vt_vbus_voltage),
    .vbus_current (vt_vbus_current),
    .vbus_stable  (buck_pgood),     // Buck PGOOD → VT3100 vbus_stable (triggers PS_RDY)
    .pd_contract  (vt_pd_contract),
    .vbus_present (vt_vbus_present),
    .protocol_id  (vt_protocol_id),
    .int_out      (vt_int_out)
);

// --- ADC Interface ---
buck_adc u_adc (
    .clk_sys      (clk_sys),
    .rst_n        (rst_n),
    .cycle_start  (cycle_start_sys),
    .adc_ch_sel   (adc_ch_sel),
    .adc_start    (adc_start),
    .adc_busy     (adc_busy),
    .adc_data     (adc_data),
    .adc_valid    (adc_valid),
    .vin_divider  (8'd50),
    .temp_divider (8'd250),
    .vbus_result  (adc_vbus),
    .isns_result  (adc_isns),
    .vin_result   (adc_vin),
    .temp_result  (adc_temp),
    .comp_update  (comp_update_pulse)
);

// --- Soft-Start ---
// Detect vbus_en rising edge for ss_start pulse
reg vbus_en_d;
always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) vbus_en_d <= 1'b0;
    else        vbus_en_d <= vt_vbus_en;
end
wire vbus_en_rise = vt_vbus_en & ~vbus_en_d;

buck_softstart u_softstart (
    .clk_sys       (clk_sys),
    .rst_n         (rst_n),
    .ss_start      (vbus_en_rise),           // Rising edge of vbus_en
    .ss_abort      (~vt_vbus_en),            // Abort on disable
    .comp_update   (comp_update_pulse),
    .final_target  (final_target),
    .ss_step       (16'h0333),               // ~5ms ramp at 500kHz (default)
    .ramped_target (ramped_target),
    .ss_done       (ss_done),
    .ss_active     (ss_active)
);

// --- Digital Compensator ---
buck_comp u_comp (
    .clk_sys        (clk_sys),
    .rst_n          (rst_n),
    .comp_update    (comp_update_pulse),
    .comp_enable    (vt_vbus_en & ~prot_shutdown),
    .vbus_adc       (adc_vbus),
    .target_voltage (ramped_target),
    .b0             (coeff_b0),
    .b1             (coeff_b1),
    .b2             (coeff_b2),
    .duty_max       (16'hBF80),  // 95% at 192 counts
    .duty_min       (16'h0280),  // 2.5%
    .duty_out       (duty_out),
    .comp_done      (comp_done),
    .error_out      ()
);

// --- PWM Generator ---
buck_pwm u_pwm (
    .clk_pwm         (clk_pwm),
    .rst_n            (rst_n),
    .duty_frac        (duty_out),
    .freq_sel         (freq_sel),
    .dead_time_cfg    (dead_time_cfg),
    .buck_enable      (vt_vbus_en),
    .pll_lock         (pll_lock),
    .ocp_trip         (ocp_trip),
    .ovp_trip         (ovp_active),
    .shutdown         (prot_shutdown),
    .fault_latch      (fault_latch),
    .hg_out           (hg_out),
    .lg_out           (lg_out),
    .pwm_cycle_start  (pwm_cycle_start_raw),
    .counter_out      (),
    .duty_eff_out     ()
);

// --- Protection Logic ---
buck_prot u_prot (
    .clk_sys        (clk_sys),
    .rst_n          (rst_n),
    .cycle_start    (cycle_start_sys),
    .ocp_comp       (ocp_comp),
    .vbus_adc       (adc_vbus),
    .vin_adc        (adc_vin),
    .temp_adc       (adc_temp),
    .target_voltage (ramped_target),
    .ovp_margin     (8'd25),       // 250mV
    .uvlo_rise      (10'd185),     // ~4.5V
    .uvlo_fall      (10'd164),     // ~4.0V
    .otp_threshold  (10'd614),     // ~150°C
    .otp_recovery   (10'd532),     // ~130°C
    .ocp_count_cfg  (4'd5),
    .ocp_window_cfg (8'd20),
    .buck_enable    (vt_vbus_en),
    .fault_clear    (1'b0),        // TODO: wire to register
    .ocp_trip       (ocp_trip),
    .ovp_active     (ovp_active),
    .shutdown       (prot_shutdown),
    .fault_latch    (fault_latch),
    .fault_code     (fault_code),
    .pgood          (buck_pgood)
);

// =============================================================================
// Output Assignments
// =============================================================================
assign pgood       = buck_pgood;
assign pd_contract = vt_pd_contract;
assign protocol_id = vt_protocol_id;
assign int_out     = vt_int_out;

endmodule
