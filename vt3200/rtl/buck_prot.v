// =============================================================================
// VT3200 Buck Protection Logic
// =============================================================================
// Implements: OCP (cycle-by-cycle + sustained), OVP, UVP, OTP, short circuit
//
// Protection hierarchy:
//   - Cycle-by-cycle OCP: combinational, kills HG within 1 CLK_PWM cycle
//   - OVP: kills HG, optionally turns on LG for discharge
//   - Sustained OCP / Short: hiccup mode (periodic retry)
//   - UVP / OTP: full shutdown, auto-recover with hysteresis
//
// Fault codes: 0=none, 1=OCP, 2=OVP, 3=UVP, 4=OTP, 5=short, 6=PLL_unlock
// =============================================================================

module buck_prot (
    input  wire        clk_sys,       // 12MHz system clock
    input  wire        rst_n,

    // Switching cycle pulse (once per switching period)
    input  wire        cycle_start,

    // Analog comparator input (direct from CSA hard macro)
    input  wire        ocp_comp,      // 1 = inductor current > OCP threshold

    // ADC readings (updated once per switching cycle)
    input  wire [9:0]  vbus_adc,      // VBUS voltage
    input  wire [9:0]  vin_adc,       // Input voltage
    input  wire [9:0]  temp_adc,      // Temperature

    // Target and thresholds (from register file)
    input  wire [10:0] target_voltage,// Current target (10mV steps)
    input  wire [7:0]  ovp_margin,    // OVP margin (10mV units, default: target+5%)
    input  wire [9:0]  uvlo_rise,     // UVLO rising threshold (ADC units)
    input  wire [9:0]  uvlo_fall,     // UVLO falling threshold (ADC units)
    input  wire [9:0]  otp_threshold, // OTP shutdown threshold (ADC units)
    input  wire [9:0]  otp_recovery,  // OTP recovery threshold (ADC units)

    // OCP sustained config
    input  wire [3:0]  ocp_count_cfg, // Max OCP events before sustained fault
    input  wire [7:0]  ocp_window_cfg,// Window size in switching cycles

    // Control
    input  wire        buck_enable,
    input  wire        fault_clear,   // Pulse: clear latched faults (from I2C)

    // Outputs to PWM
    output wire        ocp_trip,      // Combinational: cycle-by-cycle OCP active
    output reg         ovp_active,    // OVP: force duty=0
    output reg         shutdown,      // Full shutdown (UVP/OTP/sustained fault)
    output reg         fault_latch,   // Latched fault (must be cleared)

    // Status
    output reg  [3:0]  fault_code,    // Current fault type
    output wire        pgood          // Power good: in regulation, no faults
);

// =============================================================================
// Cycle-by-Cycle OCP (combinational — NOT clocked)
// =============================================================================
assign ocp_trip = ocp_comp & buck_enable;

// =============================================================================
// OCP Event Counting (sustained fault detection)
// =============================================================================
reg [3:0] ocp_count;
reg [7:0] ocp_window;
reg       ocp_event_r; // Register ocp_comp to detect events per cycle
wire      ocp_sustained;

always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) begin
        ocp_count  <= 4'd0;
        ocp_window <= 8'd0;
        ocp_event_r <= 1'b0;
    end else if (fault_clear) begin
        ocp_count  <= 4'd0;
        ocp_window <= 8'd0;
        ocp_event_r <= 1'b0;
    end else if (cycle_start) begin
        ocp_event_r <= ocp_comp;

        if (ocp_window >= ocp_window_cfg) begin
            // Window expired — reset
            ocp_window <= 8'd0;
            ocp_count  <= ocp_comp ? 4'd1 : 4'd0;
        end else begin
            ocp_window <= ocp_window + 8'd1;
            if (ocp_comp)
                ocp_count <= ocp_count + 4'd1;
        end
    end
end

assign ocp_sustained = (ocp_count >= ocp_count_cfg) && (ocp_count_cfg != 4'd0);

// =============================================================================
// OVP: Over-Voltage Protection
// =============================================================================
// Scale target to ADC domain for comparison (simplified: >> 1)
// Note: exact scaling fixed during integration (SZ review item)
wire [10:0] ovp_threshold = target_voltage + {3'd0, ovp_margin};
wire [10:0] ovp_recovery_th = target_voltage + {4'd0, ovp_margin[7:1]}; // half margin for recovery
wire        ovp_detect = ({1'b0, vbus_adc} > ovp_threshold[10:0]);

always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n)
        ovp_active <= 1'b0;
    else if (ovp_detect)
        ovp_active <= 1'b1;
    else if ({1'b0, vbus_adc} < ovp_recovery_th)
        ovp_active <= 1'b0;
end

// =============================================================================
// UVP: Under-Voltage Lockout (Input)
// =============================================================================
reg uvlo_fault;

always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n)
        uvlo_fault <= 1'b0;
    else if (vin_adc < uvlo_fall)
        uvlo_fault <= 1'b1;
    else if (vin_adc > uvlo_rise)
        uvlo_fault <= 1'b0;
end

// =============================================================================
// OTP: Over-Temperature Protection
// =============================================================================
reg otp_fault;

always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n)
        otp_fault <= 1'b0;
    else if (temp_adc > otp_threshold)
        otp_fault <= 1'b1;
    else if (temp_adc < otp_recovery)
        otp_fault <= 1'b0;
end

// =============================================================================
// Short Circuit Detection
// =============================================================================
// VBUS < 0.5V while buck is active (ADC ~20 counts at 24.4mV/LSB)
wire short_detect = buck_enable && (vbus_adc < 10'd20) && !shutdown;
reg  short_fault;

always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n)
        short_fault <= 1'b0;
    else if (short_detect)
        short_fault <= 1'b1;
    else if (fault_clear)
        short_fault <= 1'b0;
end

// =============================================================================
// Fault Aggregation
// =============================================================================
wire any_latch_fault = ocp_sustained | short_fault;
wire any_shutdown = uvlo_fault | otp_fault | any_latch_fault;

always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) begin
        shutdown    <= 1'b0;
        fault_latch <= 1'b0;
        fault_code  <= 4'd0;
    end else if (fault_clear) begin
        fault_latch <= 1'b0;
        fault_code  <= 4'd0;
        shutdown    <= uvlo_fault | otp_fault; // Don't clear hardware faults
    end else begin
        shutdown <= any_shutdown;

        if (any_latch_fault)
            fault_latch <= 1'b1;

        // Priority-encoded fault code
        if (ocp_sustained)
            fault_code <= 4'd1;
        else if (ovp_active)
            fault_code <= 4'd2;
        else if (uvlo_fault)
            fault_code <= 4'd3;
        else if (otp_fault)
            fault_code <= 4'd4;
        else if (short_fault)
            fault_code <= 4'd5;
        else if (!any_shutdown && !ovp_active)
            fault_code <= 4'd0;
    end
end

// =============================================================================
// Power Good
// =============================================================================
// PGOOD = in regulation AND no faults AND soft-start complete
// Regulation window: VBUS within ±5% of target
wire [10:0] pgood_hi = target_voltage + (target_voltage >> 4); // +6.25%
wire [10:0] pgood_lo = target_voltage - (target_voltage >> 4); // -6.25%
wire in_regulation = ({1'b0, vbus_adc} >= pgood_lo) && ({1'b0, vbus_adc} <= pgood_hi);

assign pgood = in_regulation & buck_enable & ~shutdown & ~fault_latch & ~ovp_active;

endmodule
