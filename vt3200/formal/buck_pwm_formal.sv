// =============================================================================
// Formal Verification Properties for buck_pwm
// =============================================================================
// Safety properties verified with SymbiYosys + Z3
// =============================================================================

module buck_pwm_formal (
    input  wire        clk_pwm,
    input  wire        rst_n,
    input  wire [15:0] duty_frac,
    input  wire [1:0]  freq_sel,
    input  wire [2:0]  dead_time_cfg,
    input  wire        buck_enable,
    input  wire        pll_lock,
    input  wire        ocp_trip,
    input  wire        ovp_trip,
    input  wire        shutdown,
    input  wire        fault_latch
);

    // Instantiate DUT
    wire hg_out, lg_out, pwm_cycle_start;
    wire [8:0] counter_out, duty_eff_out;

    buck_pwm dut (
        .clk_pwm(clk_pwm), .rst_n(rst_n),
        .duty_frac(duty_frac), .freq_sel(freq_sel),
        .dead_time_cfg(dead_time_cfg),
        .buck_enable(buck_enable), .pll_lock(pll_lock),
        .ocp_trip(ocp_trip), .ovp_trip(ovp_trip),
        .shutdown(shutdown), .fault_latch(fault_latch),
        .hg_out(hg_out), .lg_out(lg_out),
        .pwm_cycle_start(pwm_cycle_start),
        .counter_out(counter_out), .duty_eff_out(duty_eff_out)
    );

    // =========================================================================
    // Assumptions: proper reset sequence
    // =========================================================================
    reg f_past_valid;
    initial f_past_valid = 0;
    always @(posedge clk_pwm) f_past_valid <= 1;

    // Assume reset is held for at least 1 cycle at start
    initial assume(!rst_n);
    always @(posedge clk_pwm)
        if (!f_past_valid) assume(!rst_n);

    // Assume freq_sel and dead_time_cfg are stable (register-configured, not dynamic)
    always @(posedge clk_pwm) begin
        if (f_past_valid && rst_n) begin
            assume($stable(freq_sel));
            assume($stable(dead_time_cfg));
            assume(dead_time_cfg <= 3'd5); // Valid range 1-5
            assume(freq_sel <= 2'b10);     // Valid range 0-2
        end
    end

    // =========================================================================
    // SAFETY PROPERTY 1: HG and LG must NEVER be simultaneously high
    // This prevents shoot-through (direct VIN-to-GND short)
    // =========================================================================
    always @(posedge clk_pwm) begin
        if (rst_n) begin
            assert(!(hg_out && lg_out));
        end
    end

    // =========================================================================
    // SAFETY PROPERTY 2: When shutdown=1, both outputs must be 0
    // =========================================================================
    always @(posedge clk_pwm) begin
        if (rst_n && shutdown) begin
            assert(hg_out == 0);
            assert(lg_out == 0);
        end
    end

    // =========================================================================
    // SAFETY PROPERTY 3: When buck_enable=0, both outputs must be 0
    // =========================================================================
    always @(posedge clk_pwm) begin
        if (rst_n && !buck_enable) begin
            assert(hg_out == 0);
            assert(lg_out == 0);
        end
    end

    // =========================================================================
    // SAFETY PROPERTY 4: When pll_lock=0, both outputs must be 0
    // =========================================================================
    always @(posedge clk_pwm) begin
        if (rst_n && !pll_lock) begin
            assert(hg_out == 0);
            assert(lg_out == 0);
        end
    end

    // =========================================================================
    // SAFETY PROPERTY 5: When fault_latch=1, both outputs must be 0
    // =========================================================================
    always @(posedge clk_pwm) begin
        if (rst_n && fault_latch) begin
            assert(hg_out == 0);
            assert(lg_out == 0);
        end
    end

    // =========================================================================
    // SAFETY PROPERTY 6: OCP kills HG but NOT LG (freewheeling allowed)
    // =========================================================================
    always @(posedge clk_pwm) begin
        if (rst_n && ocp_trip && buck_enable && pll_lock && !shutdown && !fault_latch) begin
            assert(hg_out == 0);
            // LG may or may not be on (freewheeling) — no assert on LG
        end
    end

    // =========================================================================
    // SAFETY PROPERTY 7: Counter stays within valid range
    // =========================================================================
    reg [8:0] period_max_check;
    always @(*) begin
        case (freq_sel)
            2'b00: period_max_check = 9'd191;
            2'b01: period_max_check = 9'd127;
            2'b10: period_max_check = 9'd95;
            default: period_max_check = 9'd191;
        endcase
    end

    always @(posedge clk_pwm) begin
        if (rst_n) begin
            assert(counter_out <= period_max_check);
        end
    end

endmodule
