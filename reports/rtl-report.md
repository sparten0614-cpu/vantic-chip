# VT3100 / VT3200 RTL Design Report

**Document:** VANTIC-RTL-001 Rev 1.0
**Date:** 2026-03-29
**Status:** Phase 2 — FPGA Prototyping

---

## 1. Design Overview

| Parameter | VT3100 | VT3200 |
|-----------|--------|--------|
| Function | USB PD 3.1 SPR Protocol Controller | USB PD + Integrated Buck Converter |
| RTL Lines | 3,023 | 4,076 (includes VT3100 core) |
| Modules | 8 | 14 (8 inherited + 6 new) |
| Gate Count (Yosys) | 5,660 cells | 8,998 cells (3,810 flat) |
| iCE40 HX8K LUT4 | 1,342 (17.5%) | 2,202 (28.7%) |
| Target Process | 55nm CMOS | 55nm CMOS |
| Est. Die Area | ~0.03 mm² | ~0.05 mm² |
| Package | QFN-20 (3x3mm) | QFN-24 (4x4mm) |
| Clock Domains | 1 (12MHz) | 2 (12MHz sys + 96MHz PWM) |

---

## 2. VT3100 Module Summary

| Module | File | Lines | Purpose |
|--------|------|-------|---------|
| `vt3100_top` | rtl/vt3100_top.v | 374 | Top-level integration |
| `bmc_phy` | rtl/bmc_phy.v | 664 | BMC physical layer (4b5b + CRC-32) |
| `pd_msg` | rtl/pd_msg.v | 454 | PD message frame parser/builder |
| `pd_policy` | rtl/pd_policy.v | 533 | Power policy engine (14-state FSM) |
| `cc_logic` | rtl/cc_logic.v | 298 | CC pin orientation/attach/detach |
| `goodcrc` | rtl/goodcrc.v | 128 | GoodCRC auto-response (3-state FSM) |
| `i2c_slave` | rtl/i2c_slave.v | 314 | I2C slave interface (addr 0x60) |
| `reg_file` | rtl/reg_file.v | 130 | 32 configuration/status registers |

### VT3100 Port List

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | 12 MHz system clock |
| `rst_n` | in | 1 | Active-low reset |
| `cc1_comp` | in | 3 | CC1 comparator results |
| `cc2_comp` | in | 3 | CC2 comparator results |
| `rp_cc1_level` | out | 2 | Rp current source level CC1 |
| `rp_cc2_level` | out | 2 | Rp current source level CC2 |
| `cc_rx_in` | in | 1 | BMC receive |
| `cc_tx_out` | out | 1 | BMC transmit |
| `cc_sel` | out | 1 | CC orientation select |
| `scl_in` | in | 1 | I2C clock |
| `sda_in` | in | 1 | I2C data in |
| `sda_oe` | out | 1 | I2C data output enable |
| `vbus_en` | out | 1 | Power stage enable |
| `vbus_voltage` | out | 8 | Target voltage (100mV units) |
| `vbus_current` | out | 10 | Max current (10mA units) |
| `vbus_stable` | in | 1 | VBUS reached target |
| `pd_contract` | out | 1 | PD contract active |
| `vbus_present` | out | 1 | VBUS presence |
| `protocol_id` | out | 4 | Active protocol ID |
| `int_out` | out | 1 | Interrupt output |

---

## 3. VT3200 Additional Modules (Buck Converter)

| Module | File | Lines | Purpose |
|--------|------|-------|---------|
| `vt3200_top` | rtl/vt3200_top.v | 264 | Top-level (VT3100 core + Buck) |
| `buck_pwm` | rtl/buck_pwm.v | 182 | PWM generator (96MHz, sigma-delta dithering) |
| `buck_comp` | rtl/buck_comp.v | 161 | Type-II digital compensator (Q-format) |
| `buck_prot` | rtl/buck_prot.v | 206 | OCP/OVP/UVP/OTP protection |
| `buck_adc` | rtl/buck_adc.v | 168 | Multi-channel ADC interface (CDC) |
| `buck_softstart` | rtl/buck_softstart.v | 72 | Linear ramp soft-start |

