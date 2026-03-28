#!/usr/bin/env python3.12
"""
VT3100 Phase 0 — Run cocotb simulation with Verilator
"""
import cocotb
from cocotb.runner import get_runner
import os

def test_spi_slave():
    sim = os.getenv("SIM", "verilator")
    proj_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    runner = get_runner(sim)
    runner.build(
        verilog_sources=[os.path.join(proj_path, "rtl", "spi_slave.v")],
        hdl_toplevel="spi_slave",
        always=True,
        build_args=["--trace"],
    )
    runner.test(
        hdl_toplevel="spi_slave",
        test_module="test_spi_slave",
    )

if __name__ == "__main__":
    test_spi_slave()
