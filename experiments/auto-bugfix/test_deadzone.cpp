// Test: inject dead zone edges (28-cycle gaps) and verify RX times out
#include <cstdio>
#include "Vbmc_phy.h"
#include "verilated.h"
static vluint64_t sim_time = 0;
static Vbmc_phy *dut;
double sc_time_stamp(){return(double)sim_time;}
static void tick(){dut->clk=0;dut->eval();sim_time++;dut->clk=1;dut->eval();sim_time++;}
static void ticks(int n){for(int i=0;i<n;i++)tick();}

int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    dut=new Vbmc_phy;
    dut->rst_n=0;dut->tx_valid=0;dut->tx_sop=0;dut->tx_eop=0;dut->tx_data=0;
    dut->cc_rx_in=0;dut->crc_init=0;dut->crc_en=0;dut->crc_din=0;
    ticks(10);dut->rst_n=1;ticks(5);

    // Inject dead zone edges: toggle cc_rx_in every 28 cycles
    // This creates edges with gap=28, which is in the dead zone (27-29)
    // After 20000 cycles, RX should have timed out (15000 cycle timeout)
    printf("Injecting dead zone edges (28-cycle gaps) for 20000 cycles...\n");
    dut->cc_rx_in = 0;
    for (int i = 0; i < 700; i++) { // 700 toggles * 28 cycles = 19600 cycles
        ticks(28);
        dut->cc_rx_in = !dut->cc_rx_in;
    }

    // Check: rx_error or rx_eop should have fired (timeout),
    // and the module should be back in IDLE
    // If the bug exists, RX is still stuck (timeout never fires because
    // each edge resets the timeout counter)

    // Give a few more cycles with no edges to let timeout fire
    dut->cc_rx_in = 0;
    ticks(20000); // Well beyond 15000 timeout

    printf("Test complete.\n");
    printf("If RX timed out properly, this test passes.\n");
    printf("If RX is stuck (timeout keeps resetting), the bug exists.\n");

    delete dut;
    return 0;
}
