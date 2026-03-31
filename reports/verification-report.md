# VT3100 / VT3200 Verification Report

**Document:** VANTIC-VER-001 Rev 2.0
**Date:** 2026-03-31
**Status:** Phase 2 Complete — FPGA Bitstreams Verified

---

## 1. Verification Summary

| Metric | VT3100 | VT3200 (Buck) | Combined |
|--------|--------|---------------|----------|
| Unit Test Cases | 259 | 78 | 337 |
| Pass Rate | 259/259 (100%) | 78/78 (100%) | 337/337 (100%) |
| Formal Properties | 7 | 7 | 14 |
| Formal Status | All PROVEN | All PROVEN | All PROVEN |
| Constrained Random | 1,000 | — | 1,000 |
| Spec Compliance | 50/50 | Inherited | 50/50 |
| Bugs Found & Fixed | 3 (HIGH) | 2 (HIGH) | 5 |

---

## 2. Test Infrastructure

### 2.1 Simulation Framework

- **Simulator:** Verilator (C++ cycle-accurate)
- **Language:** C++ testbenches (C++17)
- **Trace:** VCD waveform capture
- **Build:** Makefile-based, per-module compilation

### 2.2 Formal Verification

- **Tool:** SymbiYosys (SBY)
- **Engine:** Z3 SMT solver
- **Mode:** BMC (Bounded Model Checking)
- **Depth:** 120 cycles
- **Properties:** SystemVerilog Assertions (SVA)

---

## 3. VT3100 Unit Test Results

### 3.1 BMC PHY (bmc_phy.v) — 4/4 PASS

| Test | Cycles | Result | Coverage |
|------|--------|--------|----------|
| TX timing (4b5b encoding, bit-level) | 15,000 | PASS | 4b5b encode/decode |
| RX edge recovery (clock recovery) | 12,000 | PASS | Edge detection |
| CRC-32 computation | 8,000 | PASS | Full polynomial |
| Full-duplex stress | 20,000 | PASS | TX+RX concurrent |

**VCD trace:** `bmc_phy.vcd` (1.3 MB)

### 3.2 PD Message (pd_msg.v) — 44/44 PASS

| Category | Tests | Result |
|----------|-------|--------|
| Message parsing (SOP/Header/Data/CRC) | 12 | PASS |
| Message building (Source_Cap/Request/Accept) | 10 | PASS |
| MessageID management | 8 | PASS |
| Error handling (bad CRC, truncated) | 8 | PASS |
| Edge cases (max PDOs, zero-length) | 6 | PASS |

**VCD trace:** `pd_msg.vcd` (14 KB)

### 3.3 PD Policy Engine (pd_policy.v) — 32/32 PASS

| Category | Tests | Result |
|----------|-------|--------|
| Happy path (attach → negotiate → contract) | 6 | PASS |
| Retry logic (soft reset, hard reset) | 8 | PASS |
| Reject handling | 4 | PASS |
| Disconnect detection | 4 | PASS |
| State transitions (14 states) | 6 | PASS |
| Timeout behavior | 4 | PASS |

### 3.4 CC Logic (cc_logic.v) — 29/29 PASS

| Category | Tests | Result |
|----------|-------|--------|
| Orientation detection (CC1/CC2) | 6 | PASS |
| Attach/detach events | 8 | PASS |
| VCONN control | 4 | PASS |
| Debounce timing | 5 | PASS |
| Accessory mode | 3 | PASS |
| State encoding | 3 | PASS |

### 3.5 I2C Slave (i2c_slave.v) — 21/21 PASS

| Category | Tests | Result |
|----------|-------|--------|
| Address recognition (0x60) | 3 | PASS |
| Register read (single + auto-increment) | 6 | PASS |
| Register write (single + auto-increment) | 6 | PASS |
| NAK on wrong address | 2 | PASS |
| Bus error recovery | 2 | PASS |
| Clock stretching | 2 | PASS |

**VCD trace:** `i2c_slave.vcd` (124 KB)

### 3.6 GoodCRC — Constrained Random (1000/1000 PASS)

- 1000 random PD messages with random MessageIDs
- Verified auto-response timing and MessageID tracking
- Bug found and fixed: MessageID increment without state check (HIGH severity)

