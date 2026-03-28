// =============================================================================
// VT3100 PD Message Builder/Parser
// =============================================================================
// Handles USB PD message serialization (TX) and deserialization (RX).
//
// USB PD Message Frame (after SOP, before CRC — CRC handled by BMC PHY):
//   [Header: 2 bytes] [Data Objects: 0-7 × 4 bytes]
//   All multi-byte fields are Little Endian (LSB first on wire).
//
// PD Message Header (16 bits, per USB PD 3.0 Table 6-1):
//   Bit [15]    : Extended
//   Bit [14:12] : Number of Data Objects (0-7)
//   Bit [11:9]  : MessageID (0-7, auto-incremented per successful TX)
//   Bit [8]     : Port Power Role (0=Sink, 1=Source)
//   Bit [7:6]   : Specification Revision (00=1.0, 01=2.0, 10=3.0)
//   Bit [5]     : Port Data Role (0=UFP, 1=DFP)
//   Bit [4:0]   : Message Type
//
// Interface to BMC PHY:
//   TX: drives tx_valid/tx_data/tx_sop/tx_eop, reads tx_ready
//   RX: reads rx_valid/rx_data/rx_sop/rx_eop
//
// Clocking: clk = 12 MHz system clock
// =============================================================================

module pd_msg (
    input  wire        clk,
    input  wire        rst_n,

    // =========================================================================
    // TX Builder Interface (from higher-level protocol engine)
    // =========================================================================
    input  wire        tx_start,         // Pulse: begin transmitting a message
    input  wire [4:0]  tx_msg_type,      // Message type field
    input  wire [2:0]  tx_num_do,        // Number of data objects (0-7)
    input  wire        tx_extended,      // Extended message flag
    // Data objects: up to 7 × 32-bit, loaded before tx_start
    input  wire [31:0] tx_do0,
    input  wire [31:0] tx_do1,
    input  wire [31:0] tx_do2,
    input  wire [31:0] tx_do3,
    input  wire [31:0] tx_do4,
    input  wire [31:0] tx_do5,
    input  wire [31:0] tx_do6,
    output reg         tx_busy,          // 1 while transmitting
    output reg         tx_done,          // Pulse: transmission complete

    // Role information (from register file / policy engine)
    input  wire        port_power_role,  // 1=Source
    input  wire        port_data_role,   // 1=DFP
    input  wire [1:0]  spec_revision,    // 10=PD 3.0

    // MessageID control
    output reg  [2:0]  tx_msg_id,        // Current TX MessageID (readable)
    input  wire        tx_msg_id_inc,    // Pulse: increment MessageID (after GoodCRC received)
    input  wire        tx_msg_id_rst,    // Pulse: reset MessageID to 0 (hard/soft reset)

    // =========================================================================
    // BMC PHY TX interface
    // =========================================================================
    output reg         phy_tx_valid,
    output reg  [7:0]  phy_tx_data,
    output reg         phy_tx_sop,
    output reg         phy_tx_eop,
    input  wire        phy_tx_ready,

    // =========================================================================
    // RX Parser Interface (to higher-level protocol engine)
    // =========================================================================
    output reg         rx_msg_valid,     // Pulse: complete message received & parsed
    output reg  [4:0]  rx_msg_type,
    output reg  [2:0]  rx_num_do,
    output reg  [2:0]  rx_msg_id,
    output reg         rx_port_power_role,
    output reg  [1:0]  rx_spec_revision,
    output reg         rx_port_data_role,
    output reg         rx_extended,
    output reg [31:0]  rx_do0,
    output reg [31:0]  rx_do1,
    output reg [31:0]  rx_do2,
    output reg [31:0]  rx_do3,
    output reg [31:0]  rx_do4,
    output reg [31:0]  rx_do5,
    output reg [31:0]  rx_do6,
    output reg         rx_error,         // Pulse: parse error (unexpected EOP, etc.)

    // =========================================================================
    // BMC PHY RX interface
    // =========================================================================
    input  wire [7:0]  phy_rx_data,
    input  wire        phy_rx_valid,
    input  wire        phy_rx_sop,
    input  wire        phy_rx_eop,
    input  wire        phy_rx_crc_ok
);

// =============================================================================
// TX MessageID counter
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        tx_msg_id <= 3'd0;
    else if (tx_msg_id_rst)
        tx_msg_id <= 3'd0;
    else if (tx_msg_id_inc)
        tx_msg_id <= tx_msg_id + 3'd1; // wraps mod 8 naturally