### VT3200 Additional Ports (vs VT3100)

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk_pwm` | in | 1 | 96 MHz PWM clock (from PLL) |
| `pll_lock` | in | 1 | PLL locked indicator |
| `hg_out` | out | 1 | High-side gate drive |
| `lg_out` | out | 1 | Low-side gate drive |
| `ocp_comp` | in | 1 | OCP comparator input |
| `adc_ch_sel` | out | 2 | ADC channel select |
| `adc_start` | out | 1 | ADC conversion start |
| `adc_busy` | in | 1 | ADC busy flag |
| `adc_data` | in | 10 | ADC data |
| `adc_valid` | in | 1 | ADC data valid |
| `pgood` | out | 1 | Power good output |

---

## 4. Synthesis Results

### 4.1 Yosys Generic Synthesis

**VT3100:**
```
Total cells: 5,660
  SB_LUT4:    1,342
  SB_DFFER:     485
  SB_CARRY:     305
  SB_DFFES:     120
  SB_DFFR:       92
  SB_DFFE:       76
  SB_DFFS:       12
```

**VT3200 (combined):**
```
Total cells: 8,998
  SB_LUT4:    2,202
  SB_DFFER:     647
  SB_CARRY:     636
  SB_DFFES:     120
  SB_DFFR:      101
  SB_DFFE:       76
  SB_DFFS:       15
```

### 4.2 FPGA Resource Utilization (iCE40 HX8K)

| Resource | VT3100 | VT3200 | HX8K Available | VT3100 % | VT3200 % |
|----------|--------|--------|----------------|-----------|-----------|
| LUT4 | 1,342 | 2,202 | 7,680 | 17.5% | 28.7% |
| DFF | 685 | 959 | 7,680 | 8.9% | 12.5% |
| CARRY | 305 | 636 | 7,680 | 4.0% | 8.3% |
| I/O | 20 ports | 26 ports | 206 | 9.7% | 12.6% |

### 4.3 Synthesis Tool

- **Yosys** 0.63 (git sha1 70a11c6)
- Target: `synth_ice40` with `-json` output
- Flattened netlist (single hierarchy level)

---

## 5. Clock Domain Crossing (VT3200)

VT3200 has two clock domains requiring CDC handling:

| Signal | From | To | Method |
|--------|------|----|--------|
| `cycle_start` | clk_pwm (96MHz) | clk_sys (12MHz) | 2-stage synchronizer + edge detect |

Implementation in `vt3200_top.v`:
- 3-stage flip-flop synchronizer (`cs_sync1` → `cs_sync2` → `cs_sync3`)
- Rising edge detection: `cycle_start_sys = cs_sync2 & ~cs_sync3`
- MTBF analysis: at 96MHz, 2-stage sync provides >100 year MTBF

---

## 6. Design Files

### RTL
```
vt3100/rtl/vt3100_top.v     vt3200/rtl/vt3200_top.v
vt3100/rtl/bmc_phy.v        vt3200/rtl/buck_pwm.v
vt3100/rtl/pd_msg.v         vt3200/rtl/buck_comp.v
vt3100/rtl/pd_policy.v      vt3200/rtl/buck_prot.v
vt3100/rtl/cc_logic.v       vt3200/rtl/buck_adc.v
vt3100/rtl/goodcrc.v        vt3200/rtl/buck_softstart.v
vt3100/rtl/i2c_slave.v
vt3100/rtl/reg_file.v
```

### FPGA Constraints
```
vt3100/fpga/vt3100.pcf      (iCE40 HX8K-CT256)
vt3200/fpga/vt3200.pcf      (iCE40 HX8K-CT256)
```

### Synthesis Outputs
```
vt3100/build/vt3100_ice40.json   (2.7 MB netlist)
vt3200/build/vt3200_ice40.json   (4.3 MB netlist)
```

---

## 7. Known Limitations

1. **SPI slave** (`spi_slave.v`) included in VT3100 RTL but not instantiated in top module
2. **VT3200 PLL** not included in RTL — assumes external PLL provides `clk_pwm`
3. **Analog blocks** (comparators, current sources, ADC) are off-chip for FPGA prototype
4. **Buck compensator** ADC calibration constants need tuning per power stage design
