// =============================================================================
// VT3100 GoodCRC Auto-Response Module
// =============================================================================
// Automatically sends GoodCRC in response to valid received messages,
// and detects GoodCRC responses to our transmitted messages.
//
// USB PD requires GoodCRC within tGoodCRCReceive (195μs).
// This module operates at the pd_msg layer:
//   - On rx_msg_valid: checks MessageID, if valid → auto-sends GoodCRC
//   - On GoodCRC received after TX: signals goodcrc_received to Policy Engine
//
// MessageID tracking:
//   - rx_expected_id: expected incoming MessageID (0-7, wraps)
//   - Messages with wrong ID are silently dropped (not forwarded)
// =============================================================================

module goodcrc (
    input  wire        clk,
    input  wire        rst_n,

    // From pd_msg RX parser
    input  wire        rx_msg_valid,
    input  wire [4:0]  rx_msg_type,
    input  wire [2:0]  rx_msg_id,
    input  wire [2:0]  rx_num_do,

    // To/from pd_msg TX builder (shared with Policy Engine via arbiter)
    output reg         gc_tx_start,
    output reg  [4:0]  gc_tx_msg_type,
    output reg  [2:0]  gc_tx_num_do,
    input  wire        gc_tx_busy,

    // Role info (passed through to GoodCRC header)
    input  wire        port_power_role,
    input  wire        port_data_role,

    // Filtered message output to Policy Engine
    output reg         filtered_rx_valid,  // Pulse: valid non-GoodCRC message with correct ID
    output reg  [4:0]  filtered_rx_type,
    output reg  [2:0]  filtered_rx_num_do,

    // GoodCRC received signal (for messages we sent)
    output reg         goodcrc_received,

    // MessageID management
    input  wire        msg_id_rst,   // Reset rx_expected_id (hard/soft reset)
    output reg  [2:0]  rx_expected_id
);

localparam [4:0] MSG_GOODCRC = 5'h01;

// =============================================================================
// RX MessageID Tracking
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rx_expected_id <= 3'd0;
    else if (msg_id_rst)
        rx_expected_id <= 3'd0;
    else if (rx_msg_valid && !(rx_msg_type == MSG_GOODCRC && rx_num_do == 3'd0) && rx_msg_id == rx_expected_id && gc_state == GC_IDLE)
        rx_expected_id <= rx_expected_id + 3'd1; // wraps mod 8
end

// =============================================================================
// Message Classification & Auto-Response
// =============================================================================
localparam [1:0] GC_IDLE    = 2'd0,
                 GC_SEND    = 2'd1,
                 GC_WAIT    = 2'd2;

reg [1:0] gc_state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        gc_state         <= GC_IDLE;
        gc_tx_start      <= 0;
        gc_tx_msg_type   <= 0;
        gc_tx_num_do     <= 0;
        filtered_rx_valid <= 0;
        filtered_rx_type  <= 0;
        filtered_rx_num_do <= 0;
        goodcrc_received <= 0;
    end else begin
        gc_tx_start      <= 0;
        filtered_rx_valid <= 0;
        goodcrc_received <= 0;

        case (gc_state)
        GC_IDLE: begin
            if (rx_msg_valid) begin
                if (rx_msg_type == MSG_GOODCRC && rx_num_do == 3'd0) begin
                    // GoodCRC is control msg: type=0x01 AND num_do=0
                    // (type 0x01 with num_do>0 is Source_Capabilities data msg)
                    goodcrc_received <= 1;
                end else if (!(rx_msg_type == MSG_GOODCRC && rx_num_do == 3'd0) &&
                            rx_msg_id == rx_expected_id) begin
                    // Valid data/control message — forward and auto-respond
                    filtered_rx_valid  <= 1;
                    filtered_rx_type   <= rx_msg_type;
                    filtered_rx_num_do <= rx_num_do;
                    // Send GoodCRC
                    gc_state <= GC_SEND;
                end
                // Wrong MessageID → silently drop (no forward, no GoodCRC)
            end
        end

        GC_SEND: begin
            if (!gc_tx_busy) begin
                gc_tx_start    <= 1;
                gc_tx_msg_type <= MSG_GOODCRC;
                gc_tx_num_do   <= 0;
                gc_state       <= GC_WAIT;
            end
        end

        GC_WAIT: begin
            // Wait for TX to complete, then return to idle
            if (!gc_tx_busy)
                gc_state <= GC_IDLE;
        end

        default: gc_state <= GC_IDLE;
        endcase
    end
end

endmodule
