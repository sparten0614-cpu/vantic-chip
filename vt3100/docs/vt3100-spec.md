[VT3100 Spec 1/7] Sections 1-2: Product Overview + Supported Protocols
# VT3100 USB PD Protocol Controller — Product Specification

**Document Number:** VT3100-PS-001
**Revision:** 1.0
**Date:** 2026-03-20
**Status:** Engineering Review Draft
**Classification:** Confidential — Vantic Semiconductor

---

## Revision History

| Rev | Date       | Author         | Description            |
|-----|------------|----------------|------------------------|
| 1.0 | 2026-03-20 | Vantic Engineering | Initial release for RTL design review |

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [Supported Protocols](#2-supported-protocols)
3. [Functional Block Diagram](#3-functional-block-diagram)
4. [Pin Definition](#4-pin-definition)
5. [Electrical Characteristics](#5-electrical-characteristics)
6. [Register Map](#6-register-map)
7. [State Machine Description](#7-state-machine-description)
8. [Interface to Power Stage](#8-interface-to-power-stage)
9. [Application Circuit](#9-application-circuit)
10. [Design Constraints for RTL Implementation](#10-design-constraints-for-rtl-implementation)
11. [Compliance and Certification](#11-compliance-and-certification)

---

## 1. Product Overview

### 1.1 General Description

The VT3100 is a highly integrated USB Power Delivery (PD) protocol controller designed for the source side of USB Type-C chargers and adapters. It implements USB PD 3.1 Standard Power Range (SPR) along with all major proprietary fast-charging protocols, making it the ideal companion IC for GaN-based fast charging solutions.

The VT3100 integrates a USB PD PHY, multi-protocol engines for QC/AFC/SCP/VOOC/UFCS, CC logic, and configurable protection monitoring — eliminating the need for a separate MCU in most charger designs.

### 1.2 Key Features

- USB PD 3.1 SPR compliant (up to 100W), PPS support
- Multi-protocol support: QC4+, Samsung AFC, Huawei SCP/FCP, OPPO VOOC detection, UFCS, Apple 2.4A, BC 1.2
- Integrated CC logic with cable orientation detection
- 10-bit ADC for VBUS/IBUS/temperature monitoring
- I2C slave interface for host MCU configuration (optional — standalone operation supported)
- 4 configurable GPIOs for LED indication and power stage control
- OVP/OCP/OTP digital protection with configurable thresholds
- OTP (one-time programmable) memory for factory calibration and default configuration
- QFN-20 3x3mm package
- 55nm digital CMOS process
- Operating temperature: -40C to +105C (industrial grade)

### 1.3 Target Applications

- GaN USB-C fast chargers (20W to 100W)
- Multi-port USB-C chargers
- USB-C car chargers
- USB-C power banks
- USB-C power adapters for laptops

### 1.4 Ordering Information

| Part Number     | Package     | Temperature Range    | Marking |
|-----------------|-------------|----------------------|---------|
| VT3100-QN20     | QFN-20 3x3mm | -40C to +105C      | VT3100  |
| VT3100-QN20-TR  | QFN-20 3x3mm (tape & reel) | -40C to +105C | VT3100 |

**Target unit price:** 1.5-2.5 CNY at volume (100K+ units)

---

## 2. Supported Protocols

### 2.1 Protocol Summary Table

| Protocol | Version | Max Power | Voltage Range | Communication | Priority |
|----------|---------|-----------|---------------|---------------|----------|
| USB PD 3.1 SPR | Rev 3.1 V1.8 | 100W | 5/9/12/15/20V | CC (BMC) | 1 (highest) |
| USB PD 3.1 PPS | Rev 3.1 V1.8 | 100W | 3.3-21V (20mV step) | CC (BMC) | 1 |
| QC 4+ | Class A/B | 27W (Class A), 18W (Class B) | 3.6-20V | D+/D- | 2 |
| QC 3.0 | N/A | 18W | 3.6-20V (200mV step) | D+/D- | 2 |
| QC 2.0 | N/A | 18W | 5/9/12V | D+/D- | 2 |
| Samsung AFC | 2.0 | 25W | 9V/12V | D+/D- (pulse) | 3 |
| Huawei FCP | 1.0 | 18W | 5/9/12V | D+/D- | 4 |
| Huawei SCP | 1.0 | 40W (LVHC) | 3.3-5.5V @ 8A | D+/D- (proprietary) | 5 |
| OPPO VOOC | Detection only | N/A | N/A | D+/D- | 6 |
| UFCS | 1.0 | 100W | 5-36V | CC (UFCS PHY) or D+/D- | 7 |
| Apple 2.4A | Legacy | 12W | 5V @ 2.4A | D+/D- divider | 8 |
| BC 1.2 | 1.2 | 7.5W | 5V @ 1.5A | D+/D- | 9 (lowest) |

### 2.2 USB PD 3.1 SPR (Standard Power Range)

**Communication method:** Biphase Mark Coding (BMC) on CC line

**Supported Source Capabilities (configurable via register or OTP):**

| PDO # | Type | Voltage | Max Current | Power |
|--------|------|---------|-------------|-------|
| PDO 1 | Fixed | 5V | 3A | 15W |
| PDO 2 | Fixed | 9V | 3A | 27W |
| PDO 3 | Fixed | 12V | 3A | 36W |
| PDO 4 | Fixed | 15V | 3A | 45W |
| PDO 5 | Fixed | 20V | 5A | 100W |
| PDO 6 | PPS (APDO) | 3.3-11V | 5A | 55W |
| PDO 7 | PPS (APDO) | 3.3-21V | 5A | 100W |

Up to 4 Fixed PDOs and 2 Augmented PDOs (PPS) can be configured simultaneously via registers 0x05-0x0C. Default configuration is loaded from OTP memory at power-on.

**Negotiation behavior:**
1. Source advertises Source_Capabilities on CC after connection detection (within tFirstSourceCap, 100-350ms after VBUS reaches vSafe5V).
2. Sink responds with a Request message selecting one of the advertised PDOs.
3. Source evaluates the request against current capability (GiveBack supported if enabled).
4. Source sends Accept and transitions the power supply to the requested voltage.
5. Source sends PS_RDY when output voltage is within the requested range.
6. For PPS: Source responds to periodic PPS requests from the Sink (every 10s max, tPPSTimeout = 14s).

**PD 3.1 SPR message support:**
- Source_Capabilities, Accept, Reject, PS_RDY, GotoMin (optional)
- Get_Source_Cap, Get_Sink_Cap (for dual-role if applicable)
- Soft_Reset, Hard_Reset (with tSafe0V / tSafe5V timing)
- Not_Supported for unsupported messages
- Alert (for OCP/OTP events)
- Status (extended message)
- Vendor_Defined (passthrough to I2C host)

### 2.3 USB PD 3.1 PPS (Programmable Power Supply)

**Communication method:** BMC on CC line (same physical layer as PD)

**PPS-specific behavior:**
- Augmented PDO (APDO) advertised in Source_Capabilities
- Voltage programmable in 20mV steps within the APDO range
- Current limit programmable in 50mA steps
- Sink sends periodic PPS_Status requests; VT3100 must respond within tPPSRequest (10s)
- If no PPS request received within tPPSTimeout (14s), VT3100 initiates Hard Reset
- Output voltage accuracy: +/- 100mV (depends on external power stage DAC resolution)
- Current limit accuracy: +/- 150mA (depends on external current sense)

### 2.4 Qualcomm Quick Charge 4+ (QC4+)

**Communication method:** D+ and D- voltage levels

**QC4+ incorporates QC 2.0 and QC 3.0 backward compatibility.**

**Class A (up to 27W):**
- 5V/3A, 9V/3A, 12V/2.25A, 20V/1.35A fixed
- Continuous mode: 3.6-20V in 200mV steps (QC 3.0 mode)

**Class B (up to 18W):**
- 5V/3A, 9V/2A, 12V/1.5A fixed
- Continuous mode: 3.6-12V in 200mV steps

**Trigger condition:** After PD negotiation fails (no PD-capable sink detected within tNoResponse = 5.5s), VT3100 monitors D+ for QC handshake.

**QC detection sequence:**
1. Sink applies 0.6V on D+ (HVDCP handshake)
2. VT3100 responds with 3.3V on D- (DCP identification)
3. Sink pulses D+ to request voltage change:
   - D+ = 0.6V, D- = 0V: 5V
   - D+ = 3.3V, D- = 0.6V: 9V
   - D+ = 0.6V, D- = 0.6V: 12V
   - D+ = 3.3V, D- = 3.3V: 20V
4. QC 3.0 continuous mode: D+ pulses (+200mV per pulse up, -200mV per pulse down)

**Internal D+/D- driver:** Resistive voltage divider with programmable output levels (0V, 0.6V, 3.3V). Absolute accuracy +/- 5%.

### 2.5 Samsung AFC (Adaptive Fast Charging)

**Communication method:** D+ and D- pulse signaling

**Supported voltages:** 9V (default), 12V (configurable)
**Maximum current:** 2.77A at 9V (25W)

**Trigger condition:** After QC handshake timeout (500ms), VT3100 begins AFC detection.

**AFC negotiation sequence:**
1. VT3100 presents DCP mode (D+ and D- shorted at 1.2V)
2. Sink sends AFC ping on D+ (pulse train)
3. VT3100 responds with byte encoding on D+: target voltage selection
4. Sink acknowledges and VT3100 transitions output to requested voltage
5. Repeated voltage negotiation supported (sink can re-request)

**D+ voltage encoding for AFC:**
- Each bit transmitted as voltage level on D+ (0.6V = 0, 3.3V = 1)
- Byte format: 8 bits, MSB first, with start/stop conditions
- Clock recovery from pulse edges

### 2.6 Huawei FCP (Fast Charge Protocol)

**Communication method:** D+ and D- signaling (similar to QC but with Huawei-specific handshake)

**Supported voltages:** 5V, 9V, 12V
**Maximum current:** 2A at 9V (18W)

**Trigger condition:** After AFC detection timeout, VT3100 attempts FCP handshake.

**FCP negotiation:**
1. VT3100 presents DCP mode
2. Sink initiates FCP handshake sequence on D+/D-
3. Half-duplex communication on D+ using proprietary encoding
4. Sink reads adapter capability register (voltage/current support)
5. Sink writes target voltage to adapter control register
6. VT3100 transitions power supply and acknowledges

### 2.7 Huawei SCP (Super Charge Protocol)

**Communication method:** D+ and D- half-duplex UART-like signaling

**Mode:** Low Voltage High Current (LVHC)
**Voltage range:** 3.3-5.5V
**Maximum current:** 8A (40W at 5V/8A)

**Trigger condition:** SCP detection runs in parallel with FCP. The sink initiates SCP-specific handshake if it supports the protocol.

**SCP communication:**
- Half-duplex serial communication on D+ line (D- used for signaling ground reference)
- Baud rate: approximately 250 kbps
- Packet structure: header + command + data + CRC
- VT3100 implements SCP slave state machine responding to sink commands
- Sink controls output voltage in fine steps (10mV resolution)
- Sink controls current limit
- VT3100 reports real-time VBUS voltage, current, and temperature via SCP telemetry

**Note:** SCP requires the power stage to support high-current low-voltage output with very tight regulation (cable IR drop compensation done by sink).

### 2.8 OPPO VOOC / SuperVOOC

**Communication method:** D+ and D- proprietary signaling

**VT3100 support level:** Protocol detection and identification ONLY. Full VOOC/SuperVOOC requires a licensed OPPO protocol IC. The VT3100 can detect when a VOOC device is connected and signal this via GPIO/interrupt to an external VOOC controller IC.

**Detection method:**
1. Monitor D+ and D- for VOOC-specific handshake pattern
2. If VOOC pattern detected, set VOOC_DET flag in status register
3. Assert interrupt (if enabled) and GPIO (if configured)
4. Do NOT attempt to negotiate; defer to external VOOC IC

### 2.9 UFCS (Universal Fast Charging Specification)

**Communication method:** CC line (UFCS PHY, coexisting with USB PD) or D+/D- (legacy mode)

**Supported power profiles (configurable):**
- 5V/3A, 9V/3A, 12V/3A, 15V/3A, 20V/5A
- Programmable voltage: 3.4-21V in 10mV steps
- Programmable current: 50mA steps

**UFCS is mandatory for new chargers sold in China (GB/T standard). VT3100 implements UFCS 1.0 specification.**

**UFCS features:**
- Source capability broadcast (similar to PD Source_Capabilities)
- Voltage and current negotiation with fine granularity
- Real-time telemetry (voltage, current, temperature reported to sink)
- Error detection and recovery
- Coexistence with USB PD on the same CC line (time-division multiplexing)
- VT3100 prioritizes USB PD over UFCS if both are attempted simultaneously

**Trigger condition:** If USB PD negotiation completes but sink also supports UFCS, the sink may initiate UFCS communication. VT3100 can also fall back to UFCS when PD is not supported by the sink.

### 2.10 Apple 2.4A

**Communication method:** D+ and D- resistor divider identification

**Voltage divider values:**
- D+ = 2.7V (via internal 75K/49.9K divider from VDD to GND)
- D- = 2.0V (via internal 75K/68K divider)

**Trigger condition:** Default state when no higher-priority protocol is detected and BC 1.2 DCP enumeration is active.

**Behavior:** VT3100 presents the Apple-specific D+/D- divider voltages to indicate 2.4A capability at 5V. This is a static identification — no active communication.

### 2.11 BC 1.2 (Battery Charging Specification 1.2)

**Communication method:** D+ and D- detection per USB BC 1.2 specification

**Supported modes:**
- **DCP (Dedicated Charging Port):** D+ and D- shorted through < 200 ohm. Advertises up to 1.5A at 5V.
- **CDP (Charging Downstream Port):** Not typically used in charger (host-side), but VT3100 can emulate CDP for specific applications via register configuration.

**Trigger condition:** BC 1.2 is the lowest-priority protocol. Active as the default identification method when no fast-charging protocol is successfully negotiated.

**Detection sequence:**
1. VT3100 shorts D+ and D- internally (DCP mode)
2. Sink detects DCP and draws up to 1.5A
3. If sink initiates a higher-priority protocol handshake, VT3100 releases D+/D- short and transitions to the appropriate protocol engine

### 2.12 Protocol Detection Priority and Fallback

The VT3100 follows a strict priority order for protocol detection after a USB Type-C connection is established:

```
Power On
  |
  v
CC Detection (Rp assertion, orientation detection)
  |
  v
VBUS 5V Output Enabled (default safe voltage)
  |
  v
[Priority 1] USB PD Negotiation (wait tNoResponse = 5.5s for PD sink)
  |-- PD Success --> PD contract established, monitor for PPS/UFCS
  |-- PD Timeout --> fall through
  v
[Priority 2] QC Detection (D+/D- handshake, wait 1.5s)
  |-- QC Success --> QC mode active
  |-- QC Timeout --> fall through
  v
[Priority 3] AFC Detection (D+ pulse, wait 500ms)
  |-- AFC Success --> AFC mode active
  |-- AFC Timeout --> fall through
  v
[Priority 4] FCP Detection (D+ signaling, wait 500ms)
  |-- FCP Success --> FCP mode active
  |-- FCP Timeout --> fall through
  v
[Priority 5] SCP Detection (concurrent with FCP, wait 500ms)
  |-- SCP Success --> SCP mode active
  |-- SCP Timeout --> fall through
  v
[Priority 6] VOOC Detection (D+/D- pattern match, wait 200ms)
  |-- VOOC Detected --> set flag, assert GPIO/IRQ
  |-- Not Detected --> fall through
  v
[Priority 7] UFCS Fallback (if not already negotiated via PD coexistence)
  |-- UFCS Success --> UFCS mode active
  |-- UFCS Timeout --> fall through

[VT3100 Spec 2/7] Section 3-4: Functional Block Diagram + Pin Definition
  v
[Priority 8] Apple 2.4A / BC 1.2 DCP (static D+/D- divider)
  |-- Default state: 5V output with DCP + Apple divider
```

**Notes on priority:**
- Individual protocols can be disabled via control register (0x03-0x04). Disabled protocols are skipped during detection.
- If a higher-priority protocol was active and the sink disconnects/reconnects, the full detection sequence restarts.
- During QC/AFC/SCP/FCP detection, VBUS remains at 5V (safe default).
- Protocol switching (e.g., QC to PD on re-attach) follows a disconnect-first model — no live protocol switching.

---

## 3. Functional Block Diagram

```
                          +-----------------------------------------------+
                          |                  VT3100                        |
                          |                                               |
    CC1 ----+---------+---| CC1 PAD --> CC Logic  --> PD PHY (BMC)  ---+  |
             |         |   |             (Rp/Rd/Ra   (Encode/Decode)   |  |
    CC2 ----+---------+---| CC2 PAD     detect,                       |  |
             |             |             orientation)                  |  |
             |             |                |                          |  |
             |             |                v                          |  |
             |             |         PD Protocol Layer                 |  |
             |             |         (Source State Machine,            |  |
             |             |          Capability Management,           |  |
             |             |          Policy Engine)                   |  |
             |             |                |                          |  |
             |             |                v                          |  |
             |             |         +------+------+                   |  |
             |             |         | Protocol    |                   |  |
             |             |         | Arbitrator  |<--- UFCS Engine --+  |
             |             |         | (Priority   |                      |
             |             |         |  Mux)       |                      |
             |             |         +------+------+                      |
             |             |                |                              |
    D+ ------+-------------| D+ PAD -----> QC/AFC/SCP/FCP Engines --------+
    D- ------+-------------| D- PAD -----> (D+/D- voltage drivers,        |
             |             |               dividers, pulse detector)       |
             |             |                                               |
             |             |         +------------------+                  |
  ADC_VBUS --+-------------| ------> |                  |                  |
  ADC_IBUS --+-------------| ------> |  10-bit SAR ADC  |----> Protection  |
  ADC_TEMP --+-------------| ------> |  (mux + convert) |     Logic (OVP/ |
             |             |         +------------------+      OCP/OTP)   |
             |             |                                     |         |
    VBUS ----+-------------| VBUS Sense (resistive divider)      |         |
             |             |                                     |         |
    SDA  ----+-------------| I2C Slave Interface <--> Register   |         |
    SCL  ----+-------------|          (400kHz)        File       |         |
             |             |                          (0x00-0x1F)|         |
             |             |                            ^        |         |
             |             |                            |        v         |
   GPIO0 ----+-------------| GPIO Controller <----------+--------+         |
   GPIO1 ----+-------------|   (4 pins,                                    |
   GPIO2 ----+-------------|    configurable I/O,                          |
   GPIO3 ----+-------------|    push-pull / open-drain)                    |
             |             |                                               |
             |             |  +-------------------+  +------------------+  |
    VDD  ----+-------------|- | Power Management  |  | OTP Memory       |  |
    VDD5 ----+-------------|- | (POR, LDO, BOD)   |  | (256 bits,       |  |
    GND  ----+-------------|- |                    |  |  trim + config)  |  |
             |             |  +-------------------+  +------------------+  |
             |             |                                               |
             |             |  +-------------------+                        |
             |             |  | Clock Generator   |                        |
             |             |  | (Internal RC OSC  |                        |
             |             |  |  12MHz, trimmed)   |                        |
             |             |  +-------------------+                        |
             |             |                                               |
             |             |  +-------------------+                        |
             |             |  | Scan / DFT Logic  |                        |
             |             |  +-------------------+                        |
             |             +-----------------------------------------------+
```

### 3.1 Block Descriptions

#### 3.1.1 USB Type-C CC Logic

**Function:** Detects USB Type-C cable attachment, determines cable orientation, and manages Rp/Rd/Ra pull-up/pull-down resistors on CC1 and CC2.

**Sub-blocks:**
- **Rp current source (programmable):** Three levels per USB Type-C spec:
  - Default USB Power: 80uA (indicates 900mA / USB 3.1 default)
  - 1.5A: 180uA
  - 3.0A: 330uA
- **CC voltage comparators:** Detect Rd (sink), Ra (active cable), and open states
- **Orientation detection logic:** Determines which CC line has the sink Rd pull-down
- **VCONN switch control:** Optional VCONN source on unused CC pin (for active cables)

**Electrical specs:**
- Rp accuracy: +/- 8% over temperature and voltage
- CC voltage detection thresholds per USB Type-C spec Table 4-36
- Debounce timer: tCCDebounce = 100-200ms (configurable)

#### 3.1.2 PD PHY (BMC Encoder/Decoder)

**Function:** Physical layer for USB PD communication on the CC line. Implements Biphase Mark Coding (BMC) per USB PD specification.

**Features:**
- BMC modulation at 300kHz (+/- 10% = 270-330kHz)
- 4b5b encoding/decoding
- CRC-32 generation and checking
- Preamble detection (minimum 55 bits)
- SOP/SOP'/SOP'' detection (for cable communication)
- Collision avoidance (for dual-role, future extension)
- GoodCRC automatic response generation (hardware-accelerated)

**Timing:**
- tBMCTimeout: 4.5-5.5ms (inter-byte timeout)
- tReceive: complete message reception within specification limits
- tTransmit: message transmission start within 195us of CRCReceiveTimer expiry

#### 3.1.3 PD Protocol Layer (Source State Machine)

**Function:** Implements the USB PD Source policy engine and protocol layer state machines.

**Key state machines:**
- Source Startup state machine
- Source Capability state machine (send/resend Source_Capabilities)
- Source Negotiation state machine (evaluate Request, Accept/Reject)
- Source Transition state machine (voltage transition, PS_RDY)
- Hard Reset state machine
- Soft Reset state machine

**Policy engine features:**
- PDO management (read from register file, configurable at runtime)
- Request evaluation (current capability check, GiveBack support)
- Power supply voltage transition sequencing
- PPS periodic request monitoring
- Extended message support (Status, Alert, Manufacturer_Info)

#### 3.1.4 QC/AFC/SCP/FCP Protocol Engines

**Function:** Implements proprietary fast-charging protocols using D+ and D- signaling.

**Shared resources:**
- D+ driver: programmable voltage output (0V, 0.6V, 2.0V, 2.7V, 3.3V) via resistive DAC
- D- driver: programmable voltage output (same levels)
- D+ comparator: multi-threshold (0.325V, 0.6V, 2.0V, 3.3V thresholds)
- D- comparator: multi-threshold
- Pulse detector: edge counter and timing measurement for AFC/SCP signaling
- D+/D- short switch: for BC 1.2 DCP mode

**Per-protocol state machines:**
- QC engine: HVDCP detection, class negotiation, continuous mode voltage tracking
- AFC engine: pulse train decoder, byte encoder/decoder, voltage transition
- FCP engine: register-based communication state machine
- SCP engine: UART-like half-duplex communication, packet framing, CRC

#### 3.1.5 UFCS Protocol Engine

**Function:** Implements UFCS 1.0 specification for China-standard fast charging.

**Features:**
- UFCS PHY on CC line (coexists with USB PD via time-division)
- Source capability broadcast
- Fine-grained voltage and current negotiation
- Real-time telemetry reporting
- Handshake and authentication
- Error recovery and timeout handling

#### 3.1.6 Configuration Interface (I2C Slave)

**Function:** Provides I2C slave interface for external MCU to configure VT3100 parameters and read status.

**Features:**
- 7-bit slave address: 0x60 (default), configurable via OTP
- Standard mode (100kHz) and Fast mode (400kHz) support
- Clock stretching supported
- Register-based access (address auto-increment)
- Interrupt output (active-low, open-drain on GPIO0 by default)

#### 3.1.7 GPIO Controller

**Function:** Manages 4 general-purpose I/O pins with configurable function.

**Per-pin configuration:**
- Direction: input or output
- Output type: push-pull or open-drain
- Pull-up/pull-down: internal 50K pull-up or pull-down (optional)
- Alternate function: interrupt output, VBUS_EN, FAULT_IN, LED drive, protocol detection flag
- Drive strength: 8mA sink/source

**Default pin functions (after POR or OTP load):**

| GPIO | Default Function | Direction | Description |
|------|------------------|-----------|-------------|
| GPIO0 | INT_N | Output (OD) | Active-low interrupt to host MCU |
| GPIO1 | VBUS_EN | Output (PP) | Enable VBUS output on power stage |
| GPIO2 | FAULT_N | Input | Fault signal from power stage (active low) |
| GPIO3 | LED | Output (PP) | Status LED drive |

#### 3.1.8 OVP/OCP/OTP Digital Monitoring Logic

**Function:** Monitors VBUS voltage, output current, and die temperature via the integrated ADC and compares against programmable thresholds.

**Protection features:**

| Protection | Source | Threshold Range | Default | Response Time | Action |
|------------|--------|-----------------|---------|---------------|--------|
| OVP (Over-Voltage) | ADC_VBUS | 5.5V - 28V | 22V | < 100us (comparator), < 1ms (ADC) | Deassert VBUS_EN, set fault flag |
| OCP (Over-Current) | ADC_IBUS | 0.5A - 6A | 3.5A | < 1ms (ADC) | Deassert VBUS_EN, set fault flag |
| OTP (Over-Temperature) | ADC_TEMP | 80C - 150C | 120C | < 10ms (ADC) | Deassert VBUS_EN, set fault flag |

**Note:** The VT3100 uses the ADC for software-monitored protection. For fast hardware OVP (< 1us), an external fast comparator with blanking is recommended. The ADC_VBUS pin also connects to an analog comparator for coarse OVP detection (threshold at ~24V, fixed).

**Fault recovery:**
- Auto-retry after fault clearance (configurable: 1/2/4 retries or disabled)
- Retry interval: 500ms (configurable: 250ms / 500ms / 1s / 2s)
- Latch mode: fault latched until cleared by I2C write or power cycle

#### 3.1.9 Power-On Reset and Clock Generation

**POR (Power-On Reset):**
- VDD rising threshold: 2.7V (typical), 2.5V (minimum)
- VDD falling threshold (brown-out): 2.4V (typical)
- POR deglitch time: 10us
- POR release to active: < 1ms

**Clock generation:**
- Internal RC oscillator: 12MHz (trimmed to +/- 2% at 25C, +/- 5% over temperature)
- Trim value stored in OTP memory (factory calibrated)
- Optional external 12MHz crystal input on two dedicated pads (shared with GPIO2/GPIO3 in alternate function mode)
- PLL: none (single 12MHz clock domain for simplicity)
- Clock dividers: /1 (12MHz for digital logic), /4 (3MHz for ADC), /40 (300kHz for BMC)

#### 3.1.10 Trim/OTP Memory

**Function:** 256-bit one-time programmable memory for factory calibration and default configuration.

**OTP fields:**

| Bits | Field | Description |
|------|-------|-------------|
| [7:0] | RC_TRIM | Internal oscillator frequency trim |
| [15:8] | ADC_OFFSET | ADC offset calibration |
| [23:16] | ADC_GAIN | ADC gain calibration |
| [31:24] | Rp_TRIM | CC Rp current source trim |
| [39:32] | I2C_ADDR | I2C slave address (default 0x60) |
| [71:40] | DEFAULT_PDO_CONFIG | Default source PDO configuration (compressed) |
| [79:72] | PROTOCOL_ENABLE | Default protocol enable mask |
| [87:80] | OVP_THRESHOLD | Default OVP threshold |
| [95:88] | OCP_THRESHOLD | Default OCP threshold |
| [103:96] | GPIO_CONFIG | Default GPIO configuration |
| [127:104] | RESERVED | Reserved for future use |
| [255:128] | CUSTOMER_AREA | Available for customer-specific configuration |

**OTP programming:**
- Programmed at wafer sort or final test via I2C command sequence
- Programming voltage: VDD + internal charge pump (no external high voltage needed)
- Programming verification: read-back and compare
- One-time only — no re-programming after fuse blow

---

## 4. Pin Definition

### 4.1 Package: QFN-20, 3x3mm, 0.4mm pitch

**Pin count:** 20 + exposed pad (EP)

```
        Pin 1 indicator
        |
   +---------+
   |20 ... 16|
 1 |         | 15
 2 |   EP    | 14
 3 |  (GND)  | 13
 4 |         | 12
 5 |         | 11
   | 6 ... 10|
   +---------+
```

### 4.2 Pin Map Table

| Pin # | Name      | Type       | I/O Direction | Description                                        | Default State |
|-------|-----------|------------|---------------|----------------------------------------------------|---------------|
| 1     | CC1       | Analog/Digital | I/O       | USB Type-C CC1 pin. Rp/Rd/Ra, BMC, UFCS.          | Rp pull-up (default USB power) |
| 2     | CC2       | Analog/Digital | I/O       | USB Type-C CC2 pin. Rp/Rd/Ra, BMC, UFCS.          | Rp pull-up (default USB power) |
| 3     | VBUS_SNS  | Analog     | Input         | VBUS voltage sense. Resistive divider input (0-28V range mapped to 0-3.3V). | High-Z |
| 4     | DP        | Analog/Digital | I/O       | USB D+ for QC/AFC/SCP/FCP/BC1.2 protocols.        | High-Z |
| 5     | DN        | Analog/Digital | I/O       | USB D- for QC/AFC/SCP/FCP/BC1.2 protocols.        | High-Z |
| 6     | VDD       | Power      | Supply        | Digital core supply, 3.0-3.6V.                     | N/A |
| 7     | GND       | Power      | Ground        | Digital ground.                                     | N/A |
| 8     | VDD5      | Power      | Supply        | 5V input supply (from VBUS via LDO or external regulator). Powers internal 3.3V LDO if VDD not separately supplied. | N/A |
| 9     | ADC_VBUS  | Analog     | Input         | ADC input for VBUS voltage monitoring. Connect via external resistive divider. Full-scale = 3.3V. | High-Z |
| 10    | ADC_IBUS  | Analog     | Input         | ADC input for output current monitoring. Connect via external current sense amplifier. Full-scale = 3.3V. | High-Z |
| 11    | ADC_TEMP  | Analog     | Input         | ADC input for temperature monitoring. Connect to external NTC thermistor divider. Full-scale = 3.3V. | High-Z |
| 12    | SDA       | Digital    | I/O (OD)      | I2C data. Open-drain, requires external 4.7K pull-up to VDD. | High-Z (input) |
| 13    | SCL       | Digital    | Input         | I2C clock. Requires external 4.7K pull-up to VDD.  | High-Z (input) |
| 14    | GPIO0     | Digital    | I/O           | General purpose I/O. Default: INT_N (active-low interrupt, open-drain). | Open-drain high (via ext pull-up) |
| 15    | GPIO1     | Digital    | I/O           | General purpose I/O. Default: VBUS_EN (push-pull output). | Low (VBUS disabled) |
| 16    | GPIO2     | Digital    | I/O           | General purpose I/O. Default: FAULT_N (input, active-low). Alt: XTAL_IN. | Input with pull-up |
| 17    | GPIO3     | Digital    | I/O           | General purpose I/O. Default: LED drive (push-pull). Alt: XTAL_OUT. | Low |
| 18    | TEST      | Digital    | Input         | Test mode entry. Connect to GND via 10K resistor in production. Pull to VDD to enter test/scan mode. | Low (normal operation) |
| 19    | NC        | -          | -             | No connect. Leave floating or connect to GND.       | - |
| 20    | NC        | -          | -             | No connect. Leave floating or connect to GND.       | - |
| EP    | GND (EP)  | Power      | Ground        | Exposed pad. Must be soldered to ground plane for thermal and electrical ground. | N/A |

### 4.3 Pin Notes

1. **CC1/CC2:** These pins handle multiple functions — analog Rp current source, digital BMC communication, and UFCS PHY signaling. Internally multiplexed. Maximum voltage: 5.5V. ESD protection: 8kV HBM.

2. **VBUS_SNS:** Direct VBUS sense input for cable orientation confirmation and protocol-level VBUS monitoring. Internally connected to a resistive divider (8:1) for safe ADC sampling of voltages up to 28V. Do NOT connect directly to VBUS without external divider if VBUS can exceed 3.6V on this pin.

3. **DP/DN:** These pins are internally connected to programmable voltage drivers and comparators for D+/D- based protocols. Maximum voltage: 3.6V. ESD protection: 8kV HBM. When USB PD is active (CC-based communication), D+/D- are in high-impedance state.

4. **VDD5:** Input for the internal LDO that generates VDD. If VDD is supplied externally (e.g., from a system 3.3V rail), VDD5 can be left unconnected (internal LDO disabled via OTP setting). If VDD5 is used, connect a 1uF decoupling capacitor close to the pin.

5. **ADC inputs:** All three ADC inputs share a single 10-bit SAR ADC via an internal multiplexer. Conversion is sequential: VBUS -> IBUS -> TEMP, round-robin at approximately 1 kSPS per channel (total ADC rate: 3 kSPS). Input impedance: > 1M ohm. External signal conditioning (divider for VBUS, amplifier for IBUS, NTC divider for TEMP) is required.

6. **TEST pin:** For manufacturing test only. When high, the VT3100 enters scan test mode with scan chain accessible on GPIO pins. Must be held low in normal operation.

---

## 5. Electrical Characteristics

### 5.1 Absolute Maximum Ratings

| Parameter | Symbol | Min | Max | Unit |
|-----------|--------|-----|-----|------|
| VDD supply voltage | VDD_MAX | -0.3 | 4.0 | V |
| VDD5 supply voltage | VDD5_MAX | -0.3 | 6.0 | V |
| CC1/CC2 pin voltage | VCC_MAX | -0.3 | 6.0 | V |

[VT3100 Spec 3/7] Section 5: Electrical Characteristics
| VBUS_SNS pin voltage | VBUS_SNS_MAX | -0.3 | 30 | V |
| DP/DN pin voltage | VDP_MAX | -0.3 | 4.0 | V |
| ADC input pin voltage | VADC_MAX | -0.3 | 3.6 | V |
| GPIO pin voltage | VGPIO_MAX | -0.3 | 4.0 | V |
| Storage temperature | T_STG | -65 | 150 | C |
| ESD (HBM) — CC, VBUS_SNS | | | +/- 8 | kV |
| ESD (HBM) — DP, DN, GPIO | | | +/- 4 | kV |
| ESD (HBM) — all other pins | | | +/- 2 | kV |
| ESD (CDM) — all pins | | | +/- 1 | kV |

**Stresses beyond Absolute Maximum Ratings may cause permanent damage. Functional operation at these conditions is not implied.**

### 5.2 Recommended Operating Conditions

| Parameter | Symbol | Min | Typ | Max | Unit |
|-----------|--------|-----|-----|-----|------|
| VDD supply voltage | VDD | 3.0 | 3.3 | 3.6 | V |
| VDD5 supply voltage | VDD5 | 4.5 | 5.0 | 5.5 | V |
| Operating temperature | T_OP | -40 | 25 | 105 | C |
| I2C SCL frequency | f_SCL | 0 | - | 400 | kHz |

### 5.3 DC Electrical Characteristics (VDD = 3.3V, T = 25C unless otherwise noted)

| Parameter | Symbol | Min | Typ | Max | Unit | Condition |
|-----------|--------|-----|-----|-----|------|-----------|
| **Supply Current** | | | | | | |
| Active mode supply current (PD negotiating) | IDD_ACTIVE | - | 5 | 10 | mA | Continuous PD communication |
| Idle mode supply current (attached, no PD traffic) | IDD_IDLE | - | 2 | 4 | mA | Protocol negotiated, monitoring |
| Standby supply current (unattached) | IDD_STBY | - | 50 | 100 | uA | CC monitoring only |
| **CC Pin** | | | | | | |
| Rp current — Default USB | Irp_def | 72 | 80 | 88 | uA | VDD = 3.3V |
| Rp current — 1.5A | Irp_1A5 | 162 | 180 | 198 | uA | VDD = 3.3V |
| Rp current — 3.0A | Irp_3A | 297 | 330 | 363 | uA | VDD = 3.3V |
| CC comparator threshold — Rd detect | V_Rd_det | - | 0.2 | - | V | Per USB Type-C spec |
| CC comparator threshold — Ra detect | V_Ra_det | - | 0.8 | - | V | Per USB Type-C spec |
| CC debounce time | tCC_debounce | 100 | 150 | 200 | ms | Configurable |
| **BMC PHY** | | | | | | |
| BMC bit rate | f_BMC | 270 | 300 | 330 | kHz | +/- 10% per PD spec |
| BMC transmit amplitude | V_BMC_TX | 1.0 | 1.15 | 1.3 | V | On CC, peak-to-peak |
| BMC receive sensitivity | V_BMC_RX | 0.3 | - | - | V | Minimum detectable amplitude |
| **D+/D- Interface** | | | | | | |
| D+ output voltage levels | V_DP | 0 | - | 3.3 | V | Programmable: 0, 0.6, 2.0, 2.7, 3.3V |
| D+ output voltage accuracy | | -5 | - | +5 | % | Over temperature |
| D+ input threshold (QC detect) | V_DP_TH | 0.3 | 0.325 | 0.35 | V | Low threshold |
| D+/D- short resistance (DCP mode) | R_DCP | - | 100 | 200 | ohm | Per BC 1.2 spec |
| **ADC** | | | | | | |
| Resolution | | - | 10 | - | bits | |
| INL | | - | - | +/- 2 | LSB | |
| DNL | | - | - | +/- 1 | LSB | |
| Conversion rate (total, round-robin) | f_ADC | - | 3 | - | kSPS | 1 kSPS per channel |
| Input impedance | R_ADC_IN | 1 | - | - | M ohm | |
| Full-scale voltage | V_ADC_FS | - | 3.3 | - | V | Equals VDD |
| **I2C Interface** | | | | | | |
| Input low threshold | V_IL_I2C | - | - | 0.3*VDD | V | |
| Input high threshold | V_IH_I2C | 0.7*VDD | - | - | V | |
| SDA output low voltage | V_OL_SDA | - | - | 0.4 | V | I_sink = 3mA |
| **GPIO** | | | | | | |
| Output high voltage (push-pull) | V_OH_GPIO | VDD-0.4 | - | - | V | I_source = 8mA |
| Output low voltage | V_OL_GPIO | - | - | 0.4 | V | I_sink = 8mA |
| Input low threshold | V_IL_GPIO | - | - | 0.3*VDD | V | |
| Input high threshold | V_IH_GPIO | 0.7*VDD | - | - | V | |
| Internal pull-up resistance | Rpu_GPIO | 30 | 50 | 80 | K ohm | |
| Internal pull-down resistance | Rpd_GPIO | 30 | 50 | 80 | K ohm | |
| **Internal Oscillator** | | | | | | |
| Frequency | f_OSC | 11.4 | 12.0 | 12.6 | MHz | After trim, 25C |
| Frequency accuracy (over temp) | | -5 | - | +5 | % | -40C to +105C |
| **Internal LDO (VDD5 to VDD)** | | | | | | |
| Output voltage | V_LDO | 3.2 | 3.3 | 3.4 | V | VDD5 = 5.0V |
| Dropout voltage | V_DO | - | 0.5 | 0.8 | V | I_load = 15mA |
| Load regulation | | - | 1 | 3 | % | 0 to 15mA |
| PSRR | | 40 | 50 | - | dB | f = 100kHz |
| **POR** | | | | | | |
| VDD rising threshold | V_POR_R | 2.5 | 2.7 | 2.9 | V | |
| VDD falling threshold (BOD) | V_POR_F | 2.2 | 2.4 | 2.6 | V | |
| POR deglitch time | t_POR | - | 10 | - | us | |

### 5.4 Timing Characteristics

| Parameter | Symbol | Min | Typ | Max | Unit | Notes |
|-----------|--------|-----|-----|-----|------|-------|
| Power-on to ready | t_POR2RDY | - | 5 | 10 | ms | OTP load + calibration |
| CC detection to VBUS enable | t_CC2VBUS | - | - | 275 | ms | tVBUSon per Type-C spec |
| Source_Capabilities first send | tFirstSourceCap | 100 | 150 | 350 | ms | After vSafe5V reached |
| PD negotiation timeout | tNoResponse | - | - | 5.5 | s | If no GoodCRC received |
| tSafe5V (hard reset to 5V) | tSafe5V | - | - | 800 | ms | |
| tSafe0V (VBUS discharge) | tSafe0V | - | - | 650 | ms | |
| tSrcRecover | tSrcRecover | 660 | - | 1000 | ms | After hard reset |
| PPS request timeout | tPPSTimeout | - | - | 14 | s | |
| ADC full conversion cycle | t_ADC_cycle | - | 1 | - | ms | 3 channels round-robin |
| GPIO output transition time | t_GPIO | - | 10 | 20 | ns | 30pF load |
| I2C start to data ready | t_I2C_ready | - | - | 5 | us | After START condition |

---

## 6. Register Map

### 6.1 Register Summary

All registers are 8-bit. Multi-byte fields are stored in little-endian order (LSB at lower address).

| Address | Name | Default | Access | Description |
|---------|------|---------|--------|-------------|
| 0x00 | DEV_ID | 0x31 | R | Device ID (0x31 = VT3100) |
| 0x01 | DEV_REV | 0x10 | R | Revision (0x10 = Rev 1.0) |
| 0x02 | STATUS_0 | 0x00 | R/C | Primary status register (connection, protocol) |
| 0x03 | STATUS_1 | 0x00 | R/C | Fault status register |
| 0x04 | CTRL_0 | 0xFF | R/W | Protocol enable control |
| 0x05 | CTRL_1 | 0x00 | R/W | Mode and feature control |
| 0x06 | PDO1_VOLT | 0x32 | R/W | PDO #1 voltage (unit: 100mV). 0x32 = 5.0V |
| 0x07 | PDO1_CURR | 0x1E | R/W | PDO #1 max current (unit: 50mA). 0x1E = 1.5A |
| 0x08 | PDO2_VOLT | 0x5A | R/W | PDO #2 voltage. 0x5A = 9.0V |
| 0x09 | PDO2_CURR | 0x3C | R/W | PDO #2 max current. 0x3C = 3.0A |
| 0x0A | PDO3_VOLT | 0x78 | R/W | PDO #3 voltage. 0x78 = 12.0V |
| 0x0B | PDO3_CURR | 0x3C | R/W | PDO #3 max current. 0x3C = 3.0A |
| 0x0C | PDO4_VOLT | 0x96 | R/W | PDO #4 voltage. 0x96 = 15.0V |
| 0x0D | PDO4_CURR | 0x3C | R/W | PDO #4 max current. 0x3C = 3.0A |
| 0x0E | PPS1_VMIN | 0x21 | R/W | PPS APDO #1 min voltage (unit: 100mV). 0x21 = 3.3V |
| 0x0F | PPS1_VMAX | 0x6E | R/W | PPS APDO #1 max voltage. 0x6E = 11.0V |
| 0x10 | PPS1_CURR | 0x64 | R/W | PPS APDO #1 max current (unit: 50mA). 0x64 = 5.0A |
| 0x11 | PPS2_VMIN | 0x21 | R/W | PPS APDO #2 min voltage. 0x21 = 3.3V |
| 0x12 | PPS2_VMAX | 0xD2 | R/W | PPS APDO #2 max voltage. 0xD2 = 21.0V |
| 0x13 | PPS2_CURR | 0x64 | R/W | PPS APDO #2 max current. 0x64 = 5.0A |
| 0x14 | QC_MAXV | 0xC8 | R/W | QC max voltage (unit: 100mV). 0xC8 = 20.0V |
| 0x15 | AFC_CFG | 0x01 | R/W | AFC voltage config |
| 0x16 | SCP_CFG | 0x01 | R/W | SCP mode config |
| 0x17 | UFCS_CFG | 0x01 | R/W | UFCS config |
| 0x18 | OVP_TH | 0xDC | R/W | OVP threshold (unit: 100mV). 0xDC = 22.0V |
| 0x19 | OCP_TH | 0x46 | R/W | OCP threshold (unit: 50mA). 0x46 = 3.5A |
| 0x1A | OTP_TH | 0x78 | R/W | OTP threshold (unit: 1C). 0x78 = 120C |
| 0x1B | ADC_VBUS_H | 0x00 | R | VBUS ADC result [9:2] |
| 0x1C | ADC_VBUS_L | 0x00 | R | VBUS ADC result [1:0] in bits [7:6], IBUS [9:4] in bits [5:0] |
| 0x1D | ADC_IBUS_L | 0x00 | R | IBUS ADC result [3:0] in bits [7:4], TEMP [9:6] in bits [3:0] |
| 0x1E | ADC_TEMP_L | 0x00 | R | TEMP ADC result [5:0] in bits [7:2], reserved [1:0] |
| 0x1F | GPIO_CFG | 0x00 | R/W | GPIO configuration |
| 0x20 | GPIO_STATUS | 0x00 | R | GPIO pin status (read current pin level) |
| 0x21 | GPIO_OUT | 0x00 | R/W | GPIO output data |
| 0x22 | INT_MASK | 0xFF | R/W | Interrupt mask (1 = masked, 0 = enabled) |
| 0x23 | INT_STATUS | 0x00 | R/C | Interrupt status (write 1 to clear) |
| 0x24 | ACTIVE_PDO | 0x00 | R | Currently active PDO index (0 = none) |
| 0x25 | ACTIVE_PROTO | 0x00 | R | Currently active protocol ID |
| 0x26 | NEG_VOLT_H | 0x00 | R | Negotiated voltage [15:8] (unit: 20mV) |
| 0x27 | NEG_VOLT_L | 0x00 | R | Negotiated voltage [7:0] |
| 0x28 | NEG_CURR_H | 0x00 | R | Negotiated current [15:8] (unit: 10mA) |
| 0x29 | NEG_CURR_L | 0x00 | R | Negotiated current [7:0] |
| 0x2A | PROT_CFG | 0x00 | R/W | Protection response config |
| 0x2B | RETRY_CFG | 0x42 | R/W | Retry configuration |
| 0x3E | OTP_CTRL | 0x00 | R/W | OTP programming control |
| 0x3F | SOFT_RST | 0x00 | W | Write 0x5A to trigger soft reset |

### 6.2 Detailed Register Bit Fields

#### 0x00: DEV_ID (Read-Only)

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| [7:0] | DEVICE_ID | 0x31 | Fixed device ID. 0x31 for VT3100. |

#### 0x01: DEV_REV (Read-Only)

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| [7:4] | MAJOR_REV | 0x1 | Major silicon revision |
| [3:0] | MINOR_REV | 0x0 | Minor silicon revision |

#### 0x02: STATUS_0 (Read / Write-1-to-Clear)

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| 7 | ATTACHED | 0 | 1 = USB Type-C device attached |
| 6 | ORIENTATION | 0 | 0 = CC1 active, 1 = CC2 active |
| 5 | PD_CONTRACT | 0 | 1 = PD explicit contract established |
| 4 | VBUS_PRESENT | 0 | 1 = VBUS output is active |
| [3:0] | PROTOCOL_ID | 0x0 | Active protocol: 0=none, 1=PD_FIXED, 2=PD_PPS, 3=QC2, 4=QC3, 5=QC4+, 6=AFC, 7=FCP, 8=SCP, 9=VOOC_DET, 10=UFCS, 11=APPLE, 12=BC1.2 |

#### 0x03: STATUS_1 (Read / Write-1-to-Clear)

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| 7 | OVP_FAULT | 0 | 1 = Over-voltage fault active |
| 6 | OCP_FAULT | 0 | 1 = Over-current fault active |
| 5 | OTP_FAULT | 0 | 1 = Over-temperature fault active |
| 4 | EXT_FAULT | 0 | 1 = External fault input asserted (GPIO2/FAULT_N) |
| 3 | PD_TIMEOUT | 0 | 1 = PD message timeout occurred |
| 2 | HARD_RESET | 0 | 1 = Hard reset received or sent |
| 1 | VCONN_OC | 0 | 1 = VCONN over-current (if VCONN sourcing enabled) |
| 0 | RESERVED | 0 | Reserved |

#### 0x04: CTRL_0 (Read/Write) — Protocol Enable

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| 7 | EN_PD | 1 | 1 = Enable USB PD protocol |
| 6 | EN_PPS | 1 | 1 = Enable PPS (Augmented PDO) |
| 5 | EN_QC | 1 | 1 = Enable QC 2.0/3.0/4+ |
| 4 | EN_AFC | 1 | 1 = Enable Samsung AFC |
| 3 | EN_FCP | 1 | 1 = Enable Huawei FCP |
| 2 | EN_SCP | 1 | 1 = Enable Huawei SCP |
| 1 | EN_UFCS | 1 | 1 = Enable UFCS |
| 0 | EN_BC12 | 1 | 1 = Enable BC 1.2 / Apple 2.4A |

#### 0x05: CTRL_1 (Read/Write) — Mode and Feature Control

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| 7 | VOOC_DET_EN | 0 | 1 = Enable VOOC detection (flag-only, no negotiation) |
| 6 | GIVEBACK_EN | 0 | 1 = Enable GiveBack flag in PD Fixed PDOs |
| 5 | UNCHUNKED_EN | 0 | 1 = Enable unchunked extended messages |
| 4 | AUTO_RETRY_EN | 1 | 0 = Fault latched until I2C clear, 1 = auto-retry |
| [3:2] | RP_LEVEL | 0b10 | CC Rp advertisement: 00=default, 01=1.5A, 10=3.0A, 11=reserved |
| 1 | EXT_CLK_EN | 0 | 1 = Use external crystal on GPIO2/GPIO3 |
| 0 | I2C_WDOG_EN | 0 | 1 = Enable I2C watchdog (reset if no I2C access within 30s) |

#### 0x06-0x0D: PDO Configuration (Fixed PDOs 1-4)

Each Fixed PDO uses two registers:

**PDOx_VOLT (even address):**

| Bit | Field | Description |
|-----|-------|-------------|
| [7:0] | VOLTAGE | Output voltage in 100mV units. Range: 0x32 (5.0V) to 0xC8 (20.0V). Set to 0x00 to disable this PDO. |

**PDOx_CURR (odd address):**

| Bit | Field | Description |
|-----|-------|-------------|
| [7:0] | CURRENT | Maximum current in 50mA units. Range: 0x01 (50mA) to 0x64 (5.0A). |

#### 0x0E-0x13: PPS APDO Configuration (PPS 1-2)

Each PPS APDO uses three registers:

**PPSx_VMIN:**

| Bit | Field | Description |
|-----|-------|-------------|
| [7:0] | MIN_VOLTAGE | Minimum PPS voltage in 100mV units. |

**PPSx_VMAX:**

| Bit | Field | Description |
|-----|-------|-------------|
| [7:0] | MAX_VOLTAGE | Maximum PPS voltage in 100mV units. |

**PPSx_CURR:**

| Bit | Field | Description |
|-----|-------|-------------|
| [7:0] | MAX_CURRENT | Maximum PPS current in 50mA units. |

#### 0x14: QC_MAXV — QC Maximum Voltage

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| [7:0] | QC_MAX_VOLT | 0xC8 | Maximum QC output voltage in 100mV units. 0xC8 = 20V. Set lower for QC Class B (e.g., 0x78 = 12V). |

#### 0x15: AFC_CFG — Samsung AFC Configuration

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| [7:4] | RESERVED | 0x0 | Reserved |
| 3 | AFC_12V_EN | 0 | 1 = Enable 12V AFC mode |
| 2 | AFC_9V_EN | 0 | 1 = Enable 9V AFC mode (default) |
| [1:0] | AFC_MAX_CURR | 0b01 | Max current: 00=1.67A, 01=2.0A, 10=2.5A, 11=2.77A |

#### 0x16: SCP_CFG — Huawei SCP Configuration

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| [7:4] | SCP_MAX_CURR | 0x0 | SCP max current in 1A units. 0x0 = 8A (default max). |
| [3:2] | SCP_VRANGE | 0b00 | Voltage range: 00=3.3-5.5V, 01=3.3-11V (extended) |
| 1 | SCP_TELEMETRY | 1 | 1 = Enable real-time V/I/T telemetry to sink |
| 0 | SCP_EN | 1 | 1 = SCP protocol enable (master switch) |

#### 0x17: UFCS_CFG — UFCS Configuration

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| 7 | UFCS_CC_MODE | 0 | 1 = Use CC line for UFCS PHY, 0 = Use D+/D- |
| [6:4] | UFCS_MAX_PDO | 0b100 | Number of UFCS power profiles (1-5). Uses same PDO table as PD. |
| 3 | UFCS_PPS_EN | 0 | 1 = Enable UFCS programmable voltage mode |
| 2 | UFCS_TELEMETRY | 1 | 1 = Enable UFCS telemetry |
| [1:0] | RESERVED | 0b01 | Reserved |

#### 0x18: OVP_TH — Over-Voltage Protection Threshold

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| [7:0] | OVP_THRESHOLD | 0xDC | OVP threshold in 100mV units. 0xDC = 22.0V. Range: 0x37 (5.5V) to 0xFF (25.5V). |

#### 0x19: OCP_TH — Over-Current Protection Threshold

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| [7:0] | OCP_THRESHOLD | 0x46 | OCP threshold in 50mA units. 0x46 = 3.5A. Range: 0x0A (0.5A) to 0x78 (6.0A). |

#### 0x1A: OTP_TH — Over-Temperature Protection Threshold

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| [7:0] | OTP_THRESHOLD | 0x78 | OTP threshold in 1C units. 0x78 = 120C. Range: 0x50 (80C) to 0x96 (150C). |

#### 0x1B-0x1E: ADC Readback (Read-Only, packed format)

ADC results are 10-bit values packed into 4 bytes to minimize register count:

| Address | Bits | Content |
|---------|------|---------|
| 0x1B | [7:0] | VBUS_ADC[9:2] |
| 0x1C | [7:6] | VBUS_ADC[1:0] |
| 0x1C | [5:0] | IBUS_ADC[9:4] |
| 0x1D | [7:4] | IBUS_ADC[3:0] |
| 0x1D | [3:0] | TEMP_ADC[9:6] |
| 0x1E | [7:2] | TEMP_ADC[5:0] |
| 0x1E | [1:0] | Reserved |

**ADC conversion formulas:**
- VBUS voltage = (ADC_VBUS / 1023) * 3.3V * (external divider ratio)
  - Recommended external divider: 100K / 12K = 9.33:1, so VBUS = ADC_voltage * 9.33
  - Full-scale VBUS: ~30.8V
- IBUS current = (ADC_IBUS / 1023) * 3.3V / (sense_amp_gain * Rsense)
  - Example: Rsense = 10m ohm, gain = 50x, full-scale = 6.6A
- Temperature = NTC lookup table (application-specific)

#### 0x1F: GPIO_CFG — GPIO Configuration

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| [7:6] | GPIO3_MODE | 0b00 | 00=push-pull out, 01=open-drain out, 10=input, 11=alt (XTAL_OUT) |
| [5:4] | GPIO2_MODE | 0b10 | 00=push-pull out, 01=open-drain out, 10=input, 11=alt (XTAL_IN) |

[VT3100 Spec 4/7] Section 6: Register Map (Part 1)
| [3:2] | GPIO1_MODE | 0b00 | 00=push-pull out, 01=open-drain out, 10=input, 11=alt (reserved) |
| [1:0] | GPIO0_MODE | 0b01 | 00=push-pull out, 01=open-drain out, 10=input, 11=alt (reserved) |

#### 0x20: GPIO_STATUS — GPIO Pin Status (Read-Only)

| Bit | Field | Description |
|-----|-------|-------------|
| [7:4] | RESERVED | Reserved |
| 3 | GPIO3_LEVEL | Current logic level on GPIO3 |
| 2 | GPIO2_LEVEL | Current logic level on GPIO2 |
| 1 | GPIO1_LEVEL | Current logic level on GPIO1 |
| 0 | GPIO0_LEVEL | Current logic level on GPIO0 |

#### 0x21: GPIO_OUT — GPIO Output Data (Read/Write)

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| [7:4] | RESERVED | 0x0 | Reserved |
| 3 | GPIO3_OUT | 0 | Output data for GPIO3 (when configured as output) |
| 2 | GPIO2_OUT | 0 | Output data for GPIO2 |
| 1 | GPIO1_OUT | 0 | Output data for GPIO1 (default: VBUS_EN) |
| 0 | GPIO0_OUT | 0 | Output data for GPIO0 (default: INT_N) |

#### 0x22: INT_MASK — Interrupt Mask (Read/Write)

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| 7 | MASK_ATTACH | 1 | 1 = Mask attach/detach interrupt |
| 6 | MASK_PD_DONE | 1 | 1 = Mask PD negotiation complete interrupt |
| 5 | MASK_PROTO_CHG | 1 | 1 = Mask protocol change interrupt |
| 4 | MASK_OVP | 1 | 1 = Mask OVP fault interrupt |
| 3 | MASK_OCP | 1 | 1 = Mask OCP fault interrupt |
| 2 | MASK_OTP | 1 | 1 = Mask OTP fault interrupt |
| 1 | MASK_EXT_FAULT | 1 | 1 = Mask external fault interrupt |
| 0 | MASK_VOOC_DET | 1 | 1 = Mask VOOC detection interrupt |

#### 0x23: INT_STATUS — Interrupt Status (Read / Write-1-to-Clear)

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| 7 | INT_ATTACH | 0 | 1 = Attach or detach event occurred |
| 6 | INT_PD_DONE | 0 | 1 = PD negotiation completed (success or fail) |
| 5 | INT_PROTO_CHG | 0 | 1 = Active protocol changed |
| 4 | INT_OVP | 0 | 1 = OVP fault occurred |
| 3 | INT_OCP | 0 | 1 = OCP fault occurred |
| 2 | INT_OTP | 0 | 1 = OTP fault occurred |
| 1 | INT_EXT_FAULT | 0 | 1 = External fault occurred |
| 0 | INT_VOOC_DET | 0 | 1 = VOOC device detected |

#### 0x24: ACTIVE_PDO — Active PDO Index (Read-Only)

| Bit | Field | Description |
|-----|-------|-------------|
| [7:4] | RESERVED | Reserved |
| [3:0] | PDO_INDEX | Currently active PDO. 0=none, 1=PDO1, 2=PDO2, ..., 5=PPS1, 6=PPS2 |

#### 0x25: ACTIVE_PROTO — Active Protocol ID (Read-Only)

| Bit | Field | Description |
|-----|-------|-------------|
| [7:4] | RESERVED | Reserved |
| [3:0] | PROTO_ID | Same encoding as STATUS_0[3:0] PROTOCOL_ID field |

#### 0x26-0x27: NEG_VOLT — Negotiated Voltage (Read-Only)

16-bit value in 20mV units (little-endian). For PPS, this is the actual negotiated PPS voltage. For fixed PDOs, this matches the PDO voltage.

Example: 9.0V = 450 = 0x01C2 -> 0x26 = 0xC2, 0x27 = 0x01

#### 0x28-0x29: NEG_CURR — Negotiated Current (Read-Only)

16-bit value in 10mA units (little-endian). The sink's requested operating current.

Example: 3.0A = 300 = 0x012C -> 0x28 = 0x2C, 0x29 = 0x01

#### 0x2A: PROT_CFG — Protection Response Configuration

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| [7:6] | OVP_RESP | 0b00 | OVP response: 00=disable VBUS+latch, 01=disable VBUS+auto retry, 10=send Alert, 11=reserved |
| [5:4] | OCP_RESP | 0b01 | OCP response: same encoding as OVP |
| [3:2] | OTP_RESP | 0b00 | OTP response: same encoding |
| 1 | FAULT_GPIO_EN | 0 | 1 = Assert GPIO0 (INT_N) on any fault |
| 0 | VBUS_DISCHARGE_EN | 0 | 1 = Enable active VBUS discharge on disconnect |

#### 0x2B: RETRY_CFG — Retry Configuration

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| [7:6] | RETRY_COUNT | 0b01 | Auto-retry count: 00=1, 01=2, 10=4, 11=infinite |
| [5:4] | RETRY_INTERVAL | 0b00 | Interval: 00=250ms, 01=500ms, 10=1s, 11=2s |
| [3:0] | PD_RETRY_COUNT | 0b0010 | Number of PD message retries before Hard Reset (0-15, default 2 per spec) |

#### 0x3E: OTP_CTRL — OTP Programming Control

| Bit | Field | Default | Description |
|-----|-------|---------|-------------|
| 7 | OTP_PROG_EN | 0 | Write 1 to enable OTP programming mode. Requires writing 0xA5 to SOFT_RST first as unlock sequence. |
| 6 | OTP_PROG_DONE | 0 | Read: 1 = programming complete. Write 1 to start programming. |
| 5 | OTP_PROG_FAIL | 0 | Read: 1 = programming failed verification |
| [4:0] | OTP_ADDR | 0x00 | OTP byte address for read/write (0-31, covering 256 bits) |

#### 0x3F: SOFT_RST — Soft Reset (Write-Only)

| Bit | Field | Description |
|-----|-------|-------------|
| [7:0] | RESET_KEY | Write 0x5A to trigger a full soft reset. All registers revert to OTP defaults. Write 0xA5 to unlock OTP programming. Any other value is ignored. |

---

## 7. State Machine Description

### 7.1 Top-Level State Machine

```
                    +----------+
     Power On ----->| POR_INIT |
                    +----+-----+
                         |
                         | OTP load complete, clock stable
                         v
                    +-----------+
                    | UNATTACHED|<---------------------------+
                    | _SRC      |                            |
                    +-----+-----+                            |
                          |                                  |
                          | CC voltage < vRd (Rd detected)   |
                          | tCCDebounce expires              |
                          v                                  |
                    +------------+                           |
                    | ATTACH_WAIT|                           |
                    | _SRC       |                           |
                    +-----+------+                           |
                          |                                  |
                          | CC stable, orientation resolved  |
                          v                                  |
                    +-----------+                            |
                    | ATTACHED  |                            |
                    | _SRC      |                            |
                    +-----+-----+                            |
                          |                                  |
                          | Enable VBUS 5V (GPIO1/VBUS_EN)   |
                          v                                  |
                    +------------+                           |
                    | PD_DETECT  |--- PD timeout ------+     |
                    |            |                      |     |
                    +-----+------+                      |     |
                          |                             |     |
                          | GoodCRC received            |     |
                          v                             v     |
                    +-----------+              +--------+--+  |
                    | PD_NEGO   |              | LEGACY    |  |
                    | TIATED    |              | _DETECT   |  |
                    +-----+-----+              +-----+-----+  |
                          |                          |         |
                          | Contract established     | QC/AFC/ |
                          v                          | SCP/... |
                    +-----------+                    v         |
                    | STEADY    |              +-----------+   |
                    | _STATE    |              | LEGACY    |   |
                    +-----+-----+              | _ACTIVE   |   |
                          |                    +-----+-----+   |
                          |                          |         |
                          | Detach / Hard Reset      | Detach  |
                          v                          v         |
                    +-----------+                              |
                    | DISCONNECT|------------------------------+
                    | _RECOVERY |
                    +-----------+
```

### 7.2 State Descriptions

#### 7.2.1 POR_INIT

**Entry:** Power-on reset released (VDD above POR threshold)
**Actions:**
1. Load OTP memory contents into shadow registers (trim values, default configuration)
2. Initialize internal oscillator with trimmed frequency
3. Initialize all registers to OTP-defined defaults
4. Run ADC self-calibration (offset/gain)
5. Initialize CC Rp current source to configured level
6. Set all GPIOs to default states (VBUS_EN = LOW / off)

**Exit:** Initialization complete (< 5ms) -> transition to UNATTACHED_SRC
**Timing:** t_POR2RDY = 5-10ms

#### 7.2.2 UNATTACHED_SRC

**Entry:** From POR_INIT or DISCONNECT_RECOVERY
**Actions:**
1. Assert Rp on both CC1 and CC2 (current source at configured level)
2. Monitor CC1 and CC2 voltage via comparators
3. VBUS output disabled (VBUS_EN = LOW)
4. D+/D- in high-impedance state
5. Low-power mode: only CC comparators and clock running

**Exit conditions:**
- CC1 or CC2 voltage drops below vRd threshold (Rd detected) -> start tCCDebounce timer -> ATTACH_WAIT_SRC
- No timeout (remain indefinitely until attachment)

**Power consumption:** ~50uA (standby mode)

#### 7.2.3 ATTACH_WAIT_SRC

**Entry:** Rd detected on CC1 or CC2
**Actions:**
1. Continue monitoring CC voltage
2. Wait for tCCDebounce (100-200ms) to confirm stable attachment
3. Determine orientation: the CC pin with Rd is the communication CC; the other may have Ra (VCONN) or open

**Exit conditions:**
- CC voltage stable below vRd for entire tCCDebounce period -> ATTACHED_SRC
- CC voltage returns above vRd (false trigger, bounce) -> UNATTACHED_SRC

#### 7.2.4 ATTACHED_SRC

**Entry:** Stable CC attachment confirmed with orientation resolved
**Actions:**
1. Record orientation (CC1 or CC2 as active communication line)
2. Enable VBUS output: assert VBUS_EN (GPIO1 = HIGH)
3. Start tVBUSon timer (max 275ms for VBUS to reach vSafe5V)
4. Start monitoring VBUS via ADC
5. Prepare Source_Capabilities message based on register/OTP PDO configuration
6. Short D+/D- internally for BC 1.2 DCP (initial safe state)
7. Apply Apple 2.4A divider on D+/D-

**Exit:** VBUS reaches vSafe5V (monitored via ADC_VBUS) -> PD_DETECT
**Error:** VBUS does not reach vSafe5V within tVBUSon -> set fault flag, retry or DISCONNECT_RECOVERY

#### 7.2.5 PD_DETECT

**Entry:** VBUS stable at 5V
**Actions:**
1. Wait tFirstSourceCap (100-350ms), then send Source_Capabilities on active CC line
2. Wait for GoodCRC response from sink
3. If GoodCRC received, wait for Request message
4. If no GoodCRC within tSenderResponse (30ms), retransmit (up to nRetryCount = 2)
5. Repeat Source_Capabilities transmission up to nCapsCount times (50) with tTypeCSendSourceCap interval (100-200ms)

**Exit conditions:**
- GoodCRC received and valid Request follows -> PD_NEGOTIATED
- All retransmissions exhausted (tNoResponse = 5.5s total) -> LEGACY_DETECT
- Hard Reset received -> DISCONNECT_RECOVERY

#### 7.2.6 PD_NEGOTIATED

**Entry:** Valid PD Request received from sink
**Sub-state machine (PD Source Negotiation):**

```
Request Received
      |
      v
  Evaluate Request
      |
      +-- Request valid (within PDO capability)
      |        |
      |        v
      |   Send Accept
      |        |
      |        v
      |   Transition Power Supply
      |   (command power stage to new voltage)
      |        |
      |        v
      |   Wait tSrcTransition (max 550ms for Fixed, 15s for PPS first request)
      |        |
      |        v
      |   Verify output voltage (via ADC)
      |        |
      |        v
      |   Send PS_RDY
      |        |
      |        v
      |   --> STEADY_STATE
      |
      +-- Request invalid (exceeds capability)
               |
               v
          Send Reject (or Wait + Reject)
               |
               v
          Resend Source_Capabilities
```

**Voltage transition sequence for power stage control:**
1. If new voltage > current voltage (step-up):
   a. Adjust power stage setpoint via GPIO/I2C
   b. Monitor ADC_VBUS until within +/- 5% of target
   c. Send PS_RDY when stable
2. If new voltage < current voltage (step-down):
   a. Adjust power stage setpoint
   b. Enable VBUS discharge if needed
   c. Monitor ADC_VBUS until within +/- 5% of target
   d. Send PS_RDY when stable

#### 7.2.7 STEADY_STATE

**Entry:** PD contract established and PS_RDY sent, or legacy protocol active
**Actions:**
1. Monitor for PD messages from sink (Get_Source_Cap, Soft_Reset, etc.)
2. Monitor PPS periodic requests (if PPS active):
   - Reset tPPSTimeout (14s) on each PPS request
   - If tPPSTimeout expires: initiate Hard Reset
3. Run continuous ADC monitoring (VBUS, IBUS, TEMP) for protection
4. Check protection thresholds each ADC cycle
5. Monitor CC for detach (CC voltage rises above vRd)
6. Respond to I2C register reads/writes from host MCU

**Exit conditions:**
- Detach detected (CC open) -> DISCONNECT_RECOVERY
- Fault detected (OVP/OCP/OTP) -> FAULT_HANDLING sub-state
- Hard Reset (from sink or self-initiated) -> DISCONNECT_RECOVERY
- Soft Reset -> re-enter PD_DETECT (resend Source_Capabilities)
- New Request from sink (re-negotiation) -> PD_NEGOTIATED
- I2C command to change PDOs -> send new Source_Capabilities

#### 7.2.8 LEGACY_DETECT

**Entry:** PD negotiation timeout (no PD-capable sink)
**Actions (sequential protocol detection):**

```
Step 1: QC Detection (if EN_QC = 1)
  - Release D+/D- short
  - Monitor D+ for HVDCP handshake (0.6V)
  - If detected within 1.5s:
    - Respond with 3.3V on D-
    - Wait for QC class negotiation

[VT3100 Spec 5/7] Section 6 continued + Section 7: State Machine
    - --> QC_ACTIVE (transition to LEGACY_ACTIVE)
  - If timeout: proceed to Step 2

Step 2: AFC Detection (if EN_AFC = 1)
  - Re-apply DCP mode (D+/D- short)
  - Monitor for AFC ping on D+ (pulse train)
  - If detected within 500ms:
    - Decode byte, respond with voltage selection
    - --> AFC_ACTIVE (transition to LEGACY_ACTIVE)
  - If timeout: proceed to Step 3

Step 3: FCP Detection (if EN_FCP = 1)
  - Monitor D+ for FCP handshake
  - If detected within 500ms:
    - Enter FCP register communication
    - --> FCP_ACTIVE (transition to LEGACY_ACTIVE)
  - If timeout: proceed to Step 4

Step 4: SCP Detection (if EN_SCP = 1)
  - Monitor D+ for SCP handshake
  - If detected within 500ms:
    - Enter SCP half-duplex communication
    - --> SCP_ACTIVE (transition to LEGACY_ACTIVE)
  - If timeout: proceed to Step 5

Step 5: VOOC Detection (if VOOC_DET_EN = 1)
  - Monitor D+/D- for VOOC pattern
  - If detected within 200ms:
    - Set VOOC_DET flag
    - Assert interrupt
    - Remain in BC1.2 DCP mode (external VOOC IC handles negotiation)
  - If timeout: proceed to Step 6

Step 6: UFCS Fallback (if EN_UFCS = 1)
  - Attempt UFCS handshake on D+/D- (or CC if configured)
  - If detected within 500ms:
    - --> UFCS_ACTIVE (transition to LEGACY_ACTIVE)
  - If timeout: proceed to Step 7

Step 7: Default (BC 1.2 / Apple 2.4A)
  - Maintain DCP mode with Apple divider
  - --> BC12_ACTIVE (transition to LEGACY_ACTIVE)
```

#### 7.2.9 LEGACY_ACTIVE

**Entry:** A legacy (non-PD) protocol successfully negotiated
**Actions:**
1. Maintain the active protocol state machine
2. For QC: monitor D+/D- for voltage change requests, adjust power stage accordingly
3. For AFC: monitor for re-negotiation pulses
4. For SCP: maintain half-duplex communication, respond to telemetry requests
5. For UFCS: maintain UFCS session
6. For BC1.2: static — maintain DCP mode
7. Run ADC protection monitoring continuously

**Exit conditions:**
- Detach detected (CC open) -> DISCONNECT_RECOVERY
- Fault detected -> FAULT_HANDLING sub-state
- Protocol error / timeout -> return to LEGACY_DETECT (restart detection)

#### 7.2.10 DISCONNECT_RECOVERY

**Entry:** Detach event, Hard Reset, or unrecoverable fault
**Actions:**
1. Deassert VBUS_EN (GPIO1 = LOW) — disable VBUS output
2. If VBUS_DISCHARGE_EN: enable active discharge on VBUS
3. Wait for VBUS to decay below vSafe0V (< 0.8V) within tSafe0V (650ms)
4. Release D+/D- (high-impedance)
5. Release CC (return to Rp pull-up only)
6. If Hard Reset: wait tSrcRecover (660-1000ms)
7. Clear protocol state, reset negotiation variables

**Exit:** Recovery complete -> UNATTACHED_SRC

### 7.3 Fault Handling Sub-State Machine

```
Fault Detected (OVP/OCP/OTP/EXT)
      |
      v
  Set fault flag in STATUS_1
  Assert interrupt (if unmasked)
      |
      v
  Deassert VBUS_EN (immediate)
      |
      v
  [PROT_CFG check]
      |
      +-- Latch mode (xxP_RESP = 00)
      |      |
      |      v
      |   FAULT_LATCHED
      |   (wait for I2C clear or power cycle)
      |
      +-- Auto-retry mode (xxP_RESP = 01)
      |      |
      |      v
      |   Wait RETRY_INTERVAL
      |      |
      |      v
      |   Check fault condition cleared?
      |      |
      |      +-- Still faulted + retry count < max
      |      |      --> wait and retry again
      |      |
      |      +-- Still faulted + retry count exhausted
      |      |      --> FAULT_LATCHED
      |      |
      |      +-- Fault cleared
      |             --> re-enable VBUS, return to STEADY_STATE
      |
      +-- Alert mode (xxP_RESP = 10)
             |
             v
          Send PD Alert message to sink (if PD active)
          Deassert VBUS_EN
          Wait for sink response or timeout
```

---

## 8. Interface to Power Stage

### 8.1 Overview

The VT3100 is a protocol controller only — it does not include a power MOSFET or voltage regulator. It controls an external power stage (typically a GaN half-bridge buck or buck-boost converter) through GPIO signals and optionally through I2C to an external PMIC.

### 8.2 Control Signals

#### 8.2.1 VBUS_EN (GPIO1, default function)

**Purpose:** Master enable/disable of the VBUS output from the power stage.

| Signal | Level | Meaning |
|--------|-------|---------|
| VBUS_EN = HIGH | Active | Power stage enabled, VBUS output active |
| VBUS_EN = LOW | Inactive | Power stage disabled, VBUS output off |

**Timing requirements:**
- VT3100 asserts VBUS_EN within 1ms of CC attachment confirmation
- VT3100 deasserts VBUS_EN within 10us of fault detection (GPIO response time)
- Power stage must respond to VBUS_EN deassertion within 50us (external requirement)
- tVBUSon (CC attach to VBUS = vSafe5V): < 275ms total, including power stage startup
- tVBUSoff (detach/fault to VBUS < vSafe0V): < 650ms

#### 8.2.2 Voltage Setting

The VT3100 supports three methods for commanding the output voltage to the power stage. The method is selected based on the power stage IC used:

**Method 1: GPIO-based voltage select (simple, limited voltage steps)**
- Use GPIO2 and GPIO3 as voltage select lines (2-bit encoding = 4 voltage levels)
- Suitable for simple charger designs with fixed voltage steps (5V/9V/12V/20V)
- Mapping configured in OTP or registers

| GPIO3 | GPIO2 | Output Voltage |
|-------|-------|----------------|
| 0 | 0 | 5V |
| 0 | 1 | 9V |
| 1 | 0 | 12V |
| 1 | 1 | 20V |

**Method 2: I2C passthrough to external PMIC**
- VT3100 acts as I2C master on the same I2C bus (using SDA/SCL pins in master mode)
- Writes target voltage to external PMIC register
- Supports fine-grained voltage control (suitable for PPS/QC3.0 continuous mode)
- I2C master mode activated via CTRL_1 register configuration
- Note: When I2C master mode is active, external MCU I2C access is paused (bus arbitration)

**Method 3: PWM DAC output (via GPIO3 alternate function)**
- GPIO3 configured as PWM output
- PWM duty cycle proportional to target voltage
- External RC filter converts PWM to analog voltage for power stage feedback
- PWM frequency: 187.5 kHz (12MHz / 64)
- Resolution: 8-bit (256 steps)
- Voltage = V_min + (duty / 255) * (V_max - V_min)
- Requires external low-pass filter (10K + 100nF, fc ~160Hz)

#### 8.2.3 FAULT_N Input (GPIO2, default function)

**Purpose:** Receives fault signal from external power stage.

| Signal | Level | Meaning |
|--------|-------|---------|
| FAULT_N = HIGH | Normal | Power stage operating normally |
| FAULT_N = LOW | Fault | Power stage fault (OCP, short circuit, thermal shutdown) |

**VT3100 response to FAULT_N assertion:**
1. Set EXT_FAULT flag in STATUS_1
2. Assert interrupt (if unmasked)
3. Deassert VBUS_EN immediately
4. Follow protection response configuration (latch/retry/alert per PROT_CFG)

**Debounce:** 10us internal deglitch on FAULT_N input to reject noise.

### 8.3 PD Spec Timing Compliance

The VT3100 + power stage system must meet these USB PD timing requirements:

| Parameter | Spec | Requirement | VT3100 Contribution | Power Stage Requirement |
|-----------|------|-------------|---------------------|------------------------|
| tVBUSon | Type-C | < 275ms | VBUS_EN asserted < 1ms after CC attach | VBUS to 5V < 274ms |
| tFirstSourceCap | PD | 100-350ms after vSafe5V | Internally timed | N/A |
| tSrcTransition | PD (Fixed) | < 550ms | Voltage command issued immediately after Accept | Settle to new voltage < 500ms |
| tSrcTransition | PD (PPS) | < 15s (first), < 550ms (subsequent) | Voltage command per PPS request | Settle < 500ms |
| tSafe5V | PD (Hard Reset) | < 800ms | VBUS_EN + voltage command to 5V | Transition to 5V < 750ms |
| tSafe0V | PD (Hard Reset) | < 650ms | VBUS_EN deasserted | VBUS discharge < 600ms |
| tSrcRecover | PD (Hard Reset) | 660-1000ms | Internally timed wait | N/A |
| tVBUSOFF | Type-C (detach) | < 650ms | VBUS_EN deasserted immediately | VBUS decay < 600ms |

### 8.4 Current Sensing

The VT3100 monitors output current via the ADC_IBUS pin. The external current sensing circuit typically consists of:
- A low-side or high-side shunt resistor (5-20 mohm) in the VBUS path
- A current sense amplifier (gain 20-100x) to amplify the shunt voltage
- Output connected to ADC_IBUS (0-3.3V range)

The VT3100 uses the ADC reading for:
- OCP threshold comparison
- PD Status message (operating current field)
- SCP/UFCS telemetry (real-time current to sink)

---

## 9. Application Circuit

### 9.1 Typical 65W GaN Charger Application

```
    AC Input                              USB-C Output
   (90-264V)                              (5-20V, 65W)
       |                                       |
       v                                       |
  +----------+    +----------+    +-------+    |
  |  EMI     |--->|  Bridge  |--->| PFC   |--->+---+
  |  Filter  |    | Rectifier|    | Stage |    |   |
  +----------+    +----------+    +-------+    |   |
                                               |   |
                        VIN_DC (380-400V)       |   |
                            |                   |   |
                            v                   |   |
                     +-------------+            |   |
                     |  GaN        |            |   |
                     |  Half-Bridge|            |   |
                     |  LLC / QR   |<---+       |   |
                     |  Flyback    |    |       |   |
                     +------+------+    |       |   |
                            |           |       |   |
                            v           |       |   |
                     +------+------+    |       |   |
                     | Output      |    |       |   |
                     | Rectifier + |    |       |   |
                     | Filter      |----+-------+---+--> VBUS (to USB-C connector)
                     +------+------+    |       |          |
                            |           |       |          |
                        VBUS_SENSE      |       |          |
                            |      FB   |       |          |
                            |    (Opto) |       |          |
   +-----------+            |           |       |          |
   |  VT3100   |<-----------+           |       |          |
   |           |            |           |       |          |
   | ADC_VBUS--+--[100K]--VBUS--[12K]--GND     |          |
   |           |                                |          |
   | ADC_IBUS--+--[Current Sense Amp]--[Rshunt]-+          |
   |           |                                           |
   | ADC_TEMP--+--[NTC Divider]                            |
   |           |                                           |
   | GPIO1-----+--VBUS_EN-->[Power Stage Enable]           |
   | GPIO3-----+--PWM/DAC-->[Optocoupler FB]-->[Primary]   |
   | GPIO2-----+--FAULT_N<--[Power Stage Fault]            |
   |           |                                           |
   | CC1-------+-------------------------------> USB-C Pin A5
   | CC2-------+-------------------------------> USB-C Pin B5
   | DP--------+-------------------------------> USB-C Pin A6/A7 (via MUX or direct)
   | DN--------+-------------------------------> USB-C Pin A6/A7
   |           |                                           |
   | VDD5------+--[1uF]--VBUS (5V default)                 |
   | VDD-------+--[100nF]--3.3V (from internal LDO)       |
   | GND-------+--GND                                     |
   |           |                                           |
   | SDA-------+--[4.7K to VDD]---> Optional MCU           |
   | SCL-------+--[4.7K to VDD]---> Optional MCU           |
   | GPIO0-----+--INT_N-----------> Optional MCU           |
   +-----------+
```

### 9.2 External Component BOM

| # | Component | Value | Package | Qty | Purpose |
|---|-----------|-------|---------|-----|---------|
| 1 | C1 | 100nF | 0402 | 1 | VDD decoupling |
| 2 | C2 | 1uF | 0402 | 1 | VDD5 decoupling |
| 3 | C3 | 100nF | 0402 | 1 | ADC_VBUS filter |
| 4 | C4 | 100nF | 0402 | 1 | ADC_IBUS filter |
| 5 | R1 | 100K | 0402 | 1 | VBUS divider high-side |
| 6 | R2 | 12K | 0402 | 1 | VBUS divider low-side |
| 7 | R3 | 4.7K | 0402 | 2 | I2C pull-ups (SDA, SCL) |
| 8 | R4 | 10K | 0402 | 1 | TEST pin pull-down |
| 9 | R5 | 10K | 0402 | 1 | FAULT_N pull-up |
| 10 | R6 | 1K | 0402 | 1 | LED series resistor |
| 11 | R_shunt | 10 mohm | 2512 | 1 | Current sense shunt |
| 12 | U2 | INA180 or equivalent | SOT-23 | 1 | Current sense amplifier |
| 13 | NTC1 | 10K NTC | 0402 | 1 | Temperature sensor |
| 14 | R7 | 10K | 0402 | 1 | NTC divider reference |

**Total external BOM for VT3100 section: 14 components** (excluding power stage, USB-C connector, and EMI filter).

### 9.3 PCB Layout Guidelines

1. Place VT3100 as close to the USB-C connector as possible (minimize CC and D+/D- trace length)
2. CC1/CC2 traces: controlled impedance not required (low-frequency BMC), but keep traces < 50mm and avoid running parallel to high-current VBUS traces
3. D+/D- traces: differential pair recommended, < 50mm, matched length within 2mm
4. ADC input traces: route away from switching noise sources. Place filter capacitors directly at the VT3100 ADC pins.
5. VDD/VDD5 decoupling capacitors: place within 1mm of VT3100 power pins
6. Exposed pad: must be soldered to a ground plane with multiple vias for thermal dissipation
7. VBUS sense divider (R1/R2): place close to VT3100, away from power switching nodes

---

## 10. Design Constraints for RTL Implementation

### 10.1 Clock Architecture

**Primary clock:** 12MHz internal RC oscillator (trimmed)
**Clock domain:** Single clock domain (12MHz) for all digital logic
**No PLL required.** All internal timing is derived from the 12MHz clock via dividers.

**Derived clocks (generated by clock dividers, synchronous to main clock):**

[VT3100 Spec 6/7] Sections 8-10: Power Stage Interface + Application Circuit + RTL Constraints
| Clock | Frequency | Source | Usage |
|-------|-----------|--------|-------|
| CLK_MAIN | 12 MHz | RC OSC / External XTAL | All digital logic, state machines, I2C |
| CLK_BMC | 300 kHz | CLK_MAIN / 40 | BMC encoder/decoder |
| CLK_ADC | 3 MHz | CLK_MAIN / 4 | SAR ADC clock |
| CLK_SCP_UART | ~250 kHz | CLK_MAIN / 48 | SCP UART-like communication |

**Important:** All dividers are implemented as enable signals synchronized to CLK_MAIN, NOT as separate gated clock domains. This ensures a truly single clock domain design with no CDC issues.

### 10.2 Reset Architecture

**Reset domains:** Single asynchronous reset, synchronous release.

| Reset Signal | Type | Source | Scope |
|--------------|------|--------|-------|
| POR_RST_N | Async assert, sync release | POR circuit (analog) | All digital logic |
| SOFT_RST_N | Sync assert, sync release | Register write (0x3F = 0x5A) | All digital logic except I2C slave address register |

**Reset sequence:**
1. POR_RST_N asserted when VDD < V_POR_R
2. POR_RST_N deasserted (synchronized to CLK_MAIN by 2-stage synchronizer) when VDD > V_POR_R for > t_POR
3. After reset release: OTP load → calibration → register initialization → normal operation

**RTL implementation:**
```
// Reset synchronizer
always @(posedge clk or negedge por_rst_n) begin
    if (!por_rst_n) begin
        rst_sync1 <= 1'b0;
        rst_sync2 <= 1'b0;
    end else begin
        rst_sync1 <= 1'b1;
        rst_sync2 <= rst_sync1;
    end
end
assign sys_rst_n = rst_sync2;
```

### 10.3 Gate Count Estimate

| Block | Estimated Gates | Notes |
|-------|----------------|-------|
| CC Logic | 2K | Comparator interface, debounce, orientation |
| PD PHY (BMC) | 8K | 4b5b codec, CRC-32, preamble, framing |
| PD Protocol Layer | 15K | Source state machines, policy engine, message buffer |
| QC Engine | 3K | HVDCP detection, continuous mode, D+/D- control |
| AFC Engine | 2K | Pulse encoder/decoder, byte communication |
| FCP Engine | 3K | Register-based communication |
| SCP Engine | 5K | UART framing, packet handling, CRC |
| UFCS Engine | 8K | Full UFCS protocol stack |
| I2C Slave | 3K | Standard I2C slave with clock stretching |
| Register File | 4K | 64 registers, read/write mux, default logic |
| GPIO Controller | 1K | 4 pins, mode configuration, alt functions |
| ADC Interface | 2K | SAR control, mux, data formatting |
| Protection Logic | 2K | Threshold comparison, fault state machine |
| Clock/Reset/OTP | 2K | Dividers, POR sync, OTP interface |
| **Total** | **~60K gates** | Target: 50K-100K range |

**Area estimate (55nm):** ~60K gates * 3.5 um2/gate = ~0.21 mm2 digital core. Well within QFN 3x3mm die budget.

### 10.4 Timing Constraints

**Target frequency:** 12 MHz (83.3 ns clock period)

**Critical paths (by priority):**
1. **I2C data setup/hold:** SDA must be valid within 300ns of SCL edge (easily met at 12MHz)
2. **BMC bit timing:** 300kHz BMC requires transitions every ~1.67us. At 12MHz, this is 20 clock cycles per BMC half-bit — ample margin.
3. **CRC-32 computation:** Must complete CRC check within one BMC byte period (~13us). Pipelined CRC can compute in 1 clock cycle.
4. **ADC conversion:** 10-bit SAR at 3MHz clock = ~3.3us per conversion, ~10us per 3-channel scan. Non-critical path.

**Synthesis constraints:**
```
# SDC constraints (synopsis design constraints)
create_clock -name clk_main -period 83.33 [get_ports CLK]
set_input_delay -clock clk_main -max 20.0 [all_inputs]
set_input_delay -clock clk_main -min 0.0 [all_inputs]
set_output_delay -clock clk_main -max 20.0 [all_outputs]
set_output_delay -clock clk_main -min 0.0 [all_outputs]

# False paths for asynchronous inputs
set_false_path -from [get_ports {CC1 CC2 DP DN FAULT_N}]
# These are re-synchronized internally

# Multicycle paths
# ADC data is latched and stable for multiple cycles
set_multicycle_path 2 -setup -from [get_cells adc_data_reg*]
```

### 10.5 Memory and Storage

| Memory | Type | Size | Usage |
|--------|------|------|-------|
| OTP | Fuse (analog macro) | 256 bits | Trim, default config |
| Register file | Flip-flops | 64 x 8 = 512 bits | Runtime configuration, status |
| PD message buffer | SRAM or flip-flops | 64 bytes TX + 64 bytes RX | PD message assembly/parsing |
| Protocol scratchpad | Flip-flops | 32 bytes | SCP/UFCS packet buffer |

**Total flip-flop storage:** ~1.2 Kbytes. No embedded SRAM macro needed — all implementable in standard cells for this size.

### 10.6 Analog IP Blocks (Not RTL — provided as hard macros)

The following blocks are analog and will be delivered as hard IP macros by the analog design team. The RTL interfaces to them through defined digital interfaces.

| Block | Interface | Notes |
|-------|-----------|-------|
| Internal RC Oscillator | CLK output (12MHz square wave) | Trimmed by OTP[7:0] |
| POR / Brown-out Detector | POR_RST_N output (active low) | Analog comparator |
| LDO (5V to 3.3V) | Enable input, PG (power good) output | Integrated LDO |
| 10-bit SAR ADC | Start, done, data[9:0], channel_sel[1:0] | With internal S/H and mux |
| CC Rp Current Source | Enable, level_sel[1:0] | 80/180/330 uA programmable |
| CC Comparators | CC_voltage level outputs (3 thresholds) | For Rd/Ra/Open detection |
| D+/D- Drivers | Voltage_sel[2:0], enable, direction | Programmable output |
| D+/D- Comparators | Threshold outputs (4 thresholds) | For QC/AFC detection |
| OTP Fuse Array | Address[4:0], data[7:0], program, read | 256-bit e-fuse |
| ESD Protection | Passive (on all pads) | 8kV HBM on CC/VBUS |

### 10.7 Testability (DFT)

**Scan chain insertion:**
- Full scan insertion on all flip-flops (except OTP shadow registers which have separate test mode)
- Target scan coverage: > 95% stuck-at fault coverage
- Scan chain count: 4 chains (balanced for pin-limited package)
- Scan clock: CLK_MAIN (12MHz, can be overdriven by tester at lower frequency)
- Scan enable and scan input/output multiplexed on GPIO pins in test mode

**Test mode entry:**
- TEST pin = HIGH activates scan test mode
- GPIO0 = SCAN_IN0, GPIO1 = SCAN_IN1, GPIO2 = SCAN_OUT0, GPIO3 = SCAN_OUT1
- SDA = SCAN_IN2, SCL = SCAN_IN3, CC1 = SCAN_OUT2, CC2 = SCAN_OUT3
- Additional scan chains routed if needed

**BIST (Built-In Self-Test):**
- ADC BIST: apply known internal reference voltage and verify ADC output
- OTP BIST: read all OTP bits and verify against expected checksum
- SRAM BIST: not applicable (no SRAM)

**Production test flow:**
1. Wafer sort: scan test + ADC BIST + OTP programming (trim values)
2. Package test: scan test + functional test (I2C read/write, CC detection, BMC loopback)
3. Final QA: sample-based protocol compliance test on evaluation board

### 10.8 RTL Coding Guidelines

1. **Language:** SystemVerilog (IEEE 1800-2017)
2. **Style:** Synchronous design, single clock domain, async reset with sync release
3. **Naming convention:**
   - Modules: `vt3100_<block>` (e.g., `vt3100_pd_phy`, `vt3100_cc_logic`)
   - Signals: `snake_case`, suffix `_n` for active-low, `_r` for registered, `_w` for wire
   - Parameters: `UPPER_CASE`
   - Clock: `clk`, Reset: `rst_n`
4. **No latches.** All storage must be flip-flops. Lint tool must flag any inferred latches as errors.
5. **No gated clocks.** Use clock enable instead.
6. **Asynchronous inputs** (CC1, CC2, DP, DN, FAULT_N, SDA, SCL) must pass through a 2-stage synchronizer before use in any logic.
7. **FSM coding:** Use `enum` types for state encoding. Two-process FSM style (combinational next-state + sequential state register). Default case in `case` statements must go to a safe/reset state.
8. **CRC-32:** Implement using LFSR-based parallel CRC (process 4 or 8 bits per clock cycle).
9. **Message buffers:** Implement as shift registers or register arrays — no inferred RAM for this size.
10. **Lint clean:** Code must pass Synopsys SpyGlass or equivalent lint checks with zero warnings in the "important" category.

### 10.9 Module Hierarchy

```
vt3100_top
  |
  +-- vt3100_por_sync          (POR synchronizer, reset distribution)
  +-- vt3100_clk_div           (Clock divider: /4, /40, /48)
  +-- vt3100_otp_ctrl          (OTP read/program controller)
  +-- vt3100_reg_file          (I2C-accessible register file)
  +-- vt3100_i2c_slave         (I2C slave interface)
  +-- vt3100_cc_logic          (CC detection, orientation, Rp control)
  |     +-- vt3100_cc_comp_if  (CC comparator digital interface)
  |     +-- vt3100_cc_debounce (Debounce timer)
  +-- vt3100_pd_phy            (BMC encoder/decoder, CRC-32, framing)
  |     +-- vt3100_bmc_tx      (BMC transmitter)
  |     +-- vt3100_bmc_rx      (BMC receiver)
  |     +-- vt3100_crc32       (CRC-32 generator/checker)
  |     +-- vt3100_4b5b        (4b5b encoder/decoder)
  +-- vt3100_pd_protocol       (PD source state machine, policy engine)
  |     +-- vt3100_pd_src_sm   (Source capability/negotiation FSM)
  |     +-- vt3100_pd_msg_buf  (TX/RX message buffers)
  |     +-- vt3100_pps_ctrl    (PPS timeout and request handler)
  +-- vt3100_qc_engine         (QC 2.0/3.0/4+ protocol engine)
  +-- vt3100_afc_engine        (Samsung AFC engine)
  +-- vt3100_fcp_engine        (Huawei FCP engine)
  +-- vt3100_scp_engine        (Huawei SCP engine)
  +-- vt3100_ufcs_engine       (UFCS protocol engine)
  +-- vt3100_legacy_detect     (D+/D- protocol detector: VOOC, Apple, BC1.2)
  +-- vt3100_proto_arb         (Protocol arbitrator / priority mux)
  +-- vt3100_adc_ctrl          (ADC interface: mux, start, read, format)
  +-- vt3100_protection        (OVP/OCP/OTP threshold comparison, fault FSM)
  +-- vt3100_gpio_ctrl         (GPIO configuration, I/O control, alt functions)
  +-- vt3100_pwm_gen           (PWM generator for voltage DAC output)
```

---

## 11. Compliance and Certification

### 11.1 USB-IF Certification

**Requirement:** USB PD 3.1 Source compliance per USB-IF Compliance Program.

**Test specifications:**
- USB Type-C Functional Test Specification (covers CC behavior, VBUS timing)
- USB Power Delivery Compliance Test Specification (covers PD messaging, timing, error handling)
- USB PD PHY Compliance Test Specification (covers BMC signaling, CRC, encoding)

**Test equipment:**
- USB-IF certified test fixtures (Total Phase Beagle, GRL USB PD Tester, or equivalent)
- Ellisys USB PD analyzer for protocol-level debugging

**Certification process:**
1. Self-test with USB-IF test tools (2-4 weeks development)
2. Pre-compliance testing at authorized test lab (1-2 weeks)
3. Fix any failures, re-test (2-4 weeks)
4. USB-IF Compliance Workshop submission (held 4-6 times per year)
5. TID (Test ID) assignment upon passing

**Estimated timeline:** 3-6 months from first silicon
**Estimated cost:** $10,000-$20,000 (test lab fees + USB-IF workshop fee)

### 11.2 UFCS Certification (China)

**Requirement:** UFCS 1.0 compliance per China CAICT (China Academy of Information and Communications Technology).

**Test specifications:**
- T/TAF 083: Universal Fast Charging Specification
- CAICT UFCS compliance test suite

**Certification process:**
1. Develop UFCS test suite compliance (2-4 weeks)
2. Submit to CAICT-authorized test lab (e.g., CTTL)
3. Test and certification cycle (4-8 weeks)

**Estimated timeline:** 2-4 months from first silicon
**Estimated cost:** 30,000-60,000 CNY

### 11.3 Safety Certification

**Standard:** IEC 62368-1 (Audio/Video, Information and Communication Technology Equipment — Safety)

**Applicable requirements for IC:**
- VT3100 itself does not need standalone IEC 62368-1 certification (it is a component)
- The end product (charger) must be certified
- VT3100 provides data for the charger manufacturer's safety file: protection features, fault behavior, creepage/clearance considerations

**VT3100 contributions to safety compliance:**
- OVP/OCP/OTP protection with configurable thresholds
- VBUS discharge on disconnect
- Fault latch mode (prevents automatic re-energization)
- ESD protection on all externally-accessible pins

### 11.4 EMC Compliance

**Applicable standards:**
- EN 55032 (CISPR 32): Electromagnetic emissions
- EN 55035 (CISPR 35): Electromagnetic immunity

**VT3100 EMC considerations:**
- BMC communication at 300kHz: low-frequency, minimal EMI contribution
- Internal oscillator at 12MHz: shielded by package, but harmonics must be considered
- D+/D- switching: fast edges on protocol transitions — add series resistors (22-47 ohm) on D+/D- traces in charger layout
- ADC sampling: susceptible to conducted interference — filter capacitors on ADC inputs are mandatory

**EMC test responsibility:** End product (charger) manufacturer. VT3100 provides application notes and layout guidelines to minimize EMC issues.

### 11.5 Certification Timeline Summary

| Certification | Owner | Timeline | Cost | Dependency |
|---------------|-------|----------|------|------------|
| USB-IF PD 3.1 | Vantic | 3-6 months post-silicon | $10K-$20K | First silicon passing self-test |
| UFCS (CAICT) | Vantic | 2-4 months post-silicon | 30K-60K CNY | First silicon passing self-test |
| IEC 62368-1 | Customer (charger OEM) | 2-3 months | Customer cost | Charger design complete |
| EN 55032/55035 | Customer (charger OEM) | 1-2 months | Customer cost | Charger design complete |
| QC certification | Vantic (optional) | 1-2 months | $5K-$10K | Qualcomm program enrollment |

### 11.6 Environmental Compliance

- **RoHS:** Compliant (lead-free, halogen-free packaging)
- **REACH:** No SVHC substances
- **Moisture sensitivity level:** MSL-3 (per J-STD-020)
- **Shelf life:** 12 months in sealed dry-pack

---

## Appendix A: Acronym Glossary

| Acronym | Definition |
|---------|------------|
| ADC | Analog-to-Digital Converter |
| AFC | Adaptive Fast Charging (Samsung) |
| APDO | Augmented Power Data Object |
| BC | Battery Charging |
| BMC | Biphase Mark Coding |
| BOD | Brown-Out Detection |
| CC | Configuration Channel (USB Type-C) |
| CDC | Clock Domain Crossing |
| CDP | Charging Downstream Port |
| CRC | Cyclic Redundancy Check |
| DAC | Digital-to-Analog Converter |
| DCP | Dedicated Charging Port |
| DFT | Design For Testability |
| ESD | Electrostatic Discharge |
| FCP | Fast Charge Protocol (Huawei) |
| GaN | Gallium Nitride |
| GPIO | General Purpose Input/Output |
| HBM | Human Body Model (ESD) |
| HVDCP | High Voltage Dedicated Charging Port |
| I2C | Inter-Integrated Circuit |
| LDO | Low Dropout Regulator |
| LFSR | Linear Feedback Shift Register |
| LVHC | Low Voltage High Current |
| NTC | Negative Temperature Coefficient |
| OCP | Over-Current Protection |
| OTP | One-Time Programmable / Over-Temperature Protection (context-dependent) |
| OVP | Over-Voltage Protection |
| PD | Power Delivery (USB) |
| PDO | Power Data Object |
| PHY | Physical Layer |
| PMIC | Power Management IC |
| POR | Power-On Reset |
| PPS | Programmable Power Supply |
| PWM | Pulse Width Modulation |
| QC | Quick Charge (Qualcomm) |
| RTL | Register Transfer Level |
| SAR | Successive Approximation Register |
| SCP | Super Charge Protocol (Huawei) |
| SDC | Synopsys Design Constraints |
| SPR | Standard Power Range |
| UFCS | Universal Fast Charging Specification |
| VOOC | Voltage Open Loop Multi-step Constant-Current Charging (OPPO) |