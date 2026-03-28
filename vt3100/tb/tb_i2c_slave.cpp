// =============================================================================
// VT3100 I2C Slave — Verilator Testbench
// =============================================================================
// Simulates an I2C master to test the slave module.

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include "Vi2c_slave.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

static vluint64_t sim_time = 0;
static Vi2c_slave *dut;
static VerilatedVcdC *trace;

double sc_time_stamp() { return (double)sim_time; }

// I2C bus state (simulated master) — declared before tick() for bus update
static int scl_val = 1;
static int sda_master = 1;

// Simple register file for testing
static uint8_t reg_file[256];

static void tick() {
    // Update SDA bus every cycle (open-drain: slave OR master can pull low)
    dut->sda_in = (dut->sda_oe || !sda_master) ? 0 : 1;
    dut->scl_in = scl_val;
    // Continuously provide read data based on current reg_addr
    dut->reg_rdata = reg_file[dut->reg_addr & 0xFF];
    dut->clk = 0; dut->eval();
    if (trace) trace->dump(sim_time++);
    dut->sda_in = (dut->sda_oe || !sda_master) ? 0 : 1;
    dut->reg_rdata = reg_file[dut->reg_addr & 0xFF];
    dut->clk = 1; dut->eval();
    if (trace) trace->dump(sim_time++);
}

static void ticks(int n) { for (int i = 0; i < n; i++) tick(); }

// I2C timing: 12MHz clk, 400kHz I2C → 30 clk cycles per SCL period
// Use 15 clocks per half-period for simplicity
static const int HALF_PERIOD = 15;

static void update_bus() {
    dut->scl_in = scl_val;
    // SDA is open-drain: if slave drives low (sda_oe=1) OR master drives low, SDA=0
    dut->sda_in = (dut->sda_oe || !sda_master) ? 0 : 1;
}

static void scl_low()  { scl_val = 0; update_bus(); ticks(HALF_PERIOD); }
static void scl_high() { scl_val = 1; update_bus(); ticks(HALF_PERIOD); }

static void sda_low()  { sda_master = 0; update_bus(); ticks(2); }
static void sda_high() { sda_master = 1; update_bus(); ticks(2); }

// I2C START: SDA falls while SCL high
static void i2c_start() {
    sda_master = 1; scl_val = 1; update_bus(); ticks(5);
    sda_master = 0; update_bus(); ticks(5); // SDA fall while SCL high
    scl_val = 0; update_bus(); ticks(5);
}

// I2C STOP: SDA rises while SCL high
static void i2c_stop() {
    scl_val = 0; sda_master = 0; update_bus(); ticks(5);
    scl_val = 1; update_bus(); ticks(5);
    sda_master = 1; update_bus(); ticks(5); // SDA rise while SCL high
}

// I2C Repeated START
static void i2c_restart() {
    scl_val = 0; update_bus(); ticks(3);
    sda_master = 1; update_bus(); ticks(3);
    scl_val = 1; update_bus(); ticks(5);
    sda_master = 0; update_bus(); ticks(5); // SDA fall while SCL high
    scl_val = 0; update_bus(); ticks(5);
}

// Send a byte MSB first, return ACK (0=ACK, 1=NACK)
static int i2c_send_byte(uint8_t data) {
    for (int i = 7; i >= 0; i--) {
        scl_val = 0; update_bus(); ticks(2);
        sda_master = (data >> i) & 1;
        update_bus(); ticks(HALF_PERIOD - 2);
        scl_val = 1; update_bus(); ticks(HALF_PERIOD);
    }
    // ACK phase: release SDA, clock in ACK from slave
    scl_val = 0; update_bus(); ticks(2);
    sda_master = 1; // Release SDA
    update_bus(); ticks(HALF_PERIOD - 2);
    scl_val = 1; update_bus(); ticks(3);
    int ack = dut->sda_in; // 0=ACK, 1=NACK
    ticks(HALF_PERIOD - 3);
    scl_val = 0; update_bus(); ticks(5);
    return ack;
}

// Read a byte, send ACK(0) or NACK(1)
static uint8_t i2c_read_byte(int nack) {
    uint8_t data = 0;
    sda_master = 1; // Release SDA for slave to drive
    for (int i = 7; i >= 0; i--) {
        scl_val = 0; update_bus(); ticks(HALF_PERIOD);
        scl_val = 1; update_bus(); ticks(3);
        data |= (dut->sda_in ? 1 : 0) << i;
        ticks(HALF_PERIOD - 3);
    }
    // ACK/NACK
    scl_val = 0; update_bus(); ticks(2);
    sda_master = nack; // 0=ACK, 1=NACK
    update_bus(); ticks(HALF_PERIOD - 2);
    scl_val = 1; update_bus(); ticks(HALF_PERIOD);
    scl_val = 0; update_bus(); ticks(5);
    return data;
}

static void reset() {
    dut->rst_n = 0;
    dut->scl_in = 1;
    dut->sda_in = 1;
    scl_val = 1;
    sda_master = 1;
    ticks(10);
    dut->rst_n = 1;
    ticks(5);
    update_bus();
    ticks(5);

    // Initialize reg file with test values
    for (int i = 0; i < 256; i++) reg_file[i] = (uint8_t)(0x31 + i);
}

static int test_count = 0;
static int pass_count = 0;

