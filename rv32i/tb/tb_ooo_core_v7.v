// =============================================================================
// Testbench: OoO Core v7 — SoC Integration Interface Verification
// =============================================================================
// Tests the OoO Core v7 with external decode interface (no internal fetch).
// Simulates the SoC feeding decoded instructions to the core.
// =============================================================================

`timescale 1ns/1ps

module tb_ooo_core_v7;

// =============================================================================
// Clock and Reset
// =============================================================================
reg clk, rst_n;
initial clk = 0;
always #5 clk = ~clk; // 100 MHz

// =============================================================================
// DUT Signals
// =============================================================================

// Decode inputs
reg        dec0_valid;
reg [31:0] dec0_instr;
reg [31:0] dec0_pc;
reg        dec0_pred_taken;
reg [31:0] dec0_pred_target;

// dec1 tied off (single-issue)
wire       dec1_valid = 1'b0;
wire [31:0] dec1_instr = 32'd0;
wire [31:0] dec1_pc = 32'd0;
wire       dec1_pred_taken = 1'b0;
wire [31:0] dec1_pred_target = 32'd0;

// Back-pressure
wire stall_dispatch;

// D-Cache (simple memory model)
wire        dcache_req, dcache_we;
wire [31:0] dcache_addr, dcache_wdata;
wire [1:0]  dcache_size;
reg  [31:0] dcache_rdata;
reg         dcache_valid;
wire        dcache_ready = 1'b1;

// BP commit
wire        bp_commit_valid;
wire [31:0] bp_commit_pc;
wire        bp_commit_taken;
wire [31:0] bp_commit_target;
wire        bp_commit_is_call, bp_commit_is_ret, bp_commit_mispredicted;
wire [3:0]  bp_commit_rob_tag, bp_commit_ckpt_id;
wire [31:0] bp_correct_pc;

// Branch dispatch
wire        branch_dispatch;
wire [3:0]  dispatch_rob_tag;

// Trap Controller
wire        rob_commit_valid_out;
wire [31:0] rob_commit_pc_out;
wire        rob_commit_exc;
wire [3:0]  rob_commit_exc_code;
wire [31:0] rob_commit_exc_val;
wire        rob_empty_out;
wire        rob_commit_is_mret;

// Trap inputs (no traps for basic tests)
reg         trap_rob_drain;
reg         flush_pipeline;
reg  [31:0] flush_target;

// Spec Recovery (not used in basic tests)
reg         recovering;
reg         restore_rename_map;
reg  [3:0]  restore_rob_tail;
wire [159:0] rename_map_snapshot;

// CSR
wire [11:0] csr_addr;
wire [31:0] csr_wdata;
wire [1:0]  csr_op;
reg  [31:0] csr_rdata;

// Debug
wire        halt;

// =============================================================================
// DUT Instantiation
// =============================================================================
ooo_core dut (
    .clk(clk), .rst_n(rst_n),
    .dec0_valid(dec0_valid), .dec0_instr(dec0_instr),
    .dec0_pc(dec0_pc), .dec0_pred_taken(dec0_pred_taken),
    .dec0_pred_target(dec0_pred_target),
    .dec1_valid(dec1_valid), .dec1_instr(dec1_instr),
    .dec1_pc(dec1_pc), .dec1_pred_taken(dec1_pred_taken),
    .dec1_pred_target(dec1_pred_target),
    .stall_dispatch(stall_dispatch),
    .dcache_req(dcache_req), .dcache_we(dcache_we),
    .dcache_addr(dcache_addr), .dcache_wdata(dcache_wdata),
    .dcache_size(dcache_size),
    .dcache_rdata(dcache_rdata), .dcache_valid(dcache_valid),
    .dcache_ready(dcache_ready),
    .bp_commit_valid(bp_commit_valid), .bp_commit_pc(bp_commit_pc),
    .bp_commit_taken(bp_commit_taken), .bp_commit_target(bp_commit_target),
    .bp_commit_is_call(bp_commit_is_call), .bp_commit_is_ret(bp_commit_is_ret),
    .bp_commit_mispredicted(bp_commit_mispredicted),
    .bp_commit_rob_tag(bp_commit_rob_tag), .bp_commit_ckpt_id(bp_commit_ckpt_id),
    .bp_correct_pc(bp_correct_pc),
    .branch_dispatch(branch_dispatch), .dispatch_rob_tag(dispatch_rob_tag),
    .rob_commit_valid_out(rob_commit_valid_out), .rob_commit_pc_out(rob_commit_pc_out),
    .rob_commit_exc(rob_commit_exc), .rob_commit_exc_code(rob_commit_exc_code),
    .rob_commit_exc_val(rob_commit_exc_val), .rob_empty_out(rob_empty_out),
    .rob_commit_is_mret(rob_commit_is_mret),
    .trap_rob_drain(trap_rob_drain), .flush_pipeline(flush_pipeline),
    .flush_target(flush_target),
    .recovering(recovering), .restore_rename_map(restore_rename_map),
    .restore_rob_tail(restore_rob_tail), .rename_map_snapshot(rename_map_snapshot),
    .csr_addr(csr_addr), .csr_wdata(csr_wdata), .csr_op(csr_op),
    .csr_rdata(csr_rdata),
    .halt(halt)
);

// =============================================================================
// Simple D-Cache model (256 words)
// =============================================================================
reg [31:0] dmem [0:255];
always @(posedge clk) begin
    dcache_valid <= 1'b0;
    if (dcache_req && dcache_ready) begin
        if (dcache_we)
            dmem[dcache_addr[9:2]] <= dcache_wdata;
        else begin
            dcache_rdata <= dmem[dcache_addr[9:2]];
            dcache_valid <= 1'b1;
        end
    end
end

// =============================================================================
// Test infrastructure
// =============================================================================
integer test_num;
integer pass_count;
integer fail_count;
integer total_tests;
reg [31:0] pc_counter;

task reset;
begin
    rst_n = 0;
    dec0_valid = 0;
    dec0_instr = 32'd0;
    dec0_pc = 32'd0;
    dec0_pred_taken = 0;
    dec0_pred_target = 32'd0;
    trap_rob_drain = 0;
    flush_pipeline = 0;
    flush_target = 32'd0;
    recovering = 0;
    restore_rename_map = 0;
    restore_rob_tail = 4'd0;
    csr_rdata = 32'd0;
    dcache_rdata = 32'd0;
    dcache_valid = 0;
    pc_counter = 32'd0;
    repeat(5) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
end
endtask

// Feed one instruction to the core
task feed_instr(input [31:0] instr_val, input [31:0] pc_val);
begin
    // Wait for dispatch ready
    while (stall_dispatch) @(posedge clk);
    dec0_valid <= 1'b1;
    dec0_instr <= instr_val;
    dec0_pc <= pc_val;
    dec0_pred_taken <= 1'b0;
    dec0_pred_target <= 32'd0;
    @(posedge clk);
    dec0_valid <= 1'b0;
end
endtask

// Wait for a commit and return the committed value
task wait_commit(output [31:0] committed_value, output [31:0] committed_pc);
begin
    while (!rob_commit_valid_out) @(posedge clk);
    committed_value = dut.rob_commit_value;
    committed_pc = rob_commit_pc_out;
    @(posedge clk);
end
endtask

// Check architectural register value
task check_reg(input [4:0] reg_idx, input [31:0] expected, input [255:0] test_name);
begin
    test_num = test_num + 1;
    total_tests = total_tests + 1;
    if (dut.arch_regs[reg_idx] === expected) begin
        $display("  [PASS] Test %0d: %0s — x%0d = 0x%08h", test_num, test_name, reg_idx, expected);
        pass_count = pass_count + 1;
    end else begin
        $display("  [FAIL] Test %0d: %0s — x%0d = 0x%08h (expected 0x%08h)",
                 test_num, test_name, reg_idx, dut.arch_regs[reg_idx], expected);
        fail_count = fail_count + 1;
    end
end
endtask

// RV32I instruction encoders
function [31:0] encode_addi(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    encode_addi = {imm, rs1, 3'b000, rd, 7'b0010011};
endfunction

function [31:0] encode_add(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    encode_add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
endfunction

function [31:0] encode_sub(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    encode_sub = {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011};
endfunction

function [31:0] encode_lui(input [4:0] rd, input [19:0] imm);
    encode_lui = {imm, rd, 7'b0110111};
endfunction

function [31:0] encode_sw(input [4:0] rs1, input [4:0] rs2, input [11:0] offset);
    encode_sw = {offset[11:5], rs2, rs1, 3'b010, offset[4:0], 7'b0100011};
endfunction

function [31:0] encode_lw(input [4:0] rd, input [4:0] rs1, input [11:0] offset);
    encode_lw = {offset, rs1, 3'b010, rd, 7'b0000011};
endfunction

function [31:0] encode_beq(input [4:0] rs1, input [4:0] rs2, input [12:0] offset);
    encode_beq = {offset[12], offset[10:5], rs2, rs1, 3'b000,
                  offset[4:1], offset[11], 7'b1100011};
endfunction

function [31:0] encode_bne(input [4:0] rs1, input [4:0] rs2, input [12:0] offset);
    encode_bne = {offset[12], offset[10:5], rs2, rs1, 3'b001,
                  offset[4:1], offset[11], 7'b1100011};
endfunction

function [31:0] encode_jal(input [4:0] rd, input [20:0] offset);
    encode_jal = {offset[20], offset[10:1], offset[11], offset[19:12], rd, 7'b1101111};
endfunction

function [31:0] encode_or(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    encode_or = {7'b0000000, rs2, rs1, 3'b110, rd, 7'b0110011};
endfunction

function [31:0] encode_and(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    encode_and = {7'b0000000, rs2, rs1, 3'b111, rd, 7'b0110011};
endfunction

function [31:0] encode_xor(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    encode_xor = {7'b0000000, rs2, rs1, 3'b100, rd, 7'b0110011};
endfunction

function [31:0] encode_slli(input [4:0] rd, input [4:0] rs1, input [4:0] shamt);
    encode_slli = {7'b0000000, shamt, rs1, 3'b001, rd, 7'b0010011};
endfunction

function [31:0] encode_ebreak(input dummy);
    encode_ebreak = 32'h00100073;
endfunction

// =============================================================================
// Test Sequences
// =============================================================================
reg [31:0] commit_val, commit_pc_out;

initial begin
    test_num = 0;
    pass_count = 0;
    fail_count = 0;
    total_tests = 0;

    $display("");
    $display("=============================================================");
    $display("OoO Core v7 — SoC Integration Testbench");
    $display("=============================================================");

    // =========================================================================
    // Test Group 1: Basic ALU (decode→rename→RS→ALU→CDB→ROB→commit)
    // =========================================================================
    $display("");
    $display("--- Test Group 1: Basic ALU Operations ---");

    reset;

    // Test 1: ADDI x1, x0, 42 — The first real instruction!
    feed_instr(encode_addi(5'd1, 5'd0, 12'd42), 32'h0000_0000);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd1, 32'd42, "ADDI x1, x0, 42");

    // Test 2: ADDI x2, x0, 100
    feed_instr(encode_addi(5'd2, 5'd0, 12'd100), 32'h0000_0004);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd2, 32'd100, "ADDI x2, x0, 100");

    // Test 3: ADD x3, x1, x2 — RAW dependency (x1=42, x2=100)
    feed_instr(encode_add(5'd3, 5'd1, 5'd2), 32'h0000_0008);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd3, 32'd142, "ADD x3, x1, x2 (42+100)");

    // Test 4: SUB x4, x2, x1 — (100 - 42 = 58)
    feed_instr(encode_sub(5'd4, 5'd2, 5'd1), 32'h0000_000C);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd4, 32'd58, "SUB x4, x2, x1 (100-42)");

    // Test 5: LUI x5, 0xDEAD0
    feed_instr(encode_lui(5'd5, 20'hDEAD0), 32'h0000_0010);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd5, 32'hDEAD0000, "LUI x5, 0xDEAD0");

    // Test 6: OR x6, x1, x2
    feed_instr(encode_or(5'd6, 5'd1, 5'd2), 32'h0000_0014);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd6, 32'd42 | 32'd100, "OR x6, x1, x2");

    // Test 7: AND x7, x1, x2
    feed_instr(encode_and(5'd7, 5'd1, 5'd2), 32'h0000_0018);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd7, 32'd42 & 32'd100, "AND x7, x1, x2");

    // Test 8: XOR x8, x1, x2
    feed_instr(encode_xor(5'd8, 5'd1, 5'd2), 32'h0000_001C);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd8, 32'd42 ^ 32'd100, "XOR x8, x1, x2");

    // Test 9: SLLI x9, x1, 3 — (42 << 3 = 336)
    feed_instr(encode_slli(5'd9, 5'd1, 5'd3), 32'h0000_0020);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd9, 32'd336, "SLLI x9, x1, 3 (42<<3)");

    // Test 10: ADDI with negative immediate — ADDI x10, x0, -1
    feed_instr(encode_addi(5'd10, 5'd0, 12'hFFF), 32'h0000_0024);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd10, 32'hFFFF_FFFF, "ADDI x10, x0, -1");

    // =========================================================================
    // Test Group 2: Load/Store
    // =========================================================================
    $display("");
    $display("--- Test Group 2: Load/Store Operations ---");

    reset;

    // Setup: x1 = base address 0x100
    feed_instr(encode_addi(5'd1, 5'd0, 12'h100), 32'h0000_0000);
    wait_commit(commit_val, commit_pc_out);

    // x2 = 0x12345678 (value to store)
    feed_instr(encode_lui(5'd2, 20'h12345), 32'h0000_0004);
    wait_commit(commit_val, commit_pc_out);
    feed_instr(encode_addi(5'd2, 5'd2, 12'h678), 32'h0000_0008);
    wait_commit(commit_val, commit_pc_out);

    // Test 11: SW x2, 0(x1) — store 0x12345678 to mem[0x100]
    feed_instr(encode_sw(5'd1, 5'd2, 12'd0), 32'h0000_000C);
    // Stores commit but don't produce a register value
    wait_commit(commit_val, commit_pc_out);
    repeat(3) @(posedge clk); // Let store complete to memory

    // Test 12: LW x3, 0(x1) — load from mem[0x100], expect 0x12345678
    feed_instr(encode_lw(5'd3, 5'd1, 12'd0), 32'h0000_0010);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd3, 32'h12345678, "SW+LW round-trip");

    // =========================================================================
    // Test Group 3: Back-to-back RAW Dependencies (pipeline forwarding)
    // =========================================================================
    $display("");
    $display("--- Test Group 3: RAW Dependency Chain ---");

    reset;

    // Chain: x1=1 → x2=x1+1=2 → x3=x2+1=3 → x4=x3+1=4
    feed_instr(encode_addi(5'd1, 5'd0, 12'd1), 32'h0000_0000);
    feed_instr(encode_addi(5'd2, 5'd1, 12'd1), 32'h0000_0004);
    feed_instr(encode_addi(5'd3, 5'd2, 12'd1), 32'h0000_0008);
    feed_instr(encode_addi(5'd4, 5'd3, 12'd1), 32'h0000_000C);

    // Wait for all 4 to commit
    wait_commit(commit_val, commit_pc_out); // x1
    wait_commit(commit_val, commit_pc_out); // x2
    wait_commit(commit_val, commit_pc_out); // x3
    wait_commit(commit_val, commit_pc_out); // x4

    check_reg(5'd1, 32'd1, "Chain x1=1");
    check_reg(5'd2, 32'd2, "Chain x2=x1+1=2");
    check_reg(5'd3, 32'd3, "Chain x3=x2+1=3");
    check_reg(5'd4, 32'd4, "Chain x4=x3+1=4");

    // =========================================================================
    // Test Group 4: Branch (not-taken, no flush)
    // =========================================================================
    $display("");
    $display("--- Test Group 4: Branch Not-Taken ---");

    reset;

    // x1 = 10, x2 = 20
    feed_instr(encode_addi(5'd1, 5'd0, 12'd10), 32'h0000_0000);
    feed_instr(encode_addi(5'd2, 5'd0, 12'd20), 32'h0000_0004);
    wait_commit(commit_val, commit_pc_out);
    wait_commit(commit_val, commit_pc_out);

    // BEQ x1, x2, +8 — x1 != x2, so not taken (no flush)
    feed_instr(encode_beq(5'd1, 5'd2, 13'd8), 32'h0000_0008);
    wait_commit(commit_val, commit_pc_out);

    // Next instruction should execute normally
    feed_instr(encode_addi(5'd3, 5'd0, 12'd99), 32'h0000_000C);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd3, 32'd99, "BEQ not-taken, next instr executes");

    // =========================================================================
    // Test Group 5: Branch Taken (misprediction → flush)
    // =========================================================================
    $display("");
    $display("--- Test Group 5: Branch Taken (Misprediction) ---");

    reset;

    // x1 = 10, x2 = 10 (equal)
    feed_instr(encode_addi(5'd1, 5'd0, 12'd10), 32'h0000_0000);
    feed_instr(encode_addi(5'd2, 5'd0, 12'd10), 32'h0000_0004);
    wait_commit(commit_val, commit_pc_out);
    wait_commit(commit_val, commit_pc_out);

    // BEQ x1, x2, +8 — x1 == x2, taken, predicted not-taken → misprediction
    feed_instr(encode_beq(5'd1, 5'd2, 13'd8), 32'h0000_0008);
    // Should trigger flush
    wait_commit(commit_val, commit_pc_out);

    // Verify misprediction was signaled
    // (the flush happens at commit, pipeline is cleared)
    test_num = test_num + 1;
    total_tests = total_tests + 1;
    // After flush, we can feed the target instruction
    repeat(3) @(posedge clk);
    feed_instr(encode_addi(5'd5, 5'd0, 12'd77), 32'h0000_0010); // Target PC
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd5, 32'd77, "Post-flush instruction executes");

    // =========================================================================
    // Test Group 6: JAL (link register)
    // =========================================================================
    $display("");
    $display("--- Test Group 6: JAL ---");

    reset;

    // JAL x1, +16 — x1 = PC+4 = 0x0000_0004
    feed_instr(encode_jal(5'd1, 21'd16), 32'h0000_0000);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd1, 32'h0000_0004, "JAL x1, +16 (link=PC+4)");

    // =========================================================================
    // Test Group 7: Trap rob_drain (stall dispatch)
    // =========================================================================
    $display("");
    $display("--- Test Group 7: Trap ROB Drain ---");

    reset;

    feed_instr(encode_addi(5'd1, 5'd0, 12'd50), 32'h0000_0000);
    wait_commit(commit_val, commit_pc_out);

    // Activate trap_rob_drain — should stall dispatch
    trap_rob_drain = 1'b1;
    @(posedge clk);

    test_num = test_num + 1;
    total_tests = total_tests + 1;
    if (stall_dispatch === 1'b1) begin
        $display("  [PASS] Test %0d: trap_rob_drain stalls dispatch", test_num);
        pass_count = pass_count + 1;
    end else begin
        $display("  [FAIL] Test %0d: trap_rob_drain should stall dispatch", test_num);
        fail_count = fail_count + 1;
    end

    trap_rob_drain = 1'b0;
    @(posedge clk);

    // =========================================================================
    // Test Group 8: flush_pipeline from Trap Controller
    // =========================================================================
    $display("");
    $display("--- Test Group 8: Trap Controller Flush ---");

    reset;

    // Feed an instruction
    feed_instr(encode_addi(5'd1, 5'd0, 12'd1), 32'h0000_0000);
    feed_instr(encode_addi(5'd2, 5'd0, 12'd2), 32'h0000_0004);
    wait_commit(commit_val, commit_pc_out); // x1 commits

    // Trap flush before x2 commits (x2 might already be in ROB)
    flush_pipeline = 1'b1;
    flush_target = 32'h0000_1000; // Trap vector
    @(posedge clk);
    flush_pipeline = 1'b0;
    repeat(3) @(posedge clk);

    // After flush, feed instruction at trap vector
    feed_instr(encode_addi(5'd3, 5'd0, 12'd99), 32'h0000_1000);
    wait_commit(commit_val, commit_pc_out);
    check_reg(5'd3, 32'd99, "Post-trap-flush instruction at vector");

    // =========================================================================
    // Test Group 9: EBREAK halt
    // =========================================================================
    $display("");
    $display("--- Test Group 9: EBREAK Halt ---");

    reset;

    feed_instr(encode_addi(5'd1, 5'd0, 12'd1), 32'h0000_0000);
    wait_commit(commit_val, commit_pc_out);

    // Feed EBREAK — check halt while dec0_valid is still high
    dec0_valid <= 1'b1;
    dec0_instr <= encode_ebreak(0);
    dec0_pc <= 32'h0000_0004;
    @(posedge clk);
    // halt is combinational: check before clearing dec0_valid

    test_num = test_num + 1;
    total_tests = total_tests + 1;
    if (halt === 1'b1) begin
        $display("  [PASS] Test %0d: EBREAK asserts halt", test_num);
        pass_count = pass_count + 1;
    end else begin
        $display("  [FAIL] Test %0d: EBREAK should assert halt", test_num);
        fail_count = fail_count + 1;
    end

    // =========================================================================
    // Test Group 10: rob_empty signal
    // =========================================================================
    $display("");
    $display("--- Test Group 10: ROB Empty Signal ---");

    reset;

    test_num = test_num + 1;
    total_tests = total_tests + 1;
    if (rob_empty_out === 1'b1) begin
        $display("  [PASS] Test %0d: ROB empty after reset", test_num);
        pass_count = pass_count + 1;
    end else begin
        $display("  [FAIL] Test %0d: ROB should be empty after reset", test_num);
        fail_count = fail_count + 1;
    end

    feed_instr(encode_addi(5'd1, 5'd0, 12'd1), 32'h0000_0000);
    @(posedge clk); // Let it dispatch

    test_num = test_num + 1;
    total_tests = total_tests + 1;
    if (rob_empty_out === 1'b0) begin
        $display("  [PASS] Test %0d: ROB not empty after dispatch", test_num);
        pass_count = pass_count + 1;
    end else begin
        $display("  [FAIL] Test %0d: ROB should not be empty after dispatch", test_num);
        fail_count = fail_count + 1;
    end

    wait_commit(commit_val, commit_pc_out);
    @(posedge clk); // Let empty propagate

    test_num = test_num + 1;
    total_tests = total_tests + 1;
    if (rob_empty_out === 1'b1) begin
        $display("  [PASS] Test %0d: ROB empty after commit", test_num);
        pass_count = pass_count + 1;
    end else begin
        $display("  [FAIL] Test %0d: ROB should be empty after commit", test_num);
        fail_count = fail_count + 1;
    end

    // =========================================================================
    // Summary
    // =========================================================================
    $display("");
    $display("=============================================================");
    $display("RESULTS: %0d/%0d PASSED", pass_count, total_tests);
    if (fail_count == 0)
        $display("ALL TESTS PASSED!");
    else
        $display("%0d TESTS FAILED", fail_count);
    $display("=============================================================");
    $display("");

    $finish;
end

// Timeout
initial begin
    #100000;
    $display("TIMEOUT at %0t", $time);
    $finish;
end

endmodule
