# Physical Register File (PRF) Design — OoO Core v8

## Current Architecture (v7)

- **Architectural Register File** (32 × 32-bit): stores committed values
- **CDB Result Buffer** (ROB_DEPTH × 32-bit): stores in-flight results indexed by ROB tag
- **Rename Table**: maps arch reg → ROB tag (pending) or arch reg (committed)
- **Problem**: ROB tag reuse can corrupt CDB result buffer; limited speculative capacity

## Target Architecture (v8 — PRF)

### Core Components

1. **Physical Register File (64 × 32-bit)**
   - Unified storage for both committed and speculative values
   - Index: physical register number (PREG_W = 6 bits)
   - 2 read ports (RS dispatch), 1 write port (CDB writeback)
   - p0 = hardwired zero (like x0)

2. **Speculative RAT (32 entries)**
   - Maps arch reg → physical reg (current speculative mapping)
   - Updated at dispatch: old_preg = RAT[rd]; RAT[rd] = new_preg
   - Used for operand resolution at dispatch

3. **Committed RAT (32 entries)**
   - Maps arch reg → physical reg (committed mapping)
   - Updated at commit: CRAT[rd] = committed_preg
   - Used for flush recovery: Spec RAT ← Committed RAT

4. **Free List (FIFO, 32 entries)**
   - Tracks available physical registers
   - Dequeue at dispatch: allocate new preg for rd
   - Enqueue at commit: free the OLD preg (replaced by the committing instruction)
   - On flush: restore free list from checkpoint

### Data Flow

```
Dispatch:
  new_preg = FreeList.dequeue()
  old_preg = SpecRAT[rd]
  SpecRAT[rd] = new_preg
  ROB entry stores: {rd, old_preg, new_preg}
  RS entry stores: {src1_preg, src2_preg, dst_preg}

Execute:
  Read PRF[src1_preg], PRF[src2_preg]
  Compute result

CDB Broadcast:
  PRF[dst_preg] = result
  Wake up RS entries waiting for dst_preg

Commit:
  CommittedRAT[rd] = new_preg
  FreeList.enqueue(old_preg)  // Free the previous physical reg

Flush:
  SpecRAT ← CommittedRAT  (copy)
  FreeList restored from checkpoint
  All speculative PRF entries remain valid (no data loss)
```

### Changes Required per Module

| Module | Change | Effort |
|--------|--------|--------|
| ooo_core_v7 | Replace arch_regs + cdb_result with PRF instance | Medium |
| reg_rename | Output preg IDs instead of ROB tags; dual RAT | High |
| rob | Store {rd, old_preg, new_preg} instead of {rd, value} | Medium |
| reservation_station | Store preg IDs; read PRF at issue | Medium |
| cdb | Broadcast preg ID instead of ROB tag | Low |
| load_store_queue | Store preg IDs for base/data operands | Medium |

### Free List Design

**FIFO approach** (preferred for simplicity):
- 32-entry circular buffer of 6-bit preg IDs
- Head (dequeue for dispatch), Tail (enqueue from commit)
- On reset: preload entries 32-63 (0-31 are initially mapped to arch regs)
- On flush: need checkpoint or count-based restore

**Checkpoint approach** for flush recovery:
- At branch dispatch: snapshot free list head pointer + SpecRAT
- On misprediction: restore head pointer + SpecRAT from checkpoint
- 4 checkpoint slots (matching spec_recovery's 4 checkpoints)

### Implementation Plan

1. **Phase 1: PRF + Dual RAT** (v8.0)
   - New module: `phys_regfile.v` (already exists from 宁宁, 99 lines)
   - Modify `reg_rename.v` → `rename_prf.v` with Spec RAT + Committed RAT
   - New module: `free_list.v`
   - Modify `ooo_core_v7.v` → replace arch_regs/cdb_result with PRF reads

2. **Phase 2: ROB adaptation** (v8.1)
   - ROB stores old_preg/new_preg instead of value
   - Commit frees old_preg to free list
   - ROB no longer needs read ports (operands come from PRF)

3. **Phase 3: RS/LSQ adaptation** (v8.2)
   - RS stores preg IDs, reads PRF at issue time
   - CDB broadcasts preg ID instead of ROB tag
   - LSQ tracks preg IDs for address/data operands

4. **Phase 4: Checkpoint** (v8.3)
   - Free list checkpoint at branch dispatch
   - SpecRAT checkpoint (integrate with 宁宁's spec_recovery)
   - Misprediction restore from checkpoint

### Estimated Size

| New/Modified Module | Lines (est) |
|---------------------|-------------|
| free_list.v | ~80 |
| rename_prf.v | ~120 |
| ooo_core_v8.v changes | ~50 |
| rob.v changes | ~30 |
| RS changes | ~20 |
| CDB changes | ~10 |
| **Total new/changed** | **~310** |

### Key Design Decisions

1. **Free list size**: 32 entries (64 total pregs - 32 initial arch mappings)
2. **Checkpoint count**: 4 (match spec_recovery)
3. **PRF read ports**: 2 (dual-source operands at issue time)
4. **PRF write ports**: 1 (CDB broadcast)
5. **宁宁's phys_regfile.v**: already has 64-entry 2R/1W — reuse directly
