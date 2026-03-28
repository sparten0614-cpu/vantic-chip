// =============================================================================
// RV32I 5-Stage Pipeline CPU — Verification Testbench
// =============================================================================
// Tests pipeline-specific behaviors: forwarding, stalls, branches, hazards

#include <cstdio>
#include <cstdint>
#include <cstring>
#include "Vrv32i_pipeline.h"
#include "verilated.h"

static vluint64_t sim_time = 0;
static Vrv32i_pipeline *dut;
double sc_time_stamp() { return (double)sim_time; }

static uint32_t mem[16384];

static void tick() {
    dut->imem_data = mem[dut->imem_addr >> 2];
    if (dut->dmem_ren)
        dut->dmem_rdata = mem[dut->dmem_addr >> 2];
    dut->clk = 0; dut->eval(); sim_time++;
    dut->clk = 1; dut->eval(); sim_time++;
    if (dut->dmem_wen) {
        uint32_t a = dut->dmem_addr >> 2;
        uint32_t d = dut->dmem_wdata;
        uint8_t s = dut->dmem_wstrb;
        uint32_t o = mem[a];
        if (s&1) o=(o&0xFFFFFF00)|(d&0xFF);
        if (s&2) o=(o&0xFFFF00FF)|(d&0xFF00);
        if (s&4) o=(o&0xFF00FFFF)|(d&0xFF0000);
        if (s&8) o=(o&0x00FFFFFF)|(d&0xFF000000);
        mem[a] = o;
    }
}
static void ticks(int n) { for(int i=0;i<n;i++) tick(); }

static void reset() {
    memset(mem,0,sizeof(mem));
    dut->rst_n=0; dut->imem_data=0; dut->dmem_rdata=0;
    ticks(10); dut->rst_n=1;
}

// Instruction encoders
static uint32_t addi(int rd,int rs1,int imm){return((imm&0xFFF)<<20)|(rs1<<15)|(0<<12)|(rd<<7)|0x13;}
static uint32_t add(int rd,int rs1,int rs2){return(0<<25)|(rs2<<20)|(rs1<<15)|(0<<12)|(rd<<7)|0x33;}
static uint32_t sub(int rd,int rs1,int rs2){return(0x20<<25)|(rs2<<20)|(rs1<<15)|(0<<12)|(rd<<7)|0x33;}
static uint32_t sw(int rs2,int rs1,int off){return((off>>5)<<25)|(rs2<<20)|(rs1<<15)|(2<<12)|((off&0x1F)<<7)|0x23;}
static uint32_t lw(int rd,int rs1,int off){return((off&0xFFF)<<20)|(rs1<<15)|(2<<12)|(rd<<7)|0x03;}
static uint32_t beq(int rs1,int rs2,int off){return((off>>12)<<31)|(((off>>5)&0x3F)<<25)|(rs2<<20)|(rs1<<15)|(0<<12)|(((off>>1)&0xF)<<8)|(((off>>11)&1)<<7)|0x63;}
static uint32_t jal(int rd,int off){return((off>>20)<<31)|(((off>>1)&0x3FF)<<21)|(((off>>11)&1)<<20)|(((off>>12)&0xFF)<<12)|(rd<<7)|0x6F;}
static uint32_t nop(){return addi(0,0,0);}
static uint32_t ebreak(){return 0x00100073;}

static int tc=0,pc=0;
static void check(const char*n,bool c){tc++;if(c){pc++;printf("  PASS: %s\n",n);}else printf("  FAIL: %s\n",n);}

// Test 1: Data forwarding (EX→EX)
static void test_forwarding() {
    printf("=== Test 1: Data forwarding ===\n");
    reset();
    mem[0] = addi(1,0,10);   // x1=10
    mem[1] = addi(2,1,20);   // x2=x1+20=30 (needs forwarding from prev instr)
    mem[2] = sw(2,0,0x100);  // mem[0x100]=x2
    mem[3] = nop(); mem[4] = nop();
    mem[5] = ebreak();
    ticks(20);
    check("forwarding: x2=30", mem[0x100/4]==30);
}

