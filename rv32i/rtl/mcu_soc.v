// =============================================================================
// RV32IM Microcontroller SoC
// =============================================================================
// Complete MCU: CPU + SRAM + UART + GPIO + Timer/Interrupts
//
// Memory Map:
//   0x00000000 - 0x00003FFF : 16KB Instruction SRAM (ROM-like, preloaded)
//   0x00004000 - 0x00007FFF : 16KB Data SRAM
//   0x10000000 - 0x100000FF : UART (TX/RX/Status/Baud)
//   0x10001000 - 0x100010FF : GPIO (32-bit I/O)
//   0x10002000 - 0x100020FF : CLINT (Timer/Interrupts)
//
// I/O:
//   uart_tx, uart_rx : Serial port
//   gpio_out[31:0]   : General purpose output
//   gpio_in[31:0]    : General purpose input
// =============================================================================

module mcu_soc (
    input  wire        clk,
    input  wire        rst_n,

    // UART
    output wire        uart_txd,
    input  wire        uart_rxd,

    // GPIO
    output reg  [31:0] gpio_out,
    input  wire [31:0] gpio_in,

    // Debug
    output wire [31:0] pc_out,
    output wire        halt
);

// =============================================================================
// CPU Core (single-cycle for simplicity in SoC integration)
// =============================================================================
wire [31:0] imem_addr, imem_data;
wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
wire [3:0]  dmem_wstrb;
wire        dmem_wen, dmem_ren;

rv32i_core cpu (
    .clk(clk), .rst_n(rst_n),
    .imem_addr(imem_addr), .imem_data(imem_data),
    .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
    .dmem_wstrb(dmem_wstrb), .dmem_wen(dmem_wen),
    .dmem_ren(dmem_ren), .dmem_rdata(dmem_rdata),
    .pc_out(pc_out), .halt(halt)
);

// =============================================================================
// Instruction Memory (16KB SRAM)
// =============================================================================
reg [31:0] imem [0:4095]; // 16KB / 4 = 4096 words
assign imem_data = imem[imem_addr[13:2]];

// =============================================================================
// Data Memory (16KB SRAM)
// =============================================================================
reg [31:0] dmem_ram [0:4095];

wire dmem_sel  = (dmem_addr[31:16] == 16'h0000) && dmem_addr[14]; // 0x00004000-0x00007FFF
wire uart_sel  = (dmem_addr[31:16] == 16'h1000) && (dmem_addr[15:12] == 4'h0); // 0x10000xxx
wire gpio_sel  = (dmem_addr[31:16] == 16'h1000) && (dmem_addr[15:12] == 4'h1); // 0x10001xxx
wire clint_sel = (dmem_addr[31:16] == 16'h1000) && (dmem_addr[15:12] == 4'h2); // 0x10002xxx

// Data SRAM read/write
wire [31:0] dmem_ram_rdata = dmem_ram[dmem_addr[13:2]];

always @(posedge clk) begin
    if (dmem_wen && dmem_sel) begin
        if (dmem_wstrb[0]) dmem_ram[dmem_addr[13:2]][7:0]   <= dmem_wdata[7:0];
        if (dmem_wstrb[1]) dmem_ram[dmem_addr[13:2]][15:8]  <= dmem_wdata[15:8];
        if (dmem_wstrb[2]) dmem_ram[dmem_addr[13:2]][23:16] <= dmem_wdata[23:16];
        if (dmem_wstrb[3]) dmem_ram[dmem_addr[13:2]][31:24] <= dmem_wdata[31:24];
    end
end

// =============================================================================
// UART
// =============================================================================
wire       uart_tx_busy;
reg        uart_tx_valid;
reg [7:0]  uart_tx_data;
wire [7:0] uart_rx_data;
wire       uart_rx_valid;

uart_tx u_uart_tx (
    .clk(clk), .rst_n(rst_n),
    .baud_div(16'd12), // 12MHz/921600 ≈ 13 → baud_div=12
    .tx_data(uart_tx_data), .tx_valid(uart_tx_valid),
    .tx_out(uart_txd), .tx_busy(uart_tx_busy)
);

uart_rx u_uart_rx (
    .clk(clk), .rst_n(rst_n),
    .baud_div(16'd12),
    .rx_in(uart_rxd),
    .rx_data(uart_rx_data), .rx_valid(uart_rx_valid),
    .rx_error()
);

// UART register interface
wire [31:0] uart_rdata;
reg [7:0] uart_rx_buf;
reg       uart_rx_buf_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uart_tx_valid    <= 1'b0;
        uart_tx_data     <= 8'd0;
        uart_rx_buf      <= 8'd0;
        uart_rx_buf_valid <= 1'b0;
    end else begin
        uart_tx_valid <= 1'b0;

        if (uart_rx_valid) begin
            uart_rx_buf       <= uart_rx_data;
            uart_rx_buf_valid <= 1'b1;
        end

        if (dmem_wen && uart_sel) begin
            case (dmem_addr[3:0])
                4'h0: begin uart_tx_data <= dmem_wdata[7:0]; uart_tx_valid <= 1'b1; end
                default: ;
            endcase
        end

        if (dmem_ren && uart_sel && dmem_addr[3:0] == 4'h4)
            uart_rx_buf_valid <= 1'b0; // Clear on read
    end
end

assign uart_rdata = (dmem_addr[3:0] == 4'h0) ? {24'd0, uart_tx_data} :
                    (dmem_addr[3:0] == 4'h4) ? {24'd0, uart_rx_buf} :
                    (dmem_addr[3:0] == 4'h8) ? {30'd0, uart_rx_buf_valid, uart_tx_busy} :
                    32'd0;

// =============================================================================
// GPIO
// =============================================================================
wire [31:0] gpio_rdata = (dmem_addr[3:0] == 4'h0) ? gpio_out :
                         (dmem_addr[3:0] == 4'h4) ? gpio_in :
                         32'd0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        gpio_out <= 32'd0;
    else if (dmem_wen && gpio_sel && dmem_addr[3:0] == 4'h0)
        gpio_out <= dmem_wdata;
end

// =============================================================================
// CLINT
// =============================================================================
wire [31:0] clint_rdata;

clint u_clint (
    .clk(clk), .rst_n(rst_n),
    .ext_irq(8'd0),
    .timer_tick(1'b0), // TODO: connect to prescaler
    .reg_addr(dmem_addr[7:0]),
    .reg_wdata(dmem_wdata),
    .reg_wen(dmem_wen && clint_sel),
    .reg_rdata(clint_rdata),
    .irq_timer(), .irq_software(), .irq_external(), .irq_any()
);

// =============================================================================
// Data Bus Mux
// =============================================================================
assign dmem_rdata = dmem_sel   ? dmem_ram_rdata :
                    uart_sel   ? uart_rdata :
                    gpio_sel   ? gpio_rdata :
                    clint_sel  ? clint_rdata :
                    32'd0;

endmodule
