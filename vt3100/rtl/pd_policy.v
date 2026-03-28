// =============================================================================
// VT3100 PD Source Policy Engine — USB PD Source Negotiation State Machine
// =============================================================================
// Implements the core USB PD Source policy engine for power delivery negotiation.
//
// Happy path: IDLE → STARTUP → SEND_CAPS → WAIT_GOODCRC → WAIT_REQUEST →
//             EVALUATE → SEND_ACCEPT → TRANSITION → SEND_PS_RDY → CONTRACT
//
// Interfaces:
//   - pd_msg: TX builder (send Source_Cap, Accept, PS_RDY) + RX parser (receive Request)
//   - cc_logic: attach/detach events, orientation
//   - Register file: PDO configuration, voltage/current settings
//   - Power stage: VBUS voltage control, ADC readback
//
// USB PD Message Types (Control):
//   0x01 = GoodCRC        0x03 = Accept        0x04 = Reject
//   0x06 = PS_RDY         0x0D = Soft_Reset
// USB PD Message Types (Data, with DOs):
//   0x01 = Source_Capabilities   0x02 = Request
//
// Timers (12 MHz clock):
//   tFirstSourceCap  = 150ms (100-350ms)
//   tSenderResponse  = 27ms  (24-30ms)
//   tTypeCSendSourceCap = 150ms (100-200ms)
//   tNoResponse      = 5.5s
//   tPSTransition    = 550ms
//   tReceive         = 1.1ms (GoodCRC timeout)
//
// Clocking: clk = 12 MHz system clock
// =============================================================================

module pd_policy (
    input  wire        clk,
    input  wire        rst_n,

    // =========================================================================
    // CC Logic interface
    // =========================================================================
    input  wire        cc_attached,      // From cc_logic: device attached
    input  wire        cc_attach_event,  // Pulse: new attachment
    input  wire        cc_detach_event,  // Pulse: detachment

    // =========================================================================
    // pd_msg TX interface (to message builder)
    // =========================================================================
    output reg         msg_tx_start,
    output reg  [4:0]  msg_tx_msg_type,
    output reg  [2:0]  msg_tx_num_do,
    output reg         msg_tx_extended,
    output reg  [31:0] msg_tx_do0,
    output reg  [31:0] msg_tx_do1,
    output reg  [31:0] msg_tx_do2,
    output reg  [31:0] msg_tx_do3,
    input  wire        msg_tx_busy,
    input  wire        msg_tx_done,

    // MessageID control (directly wired to pd_msg)
    output reg         msg_id_inc,
    output reg         msg_id_rst,

    // =========================================================================
    // pd_msg RX interface (from message parser)
    // =========================================================================
    input  wire        msg_rx_valid,     // Pulse: valid message received (CRC ok + ID matched)
    input  wire [4:0]  msg_rx_msg_type,
    input  wire [2:0]  msg_rx_num_do,
    input  wire [31:0] msg_rx_do0,       // Request DO

    // GoodCRC received indication (from auto-GoodCRC module)
    input  wire        goodcrc_received,

    // =========================================================================
    // PDO configuration (from register file)
    // =========================================================================
    input  wire [31:0] pdo0,             // Fixed 5V (mandatory)
    input  wire [31:0] pdo1,             // Fixed PDO 2 (0 = disabled)
    input  wire [31:0] pdo2,             // Fixed PDO 3
    input  wire [31:0] pdo3,             // Fixed PDO 4
    input  wire [2:0]  num_pdos,         // Number of valid PDOs (1-4, clamped internally)

    // =========================================================================
    // Power stage control
    // =========================================================================
    output reg         vbus_en,          // Enable VBUS output
    output reg  [7:0]  vbus_voltage,     // Target voltage (100mV units)
    output reg  [9:0]  vbus_current,     // Max current (10mA units, matches PD spec directly)
    input  wire        vbus_stable,      // VBUS reached target (from ADC comparator)

    // =========================================================================
    // Status outputs
    // =========================================================================
    output reg         pd_contract,      // STATUS_0[5]: PD contract established
    output reg         vbus_present,     // STATUS_0[4]: VBUS active
    output reg [3:0]   protocol_id,      // STATUS_0[3:0]: active protocol
    output reg         pd_timeout_flag,  // STATUS_1[3]: PD timeout
    output reg         int_out,        // Interrupt output (any status change)

    // Debug
    output wire [3:0]  state_out
);

