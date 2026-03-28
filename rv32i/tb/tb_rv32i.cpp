// =============================================================================
// RV32I CPU Core — Verilator Testbench
// =============================================================================
// Tests basic instruction execution with a simple program in memory.

#include <cstdio>
#include <cstdint>
#include <cstring>
#include "Vrv32i_core.h"
#include "verilated.h"

static vluint64_t sim_time = 0;
static Vrv32i_core *dut;
double sc_time_stamp() { return (double)sim_time; }

// Simple memory (64KB)
static uint32_t mem[16384]; // 64KB / 4 bytes

static void tick() {
    // Provide instruction from memory
    dut->imem_data = mem[dut->imem_addr >> 2];
    // Provide data from memory
    if (dut->dmem_ren)
        dut->dmem_rdata = mem[dut->dmem_addr >> 2];

    dut->clk = 0; dut->eval(); sim_time++;
    dut->clk = 1; dut->eval(); sim_time++;

    // Handle data writes
    if (dut->dmem_wen) {
        uint32_t addr = dut->dmem_addr >> 2;
        uint32_t wdata = dut->dmem_wdata;
        uint8_t wstrb = dut->dmem_wstrb;
        uint32_t old = mem[addr];
        if (wstrb & 1) old = (old & 0xFFFFFF00) | (wdata & 0x000000FF);
        if (wstrb & 2) old = (old & 0xFFFF00FF) | (wdata & 0x0000FF00);
        if (wstrb & 4) old = (old & 0xFF00FFFF) | (wdata & 0x00FF0000);
        if (wstrb & 8) old = (old & 0x00FFFFFF) | (wdata & 0xFF000000);
        mem[addr] = old;
    }
}

static void ticks(int n) { for (int i = 0; i < n; i++) tick(); }

static void reset() {
    memset(mem, 0, sizeof(mem));
    dut->rst_n = 0; dut->imem_data = 0; dut->dmem_rdata = 0;
    ticks(5);
    dut->rst_n = 1;
}

// Helper: encode RV32I instructions
static uint32_t r_type(uint8_t funct7, uint8_t rs2, uint8_t rs1, uint8_t funct3, uint8_t rd, uint8_t opcode) {
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode;
}
static uint32_t i_type(int16_t imm, uint8_t rs1, uint8_t funct3, uint8_t rd, uint8_t opcode) {
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode;
}
static uint32_t addi(uint8_t rd, uint8_t rs1, int16_t imm) { return i_type(imm, rs1, 0, rd, 0x13); }
static uint32_t add(uint8_t rd, uint8_t rs1, uint8_t rs2)  { return r_type(0, rs2, rs1, 0, rd, 0x33); }
static uint32_t sub(uint8_t rd, uint8_t rs1, uint8_t rs2)  { return r_type(0x20, rs2, rs1, 0, rd, 0x33); }
static uint32_t sw(uint8_t rs2, uint8_t rs1, int16_t off)  {
    return ((off>>5)<<25) | (rs2<<20) | (rs1<<15) | (2<<12) | ((off&0x1F)<<7) | 0x23;
}
static uint32_t lw(uint8_t rd, uint8_t rs1, int16_t off)   { return i_type(off, rs1, 2, rd, 0x03); }
static uint32_t lui(uint8_t rd, uint32_t imm20)             { return (imm20 << 12) | (rd << 7) | 0x37; }
static uint32_t beq(uint8_t rs1, uint8_t rs2, int16_t off) {
    return ((off>>12)<<31) | (((off>>5)&0x3F)<<25) | (rs2<<20) | (rs1<<15) | (0<<12) | (((off>>1)&0xF)<<8) | (((off>>11)&1)<<7) | 0x63;
}
static uint32_t jal(uint8_t rd, int32_t off) {
    return ((off>>20)<<31) | (((off>>1)&0x3FF)<<21) | (((off>>11)&1)<<20) | (((off>>12)&0xFF)<<12) | (rd<<7) | 0x6F;
}
static uint32_t ebreak() { return 0x00100073; }

static int tc=0, pc=0;
static void check(const char *n, bool c) {
    tc++; if(c){pc++;printf("  PASS: %s\n",n);}else{printf("  FAIL: %s\n",n);}
}

// =============================================================================
// Test 1: ADDI — x1 = 0 + 42 = 42
// =============================================================================
static void test_addi() {
    printf("=== Test 1: ADDI ===\n");
    reset();
    mem[0] = addi(1, 0, 42);    // x1 = 42
    mem[1] = addi(2, 1, 8);     // x2 = x1 + 8 = 50
    mem[2] = ebreak();
    ticks(5);
    check("halt after ebreak", dut->halt == 1);
    check("PC = 8 (3 instructions)", dut->pc_out == 8);
}

