# Physical Register File (PRF) Design Research

Compiled: 2026-03-21 | Focus: Upgrading an arch-reg OoO core to PRF-based renaming

---

## 1. PRF vs Architectural Register File: Why Switch?

### Two Renaming Styles

**Data-in-ROB (Intel P6 style):**
- The ROB stores actual result *data*. The Architectural Register File (ARF) holds only
  committed state. On writeback, results go into the ROB entry. On commit, data is
  copied from the ROB to the ARF.
- Result values exist in 4 places: reservation station operand fields, ROB entries,
  ARF, and the bypass network. Broadcasting results to all these locations costs
  power, area, and timing.
- ROB entries are wide (must hold 32/64-bit data), limiting how many entries fit.

**Tag-indexed PRF (MIPS R10000 / BOOM style):**
- A unified Physical Register File holds *all* register state — both committed and
  speculative. The ROB stores only metadata (tags, control bits) — no data.
- Result values exist in exactly 1 place: the PRF. The ROB and rename tables hold
  small pointers (~6 bits for 64 physical registers), not data.
- Retirement is a pointer swap in the committed RAT — no data movement at all.

### Why PRF Wins

| Aspect          | Data-in-ROB              | PRF-based                      |
|-----------------|--------------------------|--------------------------------|
| ROB entry size  | Wide (data + metadata)   | Narrow (metadata only)         |
| Data copies     | 4 locations              | 1 location (PRF)               |
| Commit cost     | Data copy ROB→ARF        | Pointer update in committed RAT|
| Power           | High (data broadcast)    | Lower (pointer manipulation)   |
| Scalability     | Poor for wide machines   | Good — ROB scales cheaply      |
| Read ports      | ROB needs read ports     | PRF needs read ports (similar) |

**Bottom line:** PRF eliminates data movement at commit and reduces ROB width. Every
modern high-performance OoO CPU (Intel since Sandy Bridge, ARM A76+, BOOM) uses PRF.

---

## 2. Free List Management

The free list tracks which physical registers are available for allocation.

### Data Structure

BOOM uses a **bit-vector** representation (1 bit per physical register). A priority
decoder finds the first free register. For superscalar rename (N instructions/cycle),
a cascading priority decoder allocates N registers per cycle.

The R10000 uses a **circular FIFO** (4-wide, 8-deep). Freed registers enter at the
tail; allocated registers leave from the head. Both representations are valid — the
bit-vector is simpler for small PRFs, the FIFO avoids priority decoder delay.

### Lifecycle: alloc → commit → free

**Rename:** Pop `pdst` from free list. Read current mapping as `pdst_old`. Store
`pdst_old` in ROB. Update speculative RAT: `arch_reg → pdst`. Mark `pdst` busy.

**Commit:** Free `pdst_old` (NOT `pdst`!) back to free list. Update committed RAT.

**Flush:** Restore speculative RAT from branch snapshot. Restore free list via
BOOM's **allocation list** — a bitmask of pregs allocated after each branch,
OR'd back into the free list on misprediction. Without this, pregs leak on every
misprediction until the pipeline stalls permanently.

### Free List Sizing

Minimum physical registers = `num_arch_regs + max_in_flight_instructions`.
For RV32I: 32 arch regs + 32 in-flight → 64 physical regs (6-bit tags).
At reset, regs 0–31 are mapped 1:1 to arch regs; regs 32–63 are free.

---

## 3. Rename Table (RAT) + PRF Integration

### Two RATs

**Speculative RAT:** Updated at rename. Maps arch→phys for dispatching instructions.

**Committed RAT:** Updated at commit. Maps arch→phys for committed state. Used for
exception recovery (copy committed RAT → speculative RAT in one cycle). Without it,
you must unwind the ROB entry-by-entry — slow and error-prone.

### Superscalar Rename (dispatch width > 1)

When renaming 2+ instructions per cycle, intra-group dependencies must be resolved:

```
Cycle N rename group:
  I0: add x5, x1, x2   → allocates p40 for x5
  I1: sub x6, x5, x3   → must see x5 → p40 (not the old mapping)
```

The rename stage needs **intra-group bypass**: I1's source lookup for x5 must check
whether any earlier instruction in the same rename group wrote x5, and if so, use
that physical register instead of the RAT's current entry.

### Branch Snapshots

On every branch (or JALR), BOOM snapshots the entire speculative RAT. On
misprediction, the snapshot is restored in a single cycle.

**Cost:** `num_arch_regs × log2(num_phys_regs) × num_in_flight_branches` bits.
For RV32I with 64 phys regs and 8 branches: 32 × 6 × 8 = 1536 bits. Cheap.

Each snapshot also includes the free list's allocation pointer (or allocation list),
so the free list can be restored alongside the RAT.

### x0 Handling (RISC-V)

Register x0 is hardwired to zero. It must NEVER be renamed. Any instruction writing
to x0 should not allocate a physical register and should not update the RAT. The
mapping `x0 → p0` is permanent, and p0 is hardwired to zero, never freed.

---

## 4. BOOM's PRF Implementation (Reference Numbers)

