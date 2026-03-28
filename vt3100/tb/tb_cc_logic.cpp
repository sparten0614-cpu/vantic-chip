// =============================================================================
// VT3100 CC Logic — Verilator Testbench
// =============================================================================

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include "Vcc_logic.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

static vluint64_t sim_time = 0;
static Vcc_logic *dut;
static VerilatedVcdC *trace;

double sc_time_stamp() { return (double)sim_time; }

static void tick() {
    dut->clk = 0;
    dut->eval();
    if (trace) trace->dump(sim_time++);
    dut->clk = 1;
    dut->eval();
    if (trace) trace->dump(sim_time++);
}

static void ticks(int n) {
    for (int i = 0; i < n; i++) tick();
}

// Simulate N milliseconds at 12 MHz
static void ms(int n) {
    ticks(n * 12000);
}

static void reset() {
    dut->rst_n = 0;
    dut->cc1_comp = 0;
    dut->cc2_comp = 0;
    dut->rp_level = 0b10;      // 3.0A default
    dut->debounce_cfg = 150;   // 150ms
    ticks(10);
    dut->rst_n = 1;
    ticks(5);
}

// CC comparator encodings (from spec):
// 3'b000 = open
// 3'b011 = Rd (sink)
// 3'b111 = Ra (audio/VCONN)
static const uint8_t CC_OPEN = 0b000;
static const uint8_t CC_RD   = 0b011;
static const uint8_t CC_RA   = 0b111;

static int test_count = 0;
static int pass_count = 0;

static void check(const char *name, bool cond) {
    test_count++;
    if (cond) {
        pass_count++;
        printf("  PASS: %s\n", name);
    } else {
        printf("  FAIL: %s\n", name);
    }
}

// =============================================================================
// Test 1: Unattached state — no Rd, should stay unattached
// =============================================================================
static void test_unattached() {
    printf("=== Test 1: Unattached state ===\n");
    reset();

    // No device connected — both CC lines open
    dut->cc1_comp = CC_OPEN;
    dut->cc2_comp = CC_OPEN;
    ms(500);

    check("not attached when no Rd", dut->attached == 0);
    check("state is UNATTACHED (0)", dut->state_out == 0);
    check("Rp on CC1 is 3A (0b11)", dut->rp_cc1_level == 0b11);
    check("Rp on CC2 is 3A (0b11)", dut->rp_cc2_level == 0b11);
}

// =============================================================================
// Test 2: Normal attach on CC1 with debounce
// =============================================================================
static void test_attach_cc1() {
    printf("=== Test 2: Attach on CC1 ===\n");
    reset();

    dut->cc1_comp = CC_OPEN;
    dut->cc2_comp = CC_OPEN;
    ticks(100);

    // Sink connects on CC1 (Rd detected)
    dut->cc1_comp = CC_RD;
    dut->cc2_comp = CC_OPEN;

    // Wait a bit but less than debounce — should NOT be attached yet
    ms(50);
    check("not attached before debounce (50ms)", dut->attached == 0);
    check("state is ATTACH_WAIT (1)", dut->state_out == 1);

    // Wait rest of debounce (need ~100 more ms to exceed 150ms total)
    ms(110);
    check("attached after debounce (160ms)", dut->attached == 1);
    check("orientation = CC1 (0)", dut->orientation == 0);
    check("cc_sel = CC1 (0)", dut->cc_sel == 0);
    check("state is ATTACHED (2)", dut->state_out == 2);
}

// =============================================================================
// Test 3: Normal attach on CC2
// =============================================================================
static void test_attach_cc2() {
    printf("=== Test 3: Attach on CC2 ===\n");
    reset();

    // Sink connects on CC2
    dut->cc1_comp = CC_OPEN;
    dut->cc2_comp = CC_RD;

    ms(200); // well beyond debounce

    check("attached", dut->attached == 1);
    check("orientation = CC2 (1)", dut->orientation == 1);
    check("cc_sel = CC2 (1)", dut->cc_sel == 1);
}

