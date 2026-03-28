// =============================================================================
// Testbench for OoO Core — Verifies out-of-order execution with in-order commit
// =============================================================================
// Tests:
// 1. Simple ALU sequence (ADD, SUB, XOR) — independent instructions
// 2. RAW dependency chain — x1 = 5, x2 = x1 + 3, x3 = x2 + 7
// 3. WAW test — multiple writes to same register
// 4. Load/Store — SW then LW
// 5. Mixed ALU + Memory pipeline
// =============================================================================

`timescale 1ns / 1ps

module tb_ooo_core;

reg         clk;
reg         rst_n;

// I-Cache interface
wire [31:0] icache_addr;
reg  [31:0] icache_data;
reg         icache_valid;
reg         icache_ready;

// D-Cache interface
wire        dcache_req;
wire        dcache_we;
wire [31:0] dcache_addr;
wire [31:0] dcache_wdata;
wire [1:0]  dcache_size;
reg  [31:0] dcache_rdata;
reg         dcache_valid_r;
reg         dcache_ready_r;

// Branch predictor (simple: always predict not-taken)
wire        bp_update_en;
wire [31:0] bp_update_pc;
wire        bp_update_taken;
wire [31:0] bp_update_target;
wire        bp_update_is_ret;
wire        bp_update_is_call;

wire [31:0] pc_out;
wire        halt;

// Branch prediction inputs (driven by testbench or simple BP logic)
// Predict taken only for a specific PC (simulates BTB hit)
reg         tb_bp_taken;
reg  [31:0] tb_bp_target;
reg         tb_bp_valid;
reg  [31:0] tb_bp_pc;     // PC to predict for (BTB match)

// BP is valid only when fetch PC matches the configured BP PC
wire        bp_active = tb_bp_valid && (icache_addr == tb_bp_pc);

// BP output wires
wire        bp_branch_dispatch;
wire [3:0]  bp_dispatch_rob_tag;
wire        bp_commit_mispred;
wire [3:0]  bp_commit_mispred_tag;
wire [31:0] bp_commit_correct_pc;

// Instantiate DUT
ooo_core dut (
    .clk(clk), .rst_n(rst_n),
    .icache_addr(icache_addr), .icache_data(icache_data),
    .icache_valid(icache_valid), .icache_ready(icache_ready),
    .dcache_req(dcache_req), .dcache_we(dcache_we),
    .dcache_addr(dcache_addr), .dcache_wdata(dcache_wdata),
    .dcache_size(dcache_size),
    .dcache_rdata(dcache_rdata), .dcache_valid(dcache_valid_r),
    .dcache_ready(dcache_ready_r),
    .bp_predicted_taken(tb_bp_taken && bp_active), .bp_predicted_target(tb_bp_target),
    .bp_pred_valid(bp_active),
    .bp_update_en(bp_update_en), .bp_update_pc(bp_update_pc),
    .bp_update_taken(bp_update_taken), .bp_update_target(bp_update_target),
    .bp_update_is_ret(bp_update_is_ret), .bp_update_is_call(bp_update_is_call),
    .branch_dispatch(bp_branch_dispatch), .dispatch_rob_tag_out(bp_dispatch_rob_tag),
    .commit_mispredicted(bp_commit_mispred), .commit_mispredict_tag(bp_commit_mispred_tag),
    .commit_correct_pc(bp_commit_correct_pc),
    .pc_out(pc_out), .halt(halt)
);

// Clock generation: 10ns period
initial clk = 0;
always #5 clk = ~clk;

// Debug (uncomment for tracing):
// always @(posedge clk) begin
//     if (rst_n && dut.u_rob.commit_valid) $display("[CMT] rd=x%0d val=%h tag=%0d", dut.u_rob.commit_rd, dut.u_rob.commit_value, dut.u_rob.commit_tag);
//     if (rst_n && dut.u_rob.flush) $display("[FLUSH] target=%h", dut.u_rob.flush_target);
// end

// =============================================================================
// Instruction Memory (simple ROM)
// =============================================================================
reg [31:0] imem [0:63];

always @(*) begin
    icache_data = imem[icache_addr[7:2]]; // Word-aligned
    icache_valid = 1'b1;
    icache_ready = 1'b1;
end

// =============================================================================
// Data Memory (simple RAM, 256 bytes)
// =============================================================================
reg [31:0] dmem [0:63];
reg        dcache_pending;
reg [31:0] dcache_resp_data;

always @(posedge clk) begin
    dcache_valid_r <= 1'b0;
    if (dcache_req && !dcache_we) begin
        // Load: 1-cycle latency
        dcache_resp_data <= dmem[dcache_addr[7:2]];
        dcache_valid_r <= 1'b1;
    end
    if (dcache_req && dcache_we) begin
        // Store: write immediately
        dmem[dcache_addr[7:2]] <= dcache_wdata;
    end
end

always @(*) begin
    dcache_rdata = dcache_resp_data;
    dcache_ready_r = 1'b1;
end

// =============================================================================
// RV32I Instruction Encoding Helpers
// =============================================================================
// R-type: funct7[6:0] | rs2[4:0] | rs1[4:0] | funct3[2:0] | rd[4:0] | opcode[6:0]
function [31:0] rv_add;  input [4:0] rd, rs1, rs2; rv_add  = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011}; endfunction
function [31:0] rv_sub;  input [4:0] rd, rs1, rs2; rv_sub  = {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011}; endfunction
function [31:0] rv_xor;  input [4:0] rd, rs1, rs2; rv_xor  = {7'b0000000, rs2, rs1, 3'b100, rd, 7'b0110011}; endfunction
function [31:0] rv_or;   input [4:0] rd, rs1, rs2; rv_or   = {7'b0000000, rs2, rs1, 3'b110, rd, 7'b0110011}; endfunction
function [31:0] rv_and;  input [4:0] rd, rs1, rs2; rv_and  = {7'b0000000, rs2, rs1, 3'b111, rd, 7'b0110011}; endfunction
function [31:0] rv_sll;  input [4:0] rd, rs1, rs2; rv_sll  = {7'b0000000, rs2, rs1, 3'b001, rd, 7'b0110011}; endfunction

// I-type: imm[11:0] | rs1[4:0] | funct3[2:0] | rd[4:0] | opcode[6:0]
function [31:0] rv_addi; input [4:0] rd, rs1; input [11:0] imm; rv_addi = {imm, rs1, 3'b000, rd, 7'b0010011}; endfunction
function [31:0] rv_xori; input [4:0] rd, rs1; input [11:0] imm; rv_xori = {imm, rs1, 3'b100, rd, 7'b0010011}; endfunction
function [31:0] rv_ori;  input [4:0] rd, rs1; input [11:0] imm; rv_ori  = {imm, rs1, 3'b110, rd, 7'b0010011}; endfunction
function [31:0] rv_andi; input [4:0] rd, rs1; input [11:0] imm; rv_andi = {imm, rs1, 3'b111, rd, 7'b0010011}; endfunction

// LUI: imm[31:12] | rd[4:0] | opcode[6:0]
function [31:0] rv_lui;  input [4:0] rd; input [19:0] imm; rv_lui = {imm, rd, 7'b0110111}; endfunction

// Load: imm[11:0] | rs1[4:0] | funct3[2:0] | rd[4:0] | opcode[6:0]
function [31:0] rv_lw;   input [4:0] rd, rs1; input [11:0] off; rv_lw = {off, rs1, 3'b010, rd, 7'b0000011}; endfunction

// Store: imm[11:5] | rs2[4:0] | rs1[4:0] | funct3[2:0] | imm[4:0] | opcode[6:0]
function [31:0] rv_sw;   input [4:0] rs1, rs2; input [11:0] off; rv_sw = {off[11:5], rs2, rs1, 3'b010, off[4:0], 7'b0100011}; endfunction

// EBREAK (dummy input required by iverilog)
function [31:0] rv_ebreak; input dummy; rv_ebreak = 32'h00100073; endfunction

// NOP
function [31:0] rv_nop; input dummy; rv_nop = 32'h00000013; endfunction

// =============================================================================
// Test Programs
// =============================================================================
integer test_num;
integer pass_count;
integer fail_count;
integer cycle_count;
integer max_cycles;

task wait_halt;
    integer drain;
    begin
        cycle_count = 0;
        max_cycles = 500;
        while (!halt && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        if (cycle_count >= max_cycles) begin
            $display("TIMEOUT after %0d cycles", max_cycles);
        end else begin
            // Drain pipeline: wait for all in-flight instructions to commit
            for (drain = 0; drain < 200; drain = drain + 1) begin
                @(posedge clk);
            end
            $display("  (halted at cycle %0d, drained 30 more)", cycle_count);
        end
    end
endtask

task check_reg;
    input [4:0]  reg_num;
    input [31:0] expected;
    begin
        // Access arch_regs via hierarchical path
        if (dut.arch_regs[reg_num] === expected) begin
            $display("  PASS: x%0d = 0x%08x (expected 0x%08x)", reg_num, dut.arch_regs[reg_num], expected);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: x%0d = 0x%08x (expected 0x%08x)", reg_num, dut.arch_regs[reg_num], expected);
            fail_count = fail_count + 1;
        end
    end
endtask

task reset_cpu;
    integer ri;
    begin
        rst_n = 0;
        tb_bp_taken = 1'b0;
        tb_bp_target = 32'd0;
        tb_bp_valid = 1'b0;
        tb_bp_pc = 32'hFFFFFFFF; // No match by default
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        // Clear imem
        for (ri = 0; ri < 64; ri = ri + 1) imem[ri] = rv_nop(0);
        for (ri = 0; ri < 64; ri = ri + 1) dmem[ri] = 32'd0;
    end
endtask

// =============================================================================
// Test Execution
// =============================================================================
initial begin
    $dumpfile("tb_ooo_core.vcd");
    $dumpvars(0, tb_ooo_core);

    pass_count = 0;
    fail_count = 0;

    // =========================================================================
    // Test 1: Independent ALU instructions
    // =========================================================================
    $display("\n=== Test 1: Independent ALU instructions ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'd10);   // x1 = 10
    imem[1] = rv_addi(5'd2, 5'd0, 12'd20);   // x2 = 20
    imem[2] = rv_addi(5'd3, 5'd0, 12'd30);   // x3 = 30
    imem[3] = rv_add(5'd4, 5'd0, 5'd0);      // x4 = 0 (nop-like)
    imem[4] = rv_ebreak(0);
    wait_halt();
    check_reg(1, 32'd10);
    check_reg(2, 32'd20);
    check_reg(3, 32'd30);

    // =========================================================================
    // Test 2: RAW dependency chain
    // =========================================================================
    $display("\n=== Test 2: RAW dependency chain ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'd5);    // x1 = 5
    imem[1] = rv_addi(5'd2, 5'd1, 12'd3);    // x2 = x1 + 3 = 8
    imem[2] = rv_addi(5'd3, 5'd2, 12'd7);    // x3 = x2 + 7 = 15
    imem[3] = rv_ebreak(0);
    wait_halt();
    check_reg(1, 32'd5);
    check_reg(2, 32'd8);
    check_reg(3, 32'd15);

    // =========================================================================
    // Test 3: WAW — multiple writes to same register
    // =========================================================================
    $display("\n=== Test 3: WAW — multiple writes to same register ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'd100);  // x1 = 100
    imem[1] = rv_addi(5'd1, 5'd0, 12'd200);  // x1 = 200 (overwrites)
    imem[2] = rv_addi(5'd1, 5'd0, 12'd300);  // x1 = 300 (overwrites again)
    imem[3] = rv_ebreak(0);
    wait_halt();
    check_reg(1, 32'd300);

    // =========================================================================
    // Test 4: ALU register-register ops (full)
    // =========================================================================
    $display("\n=== Test 4: ALU register-register ops ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'd15);   // x1 = 15
    imem[1] = rv_addi(5'd2, 5'd0, 12'd10);   // x2 = 10
    imem[2] = rv_add(5'd3, 5'd1, 5'd2);      // x3 = 25
    imem[3] = rv_sub(5'd4, 5'd1, 5'd2);      // x4 = 5
    imem[4] = rv_xor(5'd5, 5'd1, 5'd2);      // x5 = 5
    imem[5] = rv_or(5'd6, 5'd1, 5'd2);       // x6 = 15
    imem[6] = rv_and(5'd7, 5'd1, 5'd2);      // x7 = 10
    imem[7] = rv_ebreak(0);
    wait_halt();
    check_reg(3, 32'd25);
    check_reg(4, 32'd5);
    check_reg(5, 32'd5);
    check_reg(6, 32'd15);
    check_reg(7, 32'd10);

    // =========================================================================
    // Test 5: BEQ not-taken (fall through)
    // =========================================================================
    $display("\n=== Test 5: BEQ not-taken ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'd5);    // x1 = 5
    imem[1] = rv_addi(5'd2, 5'd0, 12'd10);   // x2 = 10
    // BEQ x1, x2, +8 (skip next) — NOT taken since 5 != 10
    imem[2] = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'b01000, 7'b1100011}; // BEQ x1,x2,+8
    imem[3] = rv_addi(5'd3, 5'd0, 12'd42);   // x3 = 42 (should execute)
    imem[4] = rv_ebreak(0);
    wait_halt();
    check_reg(1, 32'd5);
    check_reg(2, 32'd10);
    check_reg(3, 32'd42);  // Should execute since branch not taken

    // =========================================================================
    // Test 6: BEQ taken (branch forward)
    // =========================================================================
    $display("\n=== Test 6: BEQ taken ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'd5);    // x1 = 5
    imem[1] = rv_addi(5'd2, 5'd0, 12'd5);    // x2 = 5
    // BEQ x1, x2, +8 (skip next) — TAKEN since 5 == 5
    imem[2] = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'b01000, 7'b1100011}; // BEQ x1,x2,+8
    imem[3] = rv_addi(5'd3, 5'd0, 12'd99);   // x3 = 99 (should be skipped)
    imem[4] = rv_addi(5'd4, 5'd0, 12'd77);   // x4 = 77 (branch target)
    imem[5] = rv_ebreak(0);
    wait_halt();
    check_reg(1, 32'd5);
    check_reg(2, 32'd5);
    check_reg(4, 32'd77);  // Branch target reached

    // =========================================================================
    // Test 7: BNE loop (sum 1 to 5)
    // x1 = counter (starts at 5), x2 = sum (starts at 0)
    // Loop: sum += counter; counter--; if counter != 0, loop back
    // Result: sum = 15
    // =========================================================================
    $display("\n=== Test 7: BNE loop (sum 1..5) ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'd5);    // x1 = 5 (counter)
    imem[1] = rv_addi(5'd2, 5'd0, 12'd0);    // x2 = 0 (sum)
    // Loop body at PC=8:
    imem[2] = rv_add(5'd2, 5'd2, 5'd1);      // x2 = x2 + x1
    imem[3] = rv_addi(5'd1, 5'd1, 12'hFFF);  // x1 = x1 - 1 (addi -1)
    // BNE x1, x0, -8 (back to imem[2])
    // B-type encoding for offset=-8: imm=-8=0xFFFFFFF8
    // imm[12]=1, imm[11]=1, imm[10:5]=111111, imm[4:1]=1100
    // {imm[12],imm[10:5]} = 7'b1111111, rs2=x0=0, rs1=x1=1, f3=001(BNE), {imm[4:1],imm[11]} = 5'b11001
    imem[4] = {7'b1111111, 5'd0, 5'd1, 3'b001, 5'b11001, 7'b1100011}; // BNE x1,x0,-8
    imem[5] = rv_ebreak(0);
    wait_halt();
    check_reg(1, 32'd0);   // counter should be 0
    check_reg(2, 32'd15);  // sum = 5+4+3+2+1 = 15

    // =========================================================================
    // Test 8: BLT taken (signed less-than)
    // =========================================================================
    $display("\n=== Test 8: BLT taken ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'hFFE);  // x1 = -2 (signed)
    imem[1] = rv_addi(5'd2, 5'd0, 12'd5);    // x2 = 5
    // BLT x1, x2, +8 — TAKEN since -2 < 5
    imem[2] = {7'b0000000, 5'd2, 5'd1, 3'b100, 5'b01000, 7'b1100011}; // BLT x1,x2,+8
    imem[3] = rv_addi(5'd3, 5'd0, 12'd99);   // skipped
    imem[4] = rv_addi(5'd4, 5'd0, 12'd33);   // branch target
    imem[5] = rv_ebreak(0);
    wait_halt();
    check_reg(4, 32'd33);  // Branch target reached

    // =========================================================================
    // Test 9: BGE not-taken (signed greater-or-equal)
    // =========================================================================
    $display("\n=== Test 9: BGE not-taken ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'hFFE);  // x1 = -2 (signed)
    imem[1] = rv_addi(5'd2, 5'd0, 12'd5);    // x2 = 5
    // BGE x1, x2, +8 — NOT taken since -2 < 5
    imem[2] = {7'b0000000, 5'd2, 5'd1, 3'b101, 5'b01000, 7'b1100011}; // BGE x1,x2,+8
    imem[3] = rv_addi(5'd3, 5'd0, 12'd44);   // should execute
    imem[4] = rv_ebreak(0);
    wait_halt();
    check_reg(3, 32'd44);  // Fall-through executed

    // =========================================================================
    // Test 10: BLTU (unsigned less-than)
    // =========================================================================
    $display("\n=== Test 10: BLTU ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'd3);    // x1 = 3
    imem[1] = rv_addi(5'd2, 5'd0, 12'hFFE);  // x2 = 0xFFFFFFE = -2 signed, but huge unsigned
    // BLTU x1, x2, +8 — TAKEN since 3 < 0xFFFFFFFE unsigned
    imem[2] = {7'b0000000, 5'd2, 5'd1, 3'b110, 5'b01000, 7'b1100011}; // BLTU x1,x2,+8
    imem[3] = rv_addi(5'd3, 5'd0, 12'd99);   // skipped
    imem[4] = rv_addi(5'd4, 5'd0, 12'd55);   // branch target
    imem[5] = rv_ebreak(0);
    wait_halt();
    check_reg(4, 32'd55);  // Branch target reached

    // =========================================================================
    // Test 11: BGEU (unsigned greater-or-equal)
    // =========================================================================
    $display("\n=== Test 11: BGEU ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'hFFE);  // x1 = 0xFFFFFFFE (huge unsigned)
    imem[1] = rv_addi(5'd2, 5'd0, 12'd3);    // x2 = 3
    // BGEU x1, x2, +8 — TAKEN since 0xFFFFFFFE >= 3 unsigned
    imem[2] = {7'b0000000, 5'd2, 5'd1, 3'b111, 5'b01000, 7'b1100011}; // BGEU x1,x2,+8
    imem[3] = rv_addi(5'd3, 5'd0, 12'd99);   // skipped
    imem[4] = rv_addi(5'd4, 5'd0, 12'd66);   // branch target
    imem[5] = rv_ebreak(0);
    wait_halt();
    check_reg(4, 32'd66);  // Branch target reached

    // =========================================================================
    // Test 12: Predict-taken CORRECT (BP says taken, actually taken)
    // BP predicts branch at PC=8 taken to PC=16. Branch IS taken (5==5).
    // No misprediction — should follow prediction.
    // =========================================================================
    $display("\n=== Test 12: Predict-taken correct ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'd5);    // x1 = 5
    imem[1] = rv_addi(5'd2, 5'd0, 12'd5);    // x2 = 5
    // BEQ x1, x2, +8 at PC=8 — TAKEN
    imem[2] = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'b01000, 7'b1100011};
    imem[3] = rv_addi(5'd3, 5'd0, 12'd99);   // skipped (should not execute)
    imem[4] = rv_addi(5'd4, 5'd0, 12'd88);   // target (should execute)
    imem[5] = rv_ebreak(0);
    // Enable BP prediction: when PC=8, predict taken to PC=16
    tb_bp_valid = 1'b1;
    tb_bp_taken = 1'b1;
    tb_bp_target = 32'h10; // PC=16
    tb_bp_pc = 32'h08;     // Only predict for the branch at PC=8
    wait_halt();
    check_reg(4, 32'd88);  // Branch target reached

    // =========================================================================
    // Test 13: Predict-taken WRONG (BP says taken, actually NOT taken)
    // BP predicts branch at PC=8 taken to PC=16. But 5!=10 so BEQ NOT taken.
    // Misprediction → flush → redirect to PC+4=12
    // =========================================================================
    $display("\n=== Test 13: Predict-taken wrong ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'd5);    // x1 = 5
    imem[1] = rv_addi(5'd2, 5'd0, 12'd10);   // x2 = 10
    // BEQ x1, x2, +8 at PC=8 — NOT TAKEN (5 != 10)
    imem[2] = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'b01000, 7'b1100011};
    imem[3] = rv_addi(5'd3, 5'd0, 12'd42);   // fall-through (should execute)
    imem[4] = rv_addi(5'd4, 5'd0, 12'd88);   // BP target (should NOT get value from this iteration)
    imem[5] = rv_ebreak(0);
    // Enable BP prediction: predict taken (WRONG — actually not taken)
    tb_bp_valid = 1'b1;
    tb_bp_taken = 1'b1;
    tb_bp_target = 32'h10;
    tb_bp_pc = 32'h08;     // Only predict for the branch at PC=8
    wait_halt();
    check_reg(3, 32'd42);  // Fall-through should execute after misprediction recovery

    // =========================================================================
    // Test 14: Two branches, both not-taken (sequential execution)
    // Tests that multiple branches in sequence work correctly
    // =========================================================================
    $display("\n=== Test 14: Two sequential branches ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'd5);    // x1 = 5
    imem[1] = rv_addi(5'd2, 5'd0, 12'd10);   // x2 = 10
    // BEQ x1, x2, +8 at PC=8 — NOT taken (5 != 10)
    imem[2] = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'b01000, 7'b1100011};
    imem[3] = rv_addi(5'd3, 5'd0, 12'd11);   // x3 = 11 (executes)
    // BEQ x1, x2, +8 at PC=16 — NOT taken (5 != 10)
    imem[4] = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'b01000, 7'b1100011};
    imem[5] = rv_addi(5'd4, 5'd0, 12'd22);   // x4 = 22 (executes)
    imem[6] = rv_ebreak(0);
    wait_halt();
    check_reg(3, 32'd11);
    check_reg(4, 32'd22);

    // =========================================================================
    // Test 15: Two branches, both taken (consecutive mispredictions)
    // First branch taken → flush → second branch taken → flush
    // =========================================================================
    $display("\n=== Test 15: Consecutive taken branches ===");
    reset_cpu();
    imem[0] = rv_addi(5'd1, 5'd0, 12'd5);    // x1 = 5
    imem[1] = rv_addi(5'd2, 5'd0, 12'd5);    // x2 = 5
    // BEQ x1, x2, +8 at PC=8 — TAKEN → skip imem[3], go to imem[4]
    imem[2] = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'b01000, 7'b1100011};
    imem[3] = rv_addi(5'd3, 5'd0, 12'd99);   // skipped
    // BEQ x1, x2, +8 at PC=16 — TAKEN → skip imem[5], go to imem[6]
    imem[4] = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'b01000, 7'b1100011};
    imem[5] = rv_addi(5'd4, 5'd0, 12'd99);   // skipped
    imem[6] = rv_addi(5'd5, 5'd0, 12'd33);   // x5 = 33 (final target)
    imem[7] = rv_ebreak(0);
    wait_halt();
    check_reg(5, 32'd33);  // Both branches taken, reached final target

    // =========================================================================
    // Test 16: LUI
    // =========================================================================
    $display("\n=== Test 16: LUI ===");
    reset_cpu();
    imem[0] = rv_lui(5'd1, 20'hDEADB);       // x1 = 0xDEADB000
    imem[1] = rv_ebreak(0);
    wait_halt();
    check_reg(1, 32'hDEADB000);

    // =========================================================================
    // Summary
    // =========================================================================
    $display("\n========================================");
    $display("OoO Core Tests: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("========================================\n");

    if (fail_count == 0)
        $display("ALL TESTS PASSED");
    else
        $display("SOME TESTS FAILED");

    $finish;
end

endmodule
