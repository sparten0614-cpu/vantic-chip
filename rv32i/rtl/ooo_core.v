// =============================================================================
// RV32IM Out-of-Order CPU Core — Top-Level Integration (v2)
// =============================================================================
// Pipeline: Fetch → Decode/Rename → Issue(RS/LSQ) → Execute(ALU/MEM) → CDB → ROB → Commit
// =============================================================================

module ooo_core (
    input  wire        clk,
    input  wire        rst_n,

    // I-Cache interface
    output wire [31:0] icache_addr,
    input  wire [31:0] icache_data,
    input  wire        icache_valid,
    input  wire        icache_ready,

    // D-Cache interface
    output wire        dcache_req,
    output wire        dcache_we,
    output wire [31:0] dcache_addr,
    output wire [31:0] dcache_wdata,
    output wire [1:0]  dcache_size,
    input  wire [31:0] dcache_rdata,
    input  wire        dcache_valid,
    input  wire        dcache_ready,

    // Branch predictor interface
    input  wire        bp_predicted_taken,
    input  wire [31:0] bp_predicted_target,
    input  wire        bp_pred_valid,       // BP has a prediction for this PC
    output wire        bp_update_en,
    output wire [31:0] bp_update_pc,
    output wire        bp_update_taken,
    output wire [31:0] bp_update_target,
    output wire        bp_update_is_ret,
    output wire        bp_update_is_call,

    // Branch checkpoint interface (Spec Recovery)
    output wire        branch_dispatch,     // Branch being dispatched
    output wire [3:0]  dispatch_rob_tag_out,// ROB tag of dispatched branch
    output wire        commit_mispredicted, // Misprediction detected at commit
    output wire [3:0]  commit_mispredict_tag,// ROB tag of mispredicted branch
    output wire [31:0] commit_correct_pc,   // Correct target for misprediction

    // Debug
    output wire [31:0] pc_out,
    output wire        halt
);

// =============================================================================
// Forward declarations (all internal wires)
// =============================================================================

// Decode signals
wire [31:0] instr;
wire [6:0]  decode_opcode;
wire [4:0]  decode_rd, decode_rs1, decode_rs2;
wire [2:0]  decode_funct3;
wire [6:0]  decode_funct7;
wire [31:0] decode_imm_i, decode_imm_s, decode_imm_u, decode_imm_b;
wire        decode_writes_rd, decode_is_branch, decode_is_store, decode_is_load;
wire        decode_is_mem, decode_use_imm;
wire [31:0] decode_mem_offset;

// ROB signals
wire [3:0]  rob_alloc_tag;
wire        rob_alloc_ready;
wire        rob_commit_valid;
wire [4:0]  rob_commit_rd;
wire [31:0] rob_commit_value, rob_commit_pc;
wire [3:0]  rob_commit_tag;
wire        rob_flush;
wire [31:0] rob_flush_target;
wire        rob_empty, rob_full;
wire        rob_commit_is_branch, rob_commit_is_store;
wire        rob_misprediction;
wire [3:0]  rob_mispred_tag;

// CDB signals
wire        cdb_valid;
wire [3:0]  cdb_tag;
wire [31:0] cdb_value;
wire        cdb_exception;

// Rename signals
wire [3:0]  rs1_tag, rs2_tag;
wire        rs1_pending, rs2_pending;

// RS signals
wire        rs_issue_valid;
wire [6:0]  rs_issue_opcode;
wire [2:0]  rs_issue_funct3;
wire [6:0]  rs_issue_funct7;
wire [31:0] rs_issue_src1, rs_issue_src2;
wire [3:0]  rs_issue_dst_tag;
wire        rs_dispatch_ready;

// LSQ signals
wire        lsq_dispatch_ready;
wire        lsq_result_valid;
wire [3:0]  lsq_result_tag;
wire [31:0] lsq_result_value;

// Branch signals
reg         branch_taken_d1;

// Control
wire        stall_fetch;
wire        fetch_valid;
wire        dispatch_to_rs, dispatch_to_lsq;
wire [31:0] src1_value, src2_value;

