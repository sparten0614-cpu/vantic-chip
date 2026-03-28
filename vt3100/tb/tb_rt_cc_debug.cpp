#include <cstdio>
#include "Vcc_logic.h"
#include "verilated.h"
static vluint64_t sim_time = 0;
static Vcc_logic *dut;
double sc_time_stamp(){return(double)sim_time;}
static void tick(){dut->clk=0;dut->eval();sim_time++;dut->clk=1;dut->eval();sim_time++;}
static void ticks(int n){for(int i=0;i<n;i++)tick();}

int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    dut=new Vcc_logic;
    // Reset
    dut->rst_n=0; ticks(10); dut->rst_n=1; ticks(5);
    dut->rp_level=0b10;
    dut->debounce_cfg=255;
    dut->cc1_comp=0b011; // Rd
    dut->cc2_comp=0;
    
    // Check state at key timepoints
    for(int ms=0; ms<=260; ms+=10) {
        ticks(10*12000); // 10ms at a time
        if(ms%50==0 || dut->attached)
            printf("t=%dms: state=%d attached=%d\n", ms, dut->state_out, dut->attached);
        if(dut->attached) {
            printf("  ATTACHED at %dms! Expected 255ms\n", ms);
            break;
        }
    }
    delete dut;
    return 0;
}
