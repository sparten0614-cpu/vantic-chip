// =============================================================================
// VT3200 Buck ADC Interface — Verilator Testbench
// =============================================================================

#include <cstdio>
#include <cstdint>
#include "Vbuck_adc.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

static vluint64_t sim_time = 0;
static Vbuck_adc *dut;
static VerilatedVcdC *trace;
double sc_time_stamp() { return (double)sim_time; }

static void tick() {
    dut->clk_sys = 0; dut->eval();
    if (trace) trace->dump(sim_time++);
    dut->clk_sys = 1; dut->eval();
    if (trace) trace->dump(sim_time++);
}
static void ticks(int n) { for (int i = 0; i < n; i++) tick(); }

// Simulate ADC hardware: after adc_start, wait ~24 cycles then assert valid
static uint16_t adc_sim_values[4] = {205, 100, 500, 150}; // VBUS, ISNS, VIN, TEMP
static int adc_conv_counter = 0;
static bool adc_converting = false;

static void adc_model() {
    if (dut->adc_start && !adc_converting) {
        adc_converting = true;
        adc_conv_counter = 24;
    }
    if (adc_converting) {
        dut->adc_busy = 1;
        dut->adc_valid = 0;
        adc_conv_counter--;
        if (adc_conv_counter <= 0) {
            dut->adc_data = adc_sim_values[dut->adc_ch_sel];
            dut->adc_valid = 1;
            dut->adc_busy = 0;
            adc_converting = false;
        }
    } else {
        dut->adc_busy = 0;
        dut->adc_valid = 0;
    }
}

static void tick_with_adc() {
    adc_model();
    tick();
}
static void ticks_adc(int n) { for (int i = 0; i < n; i++) tick_with_adc(); }

static void reset() {
    dut->rst_n = 0;
    dut->cycle_start = 0;
    dut->adc_busy = 0;
    dut->adc_data = 0;
    dut->adc_valid = 0;
    dut->vin_divider = 50;
    dut->temp_divider = 250; // Use 250 to keep test short (not 500)
    adc_converting = false;
    ticks(10);
    dut->rst_n = 1;
    ticks(5);
}

static int tc = 0, pc = 0;
static void check(const char *n, bool c) {
    tc++; if (c) { pc++; printf("  PASS: %s\n", n); } else printf("  FAIL: %s\n", n);
}

// Test 1: VBUS + ISNS converted every cycle
static void test_basic() {
    printf("=== Test 1: Basic VBUS+ISNS conversion ===\n");
    reset();
    adc_sim_values[0] = 205; // VBUS
    adc_sim_values[1] = 100; // ISNS

    dut->cycle_start = 1; tick_with_adc(); dut->cycle_start = 0;
    // Wait for conversions (VBUS: 24 cycles, ISNS: 24 more)
    ticks_adc(60);

    check("vbus_result = 205", dut->vbus_result == 205);
    check("isns_result = 100", dut->isns_result == 100);
}

// Test 2: comp_update fires after VBUS conversion
static void test_comp_update() {
    printf("=== Test 2: comp_update timing ===\n");
    reset();

    dut->cycle_start = 1; tick_with_adc(); dut->cycle_start = 0;

    bool comp_seen = false;
    for (int i = 0; i < 50; i++) {
        tick_with_adc();
        if (dut->comp_update) { comp_seen = true; break; }
    }
    check("comp_update fires after VBUS", comp_seen);
}

// Test 3: VIN sampled periodically (every vin_divider cycles)
static void test_vin_periodic() {
    printf("=== Test 3: VIN periodic sampling ===\n");
    reset();
    dut->vin_divider = 3; // Sample every 3 cycles
    adc_sim_values[2] = 500;

    // Run 5 switching cycles
    for (int c = 0; c < 5; c++) {
        dut->cycle_start = 1; tick_with_adc(); dut->cycle_start = 0;
        ticks_adc(100);
    }
    check("vin_result = 500", dut->vin_result == 500);
}

// Test 4: TEMP sampled periodically
static void test_temp_periodic() {
    printf("=== Test 4: TEMP periodic sampling ===\n");
    reset();
    dut->temp_divider = 2; // Sample every 2 cycles
    adc_sim_values[3] = 150;

    for (int c = 0; c < 4; c++) {
        dut->cycle_start = 1; tick_with_adc(); dut->cycle_start = 0;
        ticks_adc(120);
    }
    check("temp_result = 150", dut->temp_result == 150);
}

// Test 5: Channel select correctness
static void test_channels() {
    printf("=== Test 5: Channel sequencing ===\n");
    reset();
    dut->vin_divider = 0; // Every cycle
    dut->temp_divider = 0; // Every cycle

    adc_sim_values[0] = 111;
    adc_sim_values[1] = 222;
    adc_sim_values[2] = 333;
    adc_sim_values[3] = 444;

    dut->cycle_start = 1; tick_with_adc(); dut->cycle_start = 0;
    ticks_adc(150); // All 4 conversions

    check("vbus = 111", dut->vbus_result == 111);
    check("isns = 222", dut->isns_result == 222);
    check("vin = 333", dut->vin_result == 333);
    check("temp = 444", dut->temp_result == 444);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    dut = new Vbuck_adc;
    trace = new VerilatedVcdC;
    dut->trace(trace, 10);
    trace->open("buck_adc.vcd");

    test_basic(); test_comp_update(); test_vin_periodic();
    test_temp_periodic(); test_channels();

    trace->close(); delete trace; delete dut;
    printf("\n========================================\n");
    printf("Results: %d / %d passed\n", pc, tc);
    if (pc == tc) printf("ALL TESTS PASSED\n"); else printf("SOME TESTS FAILED\n");
    printf("========================================\n");
    return (pc == tc) ? 0 : 1;
}
