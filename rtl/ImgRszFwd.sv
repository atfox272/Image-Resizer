module ImgRszFwd #(
    // Resized Image configuration
    parameter RSZ_IMG_WIDTH_SIZE    = 0,
    parameter RSZ_IMG_HEIGHT_SIZE   = 0,
    parameter RSZ_IMG_WIDTH_IDX_W   = $clog2(RSZ_IMG_WIDTH_SIZE),
    parameter RSZ_IMG_HEIGHT_IDX_W  = $clog2(RSZ_IMG_HEIGHT_SIZE),
    // Pixel configuration
    parameter PXL_PRIM_COLOR_W      = 8,    // Width of each primary color element  (Ex: R-8,   Cb-8)
    parameter PXL_PRIM_COLOR_NUM    = 1,    // Number of primary colors in 1 pixel  (Ex: RGB-3, YCbCr-3)
    // Forwarding configuartion
    parameter RSZ_PXL_FWD_SER       = 0,    // 1: Serial forwarding          || 0: Parallel forwarding
    parameter RSZ_PXL_FWD_TYP       = "ROW",// "PXL": Forwarding pixel mode  || "ROW": Forwarding row mode  || "COL": Forwarding column mode
    parameter RSZ_PXL_FWD_VLD_W     = (RSZ_PXL_FWD_SER == 1    ) ? 1                                        :   // For parallel forwarding, just need 1 handshaking port                                        :
                                      (RSZ_PXL_FWD_TYP == "ROW") ? RSZ_IMG_HEIGHT_SIZE                      :   // For row forwarding, need RSZ_IMG_HEIGHT_SIZE valid pins, associated to each row
                                      (RSZ_PXL_FWD_TYP == "COL") ? RSZ_IMG_WIDTH_SIZE                       :   // For row forwarding, need RSZ_IMG_WIDTH_SIZE valid pins, associated to each column
                                      (RSZ_PXL_FWD_SER == "PXL") ? RSZ_IMG_WIDTH_SIZE*RSZ_IMG_HEIGHT_SIZE   :   // For pixel forwarding, need all resized pixel valid pins
                                                                   0,                                           // Unsed
    parameter RSZ_PXL_FWD_RDY_W     = RSZ_PXL_FWD_VLD_W,                                                        // Same as Valid port (for handhshaking)
    // Forwarding 
    parameter RSZ_PXL_FWD_CNT_W     = 0,
    // Local data type
    parameter type FC_RSZ_PXL_TYPE  = logic, // FcRszPxlData_t
    parameter type FC_RSZ_ROW_TYPE  = logic, // FcRszPxlRow_t
    parameter type FC_RSZ_COL_TYPE  = logic, // FcRszPxlCol_t
    parameter type FC_BLK_VAL_TYPE  = logic,
    parameter type FC_RSZ_BUF_TYPE  = logic  // FcRszPxlBuf_t 
) (
    input   logic                                           Clk,
    input   logic                                           Reset, 
    // Resized Pixel
    output  FC_RSZ_PXL_TYPE                                 FwdRszPxlDat,
    output  FC_RSZ_ROW_TYPE                                 FwdRszRowDat,
    output  FC_RSZ_COL_TYPE                                 FwdRszColDat,
    output  logic               [RSZ_IMG_WIDTH_IDX_W-1:0]   FwdRszPosX,
    output  logic               [RSZ_IMG_HEIGHT_IDX_W-1:0]  FwdRszPosY,
    output                      [RSZ_PXL_FWD_VLD_W-1:0]     FwdRszVld,
    input                       [RSZ_PXL_FWD_RDY_W-1:0]     FwdRszRdy,
    // Resized Pixel Buffer
    input   FC_RSZ_BUF_TYPE                                 FcRszPxlBuf,
    input   logic               [RSZ_IMG_WIDTH_SIZE-1:0]    BlkIsExec       [RSZ_IMG_HEIGHT_SIZE-1:0],  // Block is executed by Compute Engine 
    output  logic               [RSZ_IMG_WIDTH_SIZE-1:0]    FlushBlkXMsk,   // Used to flush the block executed flag (X position of the interest block)
    output  logic               [RSZ_IMG_HEIGHT_SIZE-1:0]   FlushBlkYMsk,   // Used to flush the block executed flag (Y position of the interest block)
    output  logic                                           FlushVld,
    // Image Capturer
    output  logic               [RSZ_PXL_FWD_CNT_W:0]       FwdNum
    );
    genvar x;
    genvar y;
    genvar c;

    typedef logic           [PXL_PRIM_COLOR_W-1:0]      RszPxlData_t;
    typedef RszPxlData_t    [RSZ_IMG_WIDTH_SIZE-1:0]    RszPxlRow_t;    // Row of resized pixels
    typedef RszPxlData_t    [RSZ_IMG_HEIGHT_SIZE-1:0]   RszPxlCol_t;    // Column of resized pixels

    logic       [RSZ_PXL_FWD_CNT_W:0]       RszPxlHskNum;
    logic       [RSZ_IMG_HEIGHT_SIZE-1:0]   RszPxlRowVld;
    RszPxlRow_t [RSZ_IMG_HEIGHT_SIZE-1:0]   RszPxlRow   [PXL_PRIM_COLOR_NUM-1:0];
    logic       [RSZ_IMG_WIDTH_SIZE-1:0]    RszPxlColVld;
    RszPxlCol_t [RSZ_IMG_WIDTH_SIZE-1:0]    RszPxlCol   [PXL_PRIM_COLOR_NUM-1:0];
    
    // Find all valid rows
    always_comb begin : VldRowColComb
        for (int i = 0; i < RSZ_IMG_HEIGHT_SIZE; i++) begin
            RszPxlRowVld[i] = &BlkIsExec[i];
        end
        // Find all valid columns
        for (int i = 0; i < RSZ_IMG_WIDTH_SIZE; i++) begin
            for (int j = 0; j < RSZ_IMG_HEIGHT_SIZE; j++) begin
                RszPxlColVld[i] &= BlkIsExec[j][i];
            end
        end
    end
    generate
        if(RSZ_PXL_FWD_SER == 1) begin : Gen_SerialFwd
            // Flush related entries buffer
            assign FlushVld = FwdRszVld & FwdRszRdy;
            
            assign FwdNum   = FlushVld; // Number of forwarded resized pixel is always 1 in SERIZAL mode
            
            // Separated modes handling
            if(RSZ_PXL_FWD_TYP == "ROW") begin : Gen_FwdCntRow
                // Not use X mapping
                assign FlushBlkXMsk = '1;   // Flush all pixel in a row
                assign FwdRszPxlDat = '0;   // Unsed
                assign FwdRszColDat = '0;   // Unsed
                // Select a valid row to forward
                FindFirstSet #(
                    .DATA_W (RSZ_IMG_HEIGHT_SIZE)
                ) FindFirstVldRow (
                    .In     (RszPxlRowVld),
                    .Out    (FlushBlkYMsk)
                );
                // Forwarded resized pixel data Mapping
                for(c = 0; c < PXL_PRIM_COLOR_NUM; c++) begin : Gen_ParColor
                    // Map a corresponding row 
                    // -- Map FcRszPxlBuf --> RszPxlRow
                    for (y = 0; y < RSZ_IMG_HEIGHT_SIZE; y++) begin : Gen_MapRow
                        assign RszPxlRow[c][y] = FcRszPxlBuf[c][y];
                    end
                    OnehotMux #(
                        .DATA_TYPE  (RszPxlRow_t),
                        .SEL_NUM    (RSZ_IMG_HEIGHT_SIZE)
                    ) MapRszRow (
                        .DataIn     (RszPxlRow[c]),
                        .Sel        (FlushBlkYMsk),
                        .DataOut    (FwdRszRowDat[c])
                    );
                end
                // Forward resized pixel address Mapping
                assign FwdRszPosX = '0; // Unsed
                onehot_encoder #(
                    .INPUT_W    (RSZ_IMG_HEIGHT_SIZE),
                    .OUTPUT_W   (RSZ_IMG_HEIGHT_IDX_W)
                ) RszPxlYMap (
                    .i          (FlushBlkYMsk),
                    .o          (FwdRszPosY)
                );
                // Forwarding is valid when more than 1 pixel is valid
                assign FwdRszVld = |FlushBlkYMsk;
            end : Gen_FwdCntRow
            else if (RSZ_PXL_FWD_TYP == "COL") begin : Gen_FwdCol
                // Not use Y mapping
                assign FlushBlkYMsk = '1;   // Flush all pixel in a column
                assign FwdRszPxlDat = '0;   // Unsed
                assign FwdRszRowDat = '0;   // Unsed
                // Select a valid column to forward
                FindFirstSet #(
                    .DATA_W (RSZ_IMG_WIDTH_SIZE)
                ) FindFirstVldCol (
                    .In     (RszPxlColVld),
                    .Out    (FlushBlkXMsk)
                );
                // Forwarded resized pixel data Mapping
                for(c = 0; c < PXL_PRIM_COLOR_NUM; c++) begin : Gen_ParColor
                    // Map a corresponding row 
                    // -- Map FcRszPxlBuf --> RszPxlCol
                    for (x = 0; x < RSZ_IMG_WIDTH_SIZE; x++) begin : Gen_MapCol
                        for (y = 0; y < RSZ_IMG_HEIGHT_SIZE; y++) begin : Gen_MapRow
                            assign RszPxlCol[c][x][y] = FcRszPxlBuf[c][y][x];
                        end
                    end
                    OnehotMux #(
                        .DATA_TYPE  (RszPxlCol_t),
                        .SEL_NUM    (RSZ_IMG_WIDTH_SIZE)
                    ) MapRszCol (
                        .DataIn     (RszPxlCol[c]),
                        .Sel        (FlushBlkXMsk),
                        .DataOut    (FwdRszColDat[c])
                    );
                end
                // Forward resized pixel address Mapping
                assign FwdRszPosY = '0; // Unsed
                onehot_encoder #(
                    .INPUT_W    (RSZ_IMG_WIDTH_SIZE),
                    .OUTPUT_W   (RSZ_IMG_WIDTH_IDX_W)
                ) RszPxlXMap (
                    .i          (FlushBlkXMsk),
                    .o          (FwdRszPosX)
                );
                // Forwarding is valid when more than 1 pixel is valid
                assign FwdRszVld = |FlushBlkXMsk;
            end : Gen_FwdCol
            else if (RSZ_PXL_FWD_TYP == "PXL") begin : Gen_FwdPxl
                assign FwdRszColDat = '0;   // Unsed
                assign FwdRszRowDat = '0;   // Unsed
                // Find a valid resized pixel to forward
                FindFirstSet2D #(
                    .DATA_X_W   (RSZ_IMG_WIDTH_SIZE),
                    .DATA_Y_W   (RSZ_IMG_HEIGHT_SIZE)
                ) RszPxlMap (
                    .In         (BlkIsExec),
                    .OutX       (FlushBlkXMsk),
                    .OutY       (FlushBlkYMsk)
                );
                // Forwarded resized pixel data Mapping
                for(c = 0; c < PXL_PRIM_COLOR_NUM; c++) begin : Gen_ParColor
                    // Map a corresponding resized pixel 
                    OnehotMux2D #(
                        .DATA_TYPE  (RszPxlData_t),
                        .SEL_X_NUM  (RSZ_IMG_WIDTH_SIZE),
                        .SEL_Y_NUM  (RSZ_IMG_HEIGHT_SIZE)
                    ) FwdPxlBlkSel (
                        .DataIn     (FcRszPxlBuf[c]),
                        .SelX       (FlushBlkXMsk),
                        .SelY       (FlushBlkYMsk),
                        .DataOut    (FwdRszPxlDat[c])
                    );
                end
                // Forward resized pixel address Mapping
                onehot_encoder #(
                    .INPUT_W    (RSZ_IMG_WIDTH_SIZE),
                    .OUTPUT_W   (RSZ_IMG_WIDTH_IDX_W)
                ) RszPxlXMap (
                    .i          (FlushBlkXMsk),
                    .o          (FwdRszPosX)
                );
                onehot_encoder #(
                    .INPUT_W    (RSZ_IMG_HEIGHT_SIZE),
                    .OUTPUT_W   (RSZ_IMG_HEIGHT_IDX_W)
                ) RszPxlYMap (
                    .i          (FlushBlkYMsk),
                    .o          (FwdRszPosY)
                );
                // Forwarding is valid when more than 1 pixel is valid
                assign FwdRszVld = |FlushBlkYMsk;
            end  : Gen_FwdPxl
        end
        else if(RSZ_PXL_FWD_SER == 0) begin : Gen_ParallelFwd
            // Assign unsed signals
            assign FwdRszPosX   = '0;
            assign FwdRszPosY   = '0;
            assign FwdRszColDat = '0;
            assign FwdRszRowDat = '0;
            assign FwdRszPxlDat = '0;

            // Flush related entries buffer
            assign FlushVld = |(FwdRszVld & FwdRszRdy); // Assert if any port is handshaking

            // Count number of occuring handshaking
            always_comb begin : HskCountComb
                RszPxlHskNum = '0;
                for (int i = 0; i < RSZ_PXL_FWD_VLD_W; i++) begin
                    RszPxlHskNum += (FwdRszVld[i] & FwdRszRdy[i]);
                end
            end
            // Pipeline number of occuring handshaking to split the timing from external circuit
            always_ff @ (posedge Clk) begin
                if(Reset) begin
                    FwdNum <= '0;
                end
                else begin
                    FwdNum <= RszPxlHskNum;
                end
            end
            if(RSZ_PXL_FWD_TYP == "ROW") begin : Gen_FwdRow
                assign FwdRszVld    = RszPxlRowVld;
                assign FlushBlkXMsk = '1;
                assign FlushBlkYMsk = FwdRszRdy;
            end
            else if (RSZ_PXL_FWD_TYP == "COL") begin : Gen_FwdCol
                assign FwdRszVld    = RszPxlColVld;
                assign FlushBlkXMsk = FwdRszRdy;            
                assign FlushBlkYMsk = '1;
            end
            else if (RSZ_PXL_FWD_TYP == "PXL") begin : Gen_FwdPxl
                // Mapping Forwarding valid
                for (y = 0; y < RSZ_IMG_HEIGHT_SIZE; y++) begin : Gen_FwdVldRow
                    for (x = 0; x < RSZ_IMG_WIDTH_SIZE; x++) begin : Gen_FwdVldCol
                        assign FwdRszVld[y*RSZ_IMG_WIDTH_SIZE + x] = BlkIsExec[y][x]; // Flattern forwarding valid port 
                    end
                end
                // Clear all buffer values when all block is valid
                assign FlushBlkXMsk = '1;
                assign FlushBlkYMsk = '1;
            end
        end
endgenerate

    
endmodule