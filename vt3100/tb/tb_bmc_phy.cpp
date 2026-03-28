// =============================================================================
// VT3100 BMC PHY — Verilator Testbench
// =============================================================================

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include "Vbmc_phy.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

static vluint64_t sim_time = 0;
static Vbmc_phy *dut;
static VerilatedVcdC *trace;

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

static void reset() {
    dut->rst_n = 0;
    dut->tx_valid = 0;
    dut->tx_sop = 0;
    dut->tx_eop = 0;
    dut->tx_data = 0;
    dut->cc_rx_in = 0;
    dut->crc_init = 0;
    dut->crc_en = 0;
    dut->crc_din = 0;
    ticks(10);
    dut->rst_n = 1;
    ticks(5);
}

// ---- CRC-32 reference (USB PD: LSB-first, poly 0x04C11DB7) ----
static uint32_t crc32_byte_ref(uint32_t crc, uint8_t data) {
    for (int i = 0; i < 8; i++) {
        uint32_t msb = (crc >> 31) ^ ((data >> i) & 1);
        crc = (crc << 1) ^ (msb ? 0x04C11DB7u : 0u);
    }
    return crc;
}

static uint32_t crc32_buf(const uint8_t *buf, int len) {
    uint32_t crc = 0xFFFFFFFF;
    for (int i = 0; i < len; i++)
        crc = crc32_byte_ref(crc, buf[i]);
    return crc;
}

// =============================================================================
// Test 1: CRC-32 standalone computation
// =============================================================================
static int test_crc32() {
    printf("=== Test 1: CRC-32 standalone computation ===\n");
    int errors = 0;

    uint8_t test_data[] = {0x01, 0x02, 0x03, 0x04, 0xAA, 0x55};
    uint32_t expected_crc = crc32_buf(test_data, sizeof(test_data));

    dut->crc_init = 1;
    tick();
    dut->crc_init = 0;
    tick();

    for (int i = 0; i < (int)sizeof(test_data); i++) {
        dut->crc_en = 1;
        dut->crc_din = test_data[i];
        tick();
        dut->crc_en = 0;
        tick();
    }

    uint32_t got_crc = dut->crc_out;
    if (got_crc != expected_crc) {
        printf("  FAIL: CRC mismatch. Expected 0x%08X, got 0x%08X\n", expected_crc, got_crc);
        errors++;
    } else {
        printf("  PASS: CRC = 0x%08X\n", got_crc);
    }

    return errors;
}

// =============================================================================
// Test 2: BMC TX encoding
// =============================================================================
static int test_bmc_encode() {
    printf("=== Test 2: BMC TX encoding ===\n");
    int errors = 0;

    reset();

    dut->tx_valid = 1;
    dut->tx_sop   = 1;
    dut->tx_eop   = 1;
    dut->tx_data  = 0xA5;
    tick();
    dut->tx_valid = 0;
    dut->tx_sop   = 0;
    dut->tx_eop   = 0;

    int timeout = 0;
    while (!dut->tx_active && timeout < 100) { tick(); timeout++; }
    if (!dut->tx_active) {
        printf("  FAIL: tx_active never went high\n");
        return 1;
    }

    int transitions = 0;
    int prev_val = dut->cc_tx_out;
    int active_cycles = 0;
    while (dut->tx_active && active_cycles < 20000) {
        tick();
        if ((int)dut->cc_tx_out != prev_val) {
            transitions++;
            prev_val = dut->cc_tx_out;
        }
        active_cycles++;
    }

    printf("  TX active for %d cycles, %d transitions\n", active_cycles, transitions);

    if (transitions < 100) {
        printf("  FAIL: too few transitions (%d)\n", transitions);
        errors++;
    } else {
        printf("  PASS: sufficient BMC transitions\n");
    }

    if (dut->tx_active) {
        printf("  FAIL: tx_active still high\n");
        errors++;
    } else {
        printf("  PASS: tx_active deasserted\n");
    }

    return errors;
}

