module ImgRszBlkCompSer #(
    // Resized Image configuration
    parameter RSZ_IMG_WIDTH_SIZE    = 8,
    parameter RSZ_IMG_HEIGHT_SIZE   = 8,
    parameter RSZ_IMG_WIDTH_IDX_W   = $clog2(RSZ_IMG_WIDTH_SIZE),
    parameter RSZ_IMG_HEIGHT_IDX_W  = $clog2(RSZ_IMG_HEIGHT_SIZE)
) (
    input   logic                               Clk,
    input   logic                               Reset,
    // Particular Block Buffer
    input   logic   [RSZ_IMG_WIDTH_SIZE-1:0]    BlkIsEnough     [RSZ_IMG_HEIGHT_SIZE-1:0],
    output  logic   [RSZ_IMG_WIDTH_SIZE-1:0]    CompBlkXMsk,  // Used to flush the block counter (X position of the interest block)
    output  logic   [RSZ_IMG_HEIGHT_SIZE-1:0]   CompBlkYMsk,  // Used to flush the block counter (Y position of the interest block)
    output  logic                               CompBlkEn,    // Compute a block
    // "Compute" Stage
    output  logic   [RSZ_IMG_WIDTH_IDX_W-1:0]   CompBlkXIdx,  // Used to compute the block out and flush the block counter (X position of the interest block)
    output  logic   [RSZ_IMG_HEIGHT_IDX_W-1:0]  CompBlkYIdx,  // Used to compute the block out and flush the block counter (Y position of the interest block)
    output  logic                               CompBlkVld,   // Request to compute a block
    input   logic                               CompBlkRdy    // Computing Block is ready
    );
    // Wire declaration
    logic                           CompBlkHsk;
    
    assign CompBlkHsk = CompBlkVld & CompBlkRdy; // 1 resized pixel is just sent
    assign CompBlkEn  = CompBlkHsk;
   
    // Block counter flushing control
    FindFirstSet2D #(
      .DATA_X_W   (RSZ_IMG_WIDTH_SIZE),
      .DATA_Y_W   (RSZ_IMG_HEIGHT_SIZE)
    ) BlkPosMap (
        .In         (BlkIsEnough),
        .OutX       (CompBlkXMsk),
        .OutY       (CompBlkYMsk)
    );
    
    // Forwarding to "Compute" stage
    onehot_encoder #(
      .INPUT_W  (RSZ_IMG_WIDTH_SIZE),
      .OUTPUT_W (RSZ_IMG_WIDTH_IDX_W)
    ) RszPxlXMap (
      .i        (CompBlkXMsk),
      .o        (CompBlkXIdx)
    );
    onehot_encoder #(
      .INPUT_W  (RSZ_IMG_HEIGHT_SIZE),
      .OUTPUT_W (RSZ_IMG_HEIGHT_IDX_W)
    ) RszPxlYMap (
      .i        (CompBlkYMsk),
      .o        (CompBlkYIdx)
    );
    assign CompBlkVld = |CompBlkYMsk;    // One of rows is set -> at least 1 block is set

endmodule