end

// =============================================================================
// TX Builder
// =============================================================================
// Constructs header, then serializes header + DOs byte-by-byte to PHY.
//
// Byte order (Little Endian):
//   Byte 0: Header[7:0]
//   Byte 1: Header[15:8]
//   Byte 2: DO0[7:0]   (if num_do >= 1)
//   Byte 3: DO0[15:8]
//   Byte 4: DO0[23:16]
//   Byte 5: DO0[31:24]
//   Byte 6: DO1[7:0]   (if num_do >= 2)
//   ... and so on
//   Last byte gets tx_eop asserted.

localparam [2:0] TX_IDLE     = 3'd0,
                 TX_HDR_LO   = 3'd1,
                 TX_HDR_HI   = 3'd2,
                 TX_DO_BYTE  = 3'd3,
                 TX_WAIT_DONE = 3'd4;

reg [2:0]  tx_state;
reg [15:0] tx_header;
reg [4:0]  tx_byte_idx;  // total byte index within message (max: 2 + 7*4 = 30)
reg [2:0]  tx_do_idx;    // current data object index (0-6)
reg [1:0]  tx_do_byte;   // byte within current DO (0-3)
reg [2:0]  tx_num_do_r;  // registered num_do
reg [31:0] tx_do_mem [0:6]; // registered data objects