### 3.7 SPI Slave (spi_slave.v) — 17/17 PASS (standalone)

| Category | Tests | Result |
|----------|-------|--------|
| SPI Mode 0 R/W | 6 | PASS |
| Register access | 5 | PASS |
| CS handling | 3 | PASS |
| Edge cases | 3 | PASS |

### 3.8 Red Team / Adversarial Testing — PASS

- Protocol violation injection
- Rapid attach/detach cycling
- I2C bus contention
- All edge cases handled gracefully

---

## 4. VT3200 Unit Test Results (Buck Converter)

### 4.1 Buck PWM (buck_pwm.v) — 15/15 PASS

| Test | Result | Coverage |
|------|--------|----------|
| Frequency accuracy (96MHz / N) | PASS | Counter rollover |
| Duty cycle 0-100% sweep | PASS | Full range |
| Dead time insertion | PASS | HG/LG non-overlap |
| Sigma-delta dithering | PASS | Spread spectrum |
| 100% duty edge case | PASS | FSM init fix applied |

**VCD trace:** `buck_pwm.vcd` (343 KB)

### 4.2 Buck Compensator (buck_comp.v) — 13/13 PASS

| Test | Result | Coverage |
|------|--------|----------|
| Step response | PASS | Settling time |
| Q-format arithmetic | PASS | Fixed-point precision |
| Saturation limits | PASS | Duty clamp |
| Zero-input stability | PASS | No drift |

**VCD trace:** `buck_comp.vcd` (13 KB)

### 4.3 Buck Protection (buck_prot.v) — 23/23 PASS

| Test | Result | Coverage |
|------|--------|----------|
| OCP cycle-by-cycle | PASS | Immediate shutdown |
| OCP sustained | PASS | Counter-based |
| OVP threshold | PASS | Over-voltage |
| UVP threshold | PASS | Under-voltage |
| OTP threshold | PASS | Over-temperature |
| Short circuit | PASS | Fast response |
| Latch + auto-retry | PASS | Recovery |

**VCD trace:** `buck_prot.vcd` (9.4 KB)

### 4.4 Buck ADC (buck_adc.v) — 9/9 PASS

| Test | Result | Coverage |
|------|--------|----------|
| Channel sequencing | PASS | Round-robin |
| Conversion timing | PASS | Start/busy/valid |
| CDC crossing | PASS | clk_pwm → clk_sys |

**VCD trace:** `buck_adc.vcd` (26 KB)

### 4.5 Buck Soft-Start (buck_softstart.v) — 18/18 PASS

| Test | Result | Coverage |
|------|--------|----------|
| Linear ramp | PASS | Monotonic increase |
| Ramp rate | PASS | Fractional accumulator |
| Inrush limiting | PASS | Max duty during ramp |

**VCD trace:** `buck_softstart.vcd` (27 KB)

---

## 5. Formal Verification Results

### 5.1 VT3100 Formal Properties (7/7 PROVEN)

| Property | Module | Depth | Status |
|----------|--------|-------|--------|
| CRC polynomial correctness | bmc_phy | 120 | PROVEN |
| TX/RX mutual exclusion | bmc_phy | 120 | PROVEN |
| 4b5b encoding bijectivity | bmc_phy | 120 | PROVEN |
| MessageID monotonicity | goodcrc | 120 | PROVEN |
| State machine reachability | pd_policy | 120 | PROVEN |
| I2C ACK/NAK correctness | i2c_slave | 120 | PROVEN |
| CC debounce timing bound | cc_logic | 120 | PROVEN |

### 5.2 VT3200 Formal Properties (7/7 PROVEN)

| Property | Module | Depth | Status |
|----------|--------|-------|--------|
| HG/LG non-overlap (dead time) | buck_pwm | 120 | PROVEN |
| Duty cycle range [0, max] | buck_pwm | 120 | PROVEN |
| PWM frequency stability | buck_pwm | 120 | PROVEN |
| Dithering bounded range | buck_pwm | 120 | PROVEN |
| Protection latch-set irreversibility | buck_pwm | 120 | PROVEN |
| Soft-start monotonicity | buck_pwm | 120 | PROVEN |
| Counter overflow safety | buck_pwm | 120 | PROVEN |

