// =============================================================================
// RV32I CPU Core — Single-Cycle RISC-V Implementation
// =============================================================================
// Implements the RV32I base integer instruction set (37 instructions).
// Single-cycle: one instruction per clock cycle, no pipeline.
//
// Architecture:
//   - 32 x 32-bit general purpose registers (x0 hardwired to 0)
//   - 32-bit program counter
//   - Instruction memory interface (read-only)
//   - Data memory interface (read/write, byte/half/word)
//   - No interrupts/exceptions (minimal implementation)
//
// Instruction types: R, I, S, B, U, J
// =============================================================================

module rv32i_core (
    input  wire        clk,
    input  wire        rst_n,

    // Instruction memory interface
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,

    // Data memory interface
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,    // Byte write strobes
    output wire        dmem_wen,
    output wire        dmem_ren,
    input  wire [31:0] dmem_rdata,

    // Debug
    output wire [31:0] pc_out,
    output wire        halt           // EBREAK instruction detected
);

// =============================================================================
// Program Counter
// =============================================================================
reg [31:0] pc;
assign pc_out = pc;
assign imem_addr = pc;

wire [31:0] pc_plus4 = pc + 32'd4;

// =============================================================================
// Instruction Decode
// =============================================================================
wire [31:0] instr = imem_data;

wire [6:0]  opcode = instr[6:0];
wire [4:0]  rd     = instr[11:7];
wire [2:0]  funct3 = instr[14:12];
wire [4:0]  rs1    = instr[19:15];
wire [4:0]  rs2    = instr[24:20];
wire [6:0]  funct7 = instr[31:25];

