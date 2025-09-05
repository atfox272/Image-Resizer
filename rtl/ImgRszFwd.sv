module ImgRszFwd
    import ImgRszPkg::*;
    (
    // Resized Pixel
    output  FcRszPxlData_t                      RszPxlData,
    output  logic   [RSZ_IMG_WIDTH_IDX_W-1:0]   RszPxlX,
    output  logic   [RSZ_IMG_HEIGHT_IDX_W-1:0]  RszPxlY,
    output  logic                               RszPxlVld,
    input   logic                               RszPxlRdy,
    // Resized Pixel Forwarder
    input   logic    [RSZ_IMG_WIDTH_SIZE-1:0]   BlkIsExec       [RSZ_IMG_HEIGHT_SIZE-1:0],  // Block is executed by Compute Engine 
    input   FcRszPxlData_t                      FlushRszPxlData,// Flushed Resized Pixel data
    output  logic    [RSZ_IMG_WIDTH_SIZE-1:0]   FlushBlkXMsk,   // Used to flush the block executed flag (X position of the interest block)
    output  logic    [RSZ_IMG_HEIGHT_SIZE-1:0]  FlushBlkYMsk,   // Used to flush the block executed flag (Y position of the interest block)
    output  logic                               FlushVld,
    // Image Capturer
    output  logic                               FwdEn
    );

    for(genvar c = 0; c < PXL_PRIM_COLOR_NUM; c++) begin : Gen_ParColor
        assign RszPxlData[c] = FlushRszPxlData[c];
    end

generate
    if(RSZ_PXL_FWD_SER == 1) begin : Gen_SerialFwd
        // Find a valid resized pixel to forward
        FindFirstSet2D #(
            .DATA_X_W   (RSZ_IMG_WIDTH_SIZE),
            .DATA_Y_W   (RSZ_IMG_HEIGHT_SIZE)
        ) RszPxlMap (
            .In         (BlkIsExec),
            .OutX       (FlushBlkXMsk),
            .OutY       (FlushBlkYMsk)
        );
        assign RszPxlVld    = |FlushBlkYMsk;
    end
    else if(RSZ_PXL_FWD_SER == 0) begin : Gen_ParallelFwd
        // Clear all buffer values when all block is valid
        assign FlushBlkXMsk = '1;
        assign FlushBlkYMsk = '1;
        always_comb begin
            for(int i = 0; i < RSZ_IMG_HEIGHT_SIZE; i++) begin
               RszPxlVld &= &BlkIsExec[i];
            end
        end
    end
endgenerate

    assign FwdEn    = RszPxlVld & RszPxlRdy;
    assign FlushVld = FwdEn;
    // Convert Onehot positions to Index position
    onehot_encoder #(
      .INPUT_W  (RSZ_IMG_WIDTH_SIZE),
      .OUTPUT_W (RSZ_IMG_WIDTH_IDX_W)
    ) RszPxlXMap (
      .i        (FlushBlkXMsk),
      .o        (RszPxlX)
    );
    onehot_encoder #(
      .INPUT_W  (RSZ_IMG_HEIGHT_SIZE),
      .OUTPUT_W (RSZ_IMG_HEIGHT_IDX_W)
    ) RszPxlYMap (
      .i        (FlushBlkYMsk),
      .o        (RszPxlY)
    );
endmodule