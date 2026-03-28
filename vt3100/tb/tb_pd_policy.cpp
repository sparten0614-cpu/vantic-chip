// =============================================================================
// VT3100 PD Source Policy Engine — Verilator Testbench
// =============================================================================

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include "Vpd_policy.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

static vluint64_t sim_time = 0;
static Vpd_policy *dut;
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

static int test_count = 0;
static int pass_count = 0;

static void check(const char *name, bool cond) {
    test_count++;
    if (cond) {
        pass_count++;
        printf("  PASS: %s\n", name);
    } else {
        printf("  FAIL: %s (state=%d)\n", name, dut->state_out);
    }
}

// Wait until state_out matches target or max ticks exceeded
static bool wait_state(int target, int max_ticks) {
    for (int i = 0; i < max_ticks; i++) {
        if (dut->state_out == target) return true;
        tick();
    }
    return (dut->state_out == target);
}

enum State {
    ST_IDLE = 0, ST_STARTUP = 1, ST_SEND_CAPS = 2, ST_WAIT_GOODCRC = 3,
    ST_WAIT_REQUEST = 4, ST_EVALUATE = 5, ST_SEND_ACCEPT = 6,
    ST_WAIT_ACCEPT_GC = 7, ST_TRANSITION = 8, ST_SEND_PS_RDY = 9,
    ST_WAIT_RDY_GC = 10, ST_CONTRACT = 11, ST_SEND_REJECT = 12,
    ST_WAIT_REJECT_GC = 13, ST_DISCONNECT = 14
};

static void reset() {
    dut->rst_n = 0;
    dut->cc_attached = 0;
    dut->cc_attach_event = 0;
    dut->cc_detach_event = 0;
    dut->msg_tx_busy = 0;
    dut->msg_tx_done = 0;
    dut->msg_rx_valid = 0;
    dut->msg_rx_msg_type = 0;
    dut->msg_rx_num_do = 0;
    dut->msg_rx_do0 = 0;
    dut->goodcrc_received = 0;
    // Fixed PDO format: [19:10]=voltage(50mV), [9:0]=current(10mA)
    dut->pdo0 = (100 << 10) | 300;   // 5V / 3A
    dut->pdo1 = (180 << 10) | 300;   // 9V / 3A
    dut->pdo2 = (400 << 10) | 500;   // 20V / 5A
    dut->pdo3 = 0;
    dut->num_pdos = 3;
    dut->vbus_stable = 0;
    ticks(10);
    dut->rst_n = 1;
    ticks(5);
}

static void send_goodcrc() {
    dut->goodcrc_received = 1;
    tick();
    dut->goodcrc_received = 0;
}

static void send_request(uint8_t obj_pos, uint16_t current_10ma) {
    dut->msg_rx_valid = 1;
    dut->msg_rx_msg_type = 0x02;
    dut->msg_rx_num_do = 1;
    dut->msg_rx_do0 = ((uint32_t)obj_pos << 28) | (current_10ma & 0x3FF);
    tick();
    dut->msg_rx_valid = 0;
    dut->msg_rx_msg_type = 0;
    dut->msg_rx_num_do = 0;
    dut->msg_rx_do0 = 0;
}

// Helper: bring DUT to SEND_CAPS state (attach + vbus ready)
static void goto_send_caps() {
    dut->cc_attached = 1;
    dut->cc_attach_event = 1;
    tick();
    dut->cc_attach_event = 0;
    dut->vbus_stable = 1;
    ticks(5);
}

// Helper: bring DUT to WAIT_REQUEST (send caps + GoodCRC)
static void goto_wait_request() {
    goto_send_caps();
    wait_state(ST_WAIT_GOODCRC, 2000000); // wait for tFirstSourceCap
    send_goodcrc();
    ticks(2);
}