// Immediate generation
wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
wire [31:0] imm_u = {instr[31:12], 12'd0};
wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

// Opcode decode
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
// Register File (32 x 32-bit, x0 = 0)
// =============================================================================
reg [31:0] regs [0:31];

wire [31:0] rs1_data = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
wire [31:0] rs2_data = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

// =============================================================================
// ALU
// =============================================================================
wire        alu_sub = (opcode == OP_REG && funct7[5]) || (opcode == OP_BRANCH);
wire [31:0] alu_a   = rs1_data;
wire [31:0] alu_b   = (opcode == OP_REG || opcode == OP_BRANCH) ? rs2_data : imm_i;

wire [31:0] alu_add = alu_a + (alu_sub ? (~alu_b + 32'd1) : alu_b);
wire [31:0] alu_xor = alu_a ^ alu_b;
wire [31:0] alu_or  = alu_a | alu_b;
wire [31:0] alu_and = alu_a & alu_b;
wire [31:0] alu_sll = alu_a << alu_b[4:0];
wire [31:0] alu_srl = alu_a >> alu_b[4:0];
wire signed [31:0] alu_sra_s = $signed(alu_a) >>> alu_b[4:0];
wire [31:0] alu_sra = alu_sra_s;
wire        alu_lt  = $signed(alu_a) < $signed(alu_b);
wire        alu_ltu = alu_a < alu_b;

// ALU result mux
reg [31:0] alu_result;
always @(*) begin
    case (funct3)
        3'b000: alu_result = alu_add;
        3'b001: alu_result = alu_sll;
        3'b010: alu_result = {31'd0, alu_lt};
        3'b011: alu_result = {31'd0, alu_ltu};
        3'b100: alu_result = alu_xor;
        3'b101: alu_result = funct7[5] ? alu_sra : alu_srl;
        3'b110: alu_result = alu_or;
        3'b111: alu_result = alu_and;
    endcase
end

// =============================================================================
// Branch Logic
// =============================================================================
reg branch_taken;
always @(*) begin
    case (funct3)
        3'b000: branch_taken = (rs1_data == rs2_data);         // BEQ
        3'b001: branch_taken = (rs1_data != rs2_data);         // BNE
        3'b100: branch_taken = alu_lt;                         // BLT
        3'b101: branch_taken = !alu_lt;                        // BGE
        3'b110: branch_taken = alu_ltu;                        // BLTU
        3'b111: branch_taken = !alu_ltu;                       // BGEU
        default: branch_taken = 1'b0;
    endcase
end

// =============================================================================
// Memory Access
// =============================================================================
wire [31:0] mem_addr = rs1_data + ((opcode == OP_STORE) ? imm_s : imm_i);
assign dmem_addr  = mem_addr;
assign dmem_wen   = (opcode == OP_STORE);
assign dmem_ren   = (opcode == OP_LOAD);

// Store data alignment and byte strobes
assign dmem_wdata = (funct3[1:0] == 2'b00) ? {4{rs2_data[7:0]}} :   // SB
                    (funct3[1:0] == 2'b01) ? {2{rs2_data[15:0]}} :   // SH
                    rs2_data;                                          // SW
assign dmem_wstrb = (funct3[1:0] == 2'b00) ? (4'b0001 << mem_addr[1:0]) :
                    (funct3[1:0] == 2'b01) ? (4'b0011 << {mem_addr[1], 1'b0}) :
                    4'b1111;

// Load data extraction
reg [31:0] load_data;
always @(*) begin
    case (funct3)
        3'b000: begin // LB
            case (mem_addr[1:0])
                2'b00: load_data = {{24{dmem_rdata[7]}},  dmem_rdata[7:0]};
                2'b01: load_data = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
                2'b10: load_data = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
                2'b11: load_data = {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
            endcase
        end
        3'b001: begin // LH
            load_data = mem_addr[1] ? {{16{dmem_rdata[31]}}, dmem_rdata[31:16]}
                                    : {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
        end
        3'b010: load_data = dmem_rdata; // LW
        3'b100: begin // LBU
            case (mem_addr[1:0])
                2'b00: load_data = {24'd0, dmem_rdata[7:0]};
                2'b01: load_data = {24'd0, dmem_rdata[15:8]};
                2'b10: load_data = {24'd0, dmem_rdata[23:16]};
                2'b11: load_data = {24'd0, dmem_rdata[31:24]};
            endcase
        end
        3'b101: begin // LHU
            load_data = mem_addr[1] ? {16'd0, dmem_rdata[31:16]}
                                    : {16'd0, dmem_rdata[15:0]};
        end
        default: load_data = dmem_rdata;
    endcase
end

// =============================================================================
// Write-back Mux
// =============================================================================
reg [31:0] wb_data;
always @(*) begin
    case (opcode)
        OP_LUI:    wb_data = imm_u;
        OP_AUIPC:  wb_data = pc + imm_u;
        OP_JAL:    wb_data = pc_plus4;
        OP_JALR:   wb_data = pc_plus4;
        OP_LOAD:   wb_data = load_data;
        OP_IMM:    wb_data = alu_result;
        OP_REG:    wb_data = alu_result;
        default:   wb_data = 32'd0;
    endcase
end

// Register write enable
wire reg_wen = (opcode == OP_LUI || opcode == OP_AUIPC || opcode == OP_JAL ||
                opcode == OP_JALR || opcode == OP_LOAD || opcode == OP_IMM ||
                opcode == OP_REG) && (rd != 5'd0);

// =============================================================================
// Next PC
// =============================================================================
reg [31:0] next_pc;
always @(*) begin
    case (opcode)
        OP_JAL:    next_pc = pc + imm_j;
        OP_JALR:   next_pc = (rs1_data + imm_i) & 32'hFFFFFFFE;
        OP_BRANCH: next_pc = branch_taken ? (pc + imm_b) : pc_plus4;
        default:   next_pc = pc_plus4;
    endcase
end

// =============================================================================
// EBREAK / Halt
// =============================================================================
assign halt = (opcode == OP_SYSTEM && instr[20] == 1'b1); // EBREAK

// =============================================================================
// Sequential Logic
// =============================================================================
integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc <= 32'd0;
        for (i = 0; i < 32; i = i + 1)
            regs[i] <= 32'd0;
    end else if (!halt) begin
        pc <= next_pc;
        if (reg_wen)
            regs[rd] <= wb_data;
    end
end

endmodule