// =============================================================================
// Timer Constants (12 MHz)
// =============================================================================
// Timer values in cycles (12 MHz clock)
localparam [23:0] T_FIRST_SRC_CAP     = 24'd1_800_000;   // 150ms
localparam [23:0] T_SENDER_RESPONSE   = 24'd324_000;     // 27ms
localparam [23:0] T_PS_TRANSITION     = 24'd6_600_000;   // 550ms
localparam [23:0] T_RECEIVE           = 24'd13_200;      // 1.1ms (GoodCRC timeout)
localparam [23:0] T_VBUS_ON           = 24'd3_300_000;   // 275ms (tVBUSon)

// Retry limits
localparam [1:0] N_RETRY_COUNT = 2'd2;
localparam [5:0] N_CAPS_COUNT  = 6'd50;

// PD Message Types
localparam [4:0] MSG_ACCEPT     = 5'h03;
localparam [4:0] MSG_REJECT     = 5'h04;
localparam [4:0] MSG_PS_RDY     = 5'h06;
localparam [4:0] MSG_SRC_CAP    = 5'h01;  // Data message (num_do > 0)
localparam [4:0] MSG_REQUEST    = 5'h02;

// Protocol IDs
localparam [3:0] PROTO_NONE     = 4'd0;
localparam [3:0] PROTO_PD_FIXED = 4'd1;
localparam [3:0] PROTO_PD_PPS   = 4'd2;

// =============================================================================
// State Machine
// =============================================================================
localparam [3:0] ST_IDLE          = 4'd0,
                 ST_STARTUP       = 4'd1,   // Wait for VBUS stable at 5V
                 ST_SEND_CAPS     = 4'd2,   // Send Source_Capabilities
                 ST_WAIT_GOODCRC  = 4'd3,   // Wait for GoodCRC response
                 ST_WAIT_REQUEST  = 4'd4,   // Wait for Request from sink
                 ST_EVALUATE      = 4'd5,   // Evaluate Request DO
                 ST_SEND_ACCEPT   = 4'd6,   // Send Accept
                 ST_WAIT_ACCEPT_GC = 4'd7,  // Wait for GoodCRC on Accept
                 ST_TRANSITION    = 4'd8,   // Transition power supply
                 ST_SEND_PS_RDY   = 4'd9,   // Send PS_RDY
                 ST_WAIT_RDY_GC   = 4'd10,  // Wait for GoodCRC on PS_RDY
                 ST_CONTRACT      = 4'd11,  // PD contract established
                 ST_SEND_REJECT   = 4'd12,  // Send Reject
                 ST_WAIT_REJECT_GC = 4'd13, // Wait for GoodCRC on Reject
                 ST_DISCONNECT    = 4'd14;  // Disconnect recovery

reg [3:0]  state;
assign state_out = state;

// Timer
reg [23:0] timer;
reg        timer_en;

// Retry and caps counters
reg [1:0]  retry_cnt;
reg [5:0]  caps_cnt;

// Negotiation state
reg [2:0]  req_obj_pos;     // Requested PDO Object Position (1-based)
reg [9:0]  req_current;     // Requested operating current (10mA units)
reg [31:0] active_pdo;      // The PDO that was accepted

