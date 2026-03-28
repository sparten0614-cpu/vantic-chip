// =============================================================================
// UART Transmitter — Configurable Baud Rate
// =============================================================================
// Standard UART TX: 8N1 (8 data bits, no parity, 1 stop bit)
// Baud rate = clk_freq / (baud_div + 1)
// =============================================================================

module uart_tx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] baud_div,    // Baud rate divider (clk/baud - 1)
    input  wire [7:0]  tx_data,     // Data to transmit
    input  wire        tx_valid,    // Pulse: start transmission
    output reg         tx_out,      // UART TX pin (idle high)
    output reg         tx_busy      // Transmitting
);

localparam [3:0] IDLE  = 4'd0,
                 START = 4'd1,
                 D0=4'd2, D1=4'd3, D2=4'd4, D3=4'd5,
                 D4=4'd6, D5=4'd7, D6=4'd8, D7=4'd9,
                 STOP  = 4'd10;

reg [3:0]  state;
reg [15:0] baud_cnt;
reg [7:0]  shift_reg;

wire baud_tick = (baud_cnt == 16'd0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state     <= IDLE;
        baud_cnt  <= 16'd0;
        shift_reg <= 8'd0;
        tx_out    <= 1'b1;
        tx_busy   <= 1'b0;
    end else begin
        case (state)
        IDLE: begin
            tx_out  <= 1'b1;
            tx_busy <= 1'b0;
            if (tx_valid) begin
                shift_reg <= tx_data;
                baud_cnt  <= baud_div;
                tx_out    <= 1'b0; // Start bit
                tx_busy   <= 1'b1;
                state     <= START;
            end
        end
        START: begin
            if (baud_tick) begin
                baud_cnt <= baud_div;
                tx_out   <= shift_reg[0];
                shift_reg <= {1'b0, shift_reg[7:1]};
                state    <= D0;
            end else
                baud_cnt <= baud_cnt - 16'd1;
        end
        D0,D1,D2,D3,D4,D5,D6: begin
            if (baud_tick) begin
                baud_cnt <= baud_div;
                tx_out   <= shift_reg[0];
                shift_reg <= {1'b0, shift_reg[7:1]};
                state    <= state + 4'd1;
            end else
                baud_cnt <= baud_cnt - 16'd1;
        end
        D7: begin
            if (baud_tick) begin
                baud_cnt <= baud_div;
                tx_out   <= 1'b1; // Stop bit
                state    <= STOP;
            end else
                baud_cnt <= baud_cnt - 16'd1;
        end
        STOP: begin
            if (baud_tick) begin
                state <= IDLE;
            end else
                baud_cnt <= baud_cnt - 16'd1;
        end
        default: state <= IDLE;
        endcase
    end
end

endmodule
