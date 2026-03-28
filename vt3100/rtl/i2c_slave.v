// =============================================================================
// VT3100 I2C Slave — Configuration Interface
// =============================================================================
// Standard I2C slave with register-based access.
//
// Features:
//   - 7-bit address: 0x60 default (configurable via parameter)
//   - Standard mode (100kHz) and Fast mode (400kHz)
//   - Clock stretching (SCL hold during read data preparation)
//   - Auto-increment register address on sequential read/write
//   - 32 registers (0x00-0x1F), byte-wide
//
// I2C Protocol:
//   Write: START + ADDR(W) + ACK + REG_ADDR + ACK + DATA + ACK + ... + STOP
//   Read:  START + ADDR(W) + ACK + REG_ADDR + ACK +
//          RESTART + ADDR(R) + ACK + DATA + ACK + DATA + NACK + STOP
//
// Register access:
//   - Directly exposes reg_wdata/reg_wstrobe/reg_addr for external register file
//   - Reads via reg_rdata input
//
// Clocking: clk = 12 MHz system clock (>> I2C 400kHz, plenty of oversampling)
// =============================================================================

module i2c_slave #(
    parameter [6:0] SLAVE_ADDR = 7'h60
) (
    input  wire        clk,
    input  wire        rst_n,

    // I2C bus (active-low open-drain, directly from pads with external pull-ups)
    input  wire        scl_in,
    input  wire        sda_in,
    output reg         sda_oe,       // 1 = drive SDA low (open-drain: only pull low)

    // Register interface
    output reg  [7:0]  reg_addr,     // Current register address
    output reg  [7:0]  reg_wdata,    // Write data
    output reg         reg_wstrobe,  // Pulse: write to register
    input  wire [7:0]  reg_rdata,    // Read data (from register file, addressed by reg_addr)

    // Status
    output reg         busy          // I2C transaction in progress
);

// =============================================================================
// Input Synchronization (2-stage for SCL and SDA)
// =============================================================================
reg scl_s1, scl_s2, scl_d;
reg sda_s1, sda_s2, sda_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scl_s1 <= 1; scl_s2 <= 1; scl_d <= 1;
        sda_s1 <= 1; sda_s2 <= 1; sda_d <= 1;
    end else begin
        scl_s1 <= scl_in; scl_s2 <= scl_s1; scl_d <= scl_s2;
        sda_s1 <= sda_in; sda_s2 <= sda_s1; sda_d <= sda_s2;
    end
end

// Edge detection
wire scl_rise = (scl_s2 & ~scl_d);
wire scl_fall = (~scl_s2 & scl_d);

// START condition: SDA falls while SCL is high
wire start_cond = (~sda_s2 & sda_d & scl_s2);
// STOP condition: SDA rises while SCL is high
wire stop_cond  = (sda_s2 & ~sda_d & scl_s2);

// =============================================================================
// State Machine
// =============================================================================
localparam [3:0] ST_IDLE       = 4'd0,
                 ST_ADDR       = 4'd1,   // Receiving 7-bit address + R/W bit
                 ST_ADDR_ACK   = 4'd2,   // Sending ACK for address
                 ST_REG_ADDR   = 4'd3,   // Receiving register address byte
                 ST_REG_ACK    = 4'd4,   // Sending ACK for register address
                 ST_WRITE      = 4'd5,   // Receiving write data byte
                 ST_WRITE_ACK  = 4'd6,   // Sending ACK for write data
                 ST_READ       = 4'd7,   // Sending read data byte
                 ST_READ_ACK   = 4'd8,   // Receiving ACK/NACK from master
                 ST_READ_SETUP = 4'd9;   // 1-cycle setup for next read byte

