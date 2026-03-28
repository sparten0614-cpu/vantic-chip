// =============================================================================
// 2-Way In-Order Dual-Issue Logic — Exploration Prototype
// =============================================================================
// Determines whether two consecutive instructions can be issued in parallel.
//
// Rules for dual-issue:
//   1. No RAW hazard: instr_B.rs1/rs2 != instr_A.rd
//   2. No WAW hazard: instr_B.rd != instr_A.rd (both write)
//   3. At most one memory operation (load or store)
//   4. At most one branch/jump
//   5. Neither is a system instruction (ECALL/EBREAK/CSR)
//
// Output: issue_dual = 1 if both can be issued, 0 if only first
// =============================================================================

module dual_issue (
    // Instruction A (older, always issues)
    input  wire [6:0]  a_opcode,
    input  wire [4:0]  a_rd,
    input  wire [4:0]  a_rs1,
    input  wire [4:0]  a_rs2,

    // Instruction B (younger, conditionally issues)
    input  wire [6:0]  b_opcode,
    input  wire [4:0]  b_rd,
    input  wire [4:0]  b_rs1,
    input  wire [4:0]  b_rs2,

    // Output
    output wire        issue_dual    // 1 = both issue, 0 = only A issues
);

// Opcodes
localparam OP_LOAD   = 7'b0000011;
localparam OP_STORE  = 7'b0100011;
localparam OP_BRANCH = 7'b1100011;
localparam OP_JAL    = 7'b1101111;
localparam OP_JALR   = 7'b1100111;
localparam OP_SYSTEM = 7'b1110011;

// Does instruction A write a register?
wire a_writes = (a_rd != 5'd0) && (a_opcode != OP_STORE) &&
                (a_opcode != OP_BRANCH) && (a_opcode != OP_SYSTEM);

// Classify instructions
wire a_is_mem    = (a_opcode == OP_LOAD || a_opcode == OP_STORE);
wire b_is_mem    = (b_opcode == OP_LOAD || b_opcode == OP_STORE);
wire a_is_branch = (a_opcode == OP_BRANCH || a_opcode == OP_JAL || a_opcode == OP_JALR);
wire b_is_branch = (b_opcode == OP_BRANCH || b_opcode == OP_JAL || b_opcode == OP_JALR);
wire a_is_system = (a_opcode == OP_SYSTEM);
wire b_is_system = (b_opcode == OP_SYSTEM);

// RAW hazard: B reads what A writes
wire raw_hazard = a_writes && ((b_rs1 == a_rd) || (b_rs2 == a_rd));

// WAW hazard: both write same register
wire b_writes = (b_rd != 5'd0) && (b_opcode != OP_STORE) &&
                (b_opcode != OP_BRANCH) && (b_opcode != OP_SYSTEM);
wire waw_hazard = a_writes && b_writes && (a_rd == b_rd);

// Structural hazards
wire dual_mem    = a_is_mem && b_is_mem;
wire dual_branch = a_is_branch && b_is_branch;
wire any_system  = a_is_system || b_is_system;

// Dual-issue decision
assign issue_dual = !raw_hazard && !waw_hazard && !dual_mem && !dual_branch && !any_system;

endmodule