// Helper: bring DUT to CONTRACT via happy path
static void goto_contract(uint8_t obj_pos = 1, uint16_t current = 200) {
    goto_wait_request();
    send_request(obj_pos, current);
    wait_state(ST_EVALUATE, 5);
    tick(); // evaluate
    wait_state(ST_WAIT_ACCEPT_GC, 10);
    send_goodcrc();
    ticks(2);
    // TRANSITION — vbus_stable is already 1
    wait_state(ST_SEND_PS_RDY, 10);
    wait_state(ST_WAIT_RDY_GC, 10);
    send_goodcrc();
    ticks(2);
}

// =============================================================================
// Test 1: Idle state
// =============================================================================
static void test_idle() {
    printf("=== Test 1: Idle state ===\n");
    reset();
    ticks(100);
    check("state = IDLE", dut->state_out == ST_IDLE);
    check("vbus_en = 0", dut->vbus_en == 0);
    check("pd_contract = 0", dut->pd_contract == 0);
}

// =============================================================================
// Test 2: Attach → Startup → VBUS enable
// =============================================================================
static void test_startup() {
    printf("=== Test 2: Attach and startup ===\n");
    reset();

    dut->cc_attached = 1;
    dut->cc_attach_event = 1;
    tick();
    dut->cc_attach_event = 0;

    check("state = STARTUP", dut->state_out == ST_STARTUP);
    check("vbus_en = 1", dut->vbus_en == 1);

    dut->vbus_stable = 1;
    ticks(5);

    check("state = SEND_CAPS", dut->state_out == ST_SEND_CAPS);
    check("vbus_present = 1", dut->vbus_present == 1);
}

// =============================================================================
// Test 3: Full happy path
// =============================================================================
static void test_happy_path() {
    printf("=== Test 3: Full happy path ===\n");
    reset();
    goto_send_caps();
    check("SEND_CAPS state", dut->state_out == ST_SEND_CAPS);

    // Wait for tFirstSourceCap (150ms = 1,800,000 cycles)
    bool reached = wait_state(ST_WAIT_GOODCRC, 1900000);
    check("reached WAIT_GOODCRC", reached);

    // GoodCRC
    send_goodcrc();
    ticks(2);
    check("state = WAIT_REQUEST", dut->state_out == ST_WAIT_REQUEST);

    // Request PDO #1, 2A
    send_request(1, 200);
    // EVALUATE → SEND_ACCEPT → WAIT_ACCEPT_GC may happen in 2-3 cycles
    // (because msg_tx_busy=0 and EVALUATE is 1-cycle)
    wait_state(ST_WAIT_ACCEPT_GC, 10);
    check("reached WAIT_ACCEPT_GC", dut->state_out == ST_WAIT_ACCEPT_GC);

    send_goodcrc();
    // TRANSITION → SEND_PS_RDY → WAIT_RDY_GC may be fast (vbus_stable=1)
    wait_state(ST_WAIT_RDY_GC, 10);
    check("reached WAIT_RDY_GC", dut->state_out == ST_WAIT_RDY_GC);

    wait_state(ST_WAIT_RDY_GC, 10);
    send_goodcrc();
    ticks(2);

    check("state = CONTRACT", dut->state_out == ST_CONTRACT);
    check("pd_contract = 1", dut->pd_contract == 1);
    check("protocol_id = PD_FIXED", dut->protocol_id == 1);
}

// =============================================================================
// Test 4: Over-current → Reject
// =============================================================================
static void test_reject_overcurrent() {
    printf("=== Test 4: Over-current → Reject ===\n");
    reset();
    goto_wait_request();

    // PDO #1 max = 300 (3A), request 400 (4A) — exceeds
    send_request(1, 400);
    wait_state(ST_SEND_REJECT, 10);
    wait_state(ST_WAIT_REJECT_GC, 10);
    check("state = WAIT_REJECT_GC", dut->state_out == ST_WAIT_REJECT_GC);

    // Send GoodCRC on Reject → should go to SEND_CAPS
    send_goodcrc();
    ticks(2);
    check("back to SEND_CAPS after Reject+GoodCRC", dut->state_out == ST_SEND_CAPS);
}

