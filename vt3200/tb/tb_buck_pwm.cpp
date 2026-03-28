// =============================================================================
// VT3200 Buck PWM Generator — Verilator Testbench
// =============================================================================

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include "Vbuck_pwm.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

static vluint64_t sim_time = 0;
static Vbuck_pwm *dut;
static VerilatedVcdC *trace;

double sc_time_stamp() { return (double)sim_time; }

static void tick() {
    dut->clk_pwm = 0; dut->eval();
    if (trace) trace->dump(sim_time++);
    dut->clk_pwm = 1; dut->eval();
    if (trace) trace->dump(sim_time++);
}

static void ticks(int n) { for (int i = 0; i < n; i++) tick(); }

static void reset() {
    dut->rst_n = 0;
    dut->duty_frac = 0;
    dut->freq_sel = 0;        // 500kHz
    dut->dead_time_cfg = 3;   // 3 cycles = 31.3ns
    dut->buck_enable = 0;
    dut->pll_lock = 1;
    dut->ocp_trip = 0;
    dut->ovp_trip = 0;
    dut->shutdown = 0;
    dut->fault_latch = 0;
    ticks(10);
    dut->rst_n = 1;
    ticks(5);
}

static int test_count = 0;
static int pass_count = 0;

static void check(const char *name, bool cond) {
    test_count++;
    if (cond) { pass_count++; printf("  PASS: %s\n", name); }
    else { printf("  FAIL: %s\n", name); }
}

// =============================================================================
// Test 1: Counter period at 500kHz (period_max=191, 192 counts)
// =============================================================================
static void test_counter_period() {
    printf("=== Test 1: Counter period ===\n");
    reset();
    dut->buck_enable = 1;
    dut->freq_sel = 0b00; // 500kHz

    // Wait for cycle_start
    int cycles_to_start = 0;
    for (int i = 0; i < 300; i++) {
        tick();
        if (dut->pwm_cycle_start) { cycles_to_start = i; break; }
    }

    // Count ticks until next cycle_start
    int period = 0;
    for (int i = 0; i < 300; i++) {
        tick();
        period++;
        if (dut->pwm_cycle_start) break;
    }
    printf("  Period: %d CLK_PWM cycles\n", period);
    check("period = 192 at 500kHz", period == 192);

    // Test 750kHz
    dut->freq_sel = 0b01;
    ticks(200); // Let it settle
    // Find next start
    for (int i = 0; i < 200; i++) { tick(); if (dut->pwm_cycle_start) break; }
    period = 0;
    for (int i = 0; i < 200; i++) { tick(); period++; if (dut->pwm_cycle_start) break; }
    printf("  Period: %d CLK_PWM cycles at 750kHz\n", period);
    check("period = 128 at 750kHz", period == 128);

    // Test 1MHz
    dut->freq_sel = 0b10;
    ticks(200);
    for (int i = 0; i < 200; i++) { tick(); if (dut->pwm_cycle_start) break; }
    period = 0;
    for (int i = 0; i < 200; i++) { tick(); period++; if (dut->pwm_cycle_start) break; }
    printf("  Period: %d CLK_PWM cycles at 1MHz\n", period);
    check("period = 96 at 1MHz", period == 96);
}

// =============================================================================
// Test 2: Duty cycle — 50% at 500kHz
// =============================================================================
static void test_duty_50pct() {
    printf("=== Test 2: 50%% duty cycle ===\n");
    reset();
    dut->buck_enable = 1;
    dut->freq_sel = 0b00; // 500kHz, period=192

    // 50% = 96 counts integer, 0 fraction
    dut->duty_frac = (96 << 7) | 0;

    // Wait for cycle start
    for (int i = 0; i < 250; i++) { tick(); if (dut->pwm_cycle_start) break; }

    // Count HG high time over one period
    int hg_high = 0;
    for (int i = 0; i < 192; i++) {
        tick();
        if (dut->hg_out) hg_high++;
    }
    printf("  HG high: %d / 192 cycles\n", hg_high);
    // Account for dead time: HG turns on after dead_time_cfg+1 cycles delay
    // and turns off dead_time_cfg+1 cycles early. Expect ~96 - 2*(3+1) = ~88
    // Actually dead time doesn't shrink the high pulse — it shifts it.
    // The raw PWM is 96 cycles high. Dead time delays HG on by ~4 cycles
    // and delays LG on by ~4 cycles after HG off. HG still sees ~96-4 = ~92 cycles.
    check("HG ~50%% (within 88-96)", hg_high >= 88 && hg_high <= 96);
}

