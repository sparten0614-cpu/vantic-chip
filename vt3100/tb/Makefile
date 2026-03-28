SIM ?= verilator
TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES = $(shell pwd)/../rtl/spi_slave.v
TOPLEVEL = spi_slave
MODULE = test_spi_slave
EXTRA_ARGS += --trace

include $(shell cocotb-config --share)/lib/Makefile.sim
