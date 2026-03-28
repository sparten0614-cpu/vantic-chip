# Tomasulo Algorithm Implementation Research

Compiled: 2026-03-21 | Focus: RTL pitfalls + open-source OoO RS designs

---

## Part 1: Tomasulo Implementation Pitfalls

### 1.1 WAW Hazards in the ROB

**The Problem:** WAW (Write-After-Write) hazards occur when two instructions write to the
same architectural register. With register renaming, WAW is logically eliminated—each
instruction writes to a different physical register. The hazard resurfaces at **commit time**
if the ROB does not correctly track which physical register is the *final* writer.

**Common Bugs:**
- **Stale mapping on commit:** When instruction A (older) and instruction B (newer) both
  write to `x5`, the ROB must free A's physical register at A's commit, but the RAT must
  point to B's physical register. Bug: freeing B's physical register instead of A's, or
  updating the committed RAT to point to A's result after B has already committed.
- **Multiple commits per cycle:** In superscalar commit (e.g., BOOM commits an entire ROB
  row), if two instructions in the same commit group write to the same architectural
  register, only the *younger* instruction's mapping should survive. Failing to process
  intra-group WAW ordering causes the wrong physical register to be freed.
- **Speculative WAW + misprediction:** If both A and B are speculative and the branch
  before B is mispredicted, B is squashed but A's mapping must be restored. The snapshot
  mechanism must capture the state *before* B renamed, not after.

**Practical Advice:**
- Track the "stale physical destination" (pdst_old) at rename time. At commit, free
  pdst_old—never the current pdst. BOOM does exactly this.
- For superscalar commit, process the commit group in program order and let later
  writes to the same register overwrite earlier ones in the committed RAT.

### 1.2 CDB Broadcast Timing

**Same-Cycle Forwarding vs. Next-Cycle:**

This is one of the most FAQ-level bugs in student and hobbyist implementations. The
question: when a functional unit produces a result and broadcasts it on the CDB, can a
reservation station capture that value and issue a dependent instruction in the **same**
cycle, or must it wait until the **next** cycle?

**Option A — Same-cycle forwarding (combinational bypass):**
- The CDB result is combinationally wired into the RS comparators and the register file
  write port simultaneously.
- A dependent instruction can wake up in the same cycle the result appears on the CDB,
  and potentially issue the next cycle.
- Creates a long combinational path: FU output → CDB → tag match → wake-up → select.
- Difficult to meet timing at high frequencies.

**Option B — Next-cycle capture (registered CDB):**
- The CDB write is registered. RSs see the value one cycle later.
- Simpler timing but adds one cycle of latency to every dependency chain.
- Most practical RTL implementations use this approach.

**Common Bugs:**
- **Mixing the two models:** E.g., the register file sees the CDB value same-cycle
  (bypassed write), but the RS comparators use the registered version. An instruction
  dispatched in the same cycle as a CDB broadcast may read stale data from the register
  file while the RS correctly waits—or vice versa.
- **CDB arbitration glitches:** When multiple FUs finish simultaneously and you multiplex
  onto a single CDB, the arbitration must be stable for the entire cycle. A priority
  encoder that changes output mid-cycle (due to combinational loops) causes phantom
  wakeups.
- **Write-after-read in the register file:** If the CDB writes to the register file and
  a dispatching instruction reads the register file in the same cycle, you need to
  decide: does the read see the old or new value? The answer must be consistent with
  whether the RS will also capture the CDB value via tag match.

**Practical Advice:**
- Pick one model and enforce it everywhere. For a first implementation, next-cycle
  capture is far safer.
- If using same-cycle forwarding, explicitly pipeline the wake-up → select path so the
  critical path is: (cycle N) CDB broadcast + tag match + wake up; (cycle N+1) select +
  register read + issue. BOOM calls this "fast wakeup" for single-cycle ALU ops.
- Use a single CDB arbiter with fixed priority. Round-robin is more fair but adds
  complexity; fixed priority is fine for a first implementation.

### 1.3 Reservation Station Wake-up Logic Race Conditions

**The Problem:** Wake-up logic monitors CDB tags and compares them against the source
operand tags stored in each RS entry. When a match occurs, the operand is marked ready.
The select logic then picks a ready instruction to issue.

**Race Conditions:**
- **Wake-up vs. dispatch race:** An instruction is dispatched to the RS in the same cycle
  that its source operand appears on the CDB. If the dispatch path reads the register
  file (getting stale data) but does not also snoop the CDB, the RS entry will have
  stale data and a tag that no future CDB broadcast will match. The instruction hangs
  forever.
  - **Fix:** At dispatch, check if any source operand tag matches the current CDB tag.
    If so, grab the value from the CDB instead of the register file.
