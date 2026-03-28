// =============================================================================
// RV32M Multiply/Divide Unit
// =============================================================================
// Implements RV32M extension: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
//
// Multiply: 1-cycle (combinational 32x32→64 multiply)
// Divide: 32-cycle iterative restoring division
// =============================================================================

module rv32im_mul (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,         // Start operation
    input  wire [2:0]  funct3,        // Operation select
    input  wire [31:0] op_a,          // Operand A (rs1)
    input  wire [31:0] op_b,          // Operand B (rs2)

    output reg  [31:0] result,        // Result
    output reg         ready,         // Result valid
    output wire        busy           // Operation in progress
);

// funct3 encoding (RV32M)
localparam MUL    = 3'b000;
localparam MULH   = 3'b001;
localparam MULHSU = 3'b010;
localparam MULHU  = 3'b011;
localparam DIV    = 3'b100;
localparam DIVU   = 3'b101;
localparam REM    = 3'b110;
localparam REMU   = 3'b111;

// =============================================================================
// Multiply (combinational, 1-cycle)
// =============================================================================
wire signed [63:0] mul_ss = $signed(op_a) * $signed(op_b);
wire        [63:0] mul_uu = {32'd0, op_a} * {32'd0, op_b};
wire signed [63:0] mul_su = $signed({{32{op_a[31]}}, op_a}) * $signed({32'd0, op_b});

// =============================================================================
// Divide (32-cycle iterative restoring division)
// =============================================================================
reg [4:0]  div_count;
reg [31:0] div_quotient;
reg [31:0] div_remainder;
reg [31:0] div_divisor;
reg        div_active;
reg        div_sign_q;   // Sign of quotient
reg        div_sign_r;   // Sign of remainder
reg [2:0]  op_saved;

assign busy = div_active;

// Division step
wire [32:0] div_sub = {div_remainder, div_quotient[31]} - {1'b0, div_divisor};

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        div_active <= 1'b0;
        ready      <= 1'b0;
        result     <= 32'd0;
        div_count  <= 5'd0;
    end else begin
        ready <= 1'b0;

        if (start && !div_active) begin
            if (funct3[2]) begin
                // Division — start 32-cycle process
                div_active <= 1'b1;
                div_count  <= 5'd0;
                op_saved   <= funct3;

                // Handle signs for signed division
                if (funct3 == DIV || funct3 == REM) begin
                    div_quotient <= op_a[31] ? (~op_a + 32'd1) : op_a;
                    div_divisor  <= op_b[31] ? (~op_b + 32'd1) : op_b;
                    div_sign_q   <= op_a[31] ^ op_b[31];
                    div_sign_r   <= op_a[31];
                end else begin
                    div_quotient <= op_a;
                    div_divisor  <= op_b;
                    div_sign_q   <= 1'b0;
                    div_sign_r   <= 1'b0;
                end
                div_remainder <= 32'd0;
            end else begin
                // Multiply — 1-cycle result
                case (funct3)
                    MUL:    result <= mul_ss[31:0];
                    MULH:   result <= mul_ss[63:32];
                    MULHSU: result <= mul_su[63:32];
                    MULHU:  result <= mul_uu[63:32];
                    default: result <= 32'd0;
                endcase
                ready <= 1'b1;
            end
        end else if (div_active) begin
            if (op_b == 32'd0) begin
                // Division by zero
                result     <= (op_saved == DIV || op_saved == DIVU) ? 32'hFFFFFFFF : op_a;
                ready      <= 1'b1;
                div_active <= 1'b0;
            end else if (div_count == 5'd31) begin
                // Last step — produce result
                if (div_sub[32]) begin
                    // Subtraction failed, keep remainder
                    if (op_saved == DIV || op_saved == DIVU)
                        result <= div_sign_q ? (~{div_quotient[30:0], 1'b0} + 32'd1) : {div_quotient[30:0], 1'b0};
                    else
                        result <= div_sign_r ? (~div_remainder + 32'd1) : div_remainder;
                end else begin
                    if (op_saved == DIV || op_saved == DIVU)
                        result <= div_sign_q ? (~{div_quotient[30:0], 1'b1} + 32'd1) : {div_quotient[30:0], 1'b1};
                    else
                        result <= div_sign_r ? (~div_sub[31:0] + 32'd1) : div_sub[31:0];
                end
                ready      <= 1'b1;
                div_active <= 1'b0;
            end else begin
                // Division step
                if (div_sub[32]) begin
                    // Subtraction failed — shift 0 into quotient
                    div_remainder <= {div_remainder[30:0], div_quotient[31]};
                    div_quotient  <= {div_quotient[30:0], 1'b0};
                end else begin
                    // Subtraction succeeded — shift 1 into quotient
                    div_remainder <= {div_sub[30:0], div_quotient[31]};
                    div_quotient  <= {div_quotient[30:0], 1'b1};
                end
                div_count <= div_count + 5'd1;
            end
        end
    end
end

endmodule