- **Two PRFs:** integer (6 read, 3 write ports for 3-wide) and FP (3 read, 2 write).
- Ports are **statically provisioned** per issue slot — no read arbitration needed.
- ALU bypass at end of Register Read stage enables back-to-back execution.
- Multi-cycle units write back to PRF directly (no bypass).
- **Busy table:** 1 bit per preg. Set at rename, cleared at writeback. If both
  collide on the same preg in the same cycle, rename wins (set busy).

---

## 5. Practical RTL Design Tips for PRF Migration

### Migration Steps: Data-in-ROB → PRF

1. **Shrink ROB.** Remove data fields. Keep: `pdst`, `pdst_old`, `arch_rdst`,
   branch mask, exception bits, PC, committed flag.
2. **Add PRF.** Single-issue RV32I: 2 read + 1 write port. Dual-issue: 4R + 2W.
3. **Add free list.** Bit-vector or FIFO with alloc, free, and bulk restore.
4. **Split RAT.** Speculative + committed RAT. Add snapshot storage per branch.
5. **Add busy table.** 1 bit per physical register.
6. **Remove CDB data→ROB path.** CDB carries tag only; data goes to PRF write port.

### Common Bugs

| Bug | Symptom | Fix |
|-----|---------|-----|
| Freeing `pdst` instead of `pdst_old` at commit | Correct results destroyed, later instructions read garbage | Always free the stale mapping, never the new one |
| Free list not restored on misprediction | Pipeline eventually stalls (all pregs busy) | Implement allocation list or checkpoint-based free list recovery |
| Busy table race (writeback clears busy on a just-reallocated preg) | Dependent instruction issued with stale data | Rename (set busy) has priority over writeback (clear busy) in same cycle |
| x0 allocated a physical register | Free list leak, eventual stall | Hardwire x0 → p0, never allocate or free p0 |
| Intra-group RAT bypass missing | Second instruction in rename group reads stale mapping | Bypass within the rename stage for same-cycle WAW/RAW |
| Snapshot not taken for JALR | JALR misprediction cannot recover RAT | Treat JALR identically to conditional branches for snapshots |
| pdst_old not saved for instructions that don't write a register | Garbage freed at commit | Set pdst_old = 0 (invalid) for non-writing instructions; skip free |
| Superscalar commit WAW: two instrs in commit group write same arch reg | Wrong preg freed | Process commit group in program order; only the youngest writer's mapping survives |

### Timing-Critical Paths

1. **Rename stage:** RAT read + free list alloc + intra-group bypass + RAT write.
   This is often the critical path of the entire processor. Consider pipelining
   rename into 2 stages (RAT read | RAT write + free list alloc).

2. **Register read + bypass mux:** PRF read port + bypass mux select. For wide
   machines, the bypass mux fan-in grows with issue width. Use registered bypass
   (1 cycle penalty) if timing fails.

3. **Free list priority decoder:** For bit-vector free lists, the cascading priority
   decoder for N-way alloc is O(N × num_phys_regs). For >64 pregs with 2+ alloc
   per cycle, consider a FIFO-based free list instead.

4. **Wakeup + select:** Same as in any OoO design, but now wakeup tags are physical
   register numbers (from the PRF), not ROB indices. No functional change, but tag
   width may differ — verify comparator sizing.

### Checklist

1. Start single-issue. Add superscalar rename later.
2. 64 physical registers for RV32I (6-bit tags, 32 rename slots).
3. Committed RAT from day one — ROB unwind recovery is slow and bug-prone.
4. Bit-vector free list first. Switch to FIFO only if timing demands.
5. Store `pdst_old` in ROB at rename — most important bookkeeping field.
6. Branch snapshots (RAT + free list pointer) from day one.
7. Test: back-to-back WAW, free list exhaustion, branch storms, exceptions mid-speculation.
8. Verify free list balance: allocs must equal frees over any test run.

---

## Sources

- [BOOM Rename Stage](https://docs.boom-core.org/en/latest/sections/rename-stage.html)
- [BOOM Register Files and Bypass Network](https://docs.boom-core.org/en/latest/sections/reg-file-bypass-network.html)
- [BOOM Pipeline Overview](https://docs.boom-core.org/en/latest/sections/intro-overview/boom-pipeline.html)
- [MIPS R10000 Architecture Analysis](https://pages.cs.wisc.edu/~ragh/Qualfiles/(2.4.2)%20MIPS%20R10000.html)
- [R10000 Paper (Yeager, IEEE Micro)](https://pages.cs.wisc.edu/~markhill/restricted/ieeemicro96_r10000.pdf)
- [R10000-like OoO in Verilog (Cornell)](https://people.ece.cornell.edu/land/courses/eceprojectsland/STUDENTPROJ/2006to2007/stb25/STB25_MEng_Report_Final_Version.pdf)
- [PRF Microarchitecture Lecture (ANU)](https://comp.anu.edu.au/courses/comp3710-uarch/assets/lectures/week7.pdf)
- [Register Renaming — Wikipedia](https://en.wikipedia.org/wiki/Register_renaming)
- [Sandy Bridge Microarchitecture (RealWorldTech)](https://www.realworldtech.com/sandy-bridge/5/)
- [Physical Register Inlining (UW-Madison)](https://pharm.ece.wisc.edu/papers/isca2004_egunadi.pdf)
