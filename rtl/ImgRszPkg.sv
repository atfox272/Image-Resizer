package ImgRszPkg;
    // Original Image configuration
    parameter IMG_WIDTH_MAX_SIZE    = 1024;
    parameter IMG_HEIGHT_MAX_SIZE   = 1024;
    parameter IMG_WIDTH_IDX_W       = $clog2(IMG_WIDTH_MAX_SIZE);
    parameter IMG_HEIGHT_IDX_W      = $clog2(IMG_HEIGHT_MAX_SIZE);

    // Resized Image configuration
    parameter RSZ_ALGORITHM         = "AVR-POOLING";    // Resizing Type: "AVR-POOLING" || "MAX-POOLING"
    parameter RSZ_IMG_WIDTH_SIZE    = 8;
    parameter RSZ_IMG_HEIGHT_SIZE   = 8;
    parameter RSZ_IMG_WIDTH_IDX_W   = $clog2(RSZ_IMG_WIDTH_SIZE);
    parameter RSZ_IMG_HEIGHT_IDX_W  = $clog2(RSZ_IMG_HEIGHT_SIZE);

    // Pixel configuration
    parameter PXL_PRIM_COLOR_NUM    = 1;    // Number of primary colors in 1 pixel  (Ex: RGB-3, YCbCr-3)
    parameter PXL_PRIM_COLOR_W      = 8;    // Width of each primary color element  (Ex: R-8,   Cb-8)

    // Optional configuartion
    parameter RSZ_PXL_FWD_SER       = 0;    // 1: Serial forwarding          || 0: Parallel forwarding
    // -- Parameters are used in Parallel mode
    parameter RSZ_PXL_FWD_TYP       = "ROW";// "PXL": Forwarding pixel mode  || "ROW": Forwarding row mode  || "COL": Forwarding column mode
    parameter RSZ_PXL_FWD_VLD_W     = (RSZ_PXL_FWD_SER == 1    ) ? 1                                        :   // For parallel forwarding, just need 1 handshaking port                                        :
                                      (RSZ_PXL_FWD_TYP == "ROW") ? RSZ_IMG_HEIGHT_SIZE                      :   // For row forwarding, need RSZ_IMG_HEIGHT_SIZE valid pins, associated to each row
                                      (RSZ_PXL_FWD_TYP == "COL") ? RSZ_IMG_WIDTH_SIZE                       :   // For row forwarding, need RSZ_IMG_WIDTH_SIZE valid pins, associated to each column
                                      (RSZ_PXL_FWD_SER == "PXL") ? RSZ_IMG_WIDTH_SIZE*RSZ_IMG_HEIGHT_SIZE   :   // For pixel forwarding, need all resized pixel valid pins
                                                                   0;                                           // Unsed
    
    parameter RSZ_PXL_FWD_RDY_W     = (RSZ_PXL_FWD_SER == "PXL") ? 1                                        :   // For forwarding pixel mode, there is only 1 ready port to clear all flag
                                                                   RSZ_PXL_FWD_VLD_W;
    // -- Parameters are used in Serial mode
    parameter RSZ_PXL_FWD_ARR_W     = (RSZ_PXL_FWD_SER == "PXL") ? 1                    :   // 1 Element is 1 resized pixel
                                      (RSZ_PXL_FWD_TYP == "ROW") ? RSZ_IMG_HEIGHT_SIZE  :   // 1 Element is 1 row of resized image
                                      (RSZ_PXL_FWD_TYP == "COL") ? RSZ_IMG_WIDTH_SIZE   :   // 1 Element is 1 column of reiszed image
                                                                   1;                       // Unsed
    // Resizing Block configuration
    parameter BLK_WIDTH_MAX_SZ_W    = IMG_WIDTH_IDX_W - RSZ_IMG_WIDTH_IDX_W;    // Width of value that is equal to (ImgWidth / RszImgWidth)
    parameter BLK_HEIGHT_MAX_SZ_W   = IMG_HEIGHT_IDX_W - RSZ_IMG_HEIGHT_IDX_W;  // Width of value that is equal to (ImgHeight / RszImgWidth)
    parameter BLK_MAX_SZ_W          = BLK_WIDTH_MAX_SZ_W + BLK_HEIGHT_MAX_SZ_W;  
    parameter BLK_SUM_MAX_W         = PXL_PRIM_COLOR_W + BLK_MAX_SZ_W;          // From Prev Pipeline Stage

    // Compute Engine type
    parameter RSZ_AVR_DIV_TYPE      = 1;    // 0: Using combinational divider || 1: Using multi-cycle divider

    typedef logic        [BLK_SUM_MAX_W-1:0]                                    BlkVal_t;       // Block value value type
    typedef BlkVal_t     [PXL_PRIM_COLOR_NUM-1:0]                               FcBlkVal_t;     // Full color block value
    typedef BlkVal_t     [RSZ_IMG_HEIGHT_SIZE-1:0]  [RSZ_IMG_WIDTH_SIZE-1:0]    BlkBuf_t;       // Block buffer type
    typedef BlkBuf_t     [PXL_PRIM_COLOR_NUM-1:0]                               FcBlkBuf_t;     // Full color block buffer type

    typedef logic        [PXL_PRIM_COLOR_W-1:0]                                 RszPxlData_t;   // Resized pixel data type
    typedef RszPxlData_t [PXL_PRIM_COLOR_NUM-1:0]                               FcRszPxlData_t; // Full color resized pixel data type
    typedef RszPxlData_t [RSZ_IMG_HEIGHT_SIZE-1:0]  [RSZ_IMG_WIDTH_SIZE-1:0]    RszPxlBuf_t;    // Resized pixel buffer type
    typedef RszPxlBuf_t  [PXL_PRIM_COLOR_NUM-1:0]                               FcRszPxlBuf_t;  // Full color resized pixel buffer type

    typedef RszPxlData_t [RSZ_IMG_WIDTH_SIZE-1:0]                               RszPxlRow_t;    // Row of resized pixels
    typedef RszPxlRow_t  [PXL_PRIM_COLOR_NUM-1:0]                               FcRszPxlRow_t;  // Full color row of reiszed pixels
    
    typedef RszPxlData_t [RSZ_IMG_HEIGHT_SIZE-1:0]                              RszPxlCol_t;    // Column of resized pixels
    typedef RszPxlRow_t  [PXL_PRIM_COLOR_NUM-1:0]                               FcRszPxlCol_t;  // Full color column of reiszed pixels

    // Common
    parameter RSZ_PXL_FWD_MAX       = RSZ_PXL_FWD_VLD_W;
    parameter RSZ_PXL_FWD_CNT_W     = $clog2(RSZ_PXL_FWD_MAX);

endpackage