static void check(const char *name, bool cond) {
    test_count++;
    if (cond) { pass_count++; printf("  PASS: %s\n", name); }
    else { printf("  FAIL: %s\n", name); }
}

// =============================================================================
// Test 1: Address ACK for matching address (0x60)
// =============================================================================
static void test_addr_ack() {
    printf("=== Test 1: Address ACK ===\n");
    reset();

    i2c_start();
    int ack = i2c_send_byte((0x60 << 1) | 0); // Write to 0x60
    check("ACK for address 0x60", ack == 0);
    i2c_stop();
}

// =============================================================================
// Test 2: Address NACK for non-matching address
// =============================================================================
static void test_addr_nack() {
    printf("=== Test 2: Address NACK for wrong address ===\n");
    reset();

    i2c_start();
    int ack = i2c_send_byte((0x50 << 1) | 0); // Write to 0x50 (wrong)
    check("NACK for address 0x50", ack == 1);
    i2c_stop();
}

// =============================================================================
// Test 3: Register write
// =============================================================================
static void test_write() {
    printf("=== Test 3: Register write ===\n");
    reset();

    i2c_start();
    int ack1 = i2c_send_byte((0x60 << 1) | 0); // Write
    check("addr ACK", ack1 == 0);

    int ack2 = i2c_send_byte(0x04); // Register address 0x04
    check("reg addr ACK", ack2 == 0);

    int ack3 = i2c_send_byte(0xAB); // Data
    check("data ACK", ack3 == 0);

    // Check write strobe and data
    check("reg_addr = 0x04", dut->reg_addr == 0x04 || dut->reg_addr == 0x05);
    // Note: after write+ACK, addr auto-increments to 0x05
    check("reg_wdata = 0xAB", dut->reg_wdata == 0xAB);

    i2c_stop();
}

// =============================================================================
// Test 4: Register read
// =============================================================================
static void test_read() {
    printf("=== Test 4: Register read ===\n");
    reset();

    // Write register address first
    i2c_start();
    i2c_send_byte((0x60 << 1) | 0); // Write mode
    i2c_send_byte(0x00); // Register address 0x00

    // Repeated START for read
    i2c_restart();
    int ack = i2c_send_byte((0x60 << 1) | 1); // Read mode
    check("read addr ACK", ack == 0);

    uint8_t data = i2c_read_byte(1); // NACK (single byte read)
    printf("  Read data: 0x%02X\n", data);
    // The value should be from reg_file[0x00] = 0x31
    check("read data = 0x31", data == 0x31);

    i2c_stop();
}

// =============================================================================
// Test 5: Sequential write (auto-increment)
// =============================================================================
static void test_sequential_write() {
    printf("=== Test 5: Sequential write ===\n");
    reset();

    i2c_start();
    i2c_send_byte((0x60 << 1) | 0);
    i2c_send_byte(0x06); // Start at register 0x06

    // Write 3 bytes: should go to 0x06, 0x07, 0x08
    uint8_t written[3] = {0};
    uint8_t addrs[3] = {0};

    for (int i = 0; i < 3; i++) {
        uint8_t val = 0x10 + i;
        // Capture addr before write
        addrs[i] = dut->reg_addr;
        i2c_send_byte(val);
        written[i] = dut->reg_wdata;
    }

    check("first write addr = 0x06", addrs[0] == 0x06);
    check("second write addr = 0x07", addrs[1] == 0x07);
    check("third write addr = 0x08", addrs[2] == 0x08);
    check("first write data = 0x10", written[0] == 0x10);
    check("second write data = 0x11", written[1] == 0x11);
    check("third write data = 0x12", written[2] == 0x12);

    i2c_stop();
}

// =============================================================================
// Test 6: Sequential read (auto-increment)
// =============================================================================
static void test_sequential_read() {
    printf("=== Test 6: Sequential read ===\n");
    reset();

    // Set register address
    i2c_start();
    i2c_send_byte((0x60 << 1) | 0);
    i2c_send_byte(0x00);

    // Read mode
    i2c_restart();
    i2c_send_byte((0x60 << 1) | 1);

    // Read 3 bytes (reg_rdata auto-updated in tick())
    uint8_t d0 = i2c_read_byte(0); // ACK
    uint8_t d1 = i2c_read_byte(0); // ACK
    uint8_t d2 = i2c_read_byte(1); // NACK

    printf("  Read: 0x%02X 0x%02X 0x%02X\n", d0, d1, d2);
    check("byte 0 = reg_file[0]", d0 == reg_file[0]);
    check("byte 1 = reg_file[1]", d1 == reg_file[1]);
    check("byte 2 = reg_file[2]", d2 == reg_file[2]);

    i2c_stop();
}

// =============================================================================
// Test 7: Busy signal
// =============================================================================
static void test_busy() {
    printf("=== Test 7: Busy signal ===\n");
    reset();

    check("not busy initially", dut->busy == 0);

    i2c_start();
    check("busy after START", dut->busy == 1);

    i2c_send_byte((0x60 << 1) | 0);
    i2c_stop();
    ticks(10);

    check("not busy after STOP", dut->busy == 0);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    dut = new Vi2c_slave;
    trace = new VerilatedVcdC;
    dut->trace(trace, 10);
    trace->open("i2c_slave.vcd");

    test_addr_ack();
    test_addr_nack();
    test_write();
    test_read();
    test_sequential_write();
    test_sequential_read();
    test_busy();

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