// =============================================================================
// Test 2: ADD/SUB
// =============================================================================
static void test_add_sub() {
    printf("=== Test 2: ADD/SUB ===\n");
    reset();
    mem[0] = addi(1, 0, 100);   // x1 = 100
    mem[1] = addi(2, 0, 30);    // x2 = 30
    mem[2] = add(3, 1, 2);      // x3 = x1 + x2 = 130
    mem[3] = sub(4, 1, 2);      // x4 = x1 - x2 = 70
    mem[4] = sw(3, 0, 0x100);   // mem[0x100] = x3 = 130
    mem[5] = sw(4, 0, 0x104);   // mem[0x104] = x4 = 70
    mem[6] = ebreak();
    ticks(10);
    check("mem[0x100] = 130 (ADD)", mem[0x100/4] == 130);
    check("mem[0x104] = 70 (SUB)", mem[0x104/4] == 70);
}

// =============================================================================
// Test 3: LUI + Store/Load
// =============================================================================
static void test_lui_mem() {
    printf("=== Test 3: LUI + Memory ===\n");
    reset();
    mem[0] = lui(1, 0xDEADB);   // x1 = 0xDEADB000
    mem[1] = addi(1, 1, 0xEEF); // x1 = 0xDEADBEEF (note: sign extension)
    mem[2] = sw(1, 0, 0x200);   // mem[0x200] = x1
    mem[3] = lw(2, 0, 0x200);   // x2 = mem[0x200]
    mem[4] = sw(2, 0, 0x204);   // mem[0x204] = x2 (should equal x1)
    mem[5] = ebreak();
    ticks(10);
    check("store/load roundtrip", mem[0x200/4] == mem[0x204/4]);
}

// =============================================================================
// Test 4: BEQ (branch taken and not taken)
// =============================================================================
static void test_branch() {
    printf("=== Test 4: Branch ===\n");
    reset();
    mem[0] = addi(1, 0, 5);     // x1 = 5
    mem[1] = addi(2, 0, 5);     // x2 = 5
    mem[2] = beq(1, 2, 8);      // if x1==x2: PC += 8 (skip next 2 instrs)
    mem[3] = addi(3, 0, 99);    // x3 = 99 (should be skipped)
    mem[4] = addi(3, 0, 99);    // (skipped)
    mem[5] = addi(3, 0, 42);    // x3 = 42 (branch target)
    mem[6] = sw(3, 0, 0x300);   // mem[0x300] = x3
    mem[7] = ebreak();
    ticks(10);
    check("BEQ taken: x3 = 42 (not 99)", mem[0x300/4] == 42);
}

// =============================================================================
// Test 5: JAL (jump and link)
// =============================================================================
static void test_jal() {
    printf("=== Test 5: JAL ===\n");
    reset();
    mem[0] = jal(1, 12);        // x1 = PC+4 = 4, jump to PC+12 = 12
    mem[1] = addi(2, 0, 99);    // skipped
    mem[2] = addi(2, 0, 99);    // skipped
    mem[3] = addi(2, 0, 42);    // PC=12: x2 = 42
    mem[4] = sw(1, 0, 0x400);   // mem[0x400] = x1 (return address = 4)
    mem[5] = sw(2, 0, 0x404);   // mem[0x404] = x2 = 42
    mem[6] = ebreak();
    ticks(10);
    check("JAL: return addr = 4", mem[0x400/4] == 4);
    check("JAL: jumped correctly", mem[0x404/4] == 42);
}

// =============================================================================
// Test 6: Simple loop (sum 1 to 5 = 15)
// =============================================================================
static void test_loop() {
    printf("=== Test 6: Loop (sum 1..5) ===\n");
    reset();
    // Program: sum = 0; for (i=1; i<=5; i++) sum += i;
    mem[0] = addi(1, 0, 0);     // x1 = sum = 0
    mem[1] = addi(2, 0, 1);     // x2 = i = 1
    mem[2] = addi(3, 0, 6);     // x3 = limit = 6
    // Loop:
    mem[3] = add(1, 1, 2);      // sum += i
    mem[4] = addi(2, 2, 1);     // i++
    mem[5] = beq(2, 3, 8);      // if i==6: exit loop (skip to mem[7])
    mem[6] = jal(0, -12);       // jump back to loop (mem[3])
    mem[7] = sw(1, 0, 0x500);   // mem[0x500] = sum
    mem[8] = ebreak();
    ticks(50);
    check("sum(1..5) = 15", mem[0x500/4] == 15);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vrv32i_core;

    test_addi();
    test_add_sub();
    test_lui_mem();
    test_branch();
    test_jal();
    test_loop();

    delete dut;
    printf("\n========================================\n");
    printf("RV32I CPU: %d / %d passed\n", pc, tc);
    if (pc == tc) printf("ALL TESTS PASSED\n");
    else printf("SOME TESTS FAILED\n");
    printf("========================================\n");
    return (pc == tc) ? 0 : 1;
}
