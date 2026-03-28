// =============================================================================
// RV32IM Out-of-Order CPU Core v7 — SoC Integration
// =============================================================================
// Adapted from v6 (standalone) to plug into i7_soc_top.v
// Changes: external Fetch/Decode, Trap Controller interface, CSR interface,
//          Spec Recovery interface, enhanced BP commit, JAL/JALR execution
//
// Pipeline: [External Fetch/Decode] → Rename → Dispatch(RS/LSQ) →
//           Execute(ALU/MEM) → CDB → ROB → Commit
// =============================================================================

module ooo_core #(
    parameter ROB_TAG_W  = 4,   // log2(ROB_DEPTH): 4=16-entry, 5=32-entry
    parameter ROB_DEPTH  = (1 << ROB_TAG_W),
    parameter RS_ENTRIES = 8,
    parameter LSQ_ENTRIES = 8,
    parameter SNAPSHOT_W = 32 * (ROB_TAG_W + 1) // rename map: 32 regs × (tag + pending)
) (
    input  wire        clk,
    input  wire        rst_n,

    // =========================================================================
    // Decoded instruction inputs (from external Fetch/Decode pipeline)
    // =========================================================================
    input  wire        dec0_valid,
    input  wire [31:0] dec0_instr,
    input  wire [31:0] dec0_pc,
    input  wire        dec0_pred_taken,
    input  wire [31:0] dec0_pred_target,

    input  wire        dec1_valid,       // Second decode port (future dual-issue)
    input  wire [31:0] dec1_instr,
    input  wire [31:0] dec1_pc,
    input  wire        dec1_pred_taken,
    input  wire [31:0] dec1_pred_target,

    // Back-pressure to Fetch/Decode
    output wire        stall_dispatch,

    // =========================================================================
    // D-Cache interface
    // =========================================================================
    output wire        dcache_req,
    output wire        dcache_we,
    output wire [31:0] dcache_addr,
    output wire [31:0] dcache_wdata,
    output wire [1:0]  dcache_size,
    input  wire [31:0] dcache_rdata,
    input  wire        dcache_valid,
    input  wire        dcache_ready,

    // =========================================================================
    // Branch Predictor commit interface (enhanced)
    // =========================================================================
    output wire        bp_commit_valid,
    output wire [31:0] bp_commit_pc,
    output wire        bp_commit_taken,
    output wire [31:0] bp_commit_target,
    output wire        bp_commit_is_call,
    output wire        bp_commit_is_ret,
    output wire        bp_commit_mispredicted,
    output wire [ROB_TAG_W-1:0] bp_commit_rob_tag,
    output wire [ROB_TAG_W-1:0] bp_commit_ckpt_id,   // Checkpoint ID (= rob_tag for now)
    output wire [31:0] bp_correct_pc,

    // Branch dispatch (for Spec Recovery checkpoint creation)
    output wire        branch_dispatch,
    output wire [ROB_TAG_W-1:0] dispatch_rob_tag,

    // =========================================================================
    // Trap Controller interface
    // =========================================================================
    output wire        rob_commit_valid_out,
    output wire [31:0] rob_commit_pc_out,
    output wire        rob_commit_exc,
    output wire [4:0]  rob_commit_exc_code,  // RISC-V exception code (5-bit)
    output wire [31:0] rob_commit_exc_val,
    output wire        rob_empty_out,
    output wire        rob_commit_is_mret,

    // From Trap Controller
    input  wire        trap_rob_drain,     // Stop dispatch, let ROB drain
    input  wire        flush_pipeline,     // Trap-initiated flush
    input  wire [31:0] flush_target,       // Trap redirect PC

    // =========================================================================
    // Spec Recovery interface
    // =========================================================================
    input  wire        recovering,         // Stall dispatch during recovery
    input  wire        restore_rename_map, // Trigger rename table restore
    input  wire [ROB_TAG_W-1:0] restore_rob_tail,   // ROB tail to restore to

    // Rename map snapshot output (for checkpoint creation)
    output wire [SNAPSHOT_W-1:0] rename_map_snapshot,

    // =========================================================================
    // CSR interface
    // =========================================================================
    output reg  [11:0] csr_addr,
    output reg  [31:0] csr_wdata,
    output reg  [1:0]  csr_op,            // 00=none, 01=RW, 10=RS, 11=RC
    input  wire [31:0] csr_rdata,

    // =========================================================================
    // Debug
    // =========================================================================
    output wire        halt
);

