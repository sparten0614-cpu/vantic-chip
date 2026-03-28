// VT3100 Phase 0 Warmup — SPI Slave Controller
// AI-generated Verilog for EDA toolchain validation
// Vantic Semiconductor — 2026-03-20
//
// Standard SPI Slave (Mode 0: CPOL=0, CPHA=0)
// - 8-bit register read/write
// - 16 addressable registers (4-bit addr)
// - Protocol: [1-bit R/W][4-bit ADDR][3-bit reserved] then [8-bit DATA]

module spi_slave (
    input  wire        clk,        // System clock
    input  wire        rst_n,      // Active-low reset

    // SPI interface
    input  wire        spi_clk,    // SPI clock from master
    input  wire        spi_mosi,   // Master Out Slave In
    output reg         spi_miso,   // Master In Slave Out
    input  wire        spi_cs_n,   // Chip select (active low)

    // Register interface (directly accessible for testing)
    output reg  [3:0]  reg_addr,   // Current register address
    output reg  [7:0]  reg_wdata,  // Write data
    output reg         reg_wen,    // Write enable pulse
    input  wire [7:0]  reg_rdata,  // Read data from register file
    output reg         reg_ren     // Read enable pulse
);

    // Internal state
    reg [4:0] bit_cnt;      // Bit counter (0-15 for 16-bit frame)
    reg [7:0] shift_in;     // Input shift register
    reg [7:0] shift_out;    // Output shift register
    reg       rw_bit;       // 0=write, 1=read
    reg [3:0] addr_latched; // Latched address

    // SPI clock edge detection (synchronize to system clock)
    reg [2:0] spi_clk_sync;
    reg [2:0] spi_cs_sync;

    wire spi_clk_rise = (spi_clk_sync[2:1] == 2'b01);
    wire spi_clk_fall = (spi_clk_sync[2:1] == 2'b10);
    wire spi_cs_active = ~spi_cs_sync[2];

    // Synchronize SPI signals to system clock
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_sync <= 3'b000;
            spi_cs_sync  <= 3'b111;
        end else begin
            spi_clk_sync <= {spi_clk_sync[1:0], spi_clk};
            spi_cs_sync  <= {spi_cs_sync[1:0], spi_cs_n};
        end
    end

    // Main SPI state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt     <= 5'd0;
            shift_in    <= 8'd0;
            shift_out   <= 8'd0;
            spi_miso    <= 1'b0;
            rw_bit      <= 1'b0;
            addr_latched<= 4'd0;
            reg_addr    <= 4'd0;
            reg_wdata   <= 8'd0;
            reg_wen     <= 1'b0;
            reg_ren     <= 1'b0;
        end else begin
            // Default: clear pulse signals
            reg_wen <= 1'b0;
            reg_ren <= 1'b0;

            if (!spi_cs_active) begin
                // CS inactive — reset state
                bit_cnt  <= 5'd0;
                spi_miso <= 1'b0;
            end else begin
                // CS active — process SPI transaction

                // Sample MOSI on rising edge
                if (spi_clk_rise) begin
                    shift_in <= {shift_in[6:0], spi_mosi};
                    bit_cnt  <= bit_cnt + 5'd1;

                    // After 8 bits: command byte complete
                    if (bit_cnt == 5'd7) begin
                        // At this point shift_in[6:0] has bits [7:1], spi_mosi has bit[0]
                        // Full byte = {shift_in[6:0], spi_mosi}
                        // Byte format: [R/W(7)][ADDR3(6)][ADDR2(5)][ADDR1(4)][ADDR0(3)][RSV(2:0)]
                        rw_bit       <= shift_in[6]; // bit 7 = R/W
                        addr_latched <= shift_in[5:2]; // bits 6:3 = address
                        reg_addr     <= shift_in[5:2];

                        // If read, request data now
                        if (shift_in[6]) begin // R/W bit (already shifted)
                            reg_ren <= 1'b1;
                        end
                    end

                    // After 16 bits: data byte complete
                    if (bit_cnt == 5'd15) begin
                        if (!rw_bit) begin
                            // Write operation
                            reg_wdata <= {shift_in[6:0], spi_mosi};
                            reg_wen   <= 1'b1;
                        end
                    end
                end

                // Drive MISO on falling edge
                if (spi_clk_fall) begin
                    if (bit_cnt > 5'd8 && rw_bit) begin
                        // Read mode: shift out data
                        if (bit_cnt == 5'd9) begin
                            shift_out <= reg_rdata;
                            spi_miso  <= reg_rdata[7];
                        end else begin
                            spi_miso  <= shift_out[7];
                            shift_out <= {shift_out[6:0], 1'b0};
                        end
                    end else begin
                        spi_miso <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
