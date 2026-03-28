// =============================================================================
// VT3100 BMC PHY — Biphase Mark Coding Encoder/Decoder
// =============================================================================
// USB PD Physical Layer for CC-line communication.
//
// Features:
//   - BMC transmitter (data -> BMC-encoded signal on CC)
//   - BMC receiver   (BMC signal -> data, with clock recovery)
//   - 4b5b encoding / decoding
//   - CRC-32 generation and checking (USB PD polynomial)
//   - Preamble generation (TX) and detection (RX)
//   - SOP ordered-set detection (sliding-window)
//
// Clocking:
//   clk = 12 MHz system clock
//   BMC bit rate = 300 kHz => 40 clk cycles per bit period
//   Half-bit = 20 clk cycles
// =============================================================================

module bmc_phy (
    input  wire        clk,
    input  wire        rst_n,

    // Transmit
    input  wire        tx_valid,
    input  wire [7:0]  tx_data,
    input  wire        tx_sop,
    input  wire        tx_eop,
    output reg         tx_ready,
    output reg         tx_active,
    output reg         cc_tx_out,

    // Receive
    input  wire        cc_rx_in,
    output reg  [7:0]  rx_data,
    output reg         rx_valid,
    output reg         rx_sop,
    output reg         rx_eop,
    output reg         rx_crc_ok,
    output reg         rx_error,

    // CRC standalone
    input  wire        crc_init,
    input  wire        crc_en,
    input  wire [7:0]  crc_din,
    output wire [31:0] crc_out
);

// =============================================================================
// Parameters
// =============================================================================
localparam HALF_BIT = 20;
localparam FULL_BIT = 40;

localparam [4:0] K_SYNC1 = 5'b11000;
localparam [4:0] K_SYNC2 = 5'b10001;
localparam [4:0] K_EOP   = 5'b01101;

localparam PREAMBLE_BITS = 64;

localparam [31:0] CRC_POLY     = 32'h04C1_1DB7;
localparam [31:0] CRC_INIT_VAL = 32'hFFFF_FFFF;
localparam [31:0] CRC_RESIDUAL = 32'hC704_DD7B;

// =============================================================================
// 4b5b Tables
// =============================================================================
function [4:0] encode_4b5b;
    input [3:0] nib;
    case (nib)
        4'h0: encode_4b5b = 5'b11110;
        4'h1: encode_4b5b = 5'b01001;
        4'h2: encode_4b5b = 5'b10100;
        4'h3: encode_4b5b = 5'b10101;
        4'h4: encode_4b5b = 5'b01010;
        4'h5: encode_4b5b = 5'b01011;
        4'h6: encode_4b5b = 5'b01110;
        4'h7: encode_4b5b = 5'b01111;
        4'h8: encode_4b5b = 5'b10010;
        4'h9: encode_4b5b = 5'b10011;
        4'hA: encode_4b5b = 5'b10110;
        4'hB: encode_4b5b = 5'b10111;
        4'hC: encode_4b5b = 5'b11010;
        4'hD: encode_4b5b = 5'b11011;
        4'hE: encode_4b5b = 5'b11100;
        4'hF: encode_4b5b = 5'b11101;
    endcase
endfunction

function [3:0] decode_4b5b;
    input [4:0] sym;
    case (sym)
        5'b11110: decode_4b5b = 4'h0;
        5'b01001: decode_4b5b = 4'h1;
        5'b10100: decode_4b5b = 4'h2;
        5'b10101: decode_4b5b = 4'h3;
        5'b01010: decode_4b5b = 4'h4;
        5'b01011: decode_4b5b = 4'h5;
        5'b01110: decode_4b5b = 4'h6;
        5'b01111: decode_4b5b = 4'h7;
        5'b10010: decode_4b5b = 4'h8;
        5'b10011: decode_4b5b = 4'h9;
        5'b10110: decode_4b5b = 4'hA;
        5'b10111: decode_4b5b = 4'hB;
        5'b11010: decode_4b5b = 4'hC;
        5'b11011: decode_4b5b = 4'hD;
        5'b11100: decode_4b5b = 4'hE;
        5'b11101: decode_4b5b = 4'hF;
        default:  decode_4b5b = 4'h0;
    endcase