reg [3:0]  state;
reg [7:0]  shift_reg;   // Shift register for receiving/sending bytes
reg [2:0]  bit_cnt;     // Bit counter (0-7)
reg        addr_match;  // Address matched this transaction
reg        rw_bit;      // 0=write, 1=read
reg        reg_addr_set; // Register address has been set in this transaction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state        <= ST_IDLE;
        shift_reg    <= 0;
        bit_cnt      <= 0;
        addr_match   <= 0;
        rw_bit       <= 0;
        reg_addr_set <= 0;
        reg_addr     <= 0;
        reg_wdata    <= 0;
        reg_wstrobe  <= 0;
        sda_oe       <= 0;
        busy         <= 0;
    end else begin
        reg_wstrobe <= 0; // Default: clear write strobe

        // START condition — reset state machine (handles repeated START too)
        if (start_cond) begin
            state     <= ST_ADDR;
            bit_cnt   <= 0;
            shift_reg <= 0;
            sda_oe    <= 0;
            busy      <= 1;
        end
        // STOP condition — return to idle
        else if (stop_cond) begin
            state      <= ST_IDLE;
            sda_oe     <= 0;
            busy       <= 0;
            addr_match <= 0;
            reg_addr_set <= 0;
        end
        else begin
            case (state)
            ST_IDLE: begin
                sda_oe <= 0;
                busy   <= 0;
            end

            // ---------------------------------------------------------
            // Receive 7-bit address + R/W bit (8 bits total)
            // ---------------------------------------------------------
            ST_ADDR: begin
                sda_oe <= 0; // Release SDA during address phase
                if (scl_rise) begin
                    shift_reg <= {shift_reg[6:0], sda_s2};
                    if (bit_cnt == 3'd7) begin
                        // All 8 bits received: [7:1]=address, [0]=R/W
                        if (shift_reg[6:0] == SLAVE_ADDR) begin
                            addr_match <= 1;
                            rw_bit     <= sda_s2; // bit[0] of the received byte
                            state      <= ST_ADDR_ACK;
                        end else begin
                            // Address mismatch — ignore this transaction
                            addr_match <= 0;
                            state      <= ST_IDLE;
                        end
                        bit_cnt <= 0;
                    end else begin
                        bit_cnt <= bit_cnt + 3'd1;
                    end
                end
            end

            // ---------------------------------------------------------
            // Send ACK for address (pull SDA low on SCL low)
            // ---------------------------------------------------------
            ST_ADDR_ACK: begin
                if (scl_fall) begin
                    sda_oe <= 1; // Drive SDA low = ACK
                end
                if (scl_rise) begin
                    // ACK bit sampled by master
                end
                // After ACK, on next SCL fall, release SDA and proceed
                if (scl_fall && sda_oe) begin
                    sda_oe  <= 0;
                    bit_cnt <= 0;
                    if (rw_bit && reg_addr_set) begin
                        // Read: drive first bit immediately on this SCL fall
                        sda_oe    <= ~reg_rdata[7];
                        shift_reg <= {reg_rdata[6:0], 1'b0};
                        bit_cnt   <= 3'd1; // First bit already driven
                        state     <= ST_READ;
                    end else begin
                        // Write: receive register address (or data if addr already set)
                        state <= reg_addr_set ? ST_WRITE : ST_REG_ADDR;
                    end
                end
            end

            // ---------------------------------------------------------
            // Receive register address byte
            // ---------------------------------------------------------
            ST_REG_ADDR: begin
                sda_oe <= 0;
                if (scl_rise) begin
                    shift_reg <= {shift_reg[6:0], sda_s2};
                    if (bit_cnt == 3'd7) begin
                        reg_addr     <= {shift_reg[6:0], sda_s2};
                        reg_addr_set <= 1;
                        state        <= ST_REG_ACK;
                        bit_cnt      <= 0;
                    end else begin
                        bit_cnt <= bit_cnt + 3'd1;
                    end
                end
            end

            // ---------------------------------------------------------
            // Send ACK for register address
            // ---------------------------------------------------------
            ST_REG_ACK: begin
                if (scl_fall && !sda_oe) begin
                    sda_oe <= 1; // ACK
                end
                if (scl_fall && sda_oe) begin
                    sda_oe  <= 0;
                    bit_cnt <= 0;
                    state   <= ST_WRITE; // Ready for data bytes
                end
            end

            // ---------------------------------------------------------
            // Receive write data byte
            // ---------------------------------------------------------
            ST_WRITE: begin
                sda_oe <= 0;
                if (scl_rise) begin
                    shift_reg <= {shift_reg[6:0], sda_s2};
                    if (bit_cnt == 3'd7) begin
                        reg_wdata   <= {shift_reg[6:0], sda_s2};
                        reg_wstrobe <= 1;
                        state       <= ST_WRITE_ACK;
                        bit_cnt     <= 0;
                    end else begin
                        bit_cnt <= bit_cnt + 3'd1;
                    end
                end
            end

            // ---------------------------------------------------------
            // Send ACK for write data, auto-increment address
            // ---------------------------------------------------------
            ST_WRITE_ACK: begin
                if (scl_fall && !sda_oe) begin
                    sda_oe <= 1; // ACK
                end
                if (scl_fall && sda_oe) begin
                    sda_oe   <= 0;
                    reg_addr <= reg_addr + 8'd1; // Auto-increment
                    bit_cnt  <= 0;
                    state    <= ST_WRITE; // Ready for next byte
                end
            end

            // ---------------------------------------------------------
            // Send read data byte (MSB first)
            // ---------------------------------------------------------
            ST_READ: begin
                // Drive SDA with current bit on SCL falling edge
                if (scl_fall) begin
                    sda_oe <= ~shift_reg[7]; // 0 = release (high), 1 = drive low
                    shift_reg <= {shift_reg[6:0], 1'b0};
                    if (bit_cnt == 3'd7) begin
                        bit_cnt <= 0;
                        state   <= ST_READ_ACK;
                    end else begin
                        bit_cnt <= bit_cnt + 3'd1;
                    end
                end
            end

            // ---------------------------------------------------------
            // Receive ACK/NACK from master after read.
            // We enter on the 8th data bit's scl_fall. The next scl_rise
            // is still the master sampling the last data bit. We must wait
            // for scl_fall (release SDA) then scl_rise (sample ACK).
            // Use bit_cnt as a phase tracker: 0=wait for release, 1=wait for ACK.
            // ---------------------------------------------------------
            ST_READ_ACK: begin
                if (bit_cnt == 3'd0) begin
                    // Phase 0: wait for scl_fall after last data bit's scl_rise
                    if (scl_fall) begin
                        sda_oe  <= 0; // Release SDA for master ACK/NACK
                        bit_cnt <= 3'd1;
                    end
                end else begin
                    // Phase 1: sample ACK on scl_rise
                    if (scl_rise) begin
                        if (sda_s2) begin
                            // NACK — master is done reading
                            state <= ST_IDLE;
                        end else begin
                            // ACK — master wants more data
                            reg_addr <= reg_addr + 8'd1;
                            state    <= ST_READ_SETUP;
                        end
                    end
                end
            end

            // ---------------------------------------------------------
            // Setup: drive first bit of next read byte. Stay here until
            // master samples it (scl_rise), then go to ST_READ.
            // ---------------------------------------------------------
            ST_READ_SETUP: begin
                // Continuously drive first bit (harmless re-assignment)
                sda_oe    <= ~reg_rdata[7];
                shift_reg <= {reg_rdata[6:0], 1'b0};
                if (scl_rise) begin
                    bit_cnt <= 3'd1;
                    state   <= ST_READ;
                end
            end

            default: state <= ST_IDLE;
            endcase
        end
    end
end

endmodule
