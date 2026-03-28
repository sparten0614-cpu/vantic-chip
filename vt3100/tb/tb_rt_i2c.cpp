// Red Team: I2C Slave — STOP during various states + repeated START mid-data
#include <cstdio>
#include <cstdint>
#include "Vi2c_slave.h"
#include "verilated.h"

static vluint64_t sim_time = 0;
static Vi2c_slave *dut;
static int scl_val = 1, sda_master = 1;
double sc_time_stamp() { return (double)sim_time; }

static void tick() {
    dut->sda_in = (dut->sda_oe || !sda_master) ? 0 : 1;
    dut->scl_in = scl_val;
    dut->clk = 0; dut->eval(); sim_time++;
    dut->sda_in = (dut->sda_oe || !sda_master) ? 0 : 1;
    dut->clk = 1; dut->eval(); sim_time++;
}
static void ticks(int n) { for (int i = 0; i < n; i++) tick(); }

static void i2c_start() {
    sda_master=1; scl_val=1; ticks(5);
    sda_master=0; ticks(5);
    scl_val=0; ticks(5);
}
static void i2c_stop() {
    scl_val=0; sda_master=0; ticks(5);
    scl_val=1; ticks(5);
    sda_master=1; ticks(5);
}
static int i2c_send(uint8_t d) {
    for (int i=7;i>=0;i--) {
        scl_val=0; ticks(2); sda_master=(d>>i)&1; ticks(13);
        scl_val=1; ticks(15);
    }
    scl_val=0; ticks(2); sda_master=1; ticks(13);
    scl_val=1; ticks(3); int ack=dut->sda_in; ticks(12);
    scl_val=0; ticks(5);
    return ack;
}

static int tc=0,pc=0;
static void check(const char*n,bool c){tc++;if(c){pc++;printf("  PASS: %s\n",n);}else printf("  FAIL: %s\n",n);}

static void reset() {
    dut->rst_n=0; scl_val=1; sda_master=1; ticks(10);
    dut->rst_n=1; ticks(5);
    dut->reg_rdata=0x42;
}

// RT4: STOP during register address phase
static void test_stop_mid_regaddr() {
    printf("=== RT4: STOP during reg addr ===\n");
    reset();
    i2c_start();
    i2c_send(0xC0); // addr 0x60 write
    // Send 4 bits of reg addr then STOP
    for(int i=3;i>=0;i--) {
        scl_val=0; ticks(2); sda_master=0; ticks(13);
        scl_val=1; ticks(15);
    }
    i2c_stop();
    ticks(20);
    check("not busy after mid-regaddr STOP", dut->busy == 0);
    // Should be able to start new transaction
    i2c_start();
    int ack = i2c_send(0xC0);
    check("new transaction ACKs after abort", ack == 0);
    i2c_stop();
}

// RT5: Repeated START during write data
static void test_restart_mid_data() {
    printf("=== RT5: Repeated START mid write ===\n");
    reset();
    i2c_start();
    i2c_send(0xC0); // addr write
    i2c_send(0x00); // reg addr 0x00
    // Send 3 bits of data then repeated START
    for(int i=2;i>=0;i--) {
        scl_val=0; ticks(2); sda_master=1; ticks(13);
        scl_val=1; ticks(15);
    }
    // Repeated START
    scl_val=0; ticks(3); sda_master=1; ticks(3);
    scl_val=1; ticks(5); sda_master=0; ticks(5);
    scl_val=0; ticks(5);
    // New address
    int ack = i2c_send(0xC0);
    check("restart mid-data: addr ACK", ack == 0);
    i2c_stop();
}

// RT6: Back-to-back transactions (no gap)
static void test_back_to_back() {
    printf("=== RT6: Back-to-back transactions ===\n");
    reset();
    for (int t = 0; t < 5; t++) {
        i2c_start();
        int ack = i2c_send(0xC0);
        if (ack != 0) { check("b2b: addr ACK", false); return; }
        i2c_send(0x00);
        i2c_send(0xAA);
        i2c_stop();
        ticks(5); // Minimal gap
    }
    check("5 back-to-back transactions", true);
    check("not busy after all", dut->busy == 0);
}

int main(int argc, char**argv) {
    Verilated::commandArgs(argc,argv);
    dut = new Vi2c_slave;
    test_stop_mid_regaddr();
    test_restart_mid_data();
    test_back_to_back();
    delete dut;
    printf("\n========================================\n");
    printf("Red Team I2C: %d / %d passed\n", pc, tc);
    if(pc==tc) printf("ALL TESTS PASSED\n"); else printf("SOME TESTS FAILED\n");
    printf("========================================\n");
    return (pc==tc)?0:1;
}
