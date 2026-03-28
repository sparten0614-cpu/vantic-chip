// =============================================================================
// VT3200 Buck ADC Interface — Multiplexed ADC Controller
// =============================================================================
// Controls a 10-bit SAR ADC with 4 multiplexed channels:
//   CH0: VBUS (output voltage) — every switching cycle
//   CH1: ISNS (inductor current) — every switching cycle
//   CH2: VIN (input voltage) — periodic (every N cycles)
//   CH3: TEMP (die temperature) — periodic (every M cycles)
//
// Conversion sequence triggered by pwm_cycle_start.
// Each conversion takes ~24 CLK_SYS cycles (2µs at 12MHz).
// 4 conversions per switching cycle at 500kHz (2µs period at 96MHz).
//
// ADC hardware interface: start pulse + channel select → busy wait → data valid
// =============================================================================

module buck_adc (
    input  wire        clk_sys,
    input  wire        rst_n,

    // Trigger
    input  wire        cycle_start,   // PWM cycle start (from clk_pwm domain, synchronized)

    // ADC hardware interface (directly to SAR ADC hard macro)
    output reg  [1:0]  adc_ch_sel,    // Channel select (0-3)
    output reg         adc_start,     // Conversion start pulse
    input  wire        adc_busy,      // ADC is converting
    input  wire [9:0]  adc_data,      // Conversion result
    input  wire        adc_valid,     // Result valid pulse

    // Configuration
    input  wire [7:0]  vin_divider,   // VIN sample every N switching cycles (default: 50 = 10kHz at 500kHz fsw)
    input  wire [7:0]  temp_divider,  // TEMP sample every M switching cycles (default: 500 = 1kHz)

    // Results (registered, always valid)
    output reg  [9:0]  vbus_result,
    output reg  [9:0]  isns_result,
    output reg  [9:0]  vin_result,
    output reg  [9:0]  temp_result,

    // Compensator trigger (VBUS result ready)
    output reg         comp_update    // Pulse: VBUS conversion done, compensator can run
);

// =============================================================================
// Conversion Sequencer
// =============================================================================
localparam [2:0] SEQ_IDLE  = 3'd0,
                 SEQ_VBUS  = 3'd1,
                 SEQ_ISNS  = 3'd2,
                 SEQ_VIN   = 3'd3,
                 SEQ_TEMP  = 3'd4;

reg [2:0] seq_state;
reg       vin_due;       // VIN conversion due this cycle
reg       temp_due;      // TEMP conversion due this cycle
reg [7:0] vin_counter;
reg [7:0] temp_counter;

// Determine which optional channels to convert this cycle
always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) begin
        vin_counter  <= 8'd0;
        temp_counter <= 8'd0;
        vin_due      <= 1'b0;
        temp_due     <= 1'b0;
    end else if (cycle_start) begin
        // VIN divider
        if (vin_counter >= vin_divider) begin
            vin_counter <= 8'd0;
            vin_due     <= 1'b1;
        end else begin
            vin_counter <= vin_counter + 8'd1;
            vin_due     <= 1'b0;
        end
        // TEMP divider
        if (temp_counter >= temp_divider) begin
            temp_counter <= 8'd0;
            temp_due     <= 1'b1;
        end else begin
            temp_counter <= temp_counter + 8'd1;
            temp_due     <= 1'b0;
        end
    end
end

// =============================================================================
// State Machine — Sequential Conversion
// =============================================================================
always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) begin
        seq_state   <= SEQ_IDLE;
        adc_ch_sel  <= 2'd0;
        adc_start   <= 1'b0;
        vbus_result <= 10'd0;
        isns_result <= 10'd0;
        vin_result  <= 10'd0;
        temp_result <= 10'd0;
        comp_update <= 1'b0;
    end else begin
        adc_start   <= 1'b0;
        comp_update <= 1'b0;

        case (seq_state)
        SEQ_IDLE: begin
            if (cycle_start) begin
                // Start VBUS conversion
                adc_ch_sel <= 2'd0;
                adc_start  <= 1'b1;
                seq_state  <= SEQ_VBUS;
            end
        end

        SEQ_VBUS: begin
            if (adc_valid) begin
                vbus_result <= adc_data;
                comp_update <= 1'b1; // Trigger compensator
                // Start ISNS conversion
                adc_ch_sel <= 2'd1;
                adc_start  <= 1'b1;
                seq_state  <= SEQ_ISNS;
            end
        end

        SEQ_ISNS: begin
            if (adc_valid) begin
                isns_result <= adc_data;
                // VIN if due
                if (vin_due) begin
                    adc_ch_sel <= 2'd2;
                    adc_start  <= 1'b1;
                    seq_state  <= SEQ_VIN;
                end else if (temp_due) begin
                    adc_ch_sel <= 2'd3;
                    adc_start  <= 1'b1;
                    seq_state  <= SEQ_TEMP;
                end else begin
                    seq_state <= SEQ_IDLE;
                end
            end
        end

        SEQ_VIN: begin
            if (adc_valid) begin
                vin_result <= adc_data;
                if (temp_due) begin
                    adc_ch_sel <= 2'd3;
                    adc_start  <= 1'b1;
                    seq_state  <= SEQ_TEMP;
                end else begin
                    seq_state <= SEQ_IDLE;
                end
            end
        end

        SEQ_TEMP: begin
            if (adc_valid) begin
                temp_result <= adc_data;
                seq_state   <= SEQ_IDLE;
            end
        end

        default: seq_state <= SEQ_IDLE;
        endcase
    end
end

endmodule
