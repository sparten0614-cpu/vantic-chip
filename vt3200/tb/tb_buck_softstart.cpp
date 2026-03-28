// =============================================================================
// VT3200 Buck Soft-Start — Verilator Testbench
// =============================================================================

#include <cstdio>
#include <cstdint>
#include "Vbuck_softstart.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

static vluint64_t sim_time = 0;
static Vbuck_softstart *dut;
static VerilatedVcdC *trace;
double sc_time_stamp() { return (double)sim_time; }

static void tick() {
    dut->clk_sys = 0; dut->eval();
    if (trace) trace->dump(sim_time++);
    dut->clk_sys = 1; dut->eval();
    if (trace) trace->dump(sim_time++);
}
static void ticks(int n) { for (int i = 0; i < n; i++) tick(); }

static void comp_pulse() {
    dut->comp_update = 1; tick(); dut->comp_update = 0; tick();
}

static void reset() {
    dut->rst_n = 0;
    dut->ss_start = 0;
    dut->ss_abort = 0;
    dut->comp_update = 0;
    dut->final_target = 500; // 5V
    dut->ss_step = 0x8000;  // 1.0 per cycle (fast)
    ticks(10);
    dut->rst_n = 1;
    ticks(5);
}

static int tc = 0, pc = 0;
static void check(const char *n, bool c) {
    tc++; if (c) { pc++; printf("  PASS: %s\n", n); } else printf("  FAIL: %s\n", n);
}

// Test 1: Initial state — done, target = final
static void test_initial() {
    printf("=== Test 1: Initial state ===\n");
    reset();
    check("ss_done = 1 initially", dut->ss_done == 1);
    check("ss_active = 0", dut->ss_active == 0);
    check("ramped_target = final_target", dut->ramped_target == 500);
}

// Test 2: Fast ramp (step=1.0, target=10)
static void test_fast_ramp() {
    printf("=== Test 2: Fast ramp ===\n");
    reset();
    dut->final_target = 10;
    dut->ss_step = 0x8000; // 1.0 per cycle

    dut->ss_start = 1; tick(); dut->ss_start = 0; tick();
    check("ss_active after start", dut->ss_active == 1);
    check("ramped_target starts at 0", dut->ramped_target == 0);

    // 20 steps to reach target (10 / 0.5 = 20)
    for (int i = 0; i < 22; i++) comp_pulse();

    check("ss_done after 22 steps", dut->ss_done == 1);
    check("ramped_target = 10", dut->ramped_target == 10);
}

// Test 3: Slow ramp (step=0.5, target=5)
static void test_slow_ramp() {
    printf("=== Test 3: Slow ramp ===\n");
    reset();
    dut->final_target = 5;
    dut->ss_step = 0x4000; // 0.25 per cycle

    dut->ss_start = 1; tick(); dut->ss_start = 0; tick();

    // Need 20 steps (5 / 0.25 = 20)
    for (int i = 0; i < 15; i++) comp_pulse();
    check("still active at 15 steps", dut->ss_active == 1);

    for (int i = 0; i < 10; i++) comp_pulse();
    check("done after 25 steps", dut->ss_done == 1);
    check("ramped_target = 5", dut->ramped_target == 5);
}

// Test 4: Monotonic ramp (never decreases)
static void test_monotonic() {
    printf("=== Test 4: Monotonic ramp ===\n");
    reset();
    dut->final_target = 100;
    dut->ss_step = 0x8000;

    dut->ss_start = 1; tick(); dut->ss_start = 0; tick();

    uint16_t prev = 0;
    bool monotonic = true;
    for (int i = 0; i < 210; i++) {
        comp_pulse();
        if (dut->ramped_target < prev) monotonic = false;
        prev = dut->ramped_target;
    }
    check("ramp is monotonic", monotonic);
    check("reaches target", dut->ramped_target == 100);
}

// Test 5: Abort during ramp
static void test_abort() {
    printf("=== Test 5: Abort ===\n");
    reset();
    dut->final_target = 100;
    dut->ss_step = 0x8000;

    dut->ss_start = 1; tick(); dut->ss_start = 0; tick();
    for (int i = 0; i < 50; i++) comp_pulse();
    check("active at 50 steps", dut->ss_active == 1);

    dut->ss_abort = 1; tick(); dut->ss_abort = 0; tick();
    check("not active after abort", dut->ss_active == 0);
    check("ramped_target = final after abort", dut->ramped_target == 100);
}

// Test 6: Re-start after completion
static void test_restart() {
    printf("=== Test 6: Re-start ===\n");
    reset();
    dut->final_target = 5;
    dut->ss_step = 0x8000;

    dut->ss_start = 1; tick(); dut->ss_start = 0; tick();
    for (int i = 0; i < 12; i++) comp_pulse();
    check("done first time", dut->ss_done == 1);

    // Change target and restart
    dut->final_target = 10;
    dut->ss_start = 1; tick(); dut->ss_start = 0; tick();
    check("active on re-start", dut->ss_active == 1);
    check("ramped starts at 0", dut->ramped_target == 0);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    dut = new Vbuck_softstart;
    trace = new VerilatedVcdC;
    dut->trace(trace, 10);
    trace->open("buck_softstart.vcd");

    test_initial(); test_fast_ramp(); test_slow_ramp();
    test_monotonic(); test_abort(); test_restart();

    trace->close(); delete trace; delete dut;
    printf("\n========================================\n");
    printf("Results: %d / %d passed\n", pc, tc);
    if (pc == tc) printf("ALL TESTS PASSED\n"); else printf("SOME TESTS FAILED\n");
    printf("========================================\n");
    return (pc == tc) ? 0 : 1;
}
