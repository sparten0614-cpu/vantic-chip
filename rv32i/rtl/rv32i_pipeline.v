// =============================================================================
// RV32I 5-Stage Pipelined CPU Core
// =============================================================================
// Classic RISC pipeline: IF → ID → EX → MEM → WB
//
// Features:
//   - Full RV32I instruction set
//   - Data hazard detection with forwarding (EX→EX, MEM→EX)
//   - Load-use hazard stall (1-cycle bubble)
//   - Branch resolution in EX stage with flush
//   - No branch prediction (always not-taken, flush on taken)
//
// Performance: ~1 IPC (ideal), reduced by stalls and flushes
// =============================================================================

module rv32i_pipeline (
    input  wire        clk,
    input  wire        rst_n,

    // Instruction memory (1-cycle read latency assumed)
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,

    // Data memory
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,
    output wire        dmem_wen,
    output wire        dmem_ren,
    input  wire [31:0] dmem_rdata,

    // Debug
    output wire [31:0] pc_out,
    output wire        halt
);

// =============================================================================
// Opcodes
// =============================================================================
localparam OP_LUI    = 7'b0110111, OP_AUIPC  = 7'b0010111;
localparam OP_JAL    = 7'b1101111, OP_JALR   = 7'b1100111;
localparam OP_BRANCH = 7'b1100011, OP_LOAD   = 7'b0000011;
localparam OP_STORE  = 7'b0100011, OP_IMM    = 7'b0010011;
localparam OP_REG    = 7'b0110011, OP_SYSTEM = 7'b1110011;

// =============================================================================
// Pipeline Control
// =============================================================================
wire stall;       // Pipeline stall (load-use hazard)
wire flush;       // Flush IF/ID (branch taken or jump)
wire halt_ex;     // EBREAK detected in EX stage

// =============================================================================
// Stage 1: Instruction Fetch (IF)
// =============================================================================
reg [31:0] pc;
wire [31:0] pc_plus4 = pc + 32'd4;
wire [31:0] pc_next;

assign imem_addr = pc;
assign pc_out = pc;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pc <= 32'd0;
    else if (halt_ex)
        pc <= pc; // Halt
    else if (!stall)
        pc <= pc_next;
end

// IF/ID Pipeline Register
reg [31:0] ifid_instr, ifid_pc;
reg        ifid_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ifid_instr <= 32'h00000013; // NOP (addi x0,x0,0)
        ifid_pc    <= 32'd0;
        ifid_valid <= 1'b0;
    end else if (flush) begin
        ifid_instr <= 32'h00000013;
        ifid_pc    <= 32'd0;
        ifid_valid <= 1'b0;
    end else if (!stall) begin
        ifid_instr <= imem_data;
        ifid_pc    <= pc;
        ifid_valid <= 1'b1;
    end
end

// =============================================================================
// Stage 2: Instruction Decode (ID)
// =============================================================================
wire [6:0] id_opcode = ifid_instr[6:0];
wire [4:0] id_rd     = ifid_instr[11:7];
wire [2:0] id_funct3 = ifid_instr[14:12];
wire [4:0] id_rs1    = ifid_instr[19:15];
wire [4:0] id_rs2    = ifid_instr[24:20];
wire [6:0] id_funct7 = ifid_instr[31:25];

