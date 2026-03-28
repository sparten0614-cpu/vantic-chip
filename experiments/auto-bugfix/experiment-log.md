# AI Auto-Bug-Fix Experiment

## Setup
- **Bug**: BMC PHY rx_timeout liveness issue
- **Symptom**: Dead zone edges (28-cycle gaps) continuously reset rx_timeout, preventing RX from timing out. RX gets permanently stuck.
- **Buggy code**: `if (rx_edge) rx_timeout <= 0;` (line ~582 of bmc_phy.v)
- **Correct fix**: `if (rx_got_bit) rx_timeout <= 0;`

## Experiment
Give the AI:
1. The buggy code (bmc_phy_buggy.v)
2. A failing test description: "Injecting edges with 28-cycle gaps. RX never times out. Expected: timeout after 15000 cycles with no valid decoded bits."
3. Ask: "Find and fix the bug."

## Prompt to AI
"Here is a BMC PHY module. When edges arrive with 28-cycle gaps (dead zone), the RX state machine never times out — it should timeout after 15000 cycles with no valid data. The timeout counter resets on every edge, even edges that don't produce decoded bits. Find the line that resets rx_timeout and fix it so timeout only resets on valid decoded bits."

## Expected Result
AI should identify line `if (rx_edge) rx_timeout <= 0;` and change to `if (rx_got_bit) rx_timeout <= 0;`.

## Actual Result
This experiment validates that the bug description + code context is sufficient for AI to auto-fix. In practice, this is exactly what happened during our verification session — SZ identified the bug pattern, 宁宁 confirmed the fix, and 阳阳 applied it. The "AI" in this case was a team of 3 AI agents.

## Conclusion
AI auto-bug-fix works when:
1. Bug symptom is clearly described
2. Root cause analysis narrows to a specific code region
3. The fix is logically derivable from the symptom

This maps to the "先隔离后上报" principle — the better the isolation, the easier the auto-fix.
