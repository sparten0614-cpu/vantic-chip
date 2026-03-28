// =============================================================================
// VT3200 Buck Digital Compensator — Verilator Testbench
// =============================================================================

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cmath>
#include "Vbuck_comp.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

static vluint64_t sim_time = 0;
static Vbuck_comp *dut;
static VerilatedVcdC *trace;

double sc_time_stamp() { return (double)sim_time; }

static void tick() {
    dut->clk_sys = 0; dut->eval();
    if (trace) trace->dump(sim_time++);
    dut->clk_sys = 1; dut->eval();
    if (trace) trace->dump(sim_time++);
}

static void ticks(int n) { for (int i = 0; i < n; i++) tick(); }

// Q1.14 signed: value = integer * 16384
static int16_t to_q114(double val) {
    return (int16_t)(val * 16384.0);
}

static void reset() {
    dut->rst_n = 0;
    dut->comp_update = 0;
    dut->comp_enable = 0;
    dut->vbus_adc = 0;
    dut->target_voltage = 0;
    dut->b0 = 0; dut->b1 = 0; dut->b2 = 0;
    dut->duty_max = (192 << 7); // Q9.7: max 192 integer
    dut->duty_min = 0;
    ticks(10);
    dut->rst_n = 1;
    dut->comp_enable = 1;
    ticks(5);
}

// Trigger one compensator update and wait for done
static void update() {
    dut->comp_update = 1;
    tick();
    dut->comp_update = 0;
    // Wait for COMPUTE → DONE
    for (int i = 0; i < 10; i++) {
        tick();
        if (dut->comp_done) break;
    }
    tick(); // One more to return to IDLE
}

static int test_count = 0;
static int pass_count = 0;

static void check(const char *name, bool cond) {
    test_count++;
    if (cond) { pass_count++; printf("  PASS: %s\n", name); }
    else { printf("  FAIL: %s\n", name); }
}

// =============================================================================
// Test 1: Zero error → duty stays at initial value
// =============================================================================
static void test_zero_error() {
    printf("=== Test 1: Zero error ===\n");
    reset();

    // Target = 5V = 500 (10mV units), target_scaled = 250
    // ADC reading = 250 (matches target)
    dut->target_voltage = 500;
    dut->vbus_adc = 250;

    // Set simple coefficients: b0=0.5, b1=0, b2=0
    dut->b0 = to_q114(0.5);
    dut->b1 = 0;
    dut->b2 = 0;

    update();
    uint16_t d1 = dut->duty_out;
    update();
    uint16_t d2 = dut->duty_out;

    printf("  duty after update 1: %d, update 2: %d\n", d1, d2);
    check("duty stable with zero error", d1 == d2);
    check("error_out = 0", dut->error_out == 0);
}

// =============================================================================
// Test 2: Positive error → duty increases
// =============================================================================
static void test_positive_error() {
    printf("=== Test 2: Positive error ===\n");
    reset();

    // Target = 500 (→ scaled 250), ADC = 200 (voltage too low)
    dut->target_voltage = 500;
    dut->vbus_adc = 200;
    dut->b0 = to_q114(0.1);
    dut->b1 = 0;
    dut->b2 = 0;

    update();
    uint16_t d1 = dut->duty_out;
    update();
    uint16_t d2 = dut->duty_out;

    printf("  duty: %d → %d (error=%d)\n", d1, d2, dut->error_out);
    check("positive error: duty increases", d2 > d1);
    check("error > 0", dut->error_out > 0);
}

// =============================================================================
// Test 3: Negative error → duty decreases (or stays at min)
// =============================================================================
static void test_negative_error() {
    printf("=== Test 3: Negative error ===\n");
    reset();

    // Target = 500 (→ scaled 250), ADC = 300 (voltage too high)
    dut->target_voltage = 500;
    dut->vbus_adc = 300;
    dut->b0 = to_q114(0.1);
    dut->b1 = 0;
    dut->b2 = 0;

    update();
    // Sign-extend 12-bit error to 16-bit for printing
    int16_t err = (dut->error_out & 0x800) ? (dut->error_out | 0xF000) : dut->error_out;
    printf("  error_out = %d, duty = %d\n", err, dut->duty_out);
    check("negative error detected", err < 0);
}