// Immediate generation
wire [31:0] id_imm_i = {{20{ifid_instr[31]}}, ifid_instr[31:20]};
wire [31:0] id_imm_s = {{20{ifid_instr[31]}}, ifid_instr[31:25], ifid_instr[11:7]};
wire [31:0] id_imm_b = {{19{ifid_instr[31]}}, ifid_instr[31], ifid_instr[7], ifid_instr[30:25], ifid_instr[11:8], 1'b0};
wire [31:0] id_imm_u = {ifid_instr[31:12], 12'd0};
wire [31:0] id_imm_j = {{11{ifid_instr[31]}}, ifid_instr[31], ifid_instr[19:12], ifid_instr[20], ifid_instr[30:21], 1'b0};

// Register file
reg [31:0] regs [0:31];
wire [31:0] id_rs1_data = (id_rs1 == 5'd0) ? 32'd0 : regs[id_rs1];
wire [31:0] id_rs2_data = (id_rs2 == 5'd0) ? 32'd0 : regs[id_rs2];

// Control signals
wire id_reg_wen = (id_opcode == OP_LUI || id_opcode == OP_AUIPC || id_opcode == OP_JAL ||
                   id_opcode == OP_JALR || id_opcode == OP_LOAD || id_opcode == OP_IMM ||
                   id_opcode == OP_REG) && (id_rd != 5'd0);
wire id_mem_ren = (id_opcode == OP_LOAD);
wire id_mem_wen = (id_opcode == OP_STORE);
wire id_is_branch = (id_opcode == OP_BRANCH);
wire id_is_jal  = (id_opcode == OP_JAL);
wire id_is_jalr = (id_opcode == OP_JALR);
wire id_use_imm = (id_opcode != OP_REG && id_opcode != OP_BRANCH);

// Select immediate
reg [31:0] id_imm;
always @(*) begin
    case (id_opcode)
        OP_LUI, OP_AUIPC: id_imm = id_imm_u;
        OP_JAL:            id_imm = id_imm_j;
        OP_BRANCH:         id_imm = id_imm_b;
        OP_STORE:          id_imm = id_imm_s;
        default:           id_imm = id_imm_i;
    endcase
end

// ID/EX Pipeline Register
reg [31:0] idex_pc, idex_rs1_data, idex_rs2_data, idex_imm;
reg [4:0]  idex_rd, idex_rs1, idex_rs2;
reg [2:0]  idex_funct3;
reg [6:0]  idex_funct7, idex_opcode;
reg        idex_reg_wen, idex_mem_ren, idex_mem_wen;
reg        idex_is_branch, idex_is_jal, idex_is_jalr, idex_use_imm;
reg        idex_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        idex_valid     <= 1'b0;
        idex_reg_wen   <= 1'b0;
        idex_mem_ren   <= 1'b0;
        idex_mem_wen   <= 1'b0;
        idex_is_branch <= 1'b0;
        idex_is_jal    <= 1'b0;
        idex_is_jalr   <= 1'b0;
        idex_opcode    <= 7'd0;
    end else if (flush || (stall && !halt_ex)) begin
        idex_valid     <= 1'b0;
        idex_reg_wen   <= 1'b0;
        idex_mem_ren   <= 1'b0;
        idex_mem_wen   <= 1'b0;
        idex_is_branch <= 1'b0;
        idex_is_jal    <= 1'b0;
        idex_is_jalr   <= 1'b0;
        idex_opcode    <= 7'd0;
    end else if (!stall) begin
        idex_pc        <= ifid_pc;
        idex_rs1_data  <= id_rs1_data;
        idex_rs2_data  <= id_rs2_data;
        idex_imm       <= id_imm;
        idex_rd        <= id_rd;
        idex_rs1       <= id_rs1;
        idex_rs2       <= id_rs2;
        idex_funct3    <= id_funct3;
        idex_funct7    <= id_funct7;
        idex_opcode    <= id_opcode;
        idex_reg_wen   <= id_reg_wen;
        idex_mem_ren   <= id_mem_ren;
        idex_mem_wen   <= id_mem_wen;
        idex_is_branch <= id_is_branch;
        idex_is_jal    <= id_is_jal;
        idex_is_jalr   <= id_is_jalr;
        idex_use_imm   <= id_use_imm;
        idex_valid     <= ifid_valid;
    end
end

// =============================================================================
// Stage 3: Execute (EX)
// =============================================================================

// Forwarding mux for rs1
wire fwd_ex_mem_rs1 = (exmem_reg_wen && exmem_rd != 5'd0 && exmem_rd == idex_rs1);
wire fwd_mem_wb_rs1 = (memwb_reg_wen && memwb_rd != 5'd0 && memwb_rd == idex_rs1);
wire [31:0] ex_rs1 = fwd_ex_mem_rs1 ? exmem_alu_result :
                     fwd_mem_wb_rs1 ? wb_data :
                     idex_rs1_data;

// Forwarding mux for rs2
wire fwd_ex_mem_rs2 = (exmem_reg_wen && exmem_rd != 5'd0 && exmem_rd == idex_rs2);
wire fwd_mem_wb_rs2 = (memwb_reg_wen && memwb_rd != 5'd0 && memwb_rd == idex_rs2);
wire [31:0] ex_rs2 = fwd_ex_mem_rs2 ? exmem_alu_result :
                     fwd_mem_wb_rs2 ? wb_data :
                     idex_rs2_data;

// ALU
wire [31:0] alu_a = ex_rs1;
wire [31:0] alu_b = idex_use_imm ? idex_imm : ex_rs2;
wire        alu_sub = (idex_opcode == OP_REG && idex_funct7[5]) || idex_is_branch;

wire [31:0] alu_add = alu_a + (alu_sub ? (~alu_b + 32'd1) : alu_b);
wire        alu_lt  = $signed(alu_a) < $signed(alu_b);
wire        alu_ltu = alu_a < alu_b;

reg [31:0] alu_result;
always @(*) begin
    case (idex_opcode)
        OP_LUI:   alu_result = idex_imm;
        OP_AUIPC: alu_result = idex_pc + idex_imm;
        OP_JAL, OP_JALR: alu_result = idex_pc + 32'd4;
        default: begin
            case (idex_funct3)
                3'b000: alu_result = alu_add;
                3'b001: alu_result = alu_a << alu_b[4:0];
                3'b010: alu_result = {31'd0, alu_lt};
                3'b011: alu_result = {31'd0, alu_ltu};
                3'b100: alu_result = alu_a ^ alu_b;
                3'b101: alu_result = idex_funct7[5] ? ($signed(alu_a) >>> alu_b[4:0]) : (alu_a >> alu_b[4:0]);
                3'b110: alu_result = alu_a | alu_b;
                3'b111: alu_result = alu_a & alu_b;
            endcase
        end
    endcase
end

// Branch resolution
reg branch_taken;
always @(*) begin
    case (idex_funct3)
        3'b000: branch_taken = (ex_rs1 == ex_rs2);
        3'b001: branch_taken = (ex_rs1 != ex_rs2);
        3'b100: branch_taken = alu_lt;
        3'b101: branch_taken = !alu_lt;
        3'b110: branch_taken = alu_ltu;
        3'b111: branch_taken = !alu_ltu;
        default: branch_taken = 1'b0;
    endcase
end

wire ex_branch_taken = idex_is_branch && branch_taken && idex_valid;
wire [31:0] branch_target = idex_pc + idex_imm;
wire [31:0] jalr_target   = (ex_rs1 + idex_imm) & 32'hFFFFFFFE;
wire [31:0] jal_target    = idex_pc + idex_imm;

assign flush = ex_branch_taken || (idex_is_jal && idex_valid) || (idex_is_jalr && idex_valid);
assign pc_next = ex_branch_taken ? branch_target :
                 (idex_is_jal && idex_valid)  ? jal_target :
                 (idex_is_jalr && idex_valid) ? jalr_target :
                 pc_plus4;

// EBREAK
assign halt_ex = (idex_opcode == OP_SYSTEM && idex_imm[0] && idex_valid);
assign halt = halt_ex;

// Memory address (for load/store)
wire [31:0] ex_mem_addr = ex_rs1 + idex_imm;

// EX/MEM Pipeline Register
reg [31:0] exmem_alu_result, exmem_rs2_data, exmem_mem_addr;
reg [4:0]  exmem_rd;
reg [2:0]  exmem_funct3;
reg        exmem_reg_wen, exmem_mem_ren, exmem_mem_wen;
reg        exmem_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        exmem_valid   <= 1'b0;
        exmem_reg_wen <= 1'b0;
        exmem_mem_ren <= 1'b0;
        exmem_mem_wen <= 1'b0;
    end else if (!halt_ex) begin
        exmem_alu_result <= alu_result;
        exmem_rs2_data   <= ex_rs2;
        exmem_mem_addr   <= ex_mem_addr;
        exmem_rd         <= idex_rd;
        exmem_funct3     <= idex_funct3;
        exmem_reg_wen    <= idex_reg_wen && idex_valid;
        exmem_mem_ren    <= idex_mem_ren && idex_valid;
        exmem_mem_wen    <= idex_mem_wen && idex_valid;
        exmem_valid      <= idex_valid;
    end
end

// =============================================================================
// Stage 4: Memory Access (MEM)
// =============================================================================
assign dmem_addr  = exmem_mem_addr;
assign dmem_wen   = exmem_mem_wen;
assign dmem_ren   = exmem_mem_ren;
assign dmem_wdata = (exmem_funct3[1:0] == 2'b00) ? {4{exmem_rs2_data[7:0]}} :
                    (exmem_funct3[1:0] == 2'b01) ? {2{exmem_rs2_data[15:0]}} :
                    exmem_rs2_data;
assign dmem_wstrb = (exmem_funct3[1:0] == 2'b00) ? (4'b0001 << exmem_mem_addr[1:0]) :
                    (exmem_funct3[1:0] == 2'b01) ? (4'b0011 << {exmem_mem_addr[1], 1'b0}) :
                    4'b1111;

// MEM/WB Pipeline Register
reg [31:0] memwb_alu_result, memwb_mem_data;
reg [4:0]  memwb_rd;
reg [2:0]  memwb_funct3;
reg        memwb_reg_wen, memwb_mem_ren;
reg        memwb_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        memwb_valid   <= 1'b0;
        memwb_reg_wen <= 1'b0;
        memwb_mem_ren <= 1'b0;
    end else begin
        memwb_alu_result <= exmem_alu_result;
        memwb_mem_data   <= dmem_rdata;
        memwb_rd         <= exmem_rd;
        memwb_funct3     <= exmem_funct3;
        memwb_reg_wen    <= exmem_reg_wen;
        memwb_mem_ren    <= exmem_mem_ren;
        memwb_valid      <= exmem_valid;
    end
end

// =============================================================================
// Stage 5: Write-Back (WB)
// =============================================================================
// Load data extraction
reg [31:0] load_data;
always @(*) begin
    case (memwb_funct3)
        3'b000: case (memwb_alu_result[1:0])
            2'b00: load_data = {{24{memwb_mem_data[7]}},  memwb_mem_data[7:0]};
            2'b01: load_data = {{24{memwb_mem_data[15]}}, memwb_mem_data[15:8]};
            2'b10: load_data = {{24{memwb_mem_data[23]}}, memwb_mem_data[23:16]};
            2'b11: load_data = {{24{memwb_mem_data[31]}}, memwb_mem_data[31:24]};
        endcase
        3'b001: load_data = memwb_alu_result[1] ? {{16{memwb_mem_data[31]}}, memwb_mem_data[31:16]}
                                                 : {{16{memwb_mem_data[15]}}, memwb_mem_data[15:0]};
        3'b010: load_data = memwb_mem_data;
        3'b100: case (memwb_alu_result[1:0])
            2'b00: load_data = {24'd0, memwb_mem_data[7:0]};
            2'b01: load_data = {24'd0, memwb_mem_data[15:8]};
            2'b10: load_data = {24'd0, memwb_mem_data[23:16]};
            2'b11: load_data = {24'd0, memwb_mem_data[31:24]};
        endcase
        3'b101: load_data = memwb_alu_result[1] ? {16'd0, memwb_mem_data[31:16]}
                                                 : {16'd0, memwb_mem_data[15:0]};
        default: load_data = memwb_mem_data;
    endcase
end

wire [31:0] wb_data = memwb_mem_ren ? load_data : memwb_alu_result;

// Register write
integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] <= 32'd0;
    end else if (memwb_reg_wen && memwb_rd != 5'd0) begin
        regs[memwb_rd] <= wb_data;
    end
end

// =============================================================================
// Hazard Detection: Load-Use Stall
// =============================================================================
// If EX stage has a load and ID stage needs the result → stall 1 cycle
assign stall = idex_mem_ren && idex_valid &&
               ((idex_rd == id_rs1 && id_rs1 != 5'd0) ||
                (idex_rd == id_rs2 && id_rs2 != 5'd0));

endmodule