// Parameters are now module-level (see #(...) parameter list above)

// =============================================================================
// Opcodes
// =============================================================================
localparam OP_LUI    = 7'b0110111;
localparam OP_AUIPC  = 7'b0010111;
localparam OP_JAL    = 7'b1101111;
localparam OP_JALR   = 7'b1100111;
localparam OP_BRANCH = 7'b1100011;
localparam OP_LOAD   = 7'b0000011;
localparam OP_STORE  = 7'b0100011;
localparam OP_IMM    = 7'b0010011;
localparam OP_REG    = 7'b0110011;
localparam OP_SYSTEM = 7'b1110011;

// =============================================================================
// Decode (from dec0 — single-issue for now, dec1 reserved)
// =============================================================================
wire [31:0] instr = dec0_instr;
wire [31:0] dec_pc = dec0_pc;

wire [6:0]  decode_opcode = instr[6:0];
wire [4:0]  decode_rd     = instr[11:7];
wire [2:0]  decode_funct3 = instr[14:12];
wire [4:0]  decode_rs1    = instr[19:15];
wire [4:0]  decode_rs2    = instr[24:20];
wire [6:0]  decode_funct7 = instr[31:25];

wire [31:0] decode_imm_i = {{20{instr[31]}}, instr[31:20]};
wire [31:0] decode_imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
wire [31:0] decode_imm_u = {instr[31:12], 12'd0};
wire [31:0] decode_imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
wire [31:0] decode_imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

wire decode_writes_rd = (decode_opcode == OP_LUI || decode_opcode == OP_AUIPC ||
                          decode_opcode == OP_JAL || decode_opcode == OP_JALR ||
                          decode_opcode == OP_LOAD || decode_opcode == OP_IMM ||
                          decode_opcode == OP_REG ||
                          (decode_opcode == OP_SYSTEM && decode_funct3 != 3'b000))
                         && (decode_rd != 5'd0);

wire decode_is_branch = (decode_opcode == OP_BRANCH);
wire decode_is_store  = (decode_opcode == OP_STORE);
wire decode_is_load   = (decode_opcode == OP_LOAD);
wire decode_is_mem    = decode_is_load || decode_is_store;
wire decode_is_jal    = (decode_opcode == OP_JAL);
wire decode_is_jalr   = (decode_opcode == OP_JALR);
wire decode_is_jump   = decode_is_jal || decode_is_jalr;
wire decode_is_csr    = (decode_opcode == OP_SYSTEM && decode_funct3 != 3'b000);
wire decode_is_mret   = (decode_opcode == OP_SYSTEM && decode_funct3 == 3'b000 &&
                          instr[31:20] == 12'h302);
wire decode_use_imm   = (decode_opcode != OP_REG && decode_opcode != OP_BRANCH);
wire [31:0] decode_mem_offset = decode_is_store ? decode_imm_s : decode_imm_i;

// Branch/Jump targets computed at decode time
wire [31:0] decode_branch_target = dec_pc + decode_imm_b;
wire [31:0] decode_jal_target    = dec_pc + decode_imm_j;
wire [31:0] decode_link_value    = dec_pc + 32'd4;  // Return address for JAL/JALR

// EBREAK detection — only halt when instruction is actually valid
assign halt = dec0_valid && (decode_opcode == OP_SYSTEM && instr[20] && decode_funct3 == 3'b000 &&
               instr[31:21] == 11'b0);

// Valid instruction from decode (gated by stall)
wire dec_valid = dec0_valid && !stall_dispatch && !halt;

// =============================================================================
// Combined flush: ROB misprediction OR Trap Controller redirect
// =============================================================================
wire rob_flush;
wire [31:0] rob_flush_target;
wire pipeline_flush = rob_flush || flush_pipeline;
wire [31:0] pipeline_flush_target = flush_pipeline ? flush_target : rob_flush_target;

// =============================================================================
// Internal wires
// =============================================================================

// ROB signals
wire [ROB_TAG_W-1:0] rob_alloc_tag;
wire        rob_alloc_ready;
wire        rob_commit_valid;
wire [4:0]  rob_commit_rd;
wire [31:0] rob_commit_value, rob_commit_pc;
wire [ROB_TAG_W-1:0] rob_commit_tag;
wire        rob_empty, rob_full;
wire        rob_commit_is_branch, rob_commit_is_store;
wire        rob_misprediction;
wire [ROB_TAG_W-1:0] rob_mispred_tag;

// CDB signals
wire        cdb_valid;
wire [ROB_TAG_W-1:0] cdb_tag;
wire [31:0] cdb_value;
wire        cdb_exception;

// Rename signals
wire [ROB_TAG_W-1:0] rs1_tag, rs2_tag;
wire        rs1_pending, rs2_pending;

// RS signals
wire        rs_issue_valid;
wire [6:0]  rs_issue_opcode;
wire [2:0]  rs_issue_funct3;
wire [6:0]  rs_issue_funct7;
wire [31:0] rs_issue_src1, rs_issue_src2;
wire [ROB_TAG_W-1:0] rs_issue_dst_tag;
wire        rs_dispatch_ready;

// LSQ signals
wire        lsq_dispatch_ready;
wire        lsq_result_valid;
wire [ROB_TAG_W-1:0] lsq_result_tag;
wire [31:0] lsq_result_value;

// Branch taken from ALU
reg         branch_taken_d1;
reg [31:0]  branch_target_d1;

// Control
wire        dispatch_to_rs, dispatch_to_lsq;
wire [31:0] src1_value, src2_value;

// CSR serialization: stall dispatch until ROB drains
reg csr_serialize_stall;

// =============================================================================
// Stall / Back-pressure
// =============================================================================
assign stall_dispatch = rob_full || !rs_dispatch_ready || !lsq_dispatch_ready ||
                        trap_rob_drain || recovering || csr_serialize_stall;
reg csr_pending;         // A CSR instruction is waiting to execute
reg csr_wb_pending;      // CSR op issued, waiting for rdata writeback
reg [11:0] csr_pending_addr;
reg [1:0]  csr_pending_op;
reg [31:0] csr_pending_src;
reg [4:0]  csr_pending_rd;
reg [4:0]  csr_pending_rd_saved; // Saved rd for writeback phase

always @(posedge clk) begin
    if (!rst_n || pipeline_flush) begin
        csr_serialize_stall <= 1'b0;
        csr_pending <= 1'b0;
        csr_wb_pending <= 1'b0;
        csr_pending_rd_saved <= 5'd0;
        csr_addr  <= 12'd0;
        csr_wdata <= 32'd0;
        csr_op    <= 2'b00;
    end else begin
        csr_op <= 2'b00; // Default: no CSR operation

        // Detect CSR instruction at decode → begin serialization
        if (dec_valid && decode_is_csr && !csr_serialize_stall) begin
            csr_serialize_stall <= 1'b1;
            csr_pending <= 1'b1;
            csr_pending_addr <= instr[31:20];
            csr_pending_op <= decode_funct3[1:0]; // CSRRW=01, CSRRS=10, CSRRC=11
            csr_pending_src <= (decode_funct3[2]) ? {27'd0, decode_rs1} : src1_value; // CSRR[W/S/C]I uses zimm
            csr_pending_rd  <= decode_rd;
            csr_pending_rd_saved <= decode_rd; // Save for writeback phase
        end

        // ROB drained → execute CSR (2-phase: issue then writeback)
        if (csr_pending && rob_empty && !csr_wb_pending) begin
            csr_addr  <= csr_pending_addr;
            csr_wdata <= csr_pending_src;
            csr_op    <= csr_pending_op;
            csr_pending <= 1'b0;
            csr_wb_pending <= 1'b1; // Wait one cycle for csr_rdata
        end

        // CSR writeback: one cycle after CSR op, release stall
        // (arch_regs write happens in the commit always block below)
        if (csr_wb_pending) begin
            csr_wb_pending <= 1'b0;
            csr_serialize_stall <= 1'b0;
        end
    end
end

// =============================================================================
// Architectural Register File + CDB Result Buffer
// =============================================================================
reg [31:0] arch_regs [0:31];
wire [31:0] arch_rs1 = (decode_rs1 == 5'd0) ? 32'd0 : arch_regs[decode_rs1];
wire [31:0] arch_rs2 = (decode_rs2 == 5'd0) ? 32'd0 : arch_regs[decode_rs2];

// CDB result buffer: stores the latest CDB-broadcast value for each ROB tag
reg [31:0] cdb_result [0:ROB_DEPTH-1];
reg        cdb_result_valid [0:ROB_DEPTH-1];

// =============================================================================
// Register Rename
// =============================================================================
reg_rename #(.ROB_TAG_W(ROB_TAG_W)) u_rename (
    .clk(clk), .rst_n(rst_n),
    .lookup_rs1(decode_rs1), .lookup_rs2(decode_rs2),
    .rs1_tag(rs1_tag), .rs1_pending(rs1_pending),
    .rs2_tag(rs2_tag), .rs2_pending(rs2_pending),
    .rename_valid(decode_writes_rd && dec_valid && !decode_is_csr),
    .rename_rd(decode_rd), .rename_tag(rob_alloc_tag),
    .commit_valid(rob_commit_valid), .commit_rd(rob_commit_rd),
    .commit_tag(rob_commit_tag),
    .flush(pipeline_flush)
);

// Rename map snapshot: placeholder (actual snapshot requires reg_rename module extension)
// For now, output zeros — will be populated when PRF upgrade adds snapshot support
assign rename_map_snapshot = {SNAPSHOT_W{1'b0}}; // Placeholder until PRF upgrade

// =============================================================================
// Operand Resolution
// =============================================================================
// ROB read ports for operand bypass
wire [31:0] rob_read_val1, rob_read_val2;
wire        rob_read_done1, rob_read_done2;
wire        rob_read_exists1, rob_read_exists2;

// CDB result lookup
wire        cdb_buf_valid1 = cdb_result_valid[rs1_tag];
wire [31:0] cdb_buf_value1 = cdb_result[rs1_tag];
wire        cdb_buf_valid2 = cdb_result_valid[rs2_tag];
wire [31:0] cdb_buf_value2 = cdb_result[rs2_tag];

// Source operand resolution priority:
// 1. Not pending → architectural register file
// 2. Pending + ROB complete → ROB value
// 3. Pending + CDB result buffer → buffer value
// 4. Pending + none ready → arch value (will be fixed up by CDB snoop)
assign src1_value = !rs1_pending         ? arch_rs1 :
                    rob_read_done1       ? rob_read_val1 :
                    cdb_buf_valid1       ? cdb_buf_value1 :
                    arch_rs1;
assign src2_value = !rs2_pending         ? arch_rs2 :
                    rob_read_done2       ? rob_read_val2 :
                    cdb_buf_valid2       ? cdb_buf_value2 :
                    arch_rs2;

wire src1_ready = !rs1_pending || rob_read_done1 || cdb_buf_valid1;
wire src2_ready = !rs2_pending || rob_read_done2 || cdb_buf_valid2;

// Dispatch routing
// JAL/JALR go through RS (ALU computes link value)
// CSR/MRET do not dispatch to RS/LSQ (handled by serialization or direct commit)
assign dispatch_to_rs  = dec_valid && !decode_is_mem && !decode_is_csr &&
                          !decode_is_mret && decode_opcode != 7'd0;
assign dispatch_to_lsq = dec_valid && decode_is_mem;

// Select correct immediate based on opcode
// For JALR: pass imm_i so ALU can compute target = (rs1 + imm) & ~1
// For JAL: pass link_value (PC+4) since target is known at decode
wire [31:0] dispatch_imm = (decode_opcode == OP_LUI || decode_opcode == OP_AUIPC) ? decode_imm_u :
                            (decode_opcode == OP_JAL)  ? decode_link_value :
                            (decode_opcode == OP_JALR) ? decode_imm_i :
                            decode_imm_i;

// =============================================================================
// ROB — Extended with exception tracking and MRET flag
// =============================================================================
// ROB needs additional commit outputs for Trap Controller
// We extend the existing rob module outputs through additional tracking

rob #(.DEPTH(ROB_DEPTH), .TAG_W(ROB_TAG_W)) u_rob (
    .clk(clk), .rst_n(rst_n),
    .alloc_valid(dec_valid && decode_opcode != 7'd0 && !decode_is_csr),
    .alloc_rd(decode_writes_rd ? decode_rd : 5'd0), .alloc_pc(dec_pc),
    .alloc_is_branch(decode_is_branch || decode_is_jal || decode_is_jalr), .alloc_is_store(decode_is_store),
    .alloc_branch_target(decode_is_branch ? decode_branch_target :
                          decode_is_jal   ? decode_jal_target :
                          decode_is_jalr  ? ((src1_value + decode_imm_i) & ~32'd1) : 32'd0),
    .alloc_predicted_taken(dec0_pred_taken),
    .alloc_tag(rob_alloc_tag), .alloc_ready(rob_alloc_ready),
    .complete_valid(cdb_valid), .complete_tag(cdb_tag),
    .complete_value(cdb_value), .complete_exception(cdb_exception),
    .complete_branch_taken(branch_taken_d1), .complete_branch_target(branch_target_d1),
    .commit_valid(rob_commit_valid), .commit_rd(rob_commit_rd),
    .commit_value(rob_commit_value), .commit_pc(rob_commit_pc),
    .commit_tag(rob_commit_tag), .commit_is_store(rob_commit_is_store),
    .read_tag1(rs1_tag), .read_value1(rob_read_val1),
    .read_complete1(rob_read_done1), .read_valid1(rob_read_exists1),
    .read_tag2(rs2_tag), .read_value2(rob_read_val2),
    .read_complete2(rob_read_done2), .read_valid2(rob_read_exists2),
    .misprediction(rob_misprediction), .mispred_tag(rob_mispred_tag),
    .flush(rob_flush), .flush_target(rob_flush_target),
    .empty(rob_empty), .full(rob_full)
);

// Track is_branch per ROB tag for BP commit
// (ROB module has this internally, extract via tag matching at commit)
reg [ROB_DEPTH-1:0] rob_is_branch_vec;
reg [ROB_DEPTH-1:0] rob_is_jump_vec;
reg [ROB_DEPTH-1:0] rob_is_mret_vec;
reg [ROB_DEPTH-1:0] rob_is_call_vec;  // JAL/JALR with rd=x1 or rd=x5
reg [ROB_DEPTH-1:0] rob_is_ret_vec;   // JALR with rs1=x1 or rs1=x5, rd!=rs1

always @(posedge clk) begin
    if (!rst_n || pipeline_flush) begin
        rob_is_branch_vec <= {ROB_DEPTH{1'b0}};
        rob_is_jump_vec   <= {ROB_DEPTH{1'b0}};
        rob_is_mret_vec   <= {ROB_DEPTH{1'b0}};
        rob_is_call_vec   <= {ROB_DEPTH{1'b0}};
        rob_is_ret_vec    <= {ROB_DEPTH{1'b0}};
    end else if (dec_valid && decode_opcode != 7'd0 && !decode_is_csr) begin
        rob_is_branch_vec[rob_alloc_tag] <= decode_is_branch;
        rob_is_jump_vec[rob_alloc_tag]   <= decode_is_jump;
        rob_is_mret_vec[rob_alloc_tag]   <= decode_is_mret;
        rob_is_call_vec[rob_alloc_tag]   <= decode_is_jump &&
                                             (decode_rd == 5'd1 || decode_rd == 5'd5);
        rob_is_ret_vec[rob_alloc_tag]    <= decode_is_jalr &&
                                             (decode_rs1 == 5'd1 || decode_rs1 == 5'd5) &&
                                             decode_rd != decode_rs1;
    end
end

assign rob_commit_is_branch = rob_is_branch_vec[rob_commit_tag];

// =============================================================================
// Branch dispatch (for Spec Recovery checkpoint)
// =============================================================================
assign branch_dispatch  = dec_valid && (decode_is_branch || decode_is_jump);
assign dispatch_rob_tag = rob_alloc_tag;

// =============================================================================
// BP commit outputs (enhanced)
// =============================================================================
assign bp_commit_valid       = rob_commit_valid && rob_is_branch_vec[rob_commit_tag];
assign bp_commit_pc          = rob_commit_pc;
assign bp_commit_taken       = rob_misprediction ? !rob_flush_target[0] : 1'b0; // TODO: actual taken from ROB
assign bp_commit_target      = rob_flush_target;
assign bp_commit_is_call     = rob_is_call_vec[rob_commit_tag];
assign bp_commit_is_ret      = rob_is_ret_vec[rob_commit_tag];
assign bp_commit_mispredicted = rob_misprediction;
assign bp_commit_rob_tag     = rob_commit_tag;
assign bp_commit_ckpt_id     = rob_commit_tag;  // Checkpoint ID = ROB tag for now
assign bp_correct_pc         = rob_flush_target;

// =============================================================================
// Trap Controller outputs
// =============================================================================
assign rob_commit_valid_out = rob_commit_valid;
assign rob_commit_pc_out    = rob_commit_pc;
assign rob_commit_exc       = cdb_exception && rob_commit_valid; // Exception at commit
assign rob_commit_exc_code  = 5'd0;  // TODO: track exc_code per ROB entry
assign rob_commit_exc_val   = 32'd0; // TODO: track exc_val per ROB entry
assign rob_empty_out        = rob_empty;
assign rob_commit_is_mret   = rob_commit_valid && rob_is_mret_vec[rob_commit_tag];

// =============================================================================
// Reservation Station (ALU ops, including JAL/JALR)
// =============================================================================
reservation_station #(.ENTRIES(RS_ENTRIES), .ROB_TAG_W(ROB_TAG_W)) u_rs (
    .clk(clk), .rst_n(rst_n),
    .dispatch_valid(dispatch_to_rs),
    .dispatch_opcode(decode_opcode), .dispatch_funct3(decode_funct3),
    .dispatch_funct7(decode_funct7),
    .dispatch_src1_val(src1_value), .dispatch_src1_tag(rs1_tag),
    .dispatch_src1_ready(src1_ready),
    .dispatch_src2_val(src2_value), .dispatch_src2_tag(rs2_tag),
    .dispatch_src2_ready(src2_ready),
    .dispatch_dst_tag(rob_alloc_tag),
    .dispatch_imm(dispatch_imm), .dispatch_use_imm(decode_use_imm),
    .dispatch_ready(rs_dispatch_ready),
    .issue_valid(rs_issue_valid), .issue_opcode(rs_issue_opcode),
    .issue_funct3(rs_issue_funct3), .issue_funct7(rs_issue_funct7),
    .issue_src1(rs_issue_src1), .issue_src2(rs_issue_src2),
    .issue_dst_tag(rs_issue_dst_tag),
    .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_value(cdb_value),
    .flush(pipeline_flush)
);

// =============================================================================
// Load/Store Queue
// =============================================================================
load_store_queue #(.ENTRIES(LSQ_ENTRIES), .ROB_TAG_W(ROB_TAG_W)) u_lsq (
    .clk(clk), .rst_n(rst_n),
    .dispatch_valid(dispatch_to_lsq),
    .dispatch_is_load(decode_is_load),
    .dispatch_funct3(decode_funct3),
    .dispatch_rob_tag(rob_alloc_tag),
    .dispatch_base_val(src1_value),
    .dispatch_base_tag(rs1_tag),
    .dispatch_base_ready(src1_ready),
    .dispatch_data_val(src2_value),
    .dispatch_data_tag(rs2_tag),
    .dispatch_data_ready(src2_ready),
    .dispatch_offset(decode_mem_offset),
    .dispatch_ready(lsq_dispatch_ready),
    .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_value(cdb_value),
    .mem_req(dcache_req), .mem_we(dcache_we),
    .mem_addr(dcache_addr), .mem_wdata(dcache_wdata),
    .mem_size(dcache_size),
    .mem_rdata(dcache_rdata), .mem_valid(dcache_valid),
    .mem_ready(dcache_ready),
    .result_valid(lsq_result_valid),
    .result_tag(lsq_result_tag),
    .result_value(lsq_result_value),
    .commit_store(rob_commit_valid && rob_commit_is_store),
    .commit_tag(rob_commit_tag),
    .flush(pipeline_flush)
);

// =============================================================================
// Execute (ALU — combinational, with JAL/JALR support)
// =============================================================================
reg [31:0] alu_result;
reg        alu_branch_taken;
reg [31:0] alu_branch_target;  // For JALR: computed target = (src1 + imm) & ~1

always @(*) begin
    alu_branch_taken = 1'b0;
    alu_branch_target = 32'd0;
    alu_result = 32'd0;

    case (rs_issue_opcode)
        OP_LUI: alu_result = rs_issue_src2;  // src2 = imm_u via dispatch_imm

        OP_AUIPC: alu_result = rs_issue_src1 + rs_issue_src2;  // PC + imm_u

        OP_JAL: begin
            alu_result = rs_issue_src2;       // src2 = link_value (PC+4)
            alu_branch_taken = 1'b1;          // JAL is always taken (unconditional)
        end

        OP_JALR: begin
            // src1 = rs1 value, src2 = imm_i (immediate offset)
            // JALR target = (rs1 + imm_i) & ~1
            alu_branch_target = (rs_issue_src1 + rs_issue_src2) & ~32'd1;
            alu_result = 32'd0; // Link value (PC+4) needs ROB PC — stored at alloc
            alu_branch_taken = 1'b1;
        end

        OP_BRANCH: begin
            case (rs_issue_funct3)
                3'b000: alu_branch_taken = (rs_issue_src1 == rs_issue_src2);           // BEQ
                3'b001: alu_branch_taken = (rs_issue_src1 != rs_issue_src2);           // BNE
                3'b100: alu_branch_taken = ($signed(rs_issue_src1) < $signed(rs_issue_src2)); // BLT
                3'b101: alu_branch_taken = ($signed(rs_issue_src1) >= $signed(rs_issue_src2)); // BGE
                3'b110: alu_branch_taken = (rs_issue_src1 < rs_issue_src2);            // BLTU
                3'b111: alu_branch_taken = (rs_issue_src1 >= rs_issue_src2);           // BGEU
                default: alu_branch_taken = 1'b0;
            endcase
        end

        default: begin
            // Standard ALU operations (OP_IMM / OP_REG)
            case (rs_issue_funct3)
                3'b000: alu_result = (rs_issue_opcode == OP_REG && rs_issue_funct7[5]) ?
                                     rs_issue_src1 - rs_issue_src2 :
                                     rs_issue_src1 + rs_issue_src2;
                3'b001: alu_result = rs_issue_src1 << rs_issue_src2[4:0];
                3'b010: alu_result = {31'd0, $signed(rs_issue_src1) < $signed(rs_issue_src2)};
                3'b011: alu_result = {31'd0, rs_issue_src1 < rs_issue_src2};
                3'b100: alu_result = rs_issue_src1 ^ rs_issue_src2;
                3'b101: alu_result = rs_issue_funct7[5] ?
                                     ($signed(rs_issue_src1) >>> rs_issue_src2[4:0]) :
                                     (rs_issue_src1 >> rs_issue_src2[4:0]);
                3'b110: alu_result = rs_issue_src1 | rs_issue_src2;
                3'b111: alu_result = rs_issue_src1 & rs_issue_src2;
            endcase
        end
    endcase
end

// =============================================================================
// Branch result — registered to match CDB timing (1-cycle delay)
// =============================================================================
always @(posedge clk) begin
    if (!rst_n) begin
        branch_taken_d1 <= 1'b0;
        branch_target_d1 <= 32'd0;
    end else begin
        branch_taken_d1 <= alu_branch_taken && rs_issue_valid;
        branch_target_d1 <= alu_branch_target;
    end
end

// =============================================================================
// CDB — ALU (EU0), LSQ load (EU1), unused (EU2)
// =============================================================================
cdb #(.ROB_TAG_W(ROB_TAG_W)) u_cdb (
    .clk(clk), .rst_n(rst_n),
    .eu0_valid(rs_issue_valid), .eu0_tag(rs_issue_dst_tag),
    .eu0_value(alu_result), .eu0_exception(1'b0),
    .eu1_valid(lsq_result_valid), .eu1_tag(lsq_result_tag),
    .eu1_value(lsq_result_value), .eu1_exception(1'b0),
    .eu2_valid(1'b0), .eu2_tag({ROB_TAG_W{1'b0}}), .eu2_value(32'd0), .eu2_exception(1'b0),
    .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_value(cdb_value),
    .cdb_exception(cdb_exception),
    .eu0_stall(), .eu1_stall(), .eu2_stall()
);

// =============================================================================
// CDB Result Buffer — written when CDB broadcasts, persists until flush
// =============================================================================
integer bi;
always @(posedge clk) begin
    if (!rst_n || pipeline_flush) begin
        for (bi = 0; bi < ROB_DEPTH; bi = bi + 1)
            cdb_result_valid[bi] <= 1'b0;
    end else if (cdb_valid) begin
        cdb_result[cdb_tag]       <= cdb_value;
        cdb_result_valid[cdb_tag] <= 1'b1;
    end
end

// =============================================================================
// Commit — write to architectural register file
// =============================================================================
integer ci;
always @(posedge clk) begin
    if (!rst_n) begin
        for (ci = 0; ci < 32; ci = ci + 1)
            arch_regs[ci] <= 32'd0;
    end else if (csr_wb_pending && csr_pending_rd_saved != 5'd0) begin
        // CSR writeback has priority during serialization (ROB is empty)
        arch_regs[csr_pending_rd_saved] <= csr_rdata;
    end else if (rob_commit_valid && rob_commit_rd != 5'd0) begin
        arch_regs[rob_commit_rd] <= rob_commit_value;
    end
end

endmodule