// Test 2: Back-to-back ALU dependency chain
static void test_chain() {
    printf("=== Test 2: ALU dependency chain ===\n");
    reset();
    mem[0] = addi(1,0,1);    // x1=1
    mem[1] = addi(2,1,1);    // x2=2
    mem[2] = addi(3,2,1);    // x3=3
    mem[3] = addi(4,3,1);    // x4=4
    mem[4] = addi(5,4,1);    // x5=5
    mem[5] = sw(5,0,0x100);
    mem[6] = nop(); mem[7] = nop();
    mem[8] = ebreak();
    ticks(25);
    check("chain: x5=5", mem[0x100/4]==5);
}

// Test 3: Load-use hazard (should stall 1 cycle)
static void test_load_use() {
    printf("=== Test 3: Load-use hazard ===\n");
    reset();
    mem[0x200/4] = 42;       // Preload memory
    mem[0] = addi(1,0,0x200);// x1=0x200 (address)
    // Need a nop between addi and lw because lw uses x1 (forwarded, not load-use)
    mem[1] = lw(2,1,0);      // x2=mem[x1]=42 (forwarding of x1 from addi)
    mem[2] = addi(3,2,8);    // x3=x2+8=50 (load-use: x2 from lw needs stall)
    mem[3] = sw(3,0,0x100);
    mem[4] = nop(); mem[5] = nop();
    mem[6] = ebreak();
    ticks(25);
    check("load-use: x3=50", mem[0x100/4]==50);
}

// Test 4: Branch taken (pipeline flush)
static void test_branch() {
    printf("=== Test 4: Branch (flush) ===\n");
    reset();
    mem[0] = addi(1,0,5);
    mem[1] = addi(2,0,5);
    mem[2] = beq(1,2,12);    // taken: jump to PC+12=20 (mem[5])
    mem[3] = addi(3,0,99);   // should be flushed
    mem[4] = addi(3,0,99);   // should be flushed
    mem[5] = addi(3,0,42);   // branch target
    mem[6] = sw(3,0,0x100);
    mem[7] = nop(); mem[8] = nop();
    mem[9] = ebreak();
    ticks(30);
    check("branch flush: x3=42", mem[0x100/4]==42);
}

// Test 5: Loop (sum 1..10 = 55)
static void test_loop() {
    printf("=== Test 5: Loop sum(1..10) ===\n");
    reset();
    mem[0] = addi(1,0,0);    // sum=0
    mem[1] = addi(2,0,1);    // i=1
    mem[2] = addi(3,0,11);   // limit=11
    // Loop:
    mem[3] = add(1,1,2);     // sum+=i
    mem[4] = addi(2,2,1);    // i++
    mem[5] = beq(2,3,8);     // if i==11: exit (to mem[7])
    mem[6] = jal(0,-12);     // jump back to loop (mem[3])
    mem[7] = sw(1,0,0x100);
    mem[8] = nop(); mem[9] = nop();
    mem[10] = ebreak();
    ticks(200);
    check("sum(1..10)=55", mem[0x100/4]==55);
}

// Test 6: JAL + return
static void test_jal() {
    printf("=== Test 6: JAL ===\n");
    reset();
    mem[0] = jal(1,16);      // x1=PC+4=4, jump to mem[4]
    mem[1] = addi(2,0,99);   // flushed
    mem[2] = addi(2,0,99);   // flushed
    mem[3] = addi(2,0,99);   // flushed
    mem[4] = addi(2,0,42);   // target
    mem[5] = sw(1,0,0x100);  // mem[0x100]=return addr
    mem[6] = sw(2,0,0x104);
    mem[7] = nop(); mem[8] = nop();
    mem[9] = ebreak();
    ticks(30);
    check("JAL return=4", mem[0x100/4]==4);
    check("JAL target reached", mem[0x104/4]==42);
}

int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    dut = new Vrv32i_pipeline;

    test_forwarding();
    test_chain();
    test_load_use();
    test_branch();
    test_loop();
    test_jal();

    delete dut;
    printf("\n========================================\n");
    printf("Pipeline CPU: %d / %d passed\n",pc,tc);
    if(pc==tc) printf("ALL TESTS PASSED\n");
    else printf("SOME TESTS FAILED\n");
    printf("========================================\n");
    return (pc==tc)?0:1;
}