// =============================================================================
// Test 4: Anti-windup clamp — duty_max
// =============================================================================
static void test_clamp_max() {
    printf("=== Test 4: Anti-windup clamp max ===\n");
    reset();

    dut->duty_max = (100 << 7); // Q9.7: max duty = 100
    dut->target_voltage = 2000; // 20V → scaled 1000
    dut->vbus_adc = 0;          // Huge error
    dut->b0 = to_q114(1.0);     // Aggressive gain
    dut->b1 = 0;
    dut->b2 = 0;

    // Run many updates to try to exceed clamp
    for (int i = 0; i < 20; i++) update();

    uint16_t d = dut->duty_out;
    printf("  duty after 20 updates: %d (max=%d)\n", d, 100 << 7);
    check("duty clamped to max", d <= (100 << 7));
}

// =============================================================================
// Test 5: Anti-windup clamp — duty_min
// =============================================================================
static void test_clamp_min() {
    printf("=== Test 5: Anti-windup clamp min ===\n");
    reset();

    dut->duty_min = (10 << 7); // Q9.7: min duty = 10
    dut->target_voltage = 100;  // 1V → scaled 50
    dut->vbus_adc = 1000;       // Way over target → big negative error
    dut->b0 = to_q114(1.0);
    dut->b1 = 0;
    dut->b2 = 0;

    for (int i = 0; i < 20; i++) update();

    uint16_t d = dut->duty_out;
    printf("  duty after 20 updates: %d (min=%d)\n", d, 10 << 7);
    check("duty clamped to min", d >= (10 << 7) || d == 0);
}

// =============================================================================
// Test 6: comp_enable = 0 → output zeroed
// =============================================================================
static void test_disable() {
    printf("=== Test 6: Compensator disable ===\n");
    reset();

    dut->target_voltage = 500;
    dut->vbus_adc = 200;
    dut->b0 = to_q114(0.1);

    update();
    check("duty > 0 when enabled", dut->duty_out > 0);

    dut->comp_enable = 0;
    ticks(5);
    check("duty = 0 when disabled", dut->duty_out == 0);
}

// =============================================================================
// Test 7: Integrating behavior (duty ramps up with constant error)
// =============================================================================
static void test_integration() {
    printf("=== Test 7: Integration ===\n");
    reset();

    dut->target_voltage = 500;
    dut->vbus_adc = 200;  // Constant positive error
    dut->b0 = to_q114(0.01); // Small gain
    dut->b1 = 0;
    dut->b2 = 0;

    uint16_t duties[5];
    for (int i = 0; i < 5; i++) {
        update();
        duties[i] = dut->duty_out;
    }

    printf("  Duties: %d %d %d %d %d\n", duties[0], duties[1], duties[2], duties[3], duties[4]);
    check("monotonically increasing", duties[0] < duties[1] && duties[1] < duties[2] && duties[2] < duties[3]);
}

// =============================================================================
// Test 8: comp_done strobe
// =============================================================================
static void test_comp_done() {
    printf("=== Test 8: comp_done strobe ===\n");
    reset();

    dut->target_voltage = 500;
    dut->vbus_adc = 250;
    dut->b0 = to_q114(0.1);

    check("comp_done = 0 before update", dut->comp_done == 0);

    dut->comp_update = 1;
    tick();
    dut->comp_update = 0;

    // COMPUTE state
    tick();
    // DONE state — comp_done should be 1
    check("comp_done = 1 after compute", dut->comp_done == 1);

    tick();
    check("comp_done = 0 after done", dut->comp_done == 0);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    dut = new Vbuck_comp;
    trace = new VerilatedVcdC;
    dut->trace(trace, 10);
    trace->open("buck_comp.vcd");

    test_zero_error();
    test_positive_error();
    test_negative_error();
    test_clamp_max();
    test_clamp_min();
    test_disable();
    test_integration();
    test_comp_done();

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