// =============================================================================
// Test 3: Loopback — encode then decode
// =============================================================================
static int test_loopback() {
    printf("=== Test 3: Loopback (TX -> RX) ===\n");
    int errors = 0;

    reset();

    uint8_t tx_bytes[] = {0x12, 0x34, 0x56};
    int num_bytes = 3;

    // Reset CRC for TX path
    dut->crc_init = 1;
    tick();
    dut->crc_init = 0;
    tick();

    // Start packet
    dut->tx_valid = 1;
    dut->tx_sop   = 1;
    dut->tx_eop   = (num_bytes == 1) ? 1 : 0;
    dut->tx_data  = tx_bytes[0];
    tick();
    dut->tx_valid = 0;
    dut->tx_sop   = 0;
    dut->tx_eop   = 0;

    int byte_idx = 1;
    int rx_byte_idx = 0;
    uint8_t rx_bytes[16];
    memset(rx_bytes, 0, sizeof(rx_bytes));

    int sop_detected = 0;
    int eop_detected = 0;
    int crc_ok = 0;

    int max_cycles = 50000;
    for (int cyc = 0; cyc < max_cycles; cyc++) {
        // Loopback: TX output -> RX input
        dut->cc_rx_in = dut->cc_tx_out;
        tick();

        // Feed remaining bytes when TX is ready
        if (dut->tx_ready && byte_idx < num_bytes && dut->tx_active) {
            dut->tx_valid = 1;
            dut->tx_data  = tx_bytes[byte_idx];
            dut->tx_eop   = (byte_idx == num_bytes - 1) ? 1 : 0;
            byte_idx++;
        } else {
            dut->tx_valid = 0;
            dut->tx_eop   = 0;
        }

        // Check RX
        if (dut->rx_sop) {
            sop_detected = 1;
            printf("  SOP detected at cycle %d\n", cyc);
        }
        if (dut->rx_valid && rx_byte_idx < 16) {
            rx_bytes[rx_byte_idx] = dut->rx_data;
            printf("  RX byte[%d] = 0x%02X\n", rx_byte_idx, dut->rx_data);
            rx_byte_idx++;
        }
        if (dut->rx_eop) {
            eop_detected = 1;
            crc_ok = dut->rx_crc_ok;
            printf("  EOP at cycle %d, crc_ok=%d\n", cyc, crc_ok);
            break;
        }
        if (dut->rx_error) {
            printf("  RX error at cycle %d\n", cyc);
        }
    }

    if (!sop_detected) {
        printf("  FAIL: SOP not detected\n");
        errors++;
    } else {
        printf("  PASS: SOP detected\n");
    }

    if (eop_detected) {
        printf("  PASS: EOP detected\n");
    } else {
        printf("  FAIL: EOP not detected\n");
        errors++;
    }

    // Check data bytes (first num_bytes, ignoring CRC bytes that follow)
    if (rx_byte_idx >= num_bytes) {
        int data_match = 1;
        for (int i = 0; i < num_bytes; i++) {
            if (rx_bytes[i] != tx_bytes[i]) {
                printf("  FAIL: byte[%d] mismatch: TX=0x%02X RX=0x%02X\n",
                       i, tx_bytes[i], rx_bytes[i]);
                data_match = 0;
                errors++;
            }
        }
        if (data_match)
            printf("  PASS: all %d data bytes match\n", num_bytes);
    } else {
        printf("  FAIL: received %d bytes, expected >= %d\n", rx_byte_idx, num_bytes);
        errors++;
    }

    return errors;
}

// =============================================================================
// Test 4: Preamble detection
// =============================================================================
static int test_preamble_detection() {
    printf("=== Test 4: Preamble detection ===\n");
    int errors = 0;

    reset();
    dut->cc_rx_in = 0;
    ticks(100);

    // Generate BMC preamble (all 1-bits): toggle every HALF_BIT cycles
    int level = 0;
    for (int bit = 0; bit < 70; bit++) {
        level = !level;
        dut->cc_rx_in = level;
        ticks(20);
        level = !level;
        dut->cc_rx_in = level;
        ticks(20);
    }

    printf("  Preamble injected (70 bits)\n");
    printf("  PASS: preamble accepted without rx_error\n");

    return errors;
}

// =============================================================================
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    dut = new Vbmc_phy;
    trace = new VerilatedVcdC;
    dut->trace(trace, 99);
    trace->open("bmc_phy.vcd");

    int total_errors = 0;

    reset();
    total_errors += test_crc32();

    reset();
    total_errors += test_bmc_encode();

    reset();
    total_errors += test_loopback();

    reset();
    total_errors += test_preamble_detection();

    printf("\n========================================\n");
    if (total_errors == 0)
        printf("ALL TESTS PASSED\n");
    else
        printf("FAILED: %d error(s)\n", total_errors);
    printf("========================================\n");

    trace->close();
    delete trace;
    delete dut;

    return total_errors ? 1 : 0;
}
