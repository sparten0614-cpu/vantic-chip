// =============================================================================
// VT3200 Buck PWM Generator
// =============================================================================
// Generates high-side (HG) and low-side (LG) gate drive signals with:
//   - 9-bit counter running at CLK_PWM (96MHz)
//   - Configurable switching frequency (500kHz/750kHz/1MHz)
//   - Sigma-delta dithering for sub-count duty cycle resolution
//   - Dead time insertion (10.4-52.1ns, counted in CLK_PWM cycles)
//   - Output gating (buck_enable, pll_lock, fault protection)
//
// Clocking:
//   clk_pwm = 96MHz (from PLL, 8x system clock)
//   Compensator updates at switching frequency via pwm_cycle_start
// =============================================================================

module buck_pwm (
    input  wire        clk_pwm,       // 96MHz PWM clock
    input  wire        rst_n,

    // Duty cycle from compensator (16-bit: [15:7]=integer 9-bit, [6:0]=fraction 7-bit)
    input  wire [15:0] duty_frac,

    // Configuration (from register file, synced to clk_pwm domain)
    input  wire [1:0]  freq_sel,      // 00=500kHz, 01=750kHz, 10=1MHz
    input  wire [2:0]  dead_time_cfg, // Dead time in CLK_PWM cycles (1-5)

    // Gating inputs
    input  wire        buck_enable,
    input  wire        pll_lock,
    input  wire        ocp_trip,      // Cycle-by-cycle over-current (kills HG only)
    input  wire        ovp_trip,      // Over-voltage (kills HG)
    input  wire        shutdown,      // Thermal or fault shutdown (kills both)
    input  wire        fault_latch,   // Latched fault (kills both)

    // Outputs
    output wire        hg_out,        // High-side gate drive (pre-pad-driver)
    output wire        lg_out,        // Low-side gate drive (pre-pad-driver)
    output wire        pwm_cycle_start, // Pulse at counter=0 (for ADC trigger + compensator update)

    // Debug
    output wire [8:0]  counter_out,
    output wire [8:0]  duty_eff_out
);

// =============================================================================
// Period Configuration
// =============================================================================
reg [8:0] period_max;
always @(*) begin
    case (freq_sel)
        2'b00:   period_max = 9'd191; // 96MHz/500kHz - 1
        2'b01:   period_max = 9'd127; // 96MHz/750kHz - 1
        2'b10:   period_max = 9'd95;  // 96MHz/1MHz - 1
        default: period_max = 9'd191;
    endcase
end

// =============================================================================
// PWM Counter (9-bit, up-count, edge-aligned)
// =============================================================================
reg [8:0] pwm_counter;

always @(posedge clk_pwm or negedge rst_n) begin
    if (!rst_n)
        pwm_counter <= 9'd0;
    else if (pwm_counter >= period_max)
        pwm_counter <= 9'd0;
    else
        pwm_counter <= pwm_counter + 9'd1;
end

assign pwm_cycle_start = (pwm_counter == 9'd0);
assign counter_out = pwm_counter;

// =============================================================================
// Sigma-Delta Dithering
// =============================================================================
// Fraction[6:0] is accumulated each switching cycle.
// Carry-out adds 1 to the integer duty cycle for that cycle.
reg [6:0] sd_accum;
reg       sd_carry;

always @(posedge clk_pwm or negedge rst_n) begin
    if (!rst_n) begin
        sd_accum <= 7'd0;
        sd_carry <= 1'b0;
    end else if (pwm_cycle_start) begin
        {sd_carry, sd_accum} <= {1'b0, sd_accum} + {1'b0, duty_frac[6:0]};
    end
end

// Effective duty cycle (integer + carry from sigma-delta)
wire [8:0] duty_effective = duty_frac[15:7] + {8'd0, sd_carry};
assign duty_eff_out = duty_effective;

// Raw PWM comparison
wire pwm_raw = (pwm_counter < duty_effective);

// =============================================================================
// Dead Time Insertion
// =============================================================================
// State machine in CLK_PWM domain (10.4ns resolution)
localparam [1:0] DT_IDLE = 2'b00,
                 DT_RISE = 2'b01,  // LG off, waiting to turn HG on
                 DT_FALL = 2'b10;  // HG off, waiting to turn LG on

reg [1:0] dt_state;
reg [2:0] dt_counter;
reg       hg_pre, lg_pre;
reg       pwm_raw_d; // Delayed for edge detection

always @(posedge clk_pwm or negedge rst_n) begin
    if (!rst_n) begin
        dt_state  <= DT_IDLE;
        dt_counter <= 3'd0;
        hg_pre    <= 1'b0;
        lg_pre    <= 1'b0;
        pwm_raw_d <= 1'b0;
    end else begin
        pwm_raw_d <= pwm_raw;

        // At each cycle start, resync dead time FSM to pwm_raw state.
        // Fixes high-duty case where off-time < dead_time: DT_FALL misses
        // the next rising edge because it's still counting down.
        if (pwm_cycle_start) begin
            if (pwm_raw && !hg_pre) begin
                // PWM is high but HG not on — force DT_RISE
                lg_pre     <= 1'b0;
                dt_counter <= dead_time_cfg;
                dt_state   <= DT_RISE;
            end
        end else

        case (dt_state)
        DT_IDLE: begin
            if (pwm_raw && !pwm_raw_d) begin
                // Rising edge: turn off LG, start dead time before HG on
                lg_pre     <= 1'b0;
                dt_counter <= dead_time_cfg;
                dt_state   <= DT_RISE;
            end else if (!pwm_raw && pwm_raw_d) begin
                // Falling edge: turn off HG, start dead time before LG on
                hg_pre     <= 1'b0;
                dt_counter <= dead_time_cfg;
                dt_state   <= DT_FALL;
            end
        end

        DT_RISE: begin
            if (dt_counter == 3'd0) begin
                hg_pre   <= 1'b1;
                dt_state <= DT_IDLE;
            end else begin
                dt_counter <= dt_counter - 3'd1;
            end
        end

        DT_FALL: begin
            if (dt_counter == 3'd0) begin
                lg_pre   <= 1'b1;
                dt_state <= DT_IDLE;
            end else begin
                dt_counter <= dt_counter - 3'd1;
            end
        end

        default: dt_state <= DT_IDLE;
        endcase
    end
end

// =============================================================================
// Output Gating
// =============================================================================
// HG gated by all protection signals
assign hg_out = hg_pre & buck_enable & pll_lock & ~ocp_trip & ~ovp_trip
                & ~shutdown & ~fault_latch;

// LG gated by enable/fault but NOT by OCP (LG stays on for freewheeling during OCP)
assign lg_out = lg_pre & buck_enable & pll_lock & ~shutdown & ~fault_latch;

endmodule