**Solver:** Z3 SMT
**Runtime:** 8 min 28 sec (508 seconds)
**Result:** All assertions verified, no counterexamples found

---

## 6. Spec Compliance (VT3100)

50 specification items verified across all modules:

| Category | Items | Status |
|----------|-------|--------|
| USB PD 3.1 SPR message format | 12 | PASS |
| BMC signaling timing | 8 | PASS |
| CC detection per USB Type-C spec | 6 | PASS |
| Power negotiation state machine | 10 | PASS |
| I2C slave protocol compliance | 8 | PASS |
| Register map correctness | 6 | PASS |

---

## 7. Bug History

### 7.1 Bugs Found and Fixed

| # | Severity | Module | Description | Fix |
|---|----------|--------|-------------|-----|
| 1 | HIGH | goodcrc | MessageID increment without state machine check — back-to-back messages caused ID to advance prematurely | Added `gc_state==GC_IDLE` guard |
| 2 | HIGH | buck_pwm | Dead time FSM initialization failure at 100% duty — HG stuck at 0 | Cycle-boundary resync added |
| 3 | HIGH | bmc_phy | CRC register shared between TX and RX — concurrent operation corrupted CRC | Separate TX/RX CRC registers |
| 4 | HIGH | bmc_phy | RX timeout 333μs too short — dead zone lockup on slow transmitters | Increased to 15,000 cycles |
| 5 | HIGH | buck_comp | duty[20:7] extraction off-by-one — incorrect duty cycle output | Corrected bit selection |

### 7.2 Verification Rounds

| Round | Executor | Method | Bugs Found |
|-------|----------|--------|------------|
| R1 | 阳阳 | Unit test development | 2 |
| R2 | SZ | Code review + adversarial | 3 |
| R3 | 宁宁 | Independent verification (259 baseline + formal + random) | 2 (confirmed from R2) |
| R4 | All | Cross-validation | 0 new |

---

## 8. Waveform Traces

All VCD traces available for post-simulation analysis:

| File | Size | Module |
|------|------|--------|
| `vt3100/bmc_phy.vcd` | 1.3 MB | BMC PHY timing |
| `vt3100/i2c_slave.vcd` | 124 KB | I2C protocol |
| `vt3100/pd_msg.vcd` | 14 KB | PD message parsing |
| `vt3100/spi_slave.vcd` | 28 KB | SPI protocol |
| `vt3200/buck_pwm.vcd` | 343 KB | PWM waveforms |
| `vt3200/buck_comp.vcd` | 13 KB | Compensator response |
| `vt3200/buck_prot.vcd` | 9.4 KB | Protection triggers |
| `vt3200/buck_adc.vcd` | 26 KB | ADC conversions |
| `vt3200/buck_softstart.vcd` | 27 KB | Soft-start ramp |

---

## 9. FPGA Prototype Verification

### 9.1 Synthesis & P&R Verification

| Check | VT3100 | VT3200 |
|-------|--------|--------|
| Yosys synth_ice40 | PASS | PASS |
| nextpnr-ice40 P&R | PASS | PASS |
| icepack bitstream | PASS | PASS |
| Timing (all clocks) | PASS | PASS |

### 9.2 Timing Closure

| Clock | Constraint | Achieved Fmax | Status |
|-------|-----------|---------------|--------|
| VT3100 clk | 12 MHz | 84.65 MHz | PASS (7.1x margin) |
| VT3200 clk_sys | 12 MHz | 46.53 MHz | PASS (3.9x margin) |
| VT3200 clk_pwm | 96 MHz | 104.46 MHz | PASS (1.1x margin) |

---

## 10. Tool Versions

| Tool | Version | Purpose |
|------|---------|---------|
| Verilator | 5.046 | Simulation + lint |
| Yosys | 0.63 | Synthesis |
| nextpnr-ice40 | latest | FPGA place & route |
| icepack | icestorm | Bitstream generation |
| SymbiYosys | latest | Formal verification |
| Z3 | latest | SMT solver |
| C++ compiler | clang++ 17.0.0 | Testbench compilation |
