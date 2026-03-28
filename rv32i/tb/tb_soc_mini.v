// =============================================================================
// SoC Mini Testbench — OoO Core v7 + Fetch Stub + D-Mem Stub
// =============================================================================
// Validates that v7 can receive instructions from a SoC-style fetch stage
// and execute them correctly. Simulates the minimal SoC integration path:
//   Fetch Stub (program ROM) → OoO Core v7 → D-Mem Stub
//
// This is the stepping stone to full i7_soc_top.v integration.
// =============================================================================

`timescale 1ns/1ps

module tb_soc_mini;

// =============================================================================
// Clock and Reset
// =============================================================================
reg clk, rst_n;
initial clk = 0;
always #5 clk = ~clk;

// =============================================================================
// Program ROM — holds the test program
// =============================================================================
reg [31:0] program_rom [0:63]; // 64 instructions max
reg [31:0] program_size;       // Number of instructions

// Forward declarations
wire stall_dispatch;
wire halt;
wire pipeline_flush_out;

// =============================================================================
// Fetch Stub — reads from program ROM, feeds to OoO Core
// =============================================================================
reg [31:0] fetch_pc;
wire       fetch_stall;
reg        fetch_valid;
reg [31:0] fetch_instr;
reg [31:0] fetch_pc_out;

// Simple fetch: read one instruction per cycle from ROM, stall when OoO says so
always @(posedge clk) begin
    if (!rst_n) begin
        fetch_pc <= 32'd0;
        fetch_valid <= 1'b0;
        fetch_instr <= 32'd0;
        fetch_pc_out <= 32'd0;
    end else if (pipeline_flush_out) begin
        // On flush, redirect to flush target (like real SoC)
        fetch_pc <= dut.pipeline_flush_target;
        fetch_valid <= 1'b0;
    end else if (!fetch_stall && !halt && (fetch_pc[31:2] < program_size)) begin
        fetch_valid <= 1'b1;
        fetch_instr <= program_rom[fetch_pc[31:2]]; // Word-aligned
        fetch_pc_out <= fetch_pc;
        fetch_pc <= fetch_pc + 32'd4;
    end else if (fetch_pc[31:2] >= program_size) begin
        fetch_valid <= 1'b0; // No more instructions
    end
end

// =============================================================================
// OoO Core v7 DUT
// =============================================================================
assign fetch_stall = stall_dispatch;

// D-Cache signals
wire        dcache_req, dcache_we;
wire [31:0] dcache_addr, dcache_wdata;
wire [1:0]  dcache_size;
reg  [31:0] dcache_rdata;
reg         dcache_valid;
wire        dcache_ready = 1'b1;

// BP commit
wire        bp_commit_valid;
wire [31:0] bp_commit_pc, bp_commit_target, bp_correct_pc;
wire        bp_commit_taken, bp_commit_is_call, bp_commit_is_ret, bp_commit_mispredicted;
wire [3:0]  bp_commit_rob_tag, bp_commit_ckpt_id;

// Branch dispatch
wire        branch_dispatch;
wire [3:0]  dispatch_rob_tag;

// Trap Controller outputs
wire        rob_commit_valid_out;
wire [31:0] rob_commit_pc_out;
wire        rob_commit_exc;
wire [3:0]  rob_commit_exc_code;
wire [31:0] rob_commit_exc_val;
wire        rob_empty_out;
wire        rob_commit_is_mret;

// CSR
wire [11:0] csr_addr;
wire [31:0] csr_wdata;
wire [1:0]  csr_op;

// Rename snapshot
wire [159:0] rename_map_snapshot;

// Pipeline flush from ROB (to redirect fetch)
assign pipeline_flush_out = dut.pipeline_flush;

ooo_core dut (
    .clk(clk), .rst_n(rst_n),
    // Fetch stub → OoO Core
    .dec0_valid(fetch_valid),
    .dec0_instr(fetch_instr),
    .dec0_pc(fetch_pc_out),
    .dec0_pred_taken(1'b0),
    .dec0_pred_target(32'd0),
    .dec1_valid(1'b0), .dec1_instr(32'd0), .dec1_pc(32'd0),
    .dec1_pred_taken(1'b0), .dec1_pred_target(32'd0),
    .stall_dispatch(stall_dispatch),
    // D-Cache
    .dcache_req(dcache_req), .dcache_we(dcache_we),
    .dcache_addr(dcache_addr), .dcache_wdata(dcache_wdata),
    .dcache_size(dcache_size),
    .dcache_rdata(dcache_rdata), .dcache_valid(dcache_valid),
    .dcache_ready(dcache_ready),
    // BP commit
    .bp_commit_valid(bp_commit_valid), .bp_commit_pc(bp_commit_pc),
    .bp_commit_taken(bp_commit_taken), .bp_commit_target(bp_commit_target),
    .bp_commit_is_call(bp_commit_is_call), .bp_commit_is_ret(bp_commit_is_ret),
    .bp_commit_mispredicted(bp_commit_mispredicted),
    .bp_commit_rob_tag(bp_commit_rob_tag), .bp_commit_ckpt_id(bp_commit_ckpt_id),
    .bp_correct_pc(bp_correct_pc),
    // Branch dispatch
    .branch_dispatch(branch_dispatch), .dispatch_rob_tag(dispatch_rob_tag),
    // Trap Controller
    .rob_commit_valid_out(rob_commit_valid_out), .rob_commit_pc_out(rob_commit_pc_out),
    .rob_commit_exc(rob_commit_exc), .rob_commit_exc_code(rob_commit_exc_code),
    .rob_commit_exc_val(rob_commit_exc_val), .rob_empty_out(rob_empty_out),
    .rob_commit_is_mret(rob_commit_is_mret),
    // No traps in mini test
    .trap_rob_drain(1'b0), .flush_pipeline(1'b0), .flush_target(32'd0),
    // No spec recovery in mini test
    .recovering(1'b0), .restore_rename_map(1'b0), .restore_rob_tail(4'd0),
    .rename_map_snapshot(rename_map_snapshot),
    // CSR
    .csr_addr(csr_addr), .csr_wdata(csr_wdata), .csr_op(csr_op),
    .csr_rdata(32'd0),
    // Debug
    .halt(halt)
);

// =============================================================================
// Byte-Addressable D-Mem Stub (1KB, single-cycle)
// =============================================================================
reg [7:0] dmem_bytes [0:1023];

// Read helper: assemble word from bytes (little-endian)
wire [31:0] dmem_word = {dmem_bytes[dcache_addr[9:0]+3],
                          dmem_bytes[dcache_addr[9:0]+2],
                          dmem_bytes[dcache_addr[9:0]+1],
                          dmem_bytes[dcache_addr[9:0]+0]};

always @(posedge clk) begin
    dcache_valid <= 1'b0;
    if (dcache_req && dcache_ready) begin
        if (dcache_we) begin
            case (dcache_size)
                2'b00: begin // SB
                    dmem_bytes[dcache_addr[9:0]] <= dcache_wdata[7:0];
                    $display("  [MEM] SB:    addr=0x%08h data=0x%02h", dcache_addr, dcache_wdata[7:0]);
                end
                2'b01: begin // SH
                    dmem_bytes[dcache_addr[9:0]+0] <= dcache_wdata[7:0];
                    dmem_bytes[dcache_addr[9:0]+1] <= dcache_wdata[15:8];
                    $display("  [MEM] SH:    addr=0x%08h data=0x%04h", dcache_addr, dcache_wdata[15:0]);
                end
                default: begin // SW
                    dmem_bytes[dcache_addr[9:0]+0] <= dcache_wdata[7:0];
                    dmem_bytes[dcache_addr[9:0]+1] <= dcache_wdata[15:8];
                    dmem_bytes[dcache_addr[9:0]+2] <= dcache_wdata[23:16];
                    dmem_bytes[dcache_addr[9:0]+3] <= dcache_wdata[31:24];
                    $display("  [MEM] SW:    addr=0x%08h data=0x%08h", dcache_addr, dcache_wdata);
                end
            endcase
        end else begin
            dcache_rdata <= dmem_word;
            dcache_valid <= 1'b1;
            $display("  [MEM] LOAD:  addr=0x%08h data=0x%08h size=%0d", dcache_addr, dmem_word, dcache_size);
        end
    end
end

// =============================================================================
// Commit Monitor — tracks retired instructions
// =============================================================================
integer commit_count;
always @(posedge clk) begin
    if (!rst_n)
        commit_count <= 0;
    else if (rob_commit_valid_out) begin
        commit_count <= commit_count + 1;
        $display("  [COMMIT #%0d] PC=0x%08h rd=x%0d val=0x%08h",
                 commit_count + 1, rob_commit_pc_out,
                 dut.rob_commit_rd, dut.rob_commit_value);
    end
end

// =============================================================================
// Test Infrastructure
// =============================================================================
integer test_num, pass_count, fail_count;

task check_reg(input [4:0] reg_idx, input [31:0] expected, input [255:0] test_name);
begin
    test_num = test_num + 1;
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

// Wait for N commits
task wait_commits(input integer n);
    integer target;
begin
    target = commit_count + n;
    while (commit_count < target) @(posedge clk);
    @(posedge clk); // Extra cycle for value propagation
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

function [31:0] encode_slli(input [4:0] rd, input [4:0] rs1, input [4:0] shamt);
    encode_slli = {7'b0000000, shamt, rs1, 3'b001, rd, 7'b0010011};
endfunction

function [31:0] encode_beq(input [4:0] rs1, input [4:0] rs2, input [12:0] offset);
    encode_beq = {offset[12], offset[10:5], rs2, rs1, 3'b000,
                  offset[4:1], offset[11], 7'b1100011};
endfunction

function [31:0] encode_bne(input [4:0] rs1, input [4:0] rs2, input [12:0] offset);
    encode_bne = {offset[12], offset[10:5], rs2, rs1, 3'b001,
                  offset[4:1], offset[11], 7'b1100011};
endfunction

function [31:0] encode_blt(input [4:0] rs1, input [4:0] rs2, input [12:0] offset);
    encode_blt = {offset[12], offset[10:5], rs2, rs1, 3'b100,
                  offset[4:1], offset[11], 7'b1100011};
endfunction

function [31:0] encode_bge(input [4:0] rs1, input [4:0] rs2, input [12:0] offset);
    encode_bge = {offset[12], offset[10:5], rs2, rs1, 3'b101,
                  offset[4:1], offset[11], 7'b1100011};
endfunction

function [31:0] encode_bltu(input [4:0] rs1, input [4:0] rs2, input [12:0] offset);
    encode_bltu = {offset[12], offset[10:5], rs2, rs1, 3'b110,
                   offset[4:1], offset[11], 7'b1100011};
endfunction

function [31:0] encode_bgeu(input [4:0] rs1, input [4:0] rs2, input [12:0] offset);
    encode_bgeu = {offset[12], offset[10:5], rs2, rs1, 3'b111,
                   offset[4:1], offset[11], 7'b1100011};
endfunction

function [31:0] encode_ebreak(input dummy);
    encode_ebreak = 32'h00100073;
endfunction

// =============================================================================
// Test Programs
// =============================================================================
initial begin
    test_num = 0;
    pass_count = 0;
    fail_count = 0;

    $display("");
    $display("=============================================================");
    $display("SoC Mini Integration Test — OoO Core v7 + Fetch Stub");
    $display("=============================================================");

    // =========================================================================
    // Program 1: Basic ALU sequence (the ADDI x1, x0, 42 moment!)
    // =========================================================================
    $display("");
    $display("--- Program 1: Basic ALU Sequence ---");
    $display("--- THE FIRST REAL INSTRUCTION: ADDI x1, x0, 42 ---");

    // Load program into ROM
    program_rom[0] = encode_addi(5'd1, 5'd0, 12'd42);      // x1 = 42
    program_rom[1] = encode_addi(5'd2, 5'd0, 12'd100);     // x2 = 100
    program_rom[2] = encode_add(5'd3, 5'd1, 5'd2);         // x3 = x1 + x2 = 142
    program_rom[3] = encode_sub(5'd4, 5'd2, 5'd1);         // x4 = x2 - x1 = 58
    program_rom[4] = encode_lui(5'd5, 20'hABCDE);          // x5 = 0xABCDE000
    program_rom[5] = encode_addi(5'd5, 5'd5, 12'hF00);     // x5 = 0xABCDEF00 (sign-ext: 0xABCDDF00)
    program_rom[6] = encode_slli(5'd6, 5'd1, 5'd4);        // x6 = x1 << 4 = 42*16 = 672
    program_rom[7] = encode_ebreak(0);                        // HALT
    program_size = 8;

    // Reset and run
    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;

    // Wait for 7 commits (EBREAK doesn't commit normally)
    wait_commits(7);
    repeat(3) @(posedge clk);

    // Check results
    check_reg(5'd1, 32'd42,         "ADDI x1, x0, 42 — THE FIRST INSTRUCTION");
    check_reg(5'd2, 32'd100,        "ADDI x2, x0, 100");
    check_reg(5'd3, 32'd142,        "ADD x3, x1, x2");
    check_reg(5'd4, 32'd58,         "SUB x4, x2, x1");
    check_reg(5'd5, 32'hABCDDF00,   "LUI+ADDI x5 composite");
    check_reg(5'd6, 32'd672,        "SLLI x6, x1, 4");

    // =========================================================================
    // Program 2: Load/Store round-trip
    // =========================================================================
    $display("");
    $display("--- Program 2: Load/Store Round-Trip ---");

    program_rom[0] = encode_addi(5'd1, 5'd0, 12'h080);     // x1 = 0x80 (base addr)
    program_rom[1] = encode_addi(5'd2, 5'd0, 12'd999);     // x2 = 999
    program_rom[2] = encode_sw(5'd1, 5'd2, 12'd0);         // mem[0x80] = 999
    program_rom[3] = encode_sw(5'd1, 5'd2, 12'd4);         // mem[0x84] = 999
    program_rom[4] = encode_lw(5'd3, 5'd1, 12'd0);         // x3 = mem[0x80] = 999
    program_rom[5] = encode_lw(5'd4, 5'd1, 12'd4);         // x4 = mem[0x84] = 999
    program_rom[6] = encode_add(5'd5, 5'd3, 5'd4);         // x5 = x3 + x4 = 1998
    program_rom[7] = encode_ebreak(0);
    program_size = 8;

    // Reset and run
    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;

    wait_commits(7);
    repeat(5) @(posedge clk);

    check_reg(5'd1, 32'h80,  "Base address x1=0x80");
    check_reg(5'd2, 32'd999, "Store value x2=999");
    check_reg(5'd3, 32'd999, "LW x3 from mem[0x80]");
    check_reg(5'd4, 32'd999, "LW x4 from mem[0x84]");
    check_reg(5'd5, 32'd1998,"ADD x5 = x3 + x4");

    // =========================================================================
    // Program 3: RAW dependency chain (stress test forwarding)
    // =========================================================================
    $display("");
    $display("--- Program 3: RAW Dependency Chain (8-deep) ---");

    program_rom[0] = encode_addi(5'd1, 5'd0, 12'd1);       // x1 = 1
    program_rom[1] = encode_addi(5'd2, 5'd1, 12'd1);       // x2 = 2
    program_rom[2] = encode_addi(5'd3, 5'd2, 12'd1);       // x3 = 3
    program_rom[3] = encode_addi(5'd4, 5'd3, 12'd1);       // x4 = 4
    program_rom[4] = encode_addi(5'd5, 5'd4, 12'd1);       // x5 = 5
    program_rom[5] = encode_addi(5'd6, 5'd5, 12'd1);       // x6 = 6
    program_rom[6] = encode_addi(5'd7, 5'd6, 12'd1);       // x7 = 7
    program_rom[7] = encode_addi(5'd8, 5'd7, 12'd1);       // x8 = 8
    program_rom[8] = encode_ebreak(0);
    program_size = 9;

    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;

    wait_commits(8);
    repeat(3) @(posedge clk);

    check_reg(5'd1, 32'd1, "Chain[1] x1=1");
    check_reg(5'd2, 32'd2, "Chain[2] x2=2");
    check_reg(5'd3, 32'd3, "Chain[3] x3=3");
    check_reg(5'd4, 32'd4, "Chain[4] x4=4");
    check_reg(5'd5, 32'd5, "Chain[5] x5=5");
    check_reg(5'd6, 32'd6, "Chain[6] x6=6");
    check_reg(5'd7, 32'd7, "Chain[7] x7=7");
    check_reg(5'd8, 32'd8, "Chain[8] x8=8");

    // =========================================================================
    // Program 4: All branch types (BEQ/BNE/BLT/BGE/BLTU/BGEU)
    // =========================================================================
    $display("");
    $display("--- Program 4: Branch Type Coverage ---");

    // Note: branches cause misprediction (predicted not-taken) → flush.
    // Fetch stub stops fetching after flush. So we test not-taken branches
    // (which don't flush) and verify the sequencing is correct.
    // Taken branches verified via the v7 unit TB.

    // BNE not-taken: x1==x2 → don't branch
    program_rom[0]  = encode_addi(5'd1, 5'd0, 12'd10);     // x1 = 10
    program_rom[1]  = encode_addi(5'd2, 5'd0, 12'd10);     // x2 = 10
    program_rom[2]  = encode_bne(5'd1, 5'd2, 13'd8);       // BNE: 10!=10? No → fall through
    program_rom[3]  = encode_addi(5'd3, 5'd0, 12'd1);      // x3 = 1 (BNE fell through)

    // BEQ not-taken: x1!=x4 → don't branch
    program_rom[4]  = encode_addi(5'd4, 5'd0, 12'd20);     // x4 = 20
    program_rom[5]  = encode_beq(5'd1, 5'd4, 13'd8);       // BEQ: 10==20? No → fall through
    program_rom[6]  = encode_addi(5'd5, 5'd0, 12'd2);      // x5 = 2 (BEQ fell through)

    // BLT not-taken: x4 < x1? 20 < 10? No → fall through
    // BLT rs1=x4, rs2=x1, offset=+8 → {imm[12|10:5], rs2, rs1, 100, imm[4:1|11], 1100011}
    program_rom[7]  = encode_blt(5'd4, 5'd1, 13'd8);
    program_rom[8]  = encode_addi(5'd6, 5'd0, 12'd3);      // x6 = 3 (BLT fell through)

    // BGE not-taken: x1 >= x4? 10 >= 20? No → fall through
    program_rom[9]  = encode_bge(5'd1, 5'd4, 13'd8);
    program_rom[10] = encode_addi(5'd7, 5'd0, 12'd4);      // x7 = 4 (BGE fell through)

    program_rom[11] = encode_ebreak(0);
    program_size = 12;

    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;

    wait_commits(11);
    repeat(3) @(posedge clk);

    check_reg(5'd3, 32'd1, "BNE not-taken (equal)");
    check_reg(5'd5, 32'd2, "BEQ not-taken (not equal)");
    check_reg(5'd6, 32'd3, "BLT not-taken (20 < 10 = false)");
    check_reg(5'd7, 32'd4, "BGE not-taken (10 >= 20 = false)");

    // =========================================================================
    // Program 5: Multiple stores + loads (memory stress test)
    // =========================================================================
    $display("");
    $display("--- Program 5: Multi-Store Multi-Load ---");

    program_rom[0]  = encode_addi(5'd1, 5'd0, 12'h040);     // x1 = base 0x40
    program_rom[1]  = encode_addi(5'd10, 5'd0, 12'd11);     // x10 = 11
    program_rom[2]  = encode_addi(5'd11, 5'd0, 12'd22);     // x11 = 22
    program_rom[3]  = encode_addi(5'd12, 5'd0, 12'd33);     // x12 = 33
    program_rom[4]  = encode_sw(5'd1, 5'd10, 12'd0);        // mem[0x40] = 11
    program_rom[5]  = encode_sw(5'd1, 5'd11, 12'd4);        // mem[0x44] = 22
    program_rom[6]  = encode_sw(5'd1, 5'd12, 12'd8);        // mem[0x48] = 33
    program_rom[7]  = encode_lw(5'd20, 5'd1, 12'd0);        // x20 = mem[0x40] = 11
    program_rom[8]  = encode_lw(5'd21, 5'd1, 12'd4);        // x21 = mem[0x44] = 22
    program_rom[9]  = encode_lw(5'd22, 5'd1, 12'd8);        // x22 = mem[0x48] = 33
    program_rom[10] = encode_add(5'd23, 5'd20, 5'd21);      // x23 = 11+22 = 33
    program_rom[11] = encode_add(5'd24, 5'd23, 5'd22);      // x24 = 33+33 = 66
    program_rom[12] = encode_ebreak(0);
    program_size = 13;

    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;

    wait_commits(12);
    repeat(5) @(posedge clk);

    check_reg(5'd20, 32'd11, "LW x20 = 11");
    check_reg(5'd21, 32'd22, "LW x21 = 22");
    check_reg(5'd22, 32'd33, "LW x22 = 33");
    check_reg(5'd23, 32'd33, "ADD x23 = 11+22");
    check_reg(5'd24, 32'd66, "ADD x24 = 33+33");

    // =========================================================================
    // Program 6: WAW hazard (same rd written by multiple instructions)
    // =========================================================================
    $display("");
    $display("--- Program 6: WAW Hazard ---");

    program_rom[0] = encode_addi(5'd1, 5'd0, 12'd10);      // x1 = 10
    program_rom[1] = encode_addi(5'd1, 5'd0, 12'd20);      // x1 = 20 (overwrites)
    program_rom[2] = encode_addi(5'd1, 5'd0, 12'd30);      // x1 = 30 (overwrites)
    program_rom[3] = encode_addi(5'd2, 5'd1, 12'd5);       // x2 = x1 + 5 = 35 (must read latest x1)
    program_rom[4] = encode_ebreak(0);
    program_size = 5;

    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;

    wait_commits(4);
    repeat(3) @(posedge clk);

    check_reg(5'd1, 32'd30, "WAW: x1 final = 30");
    check_reg(5'd2, 32'd35, "WAW: x2 = latest x1 + 5 = 35");

    // =========================================================================
    // Program 7: Unsigned branches (BLTU/BGEU)
    // =========================================================================
    $display("");
    $display("--- Program 7: Unsigned Branches ---");

    // BLTU: unsigned compare. 0xFFFFFFFF > 1 unsigned, but -1 < 1 signed
    program_rom[0]  = encode_addi(5'd1, 5'd0, 12'hFFF);     // x1 = -1 = 0xFFFFFFFF
    program_rom[1]  = encode_addi(5'd2, 5'd0, 12'd1);       // x2 = 1
    // BLTU x1, x2, +8: 0xFFFFFFFF < 1 unsigned? No → not-taken
    program_rom[2]  = encode_bltu(5'd1, 5'd2, 13'd8);
    program_rom[3]  = encode_addi(5'd3, 5'd0, 12'd1);       // x3 = 1 (fell through, correct)
    // BGEU x2, x1, +8: 1 >= 0xFFFFFFFF unsigned? No → not-taken
    program_rom[4]  = encode_bgeu(5'd2, 5'd1, 13'd8);
    program_rom[5]  = encode_addi(5'd4, 5'd0, 12'd2);       // x4 = 2 (fell through, correct)
    // BLTU x2, x1, +8: 1 < 0xFFFFFFFF unsigned? Yes → taken (misprediction)
    // After flush, fetch stops, so just verify the fall-through cases
    program_rom[6]  = encode_ebreak(0);
    program_size = 7;

    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;

    wait_commits(6);
    repeat(3) @(posedge clk);

    check_reg(5'd3, 32'd1, "BLTU not-taken (0xFFFFFFFF < 1 = false unsigned)");
    check_reg(5'd4, 32'd2, "BGEU not-taken (1 >= 0xFFFFFFFF = false unsigned)");

    // =========================================================================
    // Program 8: Sub-byte store + load (SB/SH → LB/LH/LBU/LHU)
    // =========================================================================
    $display("");
    $display("--- Program 8: Sub-Byte Memory Operations ---");

    // Initialize memory to zero (using existing loop var)
    for (test_num = 0; test_num < 1024; test_num = test_num + 1)
        dmem_bytes[test_num] = 8'h00;
    test_num = pass_count + fail_count; // Restore test_num

    program_rom[0]  = encode_addi(5'd1, 5'd0, 12'h080);     // x1 = base 0x80
    program_rom[1]  = encode_addi(5'd2, 5'd0, 12'hF80);     // x2 = 0xFFFFFF80 = -128 (sign ext)
    // SB x2, 0(x1): store byte 0x80 to mem[0x80]
    program_rom[2]  = {7'b0, 5'd2, 5'd1, 3'b000, 5'b0, 7'b0100011}; // SB
    // SH x2, 4(x1): store half 0xFF80 to mem[0x84]
    program_rom[3]  = {7'b0, 5'd2, 5'd1, 3'b001, 5'b00100, 7'b0100011}; // SH offset=4
    // SW x2, 8(x1): store word 0xFFFFFF80 to mem[0x88]
    program_rom[4]  = encode_sw(5'd1, 5'd2, 12'd8);
    // LBU x3, 0(x1): load byte unsigned from mem[0x80] → 0x80 → 0x00000080
    program_rom[5]  = {12'b0, 5'd1, 3'b100, 5'd3, 7'b0000011}; // LBU x3, 0(x1)
    // LB x4, 0(x1): load byte signed from mem[0x80] → 0x80 → 0xFFFFFF80
    program_rom[6]  = {12'b0, 5'd1, 3'b000, 5'd4, 7'b0000011}; // LB x4, 0(x1)
    // LHU x5, 4(x1): load half unsigned → 0xFF80 → 0x0000FF80
    program_rom[7]  = {12'b000000000100, 5'd1, 3'b101, 5'd5, 7'b0000011}; // LHU x5, 4(x1)
    // LH x6, 4(x1): load half signed → 0xFF80 → 0xFFFFFF80
    program_rom[8]  = {12'b000000000100, 5'd1, 3'b001, 5'd6, 7'b0000011}; // LH x6, 4(x1)
    // LW x7, 8(x1): load word → 0xFFFFFF80
    program_rom[9]  = encode_lw(5'd7, 5'd1, 12'd8);
    program_rom[10] = encode_ebreak(0);
    program_size = 11;

    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;

    wait_commits(10);
    repeat(5) @(posedge clk);

    check_reg(5'd3, 32'h0000_0080, "LBU: byte 0x80 zero-extended");
    check_reg(5'd4, 32'hFFFF_FF80, "LB: byte 0x80 sign-extended");
    check_reg(5'd5, 32'h0000_FF80, "LHU: half 0xFF80 zero-extended");
    check_reg(5'd6, 32'hFFFF_FF80, "LH: half 0xFF80 sign-extended");
    check_reg(5'd7, 32'hFFFF_FF80, "LW: word 0xFFFFFF80");

    // =========================================================================
    // Program 9: BEQ taken → flush → redirect → continue
    // =========================================================================
    $display("");
    $display("--- Program 9: Branch Taken + Redirect ---");

    // PC 0x00: x1 = 10
    // PC 0x04: x2 = 10
    // PC 0x08: BEQ x1,x2,+8 → taken, redirect to PC 0x10
    // PC 0x0C: x3 = 0xBAD (should NOT execute — flushed)
    // PC 0x10: x4 = 42 (branch target — should execute)
    // PC 0x14: EBREAK
    program_rom[0]  = encode_addi(5'd1, 5'd0, 12'd10);
    program_rom[1]  = encode_addi(5'd2, 5'd0, 12'd10);
    program_rom[2]  = encode_beq(5'd1, 5'd2, 13'd8);       // BEQ +8
    program_rom[3]  = encode_addi(5'd3, 5'd0, 12'hBAD);    // Flushed path
    program_rom[4]  = encode_addi(5'd4, 5'd0, 12'd42);     // Branch target
    program_rom[5]  = encode_ebreak(0);
    program_size = 6;

    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;

    // Wait for commits: x1, x2, BEQ, then after flush: x4
    // BEQ misprediction → flush → redirect → x4 at target
    wait_commits(4); // x1, x2, BEQ commit, x4 (after redirect)
    repeat(5) @(posedge clk);

    check_reg(5'd4, 32'd42, "BEQ taken: target instruction x4=42");
    // x3 should still be 0 (flushed instruction should not commit)
    check_reg(5'd3, 32'd0, "BEQ taken: flushed path x3=0 (not 0xBAD)");

    // =========================================================================
    // Program 10: Simple counted loop (BNE backward branch)
    // =========================================================================
    $display("");
    $display("--- Program 10: Counted Loop (3 iterations) ---");

    // x1 = 3 (loop count)
    // x2 = 0 (accumulator)
    // loop: x2 = x2 + 10
    //       x1 = x1 - 1
    //       BNE x1, x0, loop (-8 = back to x2 += 10)
    // x2 should be 30 after 3 iterations

    program_rom[0]  = encode_addi(5'd1, 5'd0, 12'd3);       // x1 = 3
    program_rom[1]  = encode_addi(5'd2, 5'd0, 12'd0);       // x2 = 0
    // loop body at PC 0x08:
    program_rom[2]  = encode_addi(5'd2, 5'd2, 12'd10);      // x2 += 10
    program_rom[3]  = encode_addi(5'd1, 5'd1, 12'hFFF);     // x1 -= 1 (addi -1)
    // BNE x1, x0, -8 (back to program_rom[2])
    // B-type: offset = -8 = 0xFFF8 → imm[12:1] = 1_111111_1100_0
    // {imm[12], imm[10:5], rs2, rs1, funct3=001, imm[4:1], imm[11], opcode}
    program_rom[4]  = encode_bne(5'd1, 5'd0, -13'd8);       // BNE x1, x0, -8
    program_rom[5]  = encode_addi(5'd3, 5'd0, 12'd99);      // x3 = 99 (loop done marker)
    program_rom[6]  = encode_ebreak(0);
    program_size = 7;

    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;

    // 3 loop iterations: each iteration has 3 commits (addi, addi, bne)
    // Plus 2 setup + 1 loop-done marker + 1 final BNE (not-taken)
    // Total: 2 + 3*3 + 1 + 1 = 13 commits? Actually:
    // iter1: addi(x2+=10), addi(x1-=1), BNE taken → flush → redirect
    // iter2: addi(x2+=10), addi(x1-=1), BNE taken → flush → redirect
    // iter3: addi(x2+=10), addi(x1-=1), BNE not-taken (x1=0)
    // then: addi(x3=99)
    // Setup: 2 + loop: 3*3 + exit: 1 = 12, but flushes may add cycles
    // Just wait for enough commits and check values
    wait_commits(12);
    repeat(10) @(posedge clk);

    check_reg(5'd2, 32'd30, "Loop: x2 = 3*10 = 30");
    check_reg(5'd1, 32'd0,  "Loop: x1 = 0 (counter exhausted)");
    check_reg(5'd3, 32'd99, "Loop: exit marker x3 = 99");

    // =========================================================================
    // Summary
    // =========================================================================
    $display("");
    $display("=============================================================");
    $display("SoC MINI RESULTS: %0d/%0d PASSED", pass_count, test_num);
    if (fail_count == 0) begin
        $display("ALL TESTS PASSED!");
        $display("");
        $display(">>> MILESTONE: OoO Core v7 executes real instructions");
        $display(">>>            via SoC-style external fetch interface!");
    end else
        $display("%0d TESTS FAILED", fail_count);
    $display("=============================================================");
    $display("");

    $finish;
end

// Timeout
initial begin
    #500000;
    $display("TIMEOUT at %0t", $time);
    $finish;
end

endmodule