// =============================================================================
// Test 4: Bounce rejection (Rd appears briefly then disappears)
// =============================================================================
static void test_bounce_rejection() {
    printf("=== Test 4: Bounce rejection ===\n");
    reset();

    // Brief Rd on CC1
    dut->cc1_comp = CC_RD;
    ms(30); // 30ms — way less than 150ms debounce

    // Rd disappears (bounce)
    dut->cc1_comp = CC_OPEN;
    ms(10);

    check("not attached after bounce", dut->attached == 0);
    check("returned to UNATTACHED", dut->state_out == 0);
}

// =============================================================================
// Test 5: Detach detection
// =============================================================================
static void test_detach() {
    printf("=== Test 5: Detach detection ===\n");
    reset();

    // Attach on CC1
    dut->cc1_comp = CC_RD;
    dut->cc2_comp = CC_OPEN;
    ms(200);
    check("attached before detach", dut->attached == 1);

    // Remove Rd (detach)
    dut->cc1_comp = CC_OPEN;
    ms(5);
    check("still attached during detach debounce (5ms)", dut->attached == 1);

    ms(20); // 25ms total > 15ms detach debounce
    check("detached after detach debounce", dut->attached == 0);
    check("returned to UNATTACHED", dut->state_out == 0);
}

// =============================================================================
// Test 6: VCONN control — Ra on non-active CC
// =============================================================================
static void test_vconn() {
    printf("=== Test 6: VCONN with Ra on CC2 ===\n");
    reset();

    // Sink on CC1 (Rd), active cable on CC2 (Ra)
    dut->cc1_comp = CC_RD;
    dut->cc2_comp = CC_RA;
    ms(200);

    check("attached", dut->attached == 1);
    check("orientation = CC1 (0)", dut->orientation == 0);
    check("VCONN enabled", dut->vconn_en == 1);
    check("VCONN on CC2", dut->vconn_cc2 == 1);
}

// =============================================================================
// Test 7: Rp level switching
// =============================================================================
static void test_rp_levels() {
    printf("=== Test 7: Rp level switching ===\n");
    reset();

    // Default USB (rp_level=00)
    dut->rp_level = 0b00;
    ticks(100);
    check("rp_level 00 -> analog 01 (default)", dut->rp_cc1_level == 0b01);

    // 1.5A (rp_level=01)
    dut->rp_level = 0b01;
    ticks(100);
    check("rp_level 01 -> analog 10 (1.5A)", dut->rp_cc1_level == 0b10);

    // 3.0A (rp_level=10)
    dut->rp_level = 0b10;
    ticks(100);
    check("rp_level 10 -> analog 11 (3.0A)", dut->rp_cc1_level == 0b11);
}

// =============================================================================
// Test 8: Detach false alarm (Rd briefly disappears then comes back)
// =============================================================================
static void test_detach_false_alarm() {
    printf("=== Test 8: Detach false alarm ===\n");
    reset();

    // Attach on CC1
    dut->cc1_comp = CC_RD;
    ms(200);
    check("attached", dut->attached == 1);

    // Brief Rd loss (noise)
    dut->cc1_comp = CC_OPEN;
    ms(5); // 5ms < 15ms detach debounce
    dut->cc1_comp = CC_RD; // Rd comes back
    ms(5);

    check("still attached after false alarm", dut->attached == 1);
    check("state is ATTACHED (2)", dut->state_out == 2);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    dut = new Vcc_logic;
    trace = new VerilatedVcdC;
    dut->trace(trace, 10);
    trace->open("cc_logic.vcd");

    test_unattached();
    test_attach_cc1();
    test_attach_cc2();
    test_bounce_rejection();
    test_detach();
    test_vconn();
    test_rp_levels();
    test_detach_false_alarm();

    trace->close();
    delete trace;
    delete dut;

    printf("\n========================================\n");
    printf("Results: %d / %d passed\n", pass_count, test_count);
    if (pass_count == test_count) {
        printf("ALL TESTS PASSED\n");
    } else {
        printf("SOME TESTS FAILED\n");
    }
    printf("========================================\n");

    return (pass_count == test_count) ? 0 : 1;
}