- **Wake-up vs. select race:** In designs with same-cycle wake-up, the select logic must
  not pick an instruction that was woken up in the *current* cycle if the data is not
  yet available (registered CDB). This is the most common cause of "instruction issued
  with wrong operand" bugs.
  - **Fix:** Use a two-phase approach: wake-up in cycle N sets a "ready" flag; select in
    cycle N+1 picks from ready instructions.
- **Multiple CDB wake-ups:** If an RS entry is waiting on two operands and both appear
  on different CDBs in the same cycle, ensure both are captured. A common bug is to
  check CDB0 first, and if it matches operand A, skip checking CDB1 for operand B.
  - **Fix:** Check all CDBs against all pending operands independently (parallel match).

**Scalability Note (from BOOM docs):** Wake-up logic grows quadratically with issue width
(each RS entry must compare against each CDB). This is the primary reason BOOM splits
into separate integer, FP, and memory issue queues. For a small RV32I core, a unified
queue is fine.

### 1.4 Speculative Execution Cleanup on Branch Misprediction

**The Problem:** On a misprediction, all instructions younger than the mispredicted branch
must be squashed. This affects the ROB, RS, register rename tables, and the free list.

**Key Mechanisms (from BOOM):**

- **Branch Mask:** Each in-flight instruction carries a bitmask indicating which
  unresolved branches it depends on. When branch N resolves correctly, bit N is cleared
  from all masks. On misprediction of branch N, all instructions with bit N set are
  killed. This is the most hardware-efficient approach.
- **RAT Snapshots:** BOOM takes a full snapshot of the rename map table at each branch.
  On misprediction, the snapshot is restored in a single cycle. Cost: one full RAT copy
  per in-flight branch. For RV32I with 32 registers and 4-8 in-flight branches, this is
  32 × ceil(log2(phys_regs)) × N_branches bits—manageable.
- **Free List Recovery:** BOOM maintains an "allocation list" per branch that tracks
  which physical registers were allocated after that branch. On misprediction, these
  registers are OR'd back into the free list. Without this, physical registers leak on
  every misprediction until the processor stalls.

**Common Bugs:**
- **Partial squash:** Killing ROB entries but forgetting to also kill matching RS entries.
  The orphaned RS entry may later issue with garbage data.
- **Store buffer corruption:** Stores younger than the mispredicted branch must be removed
  from the store buffer. BOOM ensures stores cannot be sent to memory until committed.
- **Free list leak (BOOM-documented edge case):** A physical register allocated after a
  snapshot, then freed, then *reallocated* before the misprediction is detected—neither
  the snapshot nor the current free list properly tracks it. This is a known subtle bug
  that can cause eventual processor livelock.
- **Branch mask exhaustion:** If you run out of branch mask bits (e.g., 4 bits = max 4
  in-flight branches), dispatch must stall. Forgetting to stall causes silent corruption.

**Practical Advice:**
- Implement branch masks from day one. The alternative (ROB rollback one entry at a
  time) works but is extremely slow on mispredictions—BOOM supports both modes.
- Always flush the RS, ROB, and store buffer in the same cycle on misprediction.
- Test with tight branch loops (branch every 2 instructions) to stress the snapshot/
  recovery logic.

### 1.5 Register Renaming Edge Cases

**RAT Consistency:**
- **Dispatch-width > 1:** When dispatching two instructions in the same cycle where the
  first writes to `x5` and the second reads `x5`, the second instruction must see the
  *first* instruction's physical register mapping, not the one from the RAT at the start
  of the cycle. This requires intra-group bypass in the rename stage.
- **x0 handling (RISC-V specific):** Register `x0` is hardwired to zero. It must never be
  renamed. Any instruction writing to `x0` should not allocate a physical register.
  Forgetting this wastes physical registers and can corrupt the free list.
- **Exception during rename:** If the second instruction in a rename group causes a
  structural stall (e.g., free list empty), the first instruction's rename must either
  be committed or rolled back atomically. Partial rename of a group is a bug.

**Free List Management:**
- The free list must have enough entries: `num_phys_regs - num_arch_regs` entries
  available. For RV32I with 64 physical registers: 32 free list entries at reset.
- On reset, architectural registers 0-31 map to physical registers 0-31, and physical
  registers 32-63 are on the free list.

**Busy Table Timing:**
- The busy table marks a physical register as "busy" at rename (when allocated) and
  "not busy" when the instruction writes back. If writeback and rename happen in the
  same cycle for the same physical register (after it was freed and reallocated), the
  busy table must prioritize the *rename* (set busy), not the writeback (clear busy).
  Getting this wrong causes a dependent instruction to read a stale value.

