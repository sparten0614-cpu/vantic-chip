# VT3200 Architecture — USB PD Fast Charging Controller with Integrated Buck

## Overview

VT3200 = VT3100 protocol layer + 5A synchronous rectification Buck controller.

Unlike VT3100 (protocol-only, external power stage), VT3200 integrates:
- **Protocol Layer**: Reused from VT3100 (CC Logic, BMC PHY, PD Message, PD Policy, I2C, GoodCRC)
- **Buck Digital Controller**: PWM generation, digital compensation loop, protection, soft-start
- **Power MOSFET Drivers**: High-side and low-side gate drive control
- **ADC Interface**: VBUS voltage, output current, and temperature sensing

## Block Diagram

```
                    VT3200 Top
┌──────────────────────────────────────────────────────────┐
│                                                          │
│  ┌──────────────────────────────┐  ┌──────────────────┐ │
│  │     VT3100 Protocol Core     │  │  Buck Controller  │ │
│  │  ┌────────┐ ┌─────────────┐  │  │  ┌────────────┐  │ │
│  │  │CC Logic│ │  BMC PHY    │  │  │  │  PWM Gen    │  │ │
│  │  └────────┘ └─────────────┘  │  │  └────────────┘  │ │
│  │  ┌────────┐ ┌─────────────┐  │  │  ┌────────────┐  │ │
│  │  │PD Msg  │ │ PD Policy   │──┼──┼─>│ Comp Loop  │  │ │
│  │  └────────┘ └─────────────┘  │  │  └────────────┘  │ │
│  │  ┌────────┐ ┌─────────────┐  │  │  ┌────────────┐  │ │
│  │  │GoodCRC │ │  RegFile    │  │  │  │ Protection │  │ │
│  │  └────────┘ └─────────────┘  │  │  └────────────┘  │ │
│  │  ┌────────┐                  │  │  ┌────────────┐  │ │
│  │  │I2C Slave│                 │  │  │ Soft-Start │  │ │
│  │  └────────┘                  │  │  └────────────┘  │ │
│  └──────────────────────────────┘  └──────────────────┘ │
│                                                          │
│  CC1 CC2  SDA SCL  HG LG  ISNS  VBUS_SNS  BOOT  VIN   │
└──┬───┬────┬───┬────┬──┬───┬─────┬────────┬─────┬──┬────┘
   │   │    │   │    │  │   │     │        │     │  │
  USB-C    I2C     FETs  Current  VBUS   Bootstrap VIN
                   Ext.  Sense    Sense
```

## Interface Between Protocol and Buck

Key signals from PD Policy → Buck Controller:
- `vbus_en`: Enable/disable VBUS output
- `vbus_voltage[7:0]`: Target voltage (100mV units, 5V-20V)
- `vbus_current[9:0]`: Max current limit (10mA units)
- `vbus_stable` (return): VBUS reached target voltage

The PD Policy Engine issues voltage/current targets after PD negotiation.
The Buck Controller adjusts its output to match.

## Buck Controller Sub-Modules

### 1. PWM Generator (`buck_pwm`)
- Dual-output: HG (high-side) and LG (low-side) with dead-time
- Switching frequency: configurable 300kHz-1MHz (register settable)
- Duty cycle controlled by compensation loop output
- Dead-time: programmable 10-50ns (at 12MHz granularity: ~83ns minimum)

### 2. Digital Compensation Loop (`buck_comp`)
- Type-II or Type-III digital compensator
- Input: ADC voltage error (target - actual)
- Output: duty cycle adjustment
- Coefficients programmable via registers
- Update rate: once per switching cycle

### 3. Protection (`buck_prot`)
- OVP: Over-voltage (ADC-based, configurable threshold)
- OCP: Over-current (cycle-by-cycle via current sense comparator)
- OTP: Over-temperature (ADC-based)
- UVLO: Under-voltage lockout on VIN
- Hiccup mode: auto-retry after fault with increasing backoff

### 4. Soft-Start (`buck_softstart`)
- Ramp reference voltage from 0 to target over configurable time
- Pre-charge phase: low duty cycle for bootstrap capacitor
- Prevents inrush current on startup

### 5. ADC Interface (`buck_adc`)
- Interface to external or integrated SAR ADC
- Multiplexed: VBUS, ISNS, TEMP channels
- Sample timing synchronized to PWM switching

## Reuse Strategy

VT3100 RTL is reused as-is (3005 lines). Changes:
1. `vt3100_top` is wrapped as a sub-module of `vt3200_top`
2. `vbus_en`, `vbus_voltage`, `vbus_current`, `vbus_stable` wired to Buck
3. Register file extended: additional Buck registers at 0x30-0x3F
4. I2C slave address range expanded or second slave added

## Estimated Size

| Module | Est. Lines |
|--------|-----------|
| VT3100 Protocol Core | 3,005 (reuse) |
| Buck PWM Generator | ~200 |
| Buck Compensation Loop | ~300 |
| Buck Protection | ~200 |
| Buck Soft-Start | ~150 |
| Buck ADC Interface | ~150 |
| VT3200 Top + RegFile ext | ~400 |
| **Total** | **~4,400** |
