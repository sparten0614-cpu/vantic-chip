// =============================================================================
// VT3100 CC Logic — USB Type-C CC Detection, Orientation & Rp Control
// =============================================================================
// Detects cable attachment on CC1/CC2, determines orientation, manages Rp/Rd/Ra
// pull-up/pull-down resistors, and drives attach/detach state machine.
//
// Interface to analog:
//   - cc1_comp[2:0] / cc2_comp[2:0]: comparator results from analog block
//     Bit 2: voltage < vRa  (Ra detected, ~0.2V)
//     Bit 1: voltage < vRd  (Rd detected, ~0.66V for default, ~1.23V for 1.5A, ~2.6V for 3A)
//     Bit 0: voltage < vOpen (~2.6V — anything above this is open/unconnected)
//     Encoding (after Rp assertion):
//       3'b000 = open (no pull-down detected)
//       3'b001 = open (above vRd, below vOpen — shouldn't normally occur with correct thresholds)
//       3'b011 = Rd detected (sink connected)
//       3'b111 = Ra detected (audio adapter or active cable VCONN)
//
// Clocking: clk = 12 MHz system clock
// =============================================================================

module cc_logic (
    input  wire        clk,
    input  wire        rst_n,

    // Analog comparator inputs (active-high: 1 = threshold crossed)
    input  wire [2:0]  cc1_comp,      // {Ra_det, Rd_det, below_vOpen}
    input  wire [2:0]  cc2_comp,

    // Register interface
    input  wire [1:0]  rp_level,      // from CTRL_1[3:2]: 00=default, 01=1.5A, 10=3.0A
    input  wire [7:0]  debounce_cfg,  // debounce period in ms (default: 150)

    // Status outputs (directly mapped to STATUS_0 bits)
    output reg         attached,      // STATUS_0[7]
    output reg         orientation,   // STATUS_0[6]: 0=CC1 active, 1=CC2 active

    // Control outputs to analog block
    output reg  [1:0]  rp_cc1_level,  // Rp current source level for CC1 (00=off, 01=default, 10=1.5A, 11=3A)
    output reg  [1:0]  rp_cc2_level,  // Rp current source level for CC2
    output reg         vconn_en,      // Enable VCONN on non-active CC pin
    output reg         vconn_cc2,     // 1=VCONN on CC2, 0=VCONN on CC1

    // Event outputs to higher-level logic
    output reg         attach_event,  // Pulse: new attachment detected
    output reg         detach_event,  // Pulse: detachment detected
    output reg         accessory_mode, // 1 = both CC have Rd (audio accessory)

    // Communication CC mux select (for BMC PHY)
    output reg         cc_sel,        // 0=CC1, 1=CC2

    // Debug/status
    output wire [2:0]  state_out
);

// =============================================================================
// Parameters
// =============================================================================
// 12 MHz clock -> 12000 cycles per ms
localparam CYCLES_PER_MS = 16'd12000;

// Debounce counter width: 200ms * 12000 = 2,400,000 -> needs 22 bits (2^21=2,097,152 overflows)
localparam DEBOUNCE_W = 22;

// Detach debounce: tPDDebounce = 10-20ms (shorter than attach debounce)
localparam DETACH_DEBOUNCE_MS = 8'd15;

// =============================================================================
// CC Line Classification
// =============================================================================
// Classify each CC line based on comparator results
localparam [1:0] CC_OPEN = 2'd0,
                 CC_RD   = 2'd1,
                 CC_RA   = 2'd2;

function [1:0] classify_cc;
    input [2:0] comp;
    begin
        if (comp[2])           // Ra threshold crossed -> Ra (audio/VCONN)
            classify_cc = CC_RA;
        else if (comp[1])      // Rd threshold crossed -> Rd (sink)
            classify_cc = CC_RD;
        else
            classify_cc = CC_OPEN;
    end
endfunction

// Synchronized comparator inputs (2-stage sync for async analog signals)
reg [2:0] cc1_s1, cc1_s2;
reg [2:0] cc2_s1, cc2_s2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cc1_s1 <= 3'b0;
        cc1_s2 <= 3'b0;
        cc2_s1 <= 3'b0;
        cc2_s2 <= 3'b0;
    end else begin
        cc1_s1 <= cc1_comp;
        cc1_s2 <= cc1_s1;
        cc2_s1 <= cc2_comp;
        cc2_s2 <= cc2_s1;
    end
end

wire [1:0] cc1_state = classify_cc(cc1_s2);
wire [1:0] cc2_state = classify_cc(cc2_s2);

// Detect any Rd on either CC line
wire cc1_rd = (cc1_state == CC_RD);
wire cc2_rd = (cc2_state == CC_RD);
wire any_rd = cc1_rd | cc2_rd;

// Detect Ra (for VCONN decision)
wire cc1_ra = (cc1_state == CC_RA);
wire cc2_ra = (cc2_state == CC_RA);

// =============================================================================
// Rp Level Encoder
// =============================================================================
// Convert register rp_level to analog control value
// 00 -> 01 (default 80uA), 01 -> 10 (1.5A 180uA), 10 -> 11 (3A 330uA), 11 -> 11
reg [1:0] rp_analog;
always @(*) begin
    case (rp_level)
        2'b00:   rp_analog = 2'b01; // default USB power
        2'b01:   rp_analog = 2'b10; // 1.5A
        2'b10:   rp_analog = 2'b11; // 3.0A
        default: rp_analog = 2'b11; // reserved -> 3.0A
    endcase
end