---

## Part 2: Open-Source OoO Reservation Station Designs

### 2.1 BOOM (Berkeley Out-of-Order Machine) — Chisel/RISC-V

**Source:** https://github.com/riscv-boom/riscv-boom
**Language:** Chisel (Scala-based HDL), generates Verilog
**ISA:** RV64GC (configurable)
**Inspiration:** MIPS R10000, Alpha 21264

**RS / Issue Queue Design:**
- Uses unified Physical Register File with explicit renaming (not ROB-based data storage)
- **Split issue queues:** Separate queues for integer, floating-point, and memory ops
- Each queue entry stores: opcode, source tags (2), source ready bits, destination tag,
  branch mask, ROB index, immediate data, and functional unit type

**Issue Policy:**
- Supports two modes (configurable):
  - **Unordered (R10K-style):** Instructions fill first available slot. Select uses a
    static priority encoder. Risk: pathologically poor performance when branches are in
    low-priority slots.
  - **Age-ordered (collapsing queue):** Instructions enter at the bottom and shift up
    each cycle. Oldest ready instruction has highest priority. Better performance but
    uses more energy due to shifting.

**Wake-up Logic:**
- **Fast wake-up:** For single-cycle ALU results. When an ALU instruction is *issued*
  (not completed), its destination tag is broadcast. Dependent instructions can be
  selected the next cycle, reading the result via the bypass network. This is
  speculative—if the issuing instruction is later killed, dependents must be replayed.
- **Slow wake-up:** For multi-cycle ops (FP, loads). Wake-up occurs at writeback time
  when the result is guaranteed to be in the register file.

**Structural Hazard Handling:**
- Unpipelined units (e.g., divider) are marked busy; the issue queue will not select
  instructions targeting busy units.
- Issue queue full → dispatch stalls.

**Branch Recovery:**
- Branch mask per instruction (described in Section 1.4 above)
- RAT snapshots per branch, single-cycle restore
- Free list allocation lists per branch

### 2.2 NaxRiscv — SpinalHDL/RISC-V

**Source:** https://github.com/SpinalHDL/NaxRiscv
**Language:** SpinalHDL (Scala-based, generates Verilog)
**ISA:** RV32/RV64 IMAFDC (configurable)

**Architecture:**
- Superscalar OoO with register renaming
- Configurable width: e.g., 2-decode, 3-execution, 2-retire
- Plugin-based architecture—each pipeline stage is composed of plugins that can extend
  or modify behavior

**RS Design:**
- Uses an `ExecutionUnitBase` plugin as the skeleton for execution pipelines
- Each execution unit has its own dispatch/issue queue
- Physical register allocation happens in the frontend; "architectural to physical"
  mapping followed by "physical to ROB ID" conversion

**Notable Design Decisions:**
- Multi-port memories are transformed into groups of simple dual-port RAMs with XOR-based
  glue logic (custom SpinalHDL transformation) to improve FPGA synthesis
- Developer acknowledges architectural decisions that "prevent NaxRiscv scaling up" for
  multi-core on constrained FPGAs—successor VexiiRiscv addresses this
- Critical path issues observed at 100MHz on Nexys Video FPGA in quad-core configs

**Limitations for Reference:**
- Documentation is sparse; much of the architecture must be read from source code
- Less mature than BOOM; fewer published design rationale documents

### 2.3 RIDECORE — Verilog/RISC-V

**Source:** https://github.com/ridecore/ridecore
**Language:** Verilog HDL
**ISA:** RV32IM

**Architecture:**
- Based on "Modern Processor Design: Fundamentals of Superscalar Processors" (Shen/Lipasti)
- Pure Verilog implementation—easiest to read for someone writing their own RTL
- Classic Tomasulo-style with reservation stations and CDB

**RS Design:**
- Reservation stations and load buffers share a similar structure (documented in their
  codebase). Load buffer implementation can serve as a template for RS entries.
- Unified CDB for result broadcast

**Why It Matters:**
- Smallest and simplest OoO RISC-V core in Verilog
- Good starting point for understanding how Tomasulo maps to actual RTL
- Directly implements the textbook architecture without heavy abstraction layers

### 2.4 RSD (RISC-V Superscalar with Dynamic scheduling)

**Source:** https://github.com/rsd-devel/rsd
**Language:** SystemVerilog
**ISA:** RV32IM

**Architecture:**
- 2-fetch front-end, 6-issue back-end
- Up to 64 in-flight instructions (configurable)
- High-speed speculative instruction scheduler with **replay mechanism**
- Speculative OoO load/store execution with dynamic memory disambiguation

