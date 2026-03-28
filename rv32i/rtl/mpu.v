// =============================================================================
// Memory Protection Unit (MPU) — 8 Regions
// =============================================================================
// Cortex-M3 style MPU with 8 configurable memory regions.
// Each region: base address + size + permissions (RWX) + enable
//
// Protection checks happen combinationally on every memory access.
// Violation → fault output (CPU should trap to exception handler)
//
// Region registers (per region, 0-7):
//   BASE[31:5] | REGION_NUM[4:2] | reserved[1] | VALID[0]
//   ATTR: SIZE[4:0] | SRD[7:0] | TEX_S_C_B[5:0] | AP[2:0] | XN[0]
//
// Simplified: base + size + rwx per region
// =============================================================================

module mpu (
    input  wire        clk,
    input  wire        rst_n,

    // Access check (combinational)
    input  wire [31:0] check_addr,
    input  wire        check_read,
    input  wire        check_write,
    input  wire        check_exec,
    output wire        fault,         // Access violation

    // Configuration (register interface)
    input  wire [3:0]  reg_addr,      // Region number (0-7) + sub-register
    input  wire [31:0] reg_wdata,
    input  wire        reg_wen,
    output reg  [31:0] reg_rdata,

    // Control
    input  wire        mpu_enable     // Global MPU enable
);

// Per-region configuration
reg [31:0] region_base [0:7];   // Base address (aligned to size)
reg [4:0]  region_size [0:7];   // Size: 2^(size+1) bytes (min 32B)
reg        region_en [0:7];     // Region enable
reg        region_r [0:7];      // Read permission
reg        region_w [0:7];      // Write permission
reg        region_x [0:7];      // Execute permission

// =============================================================================
// Region Match Logic (combinational)
// =============================================================================
wire [7:0] region_match;
wire [7:0] read_ok, write_ok, exec_ok;

genvar g;
generate
    for (g = 0; g < 8; g = g + 1) begin : region_check
        wire [31:0] size_mask = (32'd1 << (region_size[g] + 5'd1)) - 32'd1;
        wire addr_in_region = region_en[g] &&
                             ((check_addr & ~size_mask) == (region_base[g] & ~size_mask));
        assign region_match[g] = addr_in_region;
        assign read_ok[g]  = addr_in_region & region_r[g];
        assign write_ok[g] = addr_in_region & region_w[g];
        assign exec_ok[g]  = addr_in_region & region_x[g];
    end
endgenerate

// Highest-numbered matching region wins (priority)
wire any_match = |region_match;
wire access_permitted = (!check_read  || |read_ok) &&
                        (!check_write || |write_ok) &&
                        (!check_exec  || |exec_ok);

// Fault: MPU enabled + access attempted + (no matching region OR permission denied)
assign fault = mpu_enable && (check_read || check_write || check_exec) &&
               (!any_match || !access_permitted);

// =============================================================================
// Register Interface
// =============================================================================
// reg_addr[3:1] = region number, reg_addr[0] = 0:base/enable, 1:permissions/size
wire [2:0] cfg_region = reg_addr[3:1];

integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 8; i = i + 1) begin
            region_base[i] <= 32'd0;
            region_size[i] <= 5'd0;
            region_en[i]   <= 1'b0;
            region_r[i]    <= 1'b1;
            region_w[i]    <= 1'b1;
            region_x[i]    <= 1'b1;
        end
    end else if (reg_wen) begin
        if (!reg_addr[0]) begin
            // Base register
            region_base[cfg_region] <= {reg_wdata[31:5], 5'd0};
            region_en[cfg_region]   <= reg_wdata[0];
        end else begin
            // Attribute register
            region_size[cfg_region] <= reg_wdata[4:0];
            region_r[cfg_region]    <= reg_wdata[8];
            region_w[cfg_region]    <= reg_wdata[9];
            region_x[cfg_region]    <= reg_wdata[10];
        end
    end
end

always @(*) begin
    if (!reg_addr[0])
        reg_rdata = {region_base[cfg_region][31:5], 4'd0, region_en[cfg_region]};
    else
        reg_rdata = {21'd0, region_x[cfg_region], region_w[cfg_region], region_r[cfg_region],
                     3'd0, region_size[cfg_region]};
end

endmodule
