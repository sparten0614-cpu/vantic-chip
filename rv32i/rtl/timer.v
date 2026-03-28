// =============================================================================
// 32-bit Timer/Counter with PWM and Compare Match
// =============================================================================
// Features:
//   - 32-bit up counter with auto-reload (period register)
//   - 8-bit prescaler (1 to 256)
//   - 2 compare channels (CC0, CC1) with match interrupt
//   - PWM output on each channel
//   - Overflow interrupt
//   - Start/stop/reset control
//
// Register Map:
//   0x00: CTRL      — [0]=enable, [1]=oneshot, [7:4]=prescaler_sel
//   0x04: COUNT     — Current counter value (read/write)
//   0x08: PERIOD    — Auto-reload value (counter resets when COUNT==PERIOD)
//   0x0C: CC0       — Compare channel 0 value
//   0x10: CC1       — Compare channel 1 value
//   0x14: INTEN     — Interrupt enable: [0]=overflow, [1]=CC0 match, [2]=CC1 match
//   0x18: INTFLAG   — Interrupt flags (write 1 to clear)
//   0x1C: STATUS    — [0]=running, [1]=CC0 match, [2]=CC1 match
// =============================================================================

module timer (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [7:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    input  wire        reg_wen,
    output reg  [31:0] reg_rdata,

    // Outputs
    output wire        pwm0,         // PWM output channel 0
    output wire        pwm1,         // PWM output channel 1
    output wire        irq           // Interrupt output
);

// Registers
reg        enable;
reg        oneshot;
reg [3:0]  prescaler_sel;
reg [31:0] count;
reg [31:0] period;
reg [31:0] cc0, cc1;
reg [2:0]  inten;
reg [2:0]  intflag;

// Prescaler
reg [7:0] prescaler_cnt;
wire [7:0] prescaler_max = (8'd1 << prescaler_sel) - 8'd1;
wire prescaler_tick = (prescaler_cnt >= prescaler_max);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        prescaler_cnt <= 8'd0;
    else if (!enable)
        prescaler_cnt <= 8'd0;
    else if (prescaler_tick)
        prescaler_cnt <= 8'd0;
    else
        prescaler_cnt <= prescaler_cnt + 8'd1;
end

// Counter
wire overflow = enable && prescaler_tick && (count >= period);
wire cc0_match = enable && prescaler_tick && (count == cc0);
wire cc1_match = enable && prescaler_tick && (count == cc1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        count <= 32'd0;
    else if (enable && prescaler_tick) begin
        if (count >= period) begin
            if (oneshot)
                ; // Stop
            else
                count <= 32'd0;
        end else
            count <= count + 32'd1;
    end
end

// Interrupt flags
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        intflag <= 3'd0;
    else begin
        if (overflow)  intflag[0] <= 1'b1;
        if (cc0_match) intflag[1] <= 1'b1;
        if (cc1_match) intflag[2] <= 1'b1;
        if (reg_wen && reg_addr == 8'h18)
            intflag <= intflag & ~reg_wdata[2:0];
    end
end

assign irq = |(intflag & inten);

// PWM outputs
assign pwm0 = (count < cc0);
assign pwm1 = (count < cc1);

// Register write
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        enable <= 1'b0; oneshot <= 1'b0; prescaler_sel <= 4'd0;
        period <= 32'hFFFFFFFF; cc0 <= 32'd0; cc1 <= 32'd0;
        inten <= 3'd0;
    end else if (reg_wen) begin
        case (reg_addr)
            8'h00: {prescaler_sel, oneshot, enable} <= {reg_wdata[7:4], reg_wdata[1], reg_wdata[0]};
            8'h04: ; // COUNT write handled separately
            8'h08: period <= reg_wdata;
            8'h0C: cc0   <= reg_wdata;
            8'h10: cc1   <= reg_wdata;
            8'h14: inten  <= reg_wdata[2:0];
            default: ;
        endcase
    end
end

// Register read
always @(*) begin
    case (reg_addr)
        8'h00: reg_rdata = {24'd0, prescaler_sel, 2'd0, oneshot, enable};
        8'h04: reg_rdata = count;
        8'h08: reg_rdata = period;
        8'h0C: reg_rdata = cc0;
        8'h10: reg_rdata = cc1;
        8'h14: reg_rdata = {29'd0, inten};
        8'h18: reg_rdata = {29'd0, intflag};
        8'h1C: reg_rdata = {29'd0, cc1_match, cc0_match, enable};
        default: reg_rdata = 32'd0;
    endcase
end

endmodule
