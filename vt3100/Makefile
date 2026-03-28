# =============================================================================
# VT3100 USB PD Protocol Controller — Build & Verify Makefile
# =============================================================================
# Usage:
#   make lint          — Verilator lint check (all modules)
#   make test          — Build and run all testbenches
#   make synth         — Yosys logic synthesis
#   make synth_ice40   — iCE40 FPGA synthesis (JSON netlist)
#   make fpga          — iCE40 synth + place&route + bitstream
#   make all           — lint + test + synth
#   make clean         — Remove build artifacts
# =============================================================================

VERILATOR = verilator
YOSYS = yosys
CXX = c++
CXXFLAGS = -Os -std=c++17
VFLAGS = --cc --trace -Wall -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY

VINC = $(shell $(VERILATOR) --getenv VERILATOR_ROOT)/include
VDEFS = -DVERILATOR=1 -DVM_TRACE=1 -DVM_TRACE_VCD=1

RTL = rtl/bmc_phy.v rtl/cc_logic.v rtl/pd_msg.v rtl/goodcrc.v \
      rtl/pd_policy.v rtl/i2c_slave.v rtl/reg_file.v rtl/vt3100_top.v

# Module/testbench pairs
MODULES = bmc_phy cc_logic pd_msg pd_policy i2c_slave

# FPGA config
FPGA_DEVICE = hx8k
FPGA_PACKAGE = ct256
FPGA_JSON = build/vt3100_ice40.json
FPGA_ASC = build/vt3100.asc
FPGA_BIN = build/vt3100.bin
FPGA_PCF = fpga/vt3100.pcf

.PHONY: all lint test synth synth_ice40 fpga pnr bitstream program clean

all: lint test synth

# --- Lint ---
lint:
	@echo "=== Lint Check ==="
	@$(VERILATOR) --lint-only -Wall -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY $(RTL) && echo "LINT PASS" || echo "LINT FAIL"

# --- Test all modules ---
test: $(MODULES:%=test_%)
	@echo "=== All Tests Complete ==="

define MODULE_TEST
test_$(1):
	@echo "--- Testing $(1) ---"
	@mkdir -p build/$(1)
	@$(VERILATOR) $(VFLAGS) rtl/$(1).v --Mdir build/$(1) 2>/dev/null
	@$(MAKE) -s -C build/$(1) -f V$(1).mk 2>/dev/null
	@$(CXX) $(CXXFLAGS) -I build/$(1) -I $(VINC) -I $(VINC)/vltstd $(VDEFS) \
		tb/tb_$(1).cpp build/$(1)/libV$(1).a build/$(1)/libverilated.a \
		-o build/tb_$(1) 2>/dev/null
	@./build/tb_$(1) 2>/dev/null || true
endef

$(foreach m,$(MODULES),$(eval $(call MODULE_TEST,$(m))))

# --- Synthesis ---
synth:
	@echo "=== Yosys Synthesis ==="
	@$(YOSYS) -p "read_verilog $(RTL); synth -top vt3100_top -flatten; stat" 2>&1 | grep -E "cells$$|wire bits|ports"

synth_ice40:
	@echo "=== iCE40 FPGA Synthesis ==="
	@$(YOSYS) -p "read_verilog $(RTL); synth_ice40 -top vt3100_top -json build/vt3100_ice40.json; stat" 2>&1 | grep -E "SB_LUT4|SB_DFF|SB_CARRY|cells$$"

# --- FPGA Flow (iCE40 HX8K) ---
pnr: $(FPGA_ASC)
$(FPGA_ASC): $(FPGA_JSON) $(FPGA_PCF)
	nextpnr-ice40 --$(FPGA_DEVICE) --package $(FPGA_PACKAGE) --json $(FPGA_JSON) --pcf $(FPGA_PCF) --asc $@

bitstream: $(FPGA_BIN)
$(FPGA_BIN): $(FPGA_ASC)
	icepack $< $@

program: $(FPGA_BIN)
	iceprog $<

fpga: synth_ice40 pnr bitstream

clean:
	rm -rf build obj_dir* *.vcd tb_*
