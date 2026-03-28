// =============================================================================
// 2-bit Saturating Counter Branch Predictor
// =============================================================================
// 64-entry Pattern History Table (PHT), indexed by PC[7:2]
// Each entry: 2-bit saturating counter (00=SNT, 01=WNT, 10=WT, 11=ST)
// Prediction: counter[1] = 1 → predict taken
//
// Update: on branch resolution from EX stage
//   - Taken: increment (saturate at 11)
//   - Not taken: decrement (saturate at 00)
// =============================================================================

module branch_pred (
    input  wire        clk,
    input  wire        rst_n,

    // Prediction interface (IF stage)
    input  wire [31:0] pred_pc,       // PC to predict
    output wire        pred_taken,    // Prediction: 1=taken, 0=not taken

    // Update interface (EX stage)
    input  wire        update_valid,  // Branch resolved
    input  wire [31:0] update_pc,     // Branch PC
    input  wire        update_taken   // Actual outcome
);

localparam ENTRIES = 64;
localparam IDX_BITS = 6;

// Pattern History Table: 64 × 2-bit
reg [1:0] pht [0:ENTRIES-1];

// Index extraction
wire [IDX_BITS-1:0] pred_idx   = pred_pc[IDX_BITS+1:2];
wire [IDX_BITS-1:0] update_idx = update_pc[IDX_BITS+1:2];

// Prediction: MSB of counter
assign pred_taken = pht[pred_idx][1];

// Update logic: saturating increment/decrement
integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Initialize all entries to weakly not-taken (01)
        for (i = 0; i < ENTRIES; i = i + 1)
            pht[i] <= 2'b01;
    end else if (update_valid) begin
        if (update_taken) begin
            // Increment (saturate at 11)
            if (pht[update_idx] != 2'b11)
                pht[update_idx] <= pht[update_idx] + 2'b01;
        end else begin
            // Decrement (saturate at 00)
            if (pht[update_idx] != 2'b00)
                pht[update_idx] <= pht[update_idx] - 2'b01;
        end
    end
end

endmodule