// =============================================================================
// Test 5: Invalid position → Reject
// =============================================================================
static void test_reject_position() {
    printf("=== Test 5: Invalid position → Reject ===\n");
    reset();
    goto_wait_request();

    // Only 3 PDOs, request #5
    send_request(5, 100);
    wait_state(ST_SEND_REJECT, 10);
    wait_state(ST_WAIT_REJECT_GC, 10);
    check("state = WAIT_REJECT_GC", dut->state_out == ST_WAIT_REJECT_GC);
}

// =============================================================================
// Test 6: GoodCRC timeout → retry
// =============================================================================
static void test_retry() {
    printf("=== Test 6: GoodCRC retry ===\n");
    reset();
    goto_send_caps();

    bool reached = wait_state(ST_WAIT_GOODCRC, 1900000);
    check("reached WAIT_GOODCRC", reached);

    // Timeout 1 (tReceive = 1.1ms = 13200 cycles)
    ticks(14000);
    check("still in WAIT_GOODCRC (retry 1)", dut->state_out == ST_WAIT_GOODCRC);

    // Timeout 2
    ticks(14000);
    check("still in WAIT_GOODCRC (retry 2)", dut->state_out == ST_WAIT_GOODCRC);

    // Timeout 3 — retries exhausted, back to SEND_CAPS
    ticks(14000);
    check("back to SEND_CAPS", dut->state_out == ST_SEND_CAPS);
}

// =============================================================================
// Test 7: Detach → Disconnect
// =============================================================================
static void test_detach() {
    printf("=== Test 7: Detach ===\n");
    reset();
    goto_contract();

    check("in CONTRACT", dut->state_out == ST_CONTRACT);

    dut->cc_detach_event = 1;
    tick();
    dut->cc_detach_event = 0;

    check("state = DISCONNECT", dut->state_out == ST_DISCONNECT);
    ticks(2); // vbus_en cleared on next cycle when ST_DISCONNECT entered
    check("vbus_en = 0", dut->vbus_en == 0);

    // Wait recovery (650ms = 7,800,000 cycles)
    wait_state(ST_IDLE, 8000000);
    check("state = IDLE", dut->state_out == ST_IDLE);
    check("pd_contract = 0", dut->pd_contract == 0);
}

// =============================================================================
// Test 8: 9V negotiation
// =============================================================================
static void test_9v() {
    printf("=== Test 8: Negotiate 9V ===\n");
    reset();
    goto_wait_request();

    // Request PDO #2 (9V), 2A
    send_request(2, 200);
    wait_state(ST_EVALUATE, 5);
    tick();
    wait_state(ST_WAIT_ACCEPT_GC, 10);
    send_goodcrc();
    // May pass through TRANSITION quickly since vbus_stable=1
    wait_state(ST_WAIT_RDY_GC, 10);

    // PDO #2: voltage = 180 (50mV units) → vbus_voltage = 90 (100mV units)
    check("vbus_voltage = 90 (9.0V)", dut->vbus_voltage == 90);
    send_goodcrc();
    ticks(2);

    check("state = CONTRACT", dut->state_out == ST_CONTRACT);
    check("pd_contract = 1", dut->pd_contract == 1);
}

// =============================================================================
// Test 9: Re-negotiation during contract
// =============================================================================
static void test_renegotiation() {
    printf("=== Test 9: Re-negotiation ===\n");
    reset();
    goto_contract(1, 200); // Start at 5V/2A

    check("in CONTRACT at 5V", dut->state_out == ST_CONTRACT);

    // Sink requests PDO #2 (9V)
    send_request(2, 200);
    wait_state(ST_EVALUATE, 5);
    tick();
    check("re-evaluating", dut->state_out == ST_SEND_ACCEPT);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    dut = new Vpd_policy;
    trace = new VerilatedVcdC;
    dut->trace(trace, 10);
    trace->open("pd_policy.vcd");

    test_idle();
    test_startup();
    test_happy_path();
    test_reject_overcurrent();
    test_reject_position();
    test_retry();
    test_detach();
    test_9v();
    test_renegotiation();

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
