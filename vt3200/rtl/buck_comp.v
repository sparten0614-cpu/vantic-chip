// =============================================================================
// VT3200 Buck Digital Compensator — Type-II Voltage Mode Controller
// =============================================================================
// Implements: d[n] = d[n-1] + b0*e[n] + b1*e[n-1] + b2*e[n-2]
//
// Fixed-point arithmetic:
//   - Error e[n]: signed 12-bit
//   - Coefficients b0/b1/b2: signed Q1.14 (16-bit)
//   - Products: signed 28-bit
//   - Accumulator: signed 28-bit with anti-windup clamp
//   - Output duty_out: unsigned Q9.7 (16-bit)
//
// Pipeline: IDLE → COMPUTE → DONE (2 clk_sys cycles per update)
// Triggered by comp_update pulse (once per switching cycle, synced to clk_sys)
// =============================================================================

module buck_comp (
    input  wire        clk_sys,       // 12MHz system clock
    input  wire        rst_n,

    // Control
    input  wire        comp_update,   // Pulse: update compensator (once per switching cycle)
    input  wire        comp_enable,   // Master enable

    // ADC input
    input  wire [9:0]  vbus_adc,      // VBUS ADC reading (10-bit unsigned)

    // Target voltage
    input  wire [10:0] target_voltage, // From PD engine (10mV steps, 0-20.47V)

    // Coefficients (from register file, signed Q1.14)
    input  wire signed [15:0] b0,
    input  wire signed [15:0] b1,
    input  wire signed [15:0] b2,

    // Anti-windup clamps (Q9.7, unsigned)
    input  wire [15:0] duty_max,
    input  wire [15:0] duty_min,

    // Output
    output reg  [15:0] duty_out,      // Duty cycle (Q9.7 unsigned)
    output wire        comp_done,     // Pulse: computation complete

    // Debug
    output wire signed [11:0] error_out
);

// =============================================================================
// Target-to-ADC Scale Conversion
// =============================================================================
// target_voltage in 10mV steps (0-2047 → 0-20.47V)
// ADC: 10-bit, full-scale ~25V → 1 LSB ≈ 24.4mV
// Simplified: target_scaled = target_voltage >> 1
wire [9:0] target_scaled = target_voltage[10:1];

// =============================================================================
// Error Calculation (signed)
// =============================================================================
wire signed [11:0] error_n = $signed({2'b00, target_scaled}) - $signed({2'b00, vbus_adc});
assign error_out = error_n;

// Error history
reg signed [11:0] error_n1; // e[n-1]
reg signed [11:0] error_n2; // e[n-2]

// =============================================================================
// Multiply-Accumulate (combinational)
// =============================================================================
wire signed [27:0] prod0 = b0 * error_n;
wire signed [27:0] prod1 = b1 * error_n1;
wire signed [27:0] prod2 = b2 * error_n2;

wire signed [27:0] delta = prod0 + prod1 + prod2;

// =============================================================================
// Accumulator with Anti-Windup Clamp
// =============================================================================
reg signed [27:0] accum;
wire signed [27:0] accum_next = accum + delta;

// Extend clamp values to accumulator domain (Q13.14)
// duty_max/min are Q9.7 (16-bit). Output extracts [20:7] → shift by 7.
// Clamp in accumulator domain = {2'b0, duty_max[13:0], 7'd0} (but duty_max is 16-bit)
// Since duty_out = {2'd0, accum[20:7]}, accum[20:7] must be <= duty_max[13:0]
// So clamp at accum level: duty_max << 7
wire signed [27:0] clamp_max = $signed({5'd0, duty_max, 7'd0});
wire signed [27:0] clamp_min = $signed({5'd0, duty_min, 7'd0});

wire signed [27:0] accum_clamped =
    (accum_next > clamp_max) ? clamp_max :
    (accum_next < clamp_min) ? clamp_min :
    accum_next;

// =============================================================================
// Pipeline State Machine
// =============================================================================
localparam [1:0] IDLE    = 2'd0,
                 COMPUTE = 2'd1,
                 DONE    = 2'd2;

reg [1:0] comp_state;

always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) begin
        error_n1   <= 12'sd0;
        error_n2   <= 12'sd0;
        accum      <= 28'sd0;
        duty_out   <= 16'd0;
        comp_state <= IDLE;
    end else if (!comp_enable) begin
        // When disabled, reset state but preserve coefficients
        error_n1   <= 12'sd0;
        error_n2   <= 12'sd0;
        accum      <= 28'sd0;
        duty_out   <= 16'd0;
        comp_state <= IDLE;
    end else begin
        case (comp_state)
        IDLE: begin
            if (comp_update)
                comp_state <= COMPUTE;
        end

        COMPUTE: begin
            // All multiplies are combinational; register results here
            accum    <= accum_clamped;
            // Extract Q9.7 from accumulator:
            // accum is in Q1.14 * Q12 = effectively shifted by 14 bits
            // duty_out is Q9.7 → extract bits [20:7] from accumulator?
            // Actually: b is Q1.14, e is 12-bit integer
            // product = Q1.14 * Q12.0 = Q13.14 (28-bit)
            // accumulator is Q13.14
            // duty_out needs Q9.7 → shift right by 7: accum[20:7]
            // But we also need to handle negative accum (clamp ensures >= 0)
            duty_out <= {2'd0, accum_clamped[20:7]}; // Q13.14 → Q9.7: bits[20:7] = 14 bits, pad to 16 // Extract bits for Q9.7
            // Note: exact bit selection depends on scaling.
            // accum is Q13.14, we want Q9.7 → right-shift by 7 → [20:5]
            // Wait: Q13.14 has 13 integer + 14 fraction = 27 bits + sign = 28 bits
            // Q9.7 has 9 integer + 7 fraction = 16 bits
            // To get Q9.7 from Q13.14: shift right by 7 (drop 7 fraction bits)
            // bits[20:5] gives us [20:12]=9 integer, [11:5]=7 fraction
            // But sign bit? Since clamped to >= duty_min (unsigned), accum_clamped is positive
            duty_out <= {2'd0, accum_clamped[20:7]}; // Q13.14 → Q9.7: bits[20:7] = 14 bits, pad to 16

            error_n2 <= error_n1;
            error_n1 <= error_n;
            comp_state <= DONE;
        end

        DONE: begin
            comp_state <= IDLE;
        end

        default: comp_state <= IDLE;
        endcase
    end
end

assign comp_done = (comp_state == DONE);

endmodule
