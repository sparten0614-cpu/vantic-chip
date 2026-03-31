# =============================================================================
# VT3200 USB PD + Buck Converter — Build & Verify Makefile
# =============================================================================
# Usage:
#   make lint          — Verilator lint check
#   make synth_ice40   — iCE40 FPGA synthesis (JSON netlist)
#   make fpga          — iCE40 synth + place&route + bitstream
#   make clean         — Remove build artifacts
# =============================================================================

YOSYS = yosys
VERILATOR = verilator

# VT3100 core RTL (inherited)
VT3100_RTL = ../vt3100/rtl/bmc_phy.v ../vt3100/rtl/cc_logic.v ../vt3100/rtl/pd_msg.v \
             ../vt3100/rtl/goodcrc.v ../vt3100/rtl/pd_policy.v ../vt3100/rtl/i2c_slave.v \
             ../vt3100/rtl/reg_file.v ../vt3100/rtl/vt3100_top.v

# VT3200 buck RTL
VT3200_RTL = rtl/buck_pwm.v rtl/buck_comp.v rtl/buck_prot.v \
             rtl/buck_adc.v rtl/buck_softstart.v rtl/vt3200_top.v

RTL = $(VT3100_RTL) $(VT3200_RTL)

# FPGA config
FPGA_DEVICE = hx8k
FPGA_PACKAGE = ct256
FPGA_JSON = build/vt3200_ice40.json
FPGA_ASC = build/vt3200.asc
FPGA_BIN = build/vt3200.bin
FPGA_PCF = fpga/vt3200.pcf

.PHONY: all lint synth_ice40 fpga pnr bitstream clean

all: lint synth_ice40

lint:
	@echo "=== Lint Check ==="
	@$(VERILATOR) --lint-only -Wall -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY \
		-I../vt3100/rtl $(RTL) && echo "LINT PASS" || echo "LINT FAIL"

synth_ice40:
	@echo "=== iCE40 FPGA Synthesis ==="
	@mkdir -p build
	@$(YOSYS) -p "read_verilog $(RTL); synth_ice40 -top vt3200_top -json $(FPGA_JSON); stat" 2>&1 | \
		grep -E "SB_LUT4|SB_DFF|SB_CARRY|cells$$"

pnr: $(FPGA_ASC)
$(FPGA_ASC): $(FPGA_JSON) $(FPGA_PCF)
	nextpnr-ice40 --$(FPGA_DEVICE) --package $(FPGA_PACKAGE) --json $(FPGA_JSON) --pcf $(FPGA_PCF) --asc $@

bitstream: $(FPGA_BIN)
$(FPGA_BIN): $(FPGA_ASC)
	icepack $< $@

fpga: synth_ice40 pnr bitstream

clean:
	rm -rf build
