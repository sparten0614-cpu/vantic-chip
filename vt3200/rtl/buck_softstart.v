// =============================================================================
// VT3200 Buck Soft-Start — Linear Reference Ramp Generator
// =============================================================================
// Ramps the internal voltage target from 0 to final_target over configurable time.
// Prevents inrush current at startup by gradually increasing the reference.
//
// Operation:
//   - ss_start pulse → begin ramping from 0
//   - Each switching cycle: ramped_target += ss_step (fractional)
//   - When ramped_target >= final_target → hold at final_target, assert ss_done
//   - ss_abort → immediately stop and reset
//
// Fractional accumulator: 11 integer + 16 fractional bits (27-bit total)
// ss_step is 16-bit fractional: controls ramp speed
//   - ss_step = 1.0 (0x10000) → 1 target unit per cycle → fast
//   - ss_step = 0.1 (0x1999)  → 10x slower
// =============================================================================

module buck_softstart (
    input  wire        clk_sys,
    input  wire        rst_n,

    // Control
    input  wire        ss_start,       // Pulse: begin soft-start
    input  wire        ss_abort,       // Pulse: abort and reset
    input  wire        comp_update,    // Switching cycle pulse (for ramp stepping)

    // Configuration
    input  wire [10:0] final_target,   // Target voltage (10mV units, 0-2047)
    input  wire [15:0] ss_step,        // Ramp step per switching cycle (Q0.16 fractional)

    // Output
    output wire [10:0] ramped_target,  // Current ramped target (to compensator)
    output wire        ss_done,        // 1 = soft-start complete
    output wire        ss_active       // 1 = currently ramping
);

// =============================================================================
// Fractional Accumulator (11 integer + 16 fractional = 27 bits)
// =============================================================================
reg [26:0] ss_accum;
reg        active;

always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) begin
        ss_accum <= 27'd0;
        active   <= 1'b0;
    end else if (ss_abort) begin
        ss_accum <= 27'd0;
        active   <= 1'b0;
    end else if (ss_start) begin
        ss_accum <= 27'd0;
        active   <= 1'b1;
    end else if (active && comp_update) begin
        if (ss_accum[26:16] >= final_target) begin
            // Reached target — clamp and stop
            ss_accum <= {final_target, 16'd0};
            active   <= 1'b0;
        end else begin
            ss_accum <= ss_accum + {11'd0, ss_step};
        end
    end
end

// =============================================================================
// Outputs
// =============================================================================
assign ramped_target = active ? ss_accum[26:16] : final_target;
assign ss_done   = ~active;
assign ss_active = active;

endmodule