endfunction

function is_kcode;
    input [4:0] sym;
    case (sym)
        K_SYNC1, K_SYNC2, K_EOP: is_kcode = 1'b1;
        default: is_kcode = 1'b0;
    endcase
endfunction

// =============================================================================
// CRC-32 Engine
// =============================================================================
// Standalone CRC register (external crc_init/crc_en/crc_din port)
reg [31:0] crc_reg;
// TX-private CRC register — isolated from RX and standalone to prevent corruption
reg [31:0] tx_crc_reg;

function [31:0] crc32_byte;
    input [31:0] crc_prev;
    input [7:0]  data;
    integer i;
    reg [31:0] c;
    reg        fb;
    begin
        c = crc_prev;
        for (i = 0; i < 8; i = i + 1) begin
            fb = c[31] ^ data[i];
            c = {c[30:0], 1'b0} ^ (fb ? CRC_POLY : 32'd0);
        end
        crc32_byte = c;
    end
endfunction

reg        tx_crc_en;
reg [7:0]  tx_crc_data;

// Standalone CRC register — only driven by external port
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        crc_reg <= CRC_INIT_VAL;
    else if (crc_init)
        crc_reg <= CRC_INIT_VAL;
    else if (crc_en)
        crc_reg <= crc32_byte(crc_reg, crc_din);
end

// TX CRC register — only driven by TX path
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        tx_crc_reg <= CRC_INIT_VAL;
    else if (tx_state == TX_IDLE)
        tx_crc_reg <= CRC_INIT_VAL;
    else if (tx_crc_en)
        tx_crc_reg <= crc32_byte(tx_crc_reg, tx_crc_data);
end

assign crc_out = crc_reg;

wire [31:0] crc_tx_append;
genvar gi;
generate
    for (gi = 0; gi < 32; gi = gi + 1) begin : bitrev
        assign crc_tx_append[gi] = ~tx_crc_reg[31 - gi];
    end
endgenerate

// =============================================================================
// BMC Transmitter
// =============================================================================
localparam [2:0] TX_IDLE     = 3'd0,
                 TX_PREAMBLE = 3'd1,
                 TX_SOP      = 3'd2,
                 TX_DATA     = 3'd3,
                 TX_CRC      = 3'd4,
                 TX_EOP      = 3'd5;

reg [2:0]  tx_state;
reg [5:0]  tx_timer;
reg        tx_level;
reg        tx_phase;       // 0=first half, 1=second half
reg [6:0]  tx_bit_cnt;
reg [9:0]  tx_sr;
reg [3:0]  tx_sr_bits;
reg        tx_cur_bit;
reg [7:0]  tx_byte_buf;
reg        tx_byte_loaded;
reg        tx_eop_pending;
reg [31:0] tx_crc_snap;
reg [1:0]  tx_crc_idx;
reg [1:0]  tx_sop_idx;