**Key Differentiators:**
- FPGA-optimized RAM structures (important for anyone targeting FPGA synthesis)
- Replay mechanism in the scheduler: if a speculative issue turns out to be wrong (e.g.,
  cache miss on a load that was predicted to hit), the instruction is replayed from the
  issue queue rather than re-fetched. This is more complex but avoids full pipeline flush.
- Compact enough for small FPGAs while maintaining aggressive OoO features

---

## Part 3: Comparison Summary

| Feature              | BOOM           | NaxRiscv       | RIDECORE       | RSD            |
|----------------------|----------------|----------------|----------------|----------------|
| Language             | Chisel         | SpinalHDL      | Verilog        | SystemVerilog  |
| ISA                  | RV64GC         | RV32/64IMAFDC  | RV32IM         | RV32IM         |
| RS Structure         | Split IQ       | Per-EU queues  | Unified RS     | Unified + replay|
| Issue Policy         | Age/Unordered  | Per-plugin     | Priority       | Speculative    |
| Wake-up              | Fast + Slow    | Unknown        | CDB snoop      | CDB + replay   |
| Branch Recovery      | Mask+Snapshot  | Plugin-based   | Flush          | Selective flush|
| Complexity           | Very High      | High           | Low            | Medium-High    |
| Best For             | Research/Ref   | SpinalHDL users| Learning RTL   | FPGA targets   |

---

## Part 4: Practical Implementation Checklist

For a first-time Tomasulo/OoO implementation in Verilog (RV32I scale):

1. **Start with next-cycle CDB capture.** Same-cycle bypass is an optimization—get
   correctness first.

2. **Implement the dispatch-CDB snoop.** At dispatch time, check if any source operand
   tag matches the current CDB broadcast. This single check prevents the most common
   hang bug.

3. **Use branch masks.** Even if you only support 4 in-flight branches (4-bit mask), this
   is dramatically simpler than ROB-unwind recovery.

4. **Take RAT snapshots at branches.** For RV32I with 64 physical regs, each snapshot is
   32 × 6 = 192 bits. Four snapshots = 768 bits. Cheap.

5. **Track pdst_old at rename.** This is the key to correct WAW handling and physical
   register freeing. The committed RAT tells you what to free; pdst_old is the mechanism.

6. **Never rename x0.** Hardwire x0's mapping to physical register 0 and never allocate
   or free it.

7. **Flush RS + ROB + store buffer atomically on misprediction.** Use the branch mask to
   selectively kill entries.

8. **Test with pathological sequences:**
   - WAW: `add x1, x2, x3; add x1, x4, x5` — does x1 get the right final value?
   - RAW after WAW: `add x1, x2, x3; add x1, x4, x5; add x6, x1, x7` — does x6 use
     the second add's result?
   - Branch-heavy: branches every 2 instructions with alternating taken/not-taken
   - Structural hazard: fill all RS entries, verify dispatch stalls correctly
   - Free list exhaustion: long dependency chain that prevents any commits

9. **Busy table priority:** If writeback and rename race on the same physical register in
   the same cycle, rename (set busy) wins.

10. **Single CDB first, then widen.** Multiple CDBs require parallel tag match in every RS
    entry. For RV32I with a small number of FUs, one CDB is sufficient and far simpler.

---

## Sources

- [BOOM Documentation](https://docs.boom-core.org/en/latest/)
- [BOOM Issue Units](https://docs.boom-core.org/en/latest/sections/issue-units.html)
- [BOOM Rename Stage](https://docs.boom-core.org/en/latest/sections/rename-stage.html)
- [BOOM ROB](https://docs.boom-core.org/en/latest/sections/reorder-buffer.html)
- [NaxRiscv GitHub](https://github.com/SpinalHDL/NaxRiscv)
- [NaxRiscv Documentation](https://spinalhdl.github.io/NaxRiscv-Rtd/main/NaxRiscv/introduction/index.html)
- [RIDECORE GitHub](https://github.com/ridecore/ridecore)
- [RSD GitHub](https://github.com/rsd-devel/rsd)
- [OR1K Marocchino Tomasulo Implementation](https://stffrdhrn.github.io/hardware/embedded/openrisc/2019/10/21/or1k_marocchino_tomasulo.html)
- [OoO CPU Development Blog](https://screamingpigeon.github.io/projects/ooo_pt1/)
- [Register Renaming with ROB (MIT)](https://csg.csail.mit.edu/6.375/6_375_2013_www/handouts/finals/group7_report.pdf)
- [Tomasulo's Algorithm - Wikipedia](https://en.wikipedia.org/wiki/Tomasulo's_algorithm)