// =============================================================================
// PDO Selection Helper
// =============================================================================
// Clamp num_pdos to max 4 (v1: only 4 Fixed PDO inputs)
wire [2:0] num_pdos_clamped = (num_pdos > 3'd4) ? 3'd4 : num_pdos;

// Select PDO by index (0-based)
reg [31:0] selected_pdo;
always @(*) begin
    case (req_obj_pos - 3'd1) // Object Position is 1-based
        3'd0: selected_pdo = pdo0;
        3'd1: selected_pdo = pdo1;
        3'd2: selected_pdo = pdo2;
        3'd3: selected_pdo = pdo3;
        default: selected_pdo = 32'd0;
    endcase
end

// Extract max current from Fixed PDO (bits [9:0], in 10mA units)
wire [9:0] pdo_max_current = selected_pdo[9:0];
// Extract voltage from Fixed PDO (bits [19:10], in 50mV units)
wire [9:0] pdo_voltage = selected_pdo[19:10];

// =============================================================================
// Request Validation
// =============================================================================
// Request DO format (Fixed):
//   [30:28] = Object Position (1-7)
//   [9:0]   = Operating Current (10mA units)
wire req_valid = (req_obj_pos >= 3'd1) &&
                 (req_obj_pos <= num_pdos_clamped) &&
                 (req_current <= pdo_max_current);

// =============================================================================
// Main State Machine
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= ST_IDLE;
        timer          <= 0;
        timer_en       <= 0;
        retry_cnt      <= 0;
        caps_cnt       <= 0;
        req_obj_pos    <= 0;
        req_current    <= 0;
        active_pdo     <= 0;
        msg_tx_start   <= 0;
        msg_tx_msg_type <= 0;
        msg_tx_num_do  <= 0;
        msg_tx_extended <= 0;
        msg_tx_do0     <= 0;
        msg_tx_do1     <= 0;
        msg_tx_do2     <= 0;
        msg_tx_do3     <= 0;
        msg_id_inc     <= 0;
        msg_id_rst     <= 0;
        vbus_en        <= 0;
        vbus_voltage   <= 8'd50;  // 5.0V default (100mV units)
        vbus_current   <= 0;
        pd_contract    <= 0;
        vbus_present   <= 0;
        protocol_id    <= PROTO_NONE;
        pd_timeout_flag <= 0;
        int_out      <= 0;
    end else begin
        // Default: clear pulse outputs
        msg_tx_start <= 0;
        msg_id_inc   <= 0;
        msg_id_rst   <= 0;
        int_out    <= 0;

        // Timer
        if (timer_en)
            timer <= timer + 24'd1;

        // Global: detach overrides everything
        if (cc_detach_event && state != ST_IDLE && state != ST_DISCONNECT) begin
            state <= ST_DISCONNECT;
            timer <= 0;
            timer_en <= 1;
        end else begin

        case (state)
        // ---------------------------------------------------------------
        // IDLE: Wait for CC attachment
        // ---------------------------------------------------------------
        ST_IDLE: begin
            vbus_en     <= 0;
            vbus_present <= 0;
            pd_contract <= 0;
            protocol_id <= PROTO_NONE;
            timer_en    <= 0;
            timer       <= 0;
            caps_cnt    <= 0;
            retry_cnt   <= 0;

            if (cc_attach_event) begin
                state <= ST_STARTUP;
                // Enable VBUS at 5V
                vbus_en      <= 1;
                vbus_voltage <= 8'd50; // 5.0V
                timer        <= 0;
                timer_en     <= 1;
                // Reset MessageID on new connection
                msg_id_rst   <= 1;
            end
        end

        // ---------------------------------------------------------------
        // STARTUP: Wait for VBUS to reach vSafe5V
        // ---------------------------------------------------------------
        ST_STARTUP: begin
            if (vbus_stable) begin
                vbus_present <= 1;
                // Start tFirstSourceCap timer
                timer    <= 0;
                timer_en <= 1;
                state    <= ST_SEND_CAPS;
                caps_cnt <= 0;
            end else if (timer >= T_VBUS_ON) begin
                // VBUS didn't reach 5V in time — fault
                state <= ST_DISCONNECT;
                timer <= 0;
            end
        end

        // ---------------------------------------------------------------
        // SEND_CAPS: Wait tFirstSourceCap then send Source_Capabilities
        // ---------------------------------------------------------------
        ST_SEND_CAPS: begin
            if (timer >= T_FIRST_SRC_CAP && !msg_tx_busy) begin
                // Send Source_Capabilities
                msg_tx_start    <= 1;
                msg_tx_msg_type <= MSG_SRC_CAP;
                msg_tx_num_do   <= num_pdos_clamped;
                msg_tx_extended <= 0;
                msg_tx_do0      <= pdo0;
                msg_tx_do1      <= pdo1;
                msg_tx_do2      <= pdo2;
                msg_tx_do3      <= pdo3;

                retry_cnt <= 0;
                state     <= ST_WAIT_GOODCRC;
                timer     <= 0;
                timer_en  <= 1;
            end
        end

        // ---------------------------------------------------------------
        // WAIT_GOODCRC: Wait for GoodCRC response to our Source_Caps
        // ---------------------------------------------------------------
        ST_WAIT_GOODCRC: begin
            if (goodcrc_received) begin
                // GoodCRC received — increment MessageID, wait for Request
                msg_id_inc <= 1;
                state      <= ST_WAIT_REQUEST;
                timer      <= 0;
                timer_en   <= 1;
                caps_cnt   <= caps_cnt + 6'd1;
            end else if (timer >= T_RECEIVE) begin
                // GoodCRC timeout — retry
                if (retry_cnt < N_RETRY_COUNT) begin
                    retry_cnt <= retry_cnt + 2'd1;
                    // Resend Source_Capabilities
                    msg_tx_start    <= 1;
                    msg_tx_msg_type <= MSG_SRC_CAP;
                    msg_tx_num_do   <= num_pdos_clamped;
                    msg_tx_extended <= 0;
                    msg_tx_do0      <= pdo0;
                    msg_tx_do1      <= pdo1;
                    msg_tx_do2      <= pdo2;
                    msg_tx_do3      <= pdo3;
                    timer    <= 0;
                    timer_en <= 1;
                end else begin
                    // All retries exhausted for this caps round
                    if (caps_cnt < N_CAPS_COUNT) begin
                        // Wait tTypeCSendSourceCap then resend
                        state    <= ST_SEND_CAPS;
                        timer    <= 0;
                        timer_en <= 1;
                    end else begin
                        // nCapsCount exhausted — no PD sink, go to legacy
                        pd_timeout_flag <= 1;
                        int_out       <= 1;
                        state           <= ST_IDLE; // Simplified: go idle (legacy detect TBD)
                        timer_en        <= 0;
                    end
                end
            end
        end

        // ---------------------------------------------------------------
        // WAIT_REQUEST: Wait for Request message from sink
        // ---------------------------------------------------------------
        ST_WAIT_REQUEST: begin
            if (msg_rx_valid && msg_rx_msg_type == MSG_REQUEST && msg_rx_num_do == 3'd1) begin
                // Valid Request received — extract fields
                req_obj_pos <= msg_rx_do0[30:28];
                req_current <= msg_rx_do0[9:0];
                state       <= ST_EVALUATE;
            end else if (timer >= T_SENDER_RESPONSE) begin
                // No Request within tSenderResponse — resend caps
                state    <= ST_SEND_CAPS;
                timer    <= 0;
                timer_en <= 1;
            end
        end

        // ---------------------------------------------------------------
        // EVALUATE: Check if Request is valid
        // ---------------------------------------------------------------
        ST_EVALUATE: begin
            if (req_valid) begin
                active_pdo <= selected_pdo;
                state      <= ST_SEND_ACCEPT;
            end else begin
                state <= ST_SEND_REJECT;
            end
        end

        // ---------------------------------------------------------------
        // SEND_ACCEPT: Send Accept control message
        // ---------------------------------------------------------------
        ST_SEND_ACCEPT: begin
            if (!msg_tx_busy) begin
                msg_tx_start    <= 1;
                msg_tx_msg_type <= MSG_ACCEPT;
                msg_tx_num_do   <= 0;
                msg_tx_extended <= 0;
                state           <= ST_WAIT_ACCEPT_GC;
                timer           <= 0;
                timer_en        <= 1;
            end
        end

        // ---------------------------------------------------------------
        // WAIT_ACCEPT_GC: Wait for GoodCRC on Accept
        // ---------------------------------------------------------------
        ST_WAIT_ACCEPT_GC: begin
            if (goodcrc_received) begin
                msg_id_inc <= 1;
                // Start power transition
                // pdo_voltage in 50mV units (e.g. 100=5V), vbus_voltage in 100mV units (e.g. 50=5V)
                // Conversion: divide by 2
                vbus_voltage <= pdo_voltage[8:1];
                vbus_current <= req_current; // 10mA units, passed directly to power stage
                state    <= ST_TRANSITION;
                timer    <= 0;
                timer_en <= 1;
            end else if (timer >= T_RECEIVE) begin
                // GoodCRC timeout on Accept — protocol error, simplified: disconnect
                state <= ST_DISCONNECT;
                timer <= 0;
            end
        end

        // ---------------------------------------------------------------
        // TRANSITION: Wait for power supply to reach target voltage
        // ---------------------------------------------------------------
        ST_TRANSITION: begin
            if (vbus_stable) begin
                // Voltage reached — send PS_RDY
                state <= ST_SEND_PS_RDY;
            end else if (timer >= T_PS_TRANSITION) begin
                // Transition timeout — fault
                state <= ST_DISCONNECT;
                timer <= 0;
            end
        end

        // ---------------------------------------------------------------
        // SEND_PS_RDY: Send PS_RDY control message
        // ---------------------------------------------------------------
        ST_SEND_PS_RDY: begin
            if (!msg_tx_busy) begin
                msg_tx_start    <= 1;
                msg_tx_msg_type <= MSG_PS_RDY;
                msg_tx_num_do   <= 0;
                msg_tx_extended <= 0;
                state           <= ST_WAIT_RDY_GC;
                timer           <= 0;
                timer_en        <= 1;
            end
        end

        // ---------------------------------------------------------------
        // WAIT_RDY_GC: Wait for GoodCRC on PS_RDY
        // ---------------------------------------------------------------
        ST_WAIT_RDY_GC: begin
            if (goodcrc_received) begin
                msg_id_inc  <= 1;
                pd_contract <= 1;
                protocol_id <= (active_pdo[31:30] == 2'b11) ? PROTO_PD_PPS : PROTO_PD_FIXED;
                int_out   <= 1;
                state       <= ST_CONTRACT;
                timer_en    <= 0;
            end else if (timer >= T_RECEIVE) begin
                state <= ST_DISCONNECT;
                timer <= 0;
            end
        end

        // ---------------------------------------------------------------
        // CONTRACT: PD contract established — steady state
        // ---------------------------------------------------------------
        ST_CONTRACT: begin
            // Monitor for re-negotiation (new Request)
            if (msg_rx_valid && msg_rx_msg_type == MSG_REQUEST && msg_rx_num_do == 3'd1) begin
                req_obj_pos <= msg_rx_do0[30:28];
                req_current <= msg_rx_do0[9:0];
                state       <= ST_EVALUATE;
            end
            // (Future: handle Get_Source_Cap, Soft_Reset, PPS timeout, etc.)
        end

        // ---------------------------------------------------------------
        // SEND_REJECT: Send Reject, then wait for GoodCRC
        // ---------------------------------------------------------------
        ST_SEND_REJECT: begin
            if (!msg_tx_busy) begin
                msg_tx_start    <= 1;
                msg_tx_msg_type <= MSG_REJECT;
                msg_tx_num_do   <= 0;
                msg_tx_extended <= 0;
                state    <= ST_WAIT_REJECT_GC;
                timer    <= 0;
                timer_en <= 1;
            end
        end

        // ---------------------------------------------------------------
        // WAIT_REJECT_GC: Wait for GoodCRC on Reject, then resend caps
        // ---------------------------------------------------------------
        ST_WAIT_REJECT_GC: begin
            if (goodcrc_received) begin
                msg_id_inc <= 1;
                state      <= ST_SEND_CAPS;
                timer      <= 0;
                timer_en   <= 1;
            end else if (timer >= T_RECEIVE) begin
                // GoodCRC timeout on Reject — protocol error, disconnect
                state <= ST_DISCONNECT;
                timer <= 0;
            end
        end

        // ---------------------------------------------------------------
        // DISCONNECT: Recovery — disable VBUS and return to IDLE
        // ---------------------------------------------------------------
        ST_DISCONNECT: begin
            vbus_en      <= 0;
            vbus_present <= 0;
            pd_contract  <= 0;
            protocol_id  <= PROTO_NONE;

            // Wait for VBUS discharge (simplified: wait 650ms)
            if (timer >= 24'd7_800_000) begin // 650ms
                state    <= ST_IDLE;
                timer_en <= 0;
            end
        end

        default: state <= ST_IDLE;
        endcase

        end // if not detach
    end
end

endmodule