wire tx_half_tick = (tx_timer == HALF_BIT - 1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_state       <= TX_IDLE;
        tx_timer       <= 0;
        tx_level       <= 0;
        tx_phase       <= 0;
        tx_bit_cnt     <= 0;
        tx_sr          <= 0;
        tx_sr_bits     <= 0;
        tx_cur_bit     <= 0;
        tx_byte_buf    <= 0;
        tx_byte_loaded <= 0;
        tx_eop_pending <= 0;
        tx_ready       <= 1;
        tx_active      <= 0;
        cc_tx_out      <= 0;
        tx_crc_snap    <= 0;
        tx_crc_idx     <= 0;
        tx_sop_idx     <= 0;
        tx_crc_en      <= 0;
        tx_crc_data    <= 0;
    end else begin
        tx_crc_en <= 0;

        case (tx_state)
        TX_IDLE: begin
            tx_active  <= 0;
            cc_tx_out  <= 0;
            tx_level   <= 0;
            tx_phase   <= 0;
            tx_timer   <= 0;
            tx_sr_bits <= 0;
            tx_bit_cnt <= 0;
            tx_sop_idx <= 0;
            tx_crc_idx <= 0;

            if (tx_valid) begin
                tx_byte_buf    <= tx_data;
                tx_byte_loaded <= 1;
                tx_eop_pending <= tx_eop;
                tx_ready       <= 0;
                tx_active      <= 1;
                if (tx_sop)
                    tx_state <= TX_PREAMBLE;
                else
                    tx_state <= TX_DATA;
            end else begin
                tx_ready <= 1;
            end
        end

        TX_PREAMBLE: begin
            if (tx_half_tick) begin
                tx_timer <= 0;
                tx_level <= ~tx_level;
                if (tx_phase) begin
                    tx_bit_cnt <= tx_bit_cnt + 1;
                    tx_phase <= 0;
                    if (tx_bit_cnt + 1 >= PREAMBLE_BITS) begin
                        tx_state <= TX_SOP;
                        tx_sop_idx <= 0;
                        tx_sr_bits <= 0;
                    end
                end else begin
                    tx_phase <= 1;
                end
            end else begin
                tx_timer <= tx_timer + 1;
            end
            cc_tx_out <= tx_level;
        end

        TX_SOP: begin
            if (tx_sr_bits == 0) begin
                case (tx_sop_idx)
                    2'd0: tx_sr[4:0] <= K_SYNC1;
                    2'd1: tx_sr[4:0] <= K_SYNC1;
                    2'd2: tx_sr[4:0] <= K_SYNC1;
                    2'd3: tx_sr[4:0] <= K_SYNC2;
                endcase
                tx_sr_bits <= 5;
                tx_phase <= 0;
            end else if (tx_half_tick) begin
                tx_timer <= 0;
                if (!tx_phase) begin
                    tx_level <= ~tx_level;
                    tx_cur_bit <= tx_sr[0];
                    tx_phase <= 1;
                end else begin
                    if (tx_cur_bit)
                        tx_level <= ~tx_level;
                    tx_sr <= {1'b0, tx_sr[9:1]};
                    tx_sr_bits <= tx_sr_bits - 1;
                    tx_phase <= 0;
                    if (tx_sr_bits == 1) begin
                        if (tx_sop_idx == 2'd3) begin
                            tx_state <= TX_DATA;
                            tx_sr_bits <= 0;
                        end else begin
                            tx_sop_idx <= tx_sop_idx + 1;
                            tx_sr_bits <= 0;
                        end
                    end
                end
            end else begin
                tx_timer <= tx_timer + 1;
            end
            cc_tx_out <= tx_level;
        end

        TX_DATA: begin
            if (tx_sr_bits == 0) begin
                if (tx_byte_loaded) begin
                    tx_sr[4:0] <= encode_4b5b(tx_byte_buf[3:0]);
                    tx_sr[9:5] <= encode_4b5b(tx_byte_buf[7:4]);
                    tx_sr_bits <= 10;
                    tx_phase   <= 0;
                    tx_crc_en   <= 1;
                    tx_crc_data <= tx_byte_buf;
                    tx_byte_loaded <= 0;
                    if (!tx_eop_pending)
                        tx_ready <= 1;
                end
            end else if (tx_half_tick) begin
                tx_timer <= 0;
                if (!tx_phase) begin
                    tx_level <= ~tx_level;
                    tx_cur_bit <= tx_sr[0];
                    tx_phase <= 1;
                end else begin
                    if (tx_cur_bit)
                        tx_level <= ~tx_level;
                    tx_sr <= {1'b0, tx_sr[9:1]};
                    tx_sr_bits <= tx_sr_bits - 1;
                    tx_phase <= 0;
                    if (tx_sr_bits == 1 && tx_eop_pending && !tx_byte_loaded) begin
                        tx_crc_snap <= crc_tx_append;
                        tx_crc_idx  <= 0;
                        tx_state    <= TX_CRC;
                        tx_sr_bits  <= 0;
                    end
                end
            end else begin
                tx_timer <= tx_timer + 1;
            end

            if (tx_ready && tx_valid) begin
                tx_byte_buf    <= tx_data;
                tx_byte_loaded <= 1;
                tx_eop_pending <= tx_eop;
                tx_ready       <= 0;
            end

            cc_tx_out <= tx_level;
        end

        TX_CRC: begin
            if (tx_sr_bits == 0) begin
                case (tx_crc_idx)
                    2'd0: begin
                        tx_sr[4:0] <= encode_4b5b(tx_crc_snap[3:0]);
                        tx_sr[9:5] <= encode_4b5b(tx_crc_snap[7:4]);
                    end
                    2'd1: begin
                        tx_sr[4:0] <= encode_4b5b(tx_crc_snap[11:8]);
                        tx_sr[9:5] <= encode_4b5b(tx_crc_snap[15:12]);
                    end
                    2'd2: begin
                        tx_sr[4:0] <= encode_4b5b(tx_crc_snap[19:16]);
                        tx_sr[9:5] <= encode_4b5b(tx_crc_snap[23:20]);
                    end
                    2'd3: begin
                        tx_sr[4:0] <= encode_4b5b(tx_crc_snap[27:24]);
                        tx_sr[9:5] <= encode_4b5b(tx_crc_snap[31:28]);
                    end
                endcase
                tx_sr_bits <= 10;
                tx_phase   <= 0;
            end else if (tx_half_tick) begin
                tx_timer <= 0;
                if (!tx_phase) begin
                    tx_level <= ~tx_level;
                    tx_cur_bit <= tx_sr[0];
                    tx_phase <= 1;
                end else begin
                    if (tx_cur_bit)
                        tx_level <= ~tx_level;
                    tx_sr <= {1'b0, tx_sr[9:1]};
                    tx_sr_bits <= tx_sr_bits - 1;
                    tx_phase <= 0;
                    if (tx_sr_bits == 1) begin
                        if (tx_crc_idx == 2'd3) begin
                            tx_state   <= TX_EOP;
                            tx_sr_bits <= 0;
                        end else begin
                            tx_crc_idx <= tx_crc_idx + 1;
                            tx_sr_bits <= 0;
                        end
                    end
                end
            end else begin
                tx_timer <= tx_timer + 1;
            end
            cc_tx_out <= tx_level;
        end

        TX_EOP: begin
            if (tx_sr_bits == 0) begin
                tx_sr[4:0] <= K_EOP;
                tx_sr_bits <= 5;
                tx_phase   <= 0;
            end else if (tx_half_tick) begin
                tx_timer <= 0;
                if (!tx_phase) begin
                    tx_level <= ~tx_level;
                    tx_cur_bit <= tx_sr[0];
                    tx_phase <= 1;
                end else begin
                    if (tx_cur_bit)
                        tx_level <= ~tx_level;
                    tx_sr <= {1'b0, tx_sr[9:1]};
                    tx_sr_bits <= tx_sr_bits - 1;
                    tx_phase <= 0;
                    if (tx_sr_bits == 1) begin
                        tx_state  <= TX_IDLE;
                        tx_ready  <= 1;
                        tx_active <= 0;
                    end
                end
            end else begin
                tx_timer <= tx_timer + 1;
            end
            cc_tx_out <= tx_level;
        end

        default: tx_state <= TX_IDLE;
        endcase
    end
end

// =============================================================================
// BMC Receiver
// =============================================================================

// 2-stage synchronizer
reg cc_rx_s1, cc_rx_s2, cc_rx_d;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cc_rx_s1 <= 0;
        cc_rx_s2 <= 0;
        cc_rx_d  <= 0;
    end else begin
        cc_rx_s1 <= cc_rx_in;
        cc_rx_s2 <= cc_rx_s1;
        cc_rx_d  <= cc_rx_s2;
    end
end

wire rx_edge = (cc_rx_s2 ^ cc_rx_d);

// Edge timer: counts clk cycles since last edge
reg [6:0] rx_edge_timer;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rx_edge_timer <= 0;
    else if (rx_edge)
        rx_edge_timer <= 0;
    else if (rx_edge_timer < 7'd127)
        rx_edge_timer <= rx_edge_timer + 1;
end

// Classify edge gaps
wire rx_gap_short = (rx_edge_timer >= 7'd14 && rx_edge_timer <= 7'd26);
wire rx_gap_long  = (rx_edge_timer >= 7'd30 && rx_edge_timer <= 7'd54);

// Bit decoder
// rx_got_bit: combinational pulse derived from rx_edge and gap classification
// This way it's available in the same cycle for the state machine below.
reg rx_last_was_mid;
reg rx_got_bit_r;
reg rx_bit_val_r;

// Combinational decode
reg rx_got_bit_comb;
reg rx_bit_val_comb;
reg rx_next_was_mid;

always @(*) begin
    rx_got_bit_comb = 0;
    rx_bit_val_comb = 0;
    rx_next_was_mid = rx_last_was_mid;

    if (rx_edge) begin
        if (rx_gap_long) begin
            rx_got_bit_comb = 1;
            rx_bit_val_comb = 0;
            rx_next_was_mid = 0;
        end else if (rx_gap_short) begin
            if (!rx_last_was_mid) begin
                // Start-of-bit followed by short gap => mid-bit => bit=1
                rx_got_bit_comb = 1;
                rx_bit_val_comb = 1;
                rx_next_was_mid = 1;
            end else begin
                // Mid-bit followed by short gap => start of next bit
                rx_next_was_mid = 0;
            end
        end
    end
end

// Register the mid tracking
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rx_last_was_mid <= 0;
    else if (rx_state_r == RX_IDLE)
        rx_last_was_mid <= 0;
    else if (rx_edge)
        rx_last_was_mid <= rx_next_was_mid;
end

// Register bit output for use in state machine (same cycle via comb)
wire rx_got_bit = rx_got_bit_comb;
wire rx_bit_val = rx_bit_val_comb;

// RX state machine
localparam [2:0] RX_IDLE     = 3'd0,
                 RX_SYNC     = 3'd1,  // preamble + SOP search
                 RX_ACTIVE   = 3'd2;

reg [2:0]  rx_state_r;
reg [6:0]  rx_preamble_cnt;
reg [19:0] rx_sop_sr;       // 20-bit sliding window for SOP detection
reg [4:0]  rx_sym_sr;       // 5-bit symbol accumulator (after SOP)
reg [2:0]  rx_sym_cnt;      // bits collected in current symbol
reg        rx_nibble_idx;   // 0=low, 1=high nibble
reg [3:0]  rx_lo_nibble;
reg [31:0] rx_crc_shadow;
reg [15:0] rx_timeout;

// SOP pattern: Sync-1, Sync-1, Sync-1, Sync-2
// TX sends LSB first, so in the shift register (MSB-in shift) the pattern
// should appear as received bits in order.
// TX sends K_SYNC1 bits as: bit0=0, bit1=0, bit2=0, bit3=1, bit4=1
// RX shifts new bit into MSB: {new, sr[19:1]}
// After receiving Sync1 bits 0,0,0,1,1 -> sr[4:0] = 5'b11000 = K_SYNC1
// Pattern in sr[19:0] after 4 symbols (20 bits):
//   sr[4:0]   = first symbol  (Sync-1 = 11000)
//   sr[9:5]   = second symbol (Sync-1 = 11000)
//   sr[14:10] = third symbol  (Sync-1 = 11000)
//   sr[19:15] = fourth symbol (Sync-2 = 10001)
wire [19:0] SOP_PATTERN = {K_SYNC2, K_SYNC1, K_SYNC1, K_SYNC1};
wire rx_sop_match = (rx_sop_sr == SOP_PATTERN);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_state_r      <= RX_IDLE;
        rx_data         <= 0;
        rx_valid        <= 0;
        rx_sop          <= 0;
        rx_eop          <= 0;
        rx_crc_ok       <= 0;
        rx_error        <= 0;
        rx_preamble_cnt <= 0;
        rx_sop_sr       <= 0;
        rx_sym_sr       <= 0;
        rx_sym_cnt      <= 0;
        rx_nibble_idx   <= 0;
        rx_lo_nibble    <= 0;
        rx_crc_shadow   <= CRC_INIT_VAL;
        rx_timeout      <= 0;
    end else begin
        rx_valid  <= 0;
        rx_sop    <= 0;
        rx_eop    <= 0;
        rx_error  <= 0;
        // Timeout: only reset on valid decoded bit, not on any edge.
        // Dead zone edges (27-29 cycle gaps) would otherwise keep resetting
        // the timeout, permanently locking RX in SYNC/ACTIVE state.
        if (rx_got_bit)
            rx_timeout <= 0;
        else if (rx_state_r != RX_IDLE)
            rx_timeout <= rx_timeout + 1;

        case (rx_state_r)
        RX_IDLE: begin
            rx_preamble_cnt <= 0;
            rx_sop_sr       <= 0;
            rx_sym_sr       <= 0;
            rx_sym_cnt      <= 0;
            rx_nibble_idx   <= 0;
            rx_crc_shadow   <= CRC_INIT_VAL;
            rx_timeout      <= 0;
            if (rx_edge)
                rx_state_r <= RX_SYNC;
        end

        RX_SYNC: begin
            // Combined preamble + SOP detection using sliding window
            if (rx_got_bit) begin
                rx_preamble_cnt <= rx_preamble_cnt + 1;
                rx_sop_sr <= {rx_bit_val, rx_sop_sr[19:1]};

                // Check for SOP match after enough bits
                if (rx_preamble_cnt >= 7'd19) begin
                    if ({rx_bit_val, rx_sop_sr[19:1]} == SOP_PATTERN) begin
                        rx_state_r  <= RX_ACTIVE;
                        rx_sop      <= 1;
                        rx_sym_cnt  <= 0;
                        rx_sym_sr   <= 0;
                        rx_nibble_idx <= 0;
                        rx_crc_shadow <= CRC_INIT_VAL;
                    end
                end
            end
            if (rx_timeout >= 16'd15000)
                rx_state_r <= RX_IDLE;
        end

        RX_ACTIVE: begin
            if (rx_got_bit) begin
                rx_sym_sr  <= {rx_bit_val, rx_sym_sr[4:1]};
                rx_sym_cnt <= rx_sym_cnt + 1;
                if (rx_sym_cnt == 3'd4) begin
                    rx_sym_cnt <= 0;
                    // Complete 5-bit symbol
                    if ({rx_bit_val, rx_sym_sr[4:1]} == K_EOP) begin
                        rx_eop    <= 1;
                        rx_crc_ok <= (rx_crc_shadow == CRC_RESIDUAL);
                        rx_state_r <= RX_IDLE;
                    end else if (is_kcode({rx_bit_val, rx_sym_sr[4:1]})) begin
                        rx_error   <= 1;
                        rx_state_r <= RX_IDLE;
                    end else begin
                        if (!rx_nibble_idx) begin
                            rx_lo_nibble  <= decode_4b5b({rx_bit_val, rx_sym_sr[4:1]});
                            rx_nibble_idx <= 1;
                        end else begin
                            rx_data  <= {decode_4b5b({rx_bit_val, rx_sym_sr[4:1]}), rx_lo_nibble};
                            rx_valid <= 1;
                            rx_nibble_idx <= 0;
                            rx_crc_shadow <= crc32_byte(rx_crc_shadow,
                                {decode_4b5b({rx_bit_val, rx_sym_sr[4:1]}), rx_lo_nibble});
                        end
                    end
                end
            end
            if (rx_timeout >= 16'd15000) begin
                rx_eop     <= 1;
                rx_crc_ok  <= (rx_crc_shadow == CRC_RESIDUAL);
                rx_state_r <= RX_IDLE;
            end
        end

        default: rx_state_r <= RX_IDLE;
        endcase
    end
end

endmodule
