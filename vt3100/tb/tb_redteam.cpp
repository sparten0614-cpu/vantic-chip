// =============================================================================
// VT3100 Red Team Tests — Self-attack on known weak points
// =============================================================================

#include <cstdio>
#include <cstdint>
#include "Vcc_logic.h"
#include "verilated.h"

static vluint64_t sim_time = 0;
static Vcc_logic *dut;
double sc_time_stamp() { return (double)sim_time; }

static void tick() {
    dut->clk = 0; dut->eval(); sim_time++;
    dut->clk = 1; dut->eval(); sim_time++;
}
static void ticks(int n) { for (int i = 0; i < n; i++) tick(); }

static int tc=0, pc=0;
static void check(const char *n, bool c) {
    tc++; if(c){pc++;printf("  PASS: %s\n",n);}else{printf("  FAIL: %s\n",n);}
}

// Red Team 1: debounce_cfg=0 → instant attach (no debounce)
static void test_zero_debounce() {
    printf("=== RT1: debounce_cfg=0 ===\n");
    dut->rst_n = 0; ticks(10); dut->rst_n = 1; ticks(5);
    dut->rp_level = 0b10;
    dut->debounce_cfg = 0; // Zero debounce!
    dut->cc1_comp = 0b011; // Rd on CC1
    dut->cc2_comp = 0;

    // With 0 debounce, should attach almost immediately
    ticks(100);
    check("zero debounce: attached quickly", dut->attached == 1);
    printf("  (This means a noise spike could cause false attach with cfg=0)\n");
}

// Red Team 2: debounce_cfg=255 → max debounce (255ms * 12000 = 3,060,000)
// 22-bit counter max = 4,194,303. 3,060,000 < 4,194,303, so no overflow.
static void test_max_debounce() {
    printf("=== RT2: debounce_cfg=255 ===\n");
    dut->rst_n = 0; dut->cc1_comp = 0; dut->cc2_comp = 0; dut->debounce_cfg = 255;
    ticks(10); dut->rst_n = 1; ticks(10); // Extra ticks to let debounce_cfg propagate
    dut->rp_level = 0b10;
    // Now assert Rd AFTER debounce_cfg is stable
    dut->cc1_comp = 0b011;
    dut->cc2_comp = 0;

    // After 200ms worth of ticks, should NOT be attached yet
    for(int ms=0;ms<200;ms+=50){ticks(50*12000);printf("  t=%dms: st=%d att=%d\n",ms+50,dut->state_out,dut->attached);}
    check("max debounce: not attached at 200ms", dut->attached == 0);

    // After 260ms, should be attached
    ticks(60 * 12000);
    check("max debounce: attached after 260ms", dut->attached == 1);
}

// Red Team 3: rapid attach/detach cycling (10 times in 1 second)
static void test_rapid_cycle() {
    printf("=== RT3: rapid attach/detach ===\n");
    dut->rst_n = 0; dut->cc1_comp = 0; dut->cc2_comp = 0; dut->debounce_cfg = 10;
    ticks(10); dut->rst_n = 1; ticks(10);
    dut->rp_level = 0b10;

    int attach_count = 0;
    for (int i = 0; i < 10; i++) {
        dut->cc1_comp = 0b011;
        dut->cc2_comp = 0;
        ticks(15 * 12000); // 15ms > 10ms debounce
        if (dut->attached) attach_count++;

        dut->cc1_comp = 0;
        ticks(20 * 12000); // 20ms > detach debounce (15ms)
    }
    printf("  Attached %d/10 cycles\n", attach_count);
    check("rapid cycling: all 10 attach detected", attach_count == 10);
    check("final state: detached", dut->attached == 0);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vcc_logic;

    test_zero_debounce();
    test_max_debounce();
    test_rapid_cycle();

    delete dut;
    printf("\n========================================\n");
    printf("Red Team CC Logic: %d / %d passed\n", pc, tc);
    if (pc == tc) printf("ALL TESTS PASSED\n");
    else printf("SOME TESTS FAILED\n");
    printf("========================================\n");
    return (pc == tc) ? 0 : 1;
}