// =============================================================================
// Architectural Register File + CDB Result Buffer
// =============================================================================
reg [31:0] arch_regs [0:31];
wire [31:0] arch_rs1 = (decode_rs1 == 5'd0) ? 32'd0 : arch_regs[decode_rs1];
wire [31:0] arch_rs2 = (decode_rs2 == 5'd0) ? 32'd0 : arch_regs[decode_rs2];

// CDB result buffer: stores the latest CDB-broadcast value for each ROB tag
// This persists even after ROB entries are freed
reg [31:0] cdb_result [0:15];  // Indexed by ROB tag
reg        cdb_result_valid [0:15];

// =============================================================================
// Stage 1: Fetch
// =============================================================================
reg [31:0] pc;
assign pc_out = pc;
assign icache_addr = pc;

wire [31:0] pc_plus4 = pc + 32'd4;

always @(posedge clk) begin
    if (!rst_n)
        pc <= 32'd0;
    else if (rob_flush)
        pc <= rob_flush_target;
    else if (bp_predicted_taken && icache_valid && !stall_fetch && !halt)
        pc <= bp_predicted_target;
    else if (!stall_fetch && icache_valid && !halt)
        pc <= pc_plus4;
end

assign fetch_valid = icache_valid && !stall_fetch && !halt;

// =============================================================================
// Stage 2: Decode
// =============================================================================
assign instr = icache_data;
assign decode_opcode = instr[6:0];
assign decode_rd     = instr[11:7];
assign decode_funct3 = instr[14:12];
assign decode_rs1    = instr[19:15];
assign decode_rs2    = instr[24:20];
assign decode_funct7 = instr[31:25];

assign decode_imm_i = {{20{instr[31]}}, instr[31:20]};
assign decode_imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
assign decode_imm_u = {instr[31:12], 12'd0};
assign decode_imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

localparam OP_LUI=7'b0110111, OP_AUIPC=7'b0010111, OP_JAL=7'b1101111;
localparam OP_JALR=7'b1100111, OP_BRANCH=7'b1100011, OP_LOAD=7'b0000011;
localparam OP_STORE=7'b0100011, OP_IMM=7'b0010011, OP_REG=7'b0110011;
localparam OP_SYSTEM=7'b1110011;

assign decode_writes_rd = (decode_opcode == OP_LUI || decode_opcode == OP_AUIPC ||
                           decode_opcode == OP_JAL || decode_opcode == OP_JALR ||
                           decode_opcode == OP_LOAD || decode_opcode == OP_IMM ||
                           decode_opcode == OP_REG) && (decode_rd != 5'd0);
assign decode_is_branch = (decode_opcode == OP_BRANCH);
assign decode_is_store  = (decode_opcode == OP_STORE);
assign decode_is_load   = (decode_opcode == OP_LOAD);
assign decode_is_mem    = decode_is_load || decode_is_store;
assign decode_use_imm   = (decode_opcode != OP_REG && decode_opcode != OP_BRANCH);
assign decode_mem_offset = decode_is_store ? decode_imm_s : decode_imm_i;

assign halt = (decode_opcode == OP_SYSTEM && instr[20]);

// Branch target computed at decode time
wire [31:0] decode_branch_target = pc + decode_imm_b;

// =============================================================================
// Branch Predictor Update
// =============================================================================
// BP update at commit — send actual branch outcome for training
// Note: rob_commit_is_branch needs to be properly wired from ROB
// For now, detect branch from misprediction signal or commit
assign bp_update_en     = rob_commit_valid && rob_commit_is_branch;
assign bp_update_pc     = rob_commit_pc;
assign bp_update_taken  = rob_misprediction ? !rob_flush_target[0] : 1'b0; // TODO: wire actual_taken from ROB
assign bp_update_target = rob_flush_target;
assign bp_update_is_ret = 1'b0;
assign bp_update_is_call = 1'b0;

// =============================================================================
// Register Rename
// =============================================================================
reg_rename u_rename (
    .clk(clk), .rst_n(rst_n),
    .lookup_rs1(decode_rs1), .lookup_rs2(decode_rs2),
    .rs1_tag(rs1_tag), .rs1_pending(rs1_pending),
    .rs2_tag(rs2_tag), .rs2_pending(rs2_pending),
    .rename_valid(decode_writes_rd && fetch_valid),
    .rename_rd(decode_rd), .rename_tag(rob_alloc_tag),
    .commit_valid(rob_commit_valid), .commit_rd(rob_commit_rd),
    .commit_tag(rob_commit_tag),
    .flush(rob_flush)
);

// ROB read ports for operand bypass (completed entries)
wire [31:0] rob_read_val1, rob_read_val2;
wire        rob_read_done1, rob_read_done2;
wire        rob_read_exists1, rob_read_exists2; // Entry exists in ROB

// CDB result lookup (persists after ROB entry freed)
wire        cdb_buf_valid1 = cdb_result_valid[rs1_tag];
wire [31:0] cdb_buf_value1 = cdb_result[rs1_tag];
wire        cdb_buf_valid2 = cdb_result_valid[rs2_tag];
wire [31:0] cdb_buf_value2 = cdb_result[rs2_tag];

// Source operand resolution priority:
// 1. Not pending → read from architectural register file
// 2. Pending + ROB entry complete → read from ROB
// 3. Pending + CDB result buffer valid → read from buffer (even after ROB entry freed)
// 4. Pending + none ready → value unknown, rely on CDB snoop/bypass
assign src1_value = !rs1_pending         ? arch_rs1 :
                    rob_read_done1       ? rob_read_val1 :
                    cdb_buf_valid1       ? cdb_buf_value1 :
                    arch_rs1;
assign src2_value = !rs2_pending         ? arch_rs2 :
                    rob_read_done2       ? rob_read_val2 :
                    cdb_buf_valid2       ? cdb_buf_value2 :
                    arch_rs2;

// Source ready: true if not pending, OR ROB complete, OR CDB buffer valid
wire src1_ready = !rs1_pending || rob_read_done1 || cdb_buf_valid1;
wire src2_ready = !rs2_pending || rob_read_done2 || cdb_buf_valid2;
assign dispatch_to_rs  = fetch_valid && !decode_is_mem && decode_opcode != 7'd0;
assign dispatch_to_lsq = fetch_valid && decode_is_mem;

// Select correct immediate based on opcode
wire [31:0] dispatch_imm = (decode_opcode == OP_LUI || decode_opcode == OP_AUIPC) ? decode_imm_u :
                           decode_imm_i;

// =============================================================================
// ROB
// =============================================================================
rob u_rob (
    .clk(clk), .rst_n(rst_n),
    .alloc_valid(fetch_valid && decode_opcode != 7'd0),
    .alloc_rd(decode_writes_rd ? decode_rd : 5'd0), .alloc_pc(pc),
    .alloc_is_branch(decode_is_branch), .alloc_is_store(decode_is_store),
    .alloc_branch_target(decode_branch_target),
    .alloc_predicted_taken(bp_predicted_taken && bp_pred_valid),
    .alloc_tag(rob_alloc_tag), .alloc_ready(rob_alloc_ready),
    .complete_valid(cdb_valid), .complete_tag(cdb_tag),
    .complete_value(cdb_value), .complete_exception(cdb_exception),
    .complete_branch_taken(branch_taken_d1), .complete_branch_target(32'd0),
    .commit_valid(rob_commit_valid), .commit_rd(rob_commit_rd),
    .commit_value(rob_commit_value), .commit_pc(rob_commit_pc),
    .commit_tag(rob_commit_tag), .commit_is_store(rob_commit_is_store),
    .read_tag1(rs1_tag), .read_value1(rob_read_val1), .read_complete1(rob_read_done1), .read_valid1(rob_read_exists1),
    .read_tag2(rs2_tag), .read_value2(rob_read_val2), .read_complete2(rob_read_done2), .read_valid2(rob_read_exists2),
    .misprediction(rob_misprediction), .mispred_tag(rob_mispred_tag),
    .flush(rob_flush), .flush_target(rob_flush_target),
    .empty(rob_empty), .full(rob_full)
);

assign rob_commit_is_branch = 1'b0; // TODO: wire from ROB

// Branch dispatch signals (for Spec Recovery checkpoint)
assign branch_dispatch     = fetch_valid && decode_is_branch;
assign dispatch_rob_tag_out = rob_alloc_tag;

// Misprediction outputs (for Spec Recovery)
assign commit_mispredicted  = rob_misprediction;
assign commit_mispredict_tag = rob_mispred_tag;
assign commit_correct_pc    = rob_flush_target; // Correct PC from flush target

// =============================================================================
// Reservation Station (ALU ops)
// =============================================================================
reservation_station u_rs (
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
    .flush(rob_flush)
);

// =============================================================================
// Load/Store Queue
// =============================================================================
load_store_queue u_lsq (
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
    .flush(rob_flush)
);

assign stall_fetch = rob_full || !rs_dispatch_ready || !lsq_dispatch_ready;

// =============================================================================
// Execute (ALU — combinational)
// =============================================================================
reg [31:0] alu_result;
reg        alu_branch_taken;
always @(*) begin
    alu_branch_taken = 1'b0;
    case (rs_issue_opcode)
        OP_LUI:   alu_result = rs_issue_src2;
        OP_AUIPC: alu_result = rs_issue_src1 + rs_issue_src2;
        OP_BRANCH: begin
            alu_result = 32'd0; // Branches don't produce a register value
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
    if (!rst_n)
        branch_taken_d1 <= 1'b0;
    else
        branch_taken_d1 <= alu_branch_taken && rs_issue_valid;
end

// =============================================================================
// CDB — ALU (EU0), LSQ load (EU1), unused (EU2)
// =============================================================================
cdb u_cdb (
    .clk(clk), .rst_n(rst_n),
    .eu0_valid(rs_issue_valid), .eu0_tag(rs_issue_dst_tag),
    .eu0_value(alu_result), .eu0_exception(1'b0),
    .eu1_valid(lsq_result_valid), .eu1_tag(lsq_result_tag),
    .eu1_value(lsq_result_value), .eu1_exception(1'b0),
    .eu2_valid(1'b0), .eu2_tag(4'd0), .eu2_value(32'd0), .eu2_exception(1'b0),
    .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_value(cdb_value),
    .cdb_exception(cdb_exception),
    .eu0_stall(), .eu1_stall(), .eu2_stall()
);

// =============================================================================
// CDB Result Buffer — written when CDB broadcasts, persists until flush
// =============================================================================
integer bi;
always @(posedge clk) begin
    if (!rst_n || rob_flush) begin
        for (bi = 0; bi < 16; bi = bi + 1)
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
    end else if (rob_commit_valid && rob_commit_rd != 5'd0) begin
        arch_regs[rob_commit_rd] <= rob_commit_value;
    end
end

endmodule