// =============================================================================
// Debounce Timer
// =============================================================================
reg [DEBOUNCE_W-1:0] debounce_cnt;
reg [DEBOUNCE_W-1:0] debounce_target;
reg                   debounce_active;
wire                  debounce_done = debounce_active && (debounce_cnt >= debounce_target);

// Compute debounce target from config (in ms) * cycles_per_ms
// Using a simple multiply since this only updates on config change
// Explicit width extension to avoid multiply truncation (8-bit * 16-bit = 16-bit in Verilog)
wire [DEBOUNCE_W-1:0] attach_debounce_target = {14'd0, debounce_cfg} * {6'd0, CYCLES_PER_MS};
wire [DEBOUNCE_W-1:0] detach_debounce_target = {14'd0, DETACH_DEBOUNCE_MS} * {6'd0, CYCLES_PER_MS};

// =============================================================================
// State Machine
// =============================================================================
localparam [2:0] ST_UNATTACHED   = 3'd0,
                 ST_ATTACH_WAIT  = 3'd1,
                 ST_ATTACHED     = 3'd2,
                 ST_DETACH_WAIT  = 3'd3;

reg [2:0] state;
assign state_out = state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state           <= ST_UNATTACHED;
        attached        <= 0;
        orientation     <= 0;
        rp_cc1_level    <= 2'b01;  // default Rp on both CC
        rp_cc2_level    <= 2'b01;
        vconn_en        <= 0;
        vconn_cc2       <= 0;
        attach_event    <= 0;
        detach_event    <= 0;
        accessory_mode  <= 0;
        cc_sel          <= 0;
        debounce_cnt    <= 0;
        debounce_active <= 0;
        debounce_target <= 0;
    end else begin
        // Default: clear event pulses
        attach_event <= 0;
        detach_event <= 0;

        case (state)
        // ---------------------------------------------------------------
        // UNATTACHED_SRC: Rp on both CC, wait for Rd detection
        // ---------------------------------------------------------------
        ST_UNATTACHED: begin
            attached     <= 0;
            rp_cc1_level <= rp_analog;
            rp_cc2_level <= rp_analog;
            vconn_en     <= 0;
            cc_sel       <= 0;

            debounce_cnt    <= 0;
            debounce_active <= 0;

            if (any_rd) begin
                state           <= ST_ATTACH_WAIT;
                debounce_target <= attach_debounce_target;
                debounce_active <= 1;
                debounce_cnt    <= 0;
            end
        end

        // ---------------------------------------------------------------
        // ATTACH_WAIT_SRC: Debounce Rd detection
        // ---------------------------------------------------------------
        ST_ATTACH_WAIT: begin
            rp_cc1_level <= rp_analog;
            rp_cc2_level <= rp_analog;

            if (!any_rd) begin
                // Rd disappeared -> false trigger, go back
                state           <= ST_UNATTACHED;
                debounce_active <= 0;
                debounce_cnt    <= 0;
            end else if (debounce_done) begin
                // Stable Rd for entire debounce period -> attached
                state        <= ST_ATTACHED;
                attached     <= 1;
                attach_event <= 1;

                // Determine orientation
                if (cc1_rd && !cc2_rd) begin
                    orientation <= 0; // CC1 active
                    cc_sel      <= 0;
                    // Check if CC2 has Ra (VCONN needed for active cable)
                    if (cc2_ra) begin
                        vconn_en  <= 1;
                        vconn_cc2 <= 1;
                    end
                end else if (cc2_rd && !cc1_rd) begin
                    orientation <= 1; // CC2 active
                    cc_sel      <= 1;
                    // Check if CC1 has Ra
                    if (cc1_ra) begin
                        vconn_en  <= 1;
                        vconn_cc2 <= 0;
                    end
                end else begin
                    // Both CC have Rd — audio adapter accessory mode
                    orientation    <= 0;
                    cc_sel         <= 0;
                    accessory_mode <= 1;
                end

                debounce_active <= 0;
                debounce_cnt    <= 0;
            end else begin
                debounce_cnt <= debounce_cnt + 1;
            end
        end

        // ---------------------------------------------------------------
        // ATTACHED_SRC: Cable connected, monitor for detach
        // ---------------------------------------------------------------
        ST_ATTACHED: begin
            // Keep advertising Rp on the active CC, can turn off on the other
            // (but keeping both on is safer for spec compliance)
            rp_cc1_level <= rp_analog;
            rp_cc2_level <= rp_analog;

            // Monitor for detach: active CC line Rd disappears
            if ((!orientation && !cc1_rd) || (orientation && !cc2_rd)) begin
                state           <= ST_DETACH_WAIT;
                debounce_target <= detach_debounce_target;
                debounce_active <= 1;
                debounce_cnt    <= 0;
            end
        end

        // ---------------------------------------------------------------
        // DETACH_WAIT: Debounce detach to avoid false disconnects
        // ---------------------------------------------------------------
        ST_DETACH_WAIT: begin
            // Check if Rd reappears on active CC (false alarm)
            if ((!orientation && cc1_rd) || (orientation && cc2_rd)) begin
                // Rd is back -> return to attached
                state           <= ST_ATTACHED;
                debounce_active <= 0;
                debounce_cnt    <= 0;
            end else if (debounce_done) begin
                // Confirmed detach
                state          <= ST_UNATTACHED;
                attached       <= 0;
                orientation    <= 0;
                accessory_mode <= 0;
                detach_event   <= 1;
                vconn_en       <= 0;

                debounce_active <= 0;
                debounce_cnt    <= 0;
            end else begin
                debounce_cnt <= debounce_cnt + 1;
            end
        end

        default: state <= ST_UNATTACHED;
        endcase
    end
end

endmodule