// =============================================================================
// Test 3: Dead time — HG and LG never overlap
// =============================================================================
static void test_dead_time() {
    printf("=== Test 3: Dead time (no overlap) ===\n");
    reset();
    dut->buck_enable = 1;
    dut->freq_sel = 0b00;
    dut->duty_frac = (96 << 7); // 50%

    int overlap = 0;
    for (int i = 0; i < 500; i++) {
        tick();
        if (dut->hg_out && dut->lg_out) overlap++;
    }
    check("no HG+LG overlap", overlap == 0);
}

// =============================================================================
// Test 4: Output gating — buck_enable
// =============================================================================
static void test_gating_enable() {
    printf("=== Test 4: Output gating (buck_enable) ===\n");
    reset();
    dut->buck_enable = 0;
    dut->duty_frac = (96 << 7);
    ticks(300);

    check("HG=0 when disabled", dut->hg_out == 0);
    check("LG=0 when disabled", dut->lg_out == 0);

    dut->buck_enable = 1;
    ticks(250);
    // Should see some HG activity
    int hg_seen = 0;
    for (int i = 0; i < 200; i++) { tick(); if (dut->hg_out) hg_seen++; }
    check("HG active when enabled", hg_seen > 0);
}

// =============================================================================
// Test 5: OCP kills HG but not LG
// =============================================================================
static void test_ocp() {
    printf("=== Test 5: OCP trip ===\n");
    reset();
    dut->buck_enable = 1;
    dut->duty_frac = (96 << 7);
    ticks(200);

    dut->ocp_trip = 1;
    ticks(10);
    check("HG=0 during OCP", dut->hg_out == 0);
    // LG should still be able to be on (freewheeling)
    // LG depends on lg_pre which is controlled by dead time SM
    // Just verify HG is killed
    dut->ocp_trip = 0;
    ticks(200);
    int hg_seen = 0;
    for (int i = 0; i < 200; i++) { tick(); if (dut->hg_out) hg_seen++; }
    check("HG recovers after OCP clear", hg_seen > 0);
}

// =============================================================================
// Test 6: Sigma-delta dithering — fractional duty
// =============================================================================
static void test_sigma_delta() {
    printf("=== Test 6: Sigma-delta dithering ===\n");
    reset();
    dut->buck_enable = 1;
    dut->freq_sel = 0b00; // 500kHz

    // duty = 96.5 → integer=96, fraction=64 (0.5 * 128)
    dut->duty_frac = (96 << 7) | 64;

    // Over many switching cycles, effective duty should alternate between 96 and 97
    // Average should be 96.5
    int total_duty = 0;
    int num_cycles = 0;

    for (int i = 0; i < 192 * 20; i++) { // 20 switching cycles
        tick();
        if (dut->pwm_cycle_start && num_cycles > 0) {
            // Record effective duty
            total_duty += dut->duty_eff_out;
        }
        if (dut->pwm_cycle_start) num_cycles++;
    }

    float avg_duty = (float)total_duty / (num_cycles - 1);
    printf("  Average effective duty over %d cycles: %.2f (target: 96.50)\n", num_cycles - 1, avg_duty);
    check("average duty ~96.5 (within 96.0-97.0)", avg_duty >= 96.0 && avg_duty <= 97.0);
}

// =============================================================================
// Test 7: Shutdown kills all outputs
// =============================================================================
static void test_shutdown() {
    printf("=== Test 7: Shutdown ===\n");
    reset();
    dut->buck_enable = 1;
    dut->duty_frac = (96 << 7);
    ticks(200);

    dut->shutdown = 1;
    ticks(10);
    check("HG=0 during shutdown", dut->hg_out == 0);
    check("LG=0 during shutdown", dut->lg_out == 0);
}

// =============================================================================
// Test 8: PLL unlock kills outputs
// =============================================================================
static void test_pll_unlock() {
    printf("=== Test 8: PLL unlock ===\n");
    reset();
    dut->buck_enable = 1;
    dut->duty_frac = (96 << 7);
    ticks(200);

    dut->pll_lock = 0;
    ticks(10);
    check("HG=0 when PLL unlocked", dut->hg_out == 0);
    check("LG=0 when PLL unlocked", dut->lg_out == 0);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    dut = new Vbuck_pwm;
    trace = new VerilatedVcdC;
    dut->trace(trace, 10);
    trace->open("buck_pwm.vcd");

    test_counter_period();
    test_duty_50pct();
    test_dead_time();
    test_gating_enable();
    test_ocp();
    test_sigma_delta();
    test_shutdown();
    test_pll_unlock();

    trace->close();
    delete trace;
    delete dut;

    printf("\n========================================\n");
    printf("Results: %d / %d passed\n", pass_count, test_count);
    if (pass_count == test_count) printf("ALL TESTS PASSED\n");
    else printf("SOME TESTS FAILED\n");
    printf("========================================\n");

    return (pass_count == test_count) ? 0 : 1;
}
