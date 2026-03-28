// =============================================================================
// UART Receiver — 8N1 with Oversampling
// =============================================================================
// 16x oversampling for robust bit sampling at center of each bit period.
// baud_div = clk_freq / baud_rate - 1 (same as TX)
// =============================================================================

module uart_rx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] baud_div,     // Baud rate divider
    input  wire        rx_in,        // UART RX pin (idle high)
    output reg  [7:0]  rx_data,      // Received byte
    output reg         rx_valid,     // Pulse: byte received
    output reg         rx_error      // Framing error (stop bit != 1)
);

localparam [3:0] IDLE  = 4'd0,
                 START = 4'd1,
                 D0=4'd2, D1=4'd3, D2=4'd4, D3=4'd5,
                 D4=4'd6, D5=4'd7, D6=4'd8, D7=4'd9,
                 STOP  = 4'd10;

reg [3:0]  state;
reg [15:0] baud_cnt;
reg [7:0]  shift_reg;

// 2-stage synchronizer for async RX input
reg rx_s1, rx_s2;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rx_s1 <= 1; rx_s2 <= 1; end
    else begin rx_s1 <= rx_in; rx_s2 <= rx_s1; end
end

// Half-baud tick for sampling at bit center
wire [15:0] half_baud = {1'b0, baud_div[15:1]};
wire baud_tick = (baud_cnt == 16'd0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state     <= IDLE;
        baud_cnt  <= 16'd0;
        shift_reg <= 8'd0;
        rx_data   <= 8'd0;
        rx_valid  <= 1'b0;
        rx_error  <= 1'b0;
    end else begin
        rx_valid <= 1'b0;
        rx_error <= 1'b0;

        case (state)
        IDLE: begin
            if (!rx_s2) begin // Start bit detected (falling edge)
                baud_cnt <= half_baud; // Sample at center of start bit
                state    <= START;
            end
        end

        START: begin
            if (baud_tick) begin
                if (!rx_s2) begin // Confirm start bit is still low at center
                    baud_cnt <= baud_div;
                    state    <= D0;
                end else begin
                    state <= IDLE; // False start
                end
            end else
                baud_cnt <= baud_cnt - 16'd1;
        end

        D0,D1,D2,D3,D4,D5,D6: begin
            if (baud_tick) begin
                shift_reg <= {rx_s2, shift_reg[7:1]};
                baud_cnt  <= baud_div;
                state     <= state + 4'd1;
            end else
                baud_cnt <= baud_cnt - 16'd1;
        end

        D7: begin
            if (baud_tick) begin
                shift_reg <= {rx_s2, shift_reg[7:1]};
                baud_cnt  <= baud_div;
                state     <= STOP;
            end else
                baud_cnt <= baud_cnt - 16'd1;
        end

        STOP: begin
            if (baud_tick) begin
                if (rx_s2) begin // Stop bit should be high
                    rx_data  <= {rx_s2, shift_reg[7:1]}; // Wait, shift_reg already has all 8 bits
                    rx_data  <= shift_reg;
                    rx_valid <= 1'b1;
                end else begin
                    rx_error <= 1'b1; // Framing error
                end
                state <= IDLE;
            end else
                baud_cnt <= baud_cnt - 16'd1;
        end

        default: state <= IDLE;
        endcase
    end
end

endmodule