// Total bytes in message: 2 (header) + num_do * 4
wire [4:0] tx_total_bytes = 5'd2 + {2'b0, tx_num_do_r} * 5'd4;
// Is this the last byte?
wire tx_last_byte = (tx_byte_idx == tx_total_bytes - 5'd1);

// Select current DO byte
reg [7:0] tx_do_cur_byte;
always @(*) begin
    case (tx_do_byte)
        2'd0: tx_do_cur_byte = tx_do_mem[tx_do_idx][7:0];
        2'd1: tx_do_cur_byte = tx_do_mem[tx_do_idx][15:8];
        2'd2: tx_do_cur_byte = tx_do_mem[tx_do_idx][23:16];
        2'd3: tx_do_cur_byte = tx_do_mem[tx_do_idx][31:24];
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_state     <= TX_IDLE;
        tx_busy      <= 0;
        tx_done      <= 0;
        phy_tx_valid <= 0;
        phy_tx_data  <= 0;
        phy_tx_sop   <= 0;
        phy_tx_eop   <= 0;
        tx_header    <= 0;
        tx_byte_idx  <= 0;
        tx_do_idx    <= 0;
        tx_do_byte   <= 0;
        tx_num_do_r  <= 0;
    end else begin
        tx_done <= 0;

        case (tx_state)
        TX_IDLE: begin
            phy_tx_valid <= 0;
            phy_tx_sop   <= 0;
            phy_tx_eop   <= 0;

            if (tx_start) begin
                tx_busy <= 1;
                // Build header
                tx_header <= {tx_extended, tx_num_do, tx_msg_id,
                              port_power_role, spec_revision,
                              port_data_role, tx_msg_type};
                tx_num_do_r <= tx_num_do;
                // Register data objects
                tx_do_mem[0] <= tx_do0;
                tx_do_mem[1] <= tx_do1;
                tx_do_mem[2] <= tx_do2;
                tx_do_mem[3] <= tx_do3;
                tx_do_mem[4] <= tx_do4;
                tx_do_mem[5] <= tx_do5;
                tx_do_mem[6] <= tx_do6;
                tx_byte_idx  <= 0;
                tx_do_idx    <= 0;
                tx_do_byte   <= 0;
                tx_state     <= TX_HDR_LO;
            end else begin
                tx_busy <= 0;
            end
        end

        // Send Header byte 0 (low byte, with SOP)
        TX_HDR_LO: begin
            phy_tx_valid <= 1;
            phy_tx_data  <= tx_header[7:0];
            phy_tx_sop   <= 1;
            // EOP if this is a 0-DO message? No — header is always 2 bytes minimum.
            phy_tx_eop   <= 0;

            if (phy_tx_ready) begin
                tx_byte_idx <= 5'd1;
                tx_state    <= TX_HDR_HI;
            end
        end

        // Send Header byte 1 (high byte)
        TX_HDR_HI: begin
            phy_tx_valid <= 1;
            phy_tx_data  <= tx_header[15:8];
            phy_tx_sop   <= 0;
            phy_tx_eop   <= (tx_num_do_r == 3'd0); // EOP if no data objects

            if (phy_tx_ready) begin
                if (tx_num_do_r == 3'd0) begin
                    // Control message (no DOs) — done
                    tx_state     <= TX_WAIT_DONE;
                    phy_tx_valid <= 0;
                    phy_tx_eop   <= 0;
                end else begin
                    tx_byte_idx <= 5'd2;
                    tx_do_idx   <= 0;
                    tx_do_byte  <= 0;
                    tx_state    <= TX_DO_BYTE;
                end
            end
        end

        // Send Data Object bytes
        TX_DO_BYTE: begin
            phy_tx_valid <= 1;
            phy_tx_data  <= tx_do_cur_byte;
            phy_tx_sop   <= 0;
            phy_tx_eop   <= tx_last_byte;

            if (phy_tx_ready) begin
                tx_byte_idx <= tx_byte_idx + 5'd1;

                if (tx_last_byte) begin
                    tx_state     <= TX_WAIT_DONE;
                    phy_tx_valid <= 0;
                    phy_tx_eop   <= 0;
                end else begin
                    // Advance DO byte counter
                    if (tx_do_byte == 2'd3) begin
                        tx_do_byte <= 0;
                        tx_do_idx  <= tx_do_idx + 3'd1;
                    end else begin
                        tx_do_byte <= tx_do_byte + 2'd1;
                    end
                end
            end
        end

        TX_WAIT_DONE: begin
            phy_tx_valid <= 0;
            phy_tx_sop   <= 0;
            phy_tx_eop   <= 0;
            tx_done      <= 1;
            tx_busy      <= 0;
            tx_state     <= TX_IDLE;
        end

        default: tx_state <= TX_IDLE;
        endcase
    end
end

// =============================================================================
// RX Parser
// =============================================================================
// Receives bytes from BMC PHY, assembles header and data objects.
// rx_sop marks the first byte. rx_eop marks the last byte (after CRC check).

localparam [1:0] RX_IDLE   = 2'd0,
                 RX_HDR_LO = 2'd1,
                 RX_HDR_HI = 2'd2,
                 RX_DO     = 2'd3;

reg [1:0]  rx_state;
reg [15:0] rx_header;
reg [2:0]  rx_do_idx;
reg [1:0]  rx_do_byte;
reg [2:0]  rx_expected_do;
reg [4:0]  rx_byte_cnt;  // total bytes received (for error checking)
reg [31:0] rx_do_accum;  // accumulator for current DO being assembled

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_state     <= RX_IDLE;
        rx_msg_valid <= 0;
        rx_error     <= 0;
        rx_header    <= 0;
        rx_msg_type  <= 0;
        rx_num_do    <= 0;
        rx_msg_id    <= 0;
        rx_port_power_role <= 0;
        rx_spec_revision   <= 0;
        rx_port_data_role  <= 0;
        rx_extended  <= 0;
        rx_do0       <= 0;
        rx_do1       <= 0;
        rx_do2       <= 0;
        rx_do3       <= 0;
        rx_do4       <= 0;
        rx_do5       <= 0;
        rx_do6       <= 0;
        rx_do_idx    <= 0;
        rx_do_byte   <= 0;
        rx_expected_do <= 0;
        rx_byte_cnt  <= 0;
        rx_do_accum  <= 0;
    end else begin
        rx_msg_valid <= 0;
        rx_error     <= 0;

        case (rx_state)
        RX_IDLE: begin
            rx_byte_cnt <= 0;
            rx_do_idx   <= 0;
            rx_do_byte  <= 0;
            rx_do_accum <= 0;

            // SOP from PHY starts a new message
            if (phy_rx_sop) begin
                rx_state <= RX_HDR_LO;
                // If first byte arrives with SOP, capture it immediately
                if (phy_rx_valid) begin
                    rx_header[7:0] <= phy_rx_data;
                    rx_byte_cnt    <= 5'd1;
                    rx_state       <= RX_HDR_HI;
                end
            end
        end

        RX_HDR_LO: begin
            // Waiting for first byte (if SOP didn't come with data)
            if (phy_rx_valid) begin
                rx_header[7:0] <= phy_rx_data;
                rx_byte_cnt    <= 5'd1;
                rx_state       <= RX_HDR_HI;
            end
            if (phy_rx_eop) begin
                rx_error <= 1; // Premature EOP
                rx_state <= RX_IDLE;
            end
        end

        RX_HDR_HI: begin
            if (phy_rx_valid) begin
                rx_header[15:8] <= phy_rx_data;
                rx_byte_cnt     <= 5'd2;

                // Parse header fields (byte 0 in rx_header[7:0], byte 1 is phy_rx_data)
                rx_msg_type        <= rx_header[4:0];
                rx_port_data_role  <= rx_header[5];
                rx_spec_revision   <= rx_header[7:6];
                rx_port_power_role <= phy_rx_data[0];    // bit 8
                rx_msg_id          <= phy_rx_data[3:1];  // bits [11:9]
                rx_num_do          <= phy_rx_data[6:4];  // bits [14:12]
                rx_extended        <= phy_rx_data[7];     // bit 15
                rx_expected_do     <= phy_rx_data[6:4];  // save for byte count validation

                if (phy_rx_data[6:4] == 3'd0) begin
                    // Control message — no data objects expected
                    // Wait for EOP
                    if (phy_rx_eop) begin
                        rx_msg_valid <= phy_rx_crc_ok;
                        rx_error     <= ~phy_rx_crc_ok;
                        rx_state     <= RX_IDLE;
                    end else begin
                        // EOP should come from PHY on the same or next cycle
                        // Stay here briefly — but actually EOP might not come
                        // with this byte. We need a state to wait for EOP.
                        rx_state <= RX_DO; // will handle EOP in RX_DO
                    end
                end else begin
                    rx_do_idx   <= 0;
                    rx_do_byte  <= 0;
                    rx_do_accum <= 0;
                    rx_state    <= RX_DO;
                end
            end
            if (phy_rx_eop && !phy_rx_valid) begin
                rx_error <= 1;
                rx_state <= RX_IDLE;
            end
        end

        RX_DO: begin
            if (phy_rx_valid) begin
                rx_byte_cnt <= rx_byte_cnt + 5'd1;

                // Accumulate DO bytes (Little Endian)
                case (rx_do_byte)
                    2'd0: rx_do_accum[7:0]   <= phy_rx_data;
                    2'd1: rx_do_accum[15:8]  <= phy_rx_data;
                    2'd2: rx_do_accum[23:16] <= phy_rx_data;
                    2'd3: begin
                        // Complete DO assembled
                        case (rx_do_idx)
                            3'd0: rx_do0 <= {phy_rx_data, rx_do_accum[23:0]};
                            3'd1: rx_do1 <= {phy_rx_data, rx_do_accum[23:0]};
                            3'd2: rx_do2 <= {phy_rx_data, rx_do_accum[23:0]};
                            3'd3: rx_do3 <= {phy_rx_data, rx_do_accum[23:0]};
                            3'd4: rx_do4 <= {phy_rx_data, rx_do_accum[23:0]};
                            3'd5: rx_do5 <= {phy_rx_data, rx_do_accum[23:0]};
                            3'd6: rx_do6 <= {phy_rx_data, rx_do_accum[23:0]};
                            default: ; // Max 7 DOs — ignore overflow
                        endcase
                        rx_do_idx  <= rx_do_idx + 3'd1;
                        rx_do_accum <= 0;
                    end
                endcase

                if (rx_do_byte == 2'd3)
                    rx_do_byte <= 0;
                else
                    rx_do_byte <= rx_do_byte + 2'd1;
            end

            // EOP handling (can coincide with rx_valid or come separately)
            if (phy_rx_eop) begin
                // Byte count validation: expected = 2 (header) + expected_do * 4
                // If rx_valid is also high this cycle, the byte_cnt NBA hasn't taken
                // effect yet, so add 1 to get the final count.
                if (phy_rx_crc_ok &&
                    ((phy_rx_valid ? rx_byte_cnt + 5'd1 : rx_byte_cnt) ==
                     (5'd2 + {2'b0, rx_expected_do} * 5'd4))) begin
                    rx_msg_valid <= 1;
                    rx_error     <= 0;
                end else begin
                    rx_msg_valid <= 0;
                    rx_error     <= 1;
                end
                rx_state <= RX_IDLE;
            end
        end

        default: rx_state <= RX_IDLE;
        endcase
    end
end

endmodule
