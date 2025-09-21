module ImgRsz #(
    // Original Image configuration
    parameter IMG_WIDTH_MAX_SIZE    = 1024,
    parameter IMG_HEIGHT_MAX_SIZE   = 1024,
    parameter IMG_WIDTH_IDX_W       = $clog2(IMG_WIDTH_MAX_SIZE),
    parameter IMG_HEIGHT_IDX_W      = $clog2(IMG_HEIGHT_MAX_SIZE),
    // Resized Image configuration
    parameter RSZ_ALGORITHM         = "AVR-POOLING",    // Resizing Type: "AVR-POOLING" || "MAX-POOLING"
    parameter RSZ_IMG_WIDTH_SIZE    = 32,
    parameter RSZ_IMG_HEIGHT_SIZE   = 32,
    parameter RSZ_IMG_WIDTH_IDX_W   = $clog2(RSZ_IMG_WIDTH_SIZE),
    parameter RSZ_IMG_HEIGHT_IDX_W  = $clog2(RSZ_IMG_HEIGHT_SIZE),
    // Pixel configuration
    parameter PXL_PRIM_COLOR_NUM    = 1,    // Number of primary colors in 1 pixel  (Ex: RGB-3, YCbCr-3)
    parameter PXL_PRIM_COLOR_W      = 8,    // Width of each primary color element  (Ex: R-8,   Cb-8)
    // Forwarding configuartion
    parameter RSZ_PXL_FWD_SER       = 0,    // 1: Serial forwarding          || 0: Parallel forwarding
    parameter RSZ_PXL_FWD_TYP       = "ROW",// "PXL": Forwarding pixel mode  || "ROW": Forwarding row mode  || "COL": Forwarding column mode
    parameter RSZ_PXL_FWD_VLD_W     = (RSZ_PXL_FWD_SER == 1    ) ? 1                                        :   // For parallel forwarding, just need 1 handshaking port                                        :
                                      (RSZ_PXL_FWD_TYP == "ROW") ? RSZ_IMG_HEIGHT_SIZE                      :   // For row forwarding, need RSZ_IMG_HEIGHT_SIZE valid pins, associated to each row
                                      (RSZ_PXL_FWD_TYP == "COL") ? RSZ_IMG_WIDTH_SIZE                       :   // For row forwarding, need RSZ_IMG_WIDTH_SIZE valid pins, associated to each column
                                      (RSZ_PXL_FWD_SER == "PXL") ? RSZ_IMG_WIDTH_SIZE*RSZ_IMG_HEIGHT_SIZE   :   // For pixel forwarding, need all resized pixel valid pins
                                                                   0,                                           // Unsed
    parameter RSZ_PXL_FWD_RDY_W     = RSZ_PXL_FWD_VLD_W,                                                        // Same as Valid port (for handhshaking)
    // Compute Engine type
    parameter RSZ_AVR_DIV_TYPE      = 1     // Used for frequence target - 0: Using combinational divider || 1: Using multi-cycle divider
) (
    input   logic                                                                                   Clk,
    input   logic                                                                                   Reset,
    // Image information
    input   logic                                                       [IMG_WIDTH_IDX_W-1:0]       ImgWidth,
    input   logic                                                       [IMG_HEIGHT_IDX_W-1:0]      ImgHeight,
    // Pixel information                          
    input   logic                                                       [PXL_PRIM_COLOR_W-1:0]      PxlData         [PXL_PRIM_COLOR_NUM-1:0],
    input   logic                                                       [IMG_WIDTH_IDX_W-1:0]       PxlX,
    input   logic                                                       [IMG_HEIGHT_IDX_W-1:0]      PxlY,
    input                                                                                           PxlVld,
    output                                                                                          PxlRdy,
    // Resized Pixel
    output  logic                                                       [PXL_PRIM_COLOR_W-1:0]      FwdRszPxlDat    [PXL_PRIM_COLOR_NUM-1:0],   // For serial pixel forwarding 
    output  logic                           [RSZ_IMG_WIDTH_SIZE-1:0]    [PXL_PRIM_COLOR_W-1:0]      FwdRszRowDat    [PXL_PRIM_COLOR_NUM-1:0],   // For serial row forwarding
    output  logic                           [RSZ_IMG_HEIGHT_SIZE-1:0]   [PXL_PRIM_COLOR_W-1:0]      FwdRszColDat    [PXL_PRIM_COLOR_NUM-1:0],   // For serial column forwarding
    output  logic [RSZ_IMG_HEIGHT_SIZE-1:0] [RSZ_IMG_WIDTH_SIZE-1:0]    [PXL_PRIM_COLOR_W-1:0]      FwdRszPxlBuf    [PXL_PRIM_COLOR_NUM-1:0],   // For parallel forwarding
    output  logic                                                       [RSZ_IMG_WIDTH_IDX_W-1:0]   FwdRszPosX,
    output  logic                                                       [RSZ_IMG_HEIGHT_IDX_W-1:0]  FwdRszPosY,
    output                                                              [RSZ_PXL_FWD_VLD_W-1:0]     FwdRszVld,
    input                                                               [RSZ_PXL_FWD_RDY_W-1:0]     FwdRszRdy
    );
    // Variable declaration
    genvar x;
    genvar y;
    genvar c;

    // Local parametes
    // -- Common block parameter
    localparam BLK_WIDTH_MAX_SZ_W   = IMG_WIDTH_IDX_W - RSZ_IMG_WIDTH_IDX_W;    // Width of value that is equal to (ImgWidth / RszImgWidth)
    localparam BLK_HEIGHT_MAX_SZ_W  = IMG_HEIGHT_IDX_W - RSZ_IMG_HEIGHT_IDX_W;  // Width of value that is equal to (ImgHeight / RszImgWidth)
    localparam BLK_MAX_SZ_W         = BLK_WIDTH_MAX_SZ_W + BLK_HEIGHT_MAX_SZ_W; // Maximum block size
    localparam BLK_SUM_MAX_W        = PXL_PRIM_COLOR_W + BLK_MAX_SZ_W;          // From Prev Pipeline Stage
    
    localparam RSZ_PXL_FWD_MAX      = RSZ_PXL_FWD_VLD_W;
    localparam RSZ_PXL_FWD_CNT_W    = $clog2(RSZ_PXL_FWD_MAX);
    
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

    // Image Capture <-> Block Buffer
    FcRszPxlData_t                      PxlData_d1;
    logic   [IMG_WIDTH_IDX_W-1:0]       PxlX_d1;        
    logic   [IMG_HEIGHT_IDX_W-1:0]      PxlY_d1;
    logic                               PxlVld_d1;
    logic                               PxlRdy_d1;
    logic   [IMG_WIDTH_IDX_W-1:0]       ProcImgWidth;
    logic   [IMG_HEIGHT_IDX_W-1:0]      ProcImgHeight;
    // Block Buffer <-> Block Compute Serializer
    logic   [RSZ_IMG_WIDTH_SIZE-1:0]    BlkIsEnough [RSZ_IMG_HEIGHT_SIZE-1:0];  // The block collected all corresponding pixels
    FcBlkVal_t                          CompBlkData;    // Computed Block data
    logic   [RSZ_IMG_WIDTH_SIZE-1:0]    CompBlkXMsk;    // Used to flush the block counter (X position of the interest block)
    logic   [RSZ_IMG_HEIGHT_SIZE-1:0]   CompBlkYMsk;    // Used to flush the block counter (Y position of the interest block)
    logic                               CompBlkEn;      // Compute a block
    // Block Buffer <-> Compute Engine
    logic   [BLK_MAX_SZ_W-1:0]          ProcBlkSz;      // Processed Block size
    logic                               CompEngRdy;     // Compute Engine is ready (BlkSz is valid now)
    FcRszPxlData_t                      CeRszPxlData;   // Resized pixel data from Compute Engine
    logic   [RSZ_IMG_WIDTH_SIZE-1:0]    CeRszPxlXMsk;   
    logic   [RSZ_IMG_HEIGHT_SIZE-1:0]   CeRszPxlYMsk;
    logic                               CeCompVld;      // The Payload of Compute Engine is valid
    // Block Compute Serializer <-> Compute Engine
    logic   [RSZ_IMG_WIDTH_IDX_W-1:0]   CompBlkXIdx;    // Used to compute the block out and flush the block counter (X position of the interest block)
    logic   [RSZ_IMG_HEIGHT_IDX_W-1:0]  CompBlkYIdx;    // Used to compute the block out and flush the block counter (Y position of the interest block)
    logic                               CompBlkVld;     // Request to compute a block
    logic                               CompBlkRdy;     // Computing Block is ready
    // Image Capture <-> Compute Engine
    logic                               IsFstPxl;
    logic                               PxlCap;
    logic   [BLK_WIDTH_MAX_SZ_W-1:0]    BlkSzHor;
    logic   [BLK_HEIGHT_MAX_SZ_W-1:0]   BlkSzVer;
    logic                               RszImgComp;
    // Image Capture <-> Forwarder
    logic   [RSZ_PXL_FWD_CNT_W:0]       FwdNum;
    // Block Buffer <-> Forwarder
    logic    [RSZ_IMG_WIDTH_SIZE-1:0]   BlkIsExec   [RSZ_IMG_HEIGHT_SIZE-1:0]; // Block is executed by Compute Engine 
    FcRszPxlData_t                      FlushRszPxlData;// Flushed Resized Pixel data
    logic    [RSZ_IMG_WIDTH_SIZE-1:0]   FlushBlkXMsk;   // Used to flush the block executed flag (X position of the interest block)
    logic    [RSZ_IMG_HEIGHT_SIZE-1:0]  FlushBlkYMsk;   // Used to flush the block executed flag (Y position of the interest block)
    logic                               FlushVld;
    // Common use
    FcBlkBuf_t                          FcBlkBuf;    // Block accumulated value buffer
    FcRszPxlBuf_t                       FcRszPxlBuf; // Resized pixel buffer
    // Forwarding interface (internal)
    FcRszPxlData_t                      IntFwdRszPxlDat;
    FcRszPxlRow_t                       IntFwdRszRowDat;
    FcRszPxlCol_t                       IntFwdRszColDat;
    
    for (c = 0; c < PXL_PRIM_COLOR_NUM; c++) begin          : Gen_MapColor
        assign FwdRszPxlDat[c] = IntFwdRszPxlDat[c]; // Unpacking output
        for(y = 0; y < RSZ_IMG_HEIGHT_SIZE; y++) begin      : Gen_MapY
            assign FwdRszColDat[c][y] = IntFwdRszColDat[c][y];
            for(x = 0; x < RSZ_IMG_WIDTH_SIZE; x++) begin   : Gen_MapX
                assign FcRszPxlBuf[c][y][x]     = RszPxlData_t'(FcBlkBuf[c][y][x]);
                assign FwdRszPxlBuf[c][y][x]    = FcRszPxlBuf[c][y][x]; // Unpacking output
            end
        end
        for(x = 0; x < RSZ_IMG_WIDTH_SIZE; x++) begin   : Gen_MapX
            assign FwdRszRowDat[c][x] = IntFwdRszRowDat[c][x]; // Unpacking output
        end
    end

    ImgRszImgCap #(
        .IMG_WIDTH_IDX_W        (IMG_WIDTH_IDX_W),         
        .IMG_HEIGHT_IDX_W       (IMG_HEIGHT_IDX_W),
        .RSZ_IMG_WIDTH_SIZE     (RSZ_IMG_WIDTH_SIZE),
        .RSZ_IMG_HEIGHT_SIZE    (RSZ_IMG_HEIGHT_SIZE),
        .PXL_PRIM_COLOR_NUM     (PXL_PRIM_COLOR_NUM),         
        .PXL_PRIM_COLOR_W       (PXL_PRIM_COLOR_W),         
        .RSZ_PXL_FWD_TYP        (RSZ_PXL_FWD_TYP),
        .RSZ_PXL_FWD_CNT_W      (RSZ_PXL_FWD_CNT_W),
        .BLK_WIDTH_MAX_SZ_W     (BLK_WIDTH_MAX_SZ_W),
        .BLK_HEIGHT_MAX_SZ_W    (BLK_HEIGHT_MAX_SZ_W),
        .FC_RSZ_PXL_TYPE        (FcRszPxlData_t)     
    ) Igc (
        .Clk                    (Clk),
        .Reset                  (Reset),
        .ImgWidth               (ImgWidth),
        .ImgHeight              (ImgHeight),
        .PxlData                (PxlData),
        .PxlX                   (PxlX),
        .PxlY                   (PxlY),
        .PxlVld                 (PxlVld),
        .PxlRdy                 (PxlRdy),
        .PxlData_d1             (PxlData_d1),
        .PxlX_d1                (PxlX_d1),
        .PxlY_d1                (PxlY_d1),
        .PxlVld_d1              (PxlVld_d1),
        .PxlRdy_d1              (PxlRdy_d1),
        .FwdNum                 (FwdNum),
        .ProcImgWidth           (ProcImgWidth),
        .ProcImgHeight          (ProcImgHeight),
        .IsFstPxl               (IsFstPxl),
        .PxlCap                 (PxlCap),
        .BlkSzHor               (BlkSzHor),
        .BlkSzVer               (BlkSzVer),
        .RszImgComp             (RszImgComp)
    );

    ImgRszBlkBuf #(
        .IMG_WIDTH_IDX_W        (IMG_WIDTH_IDX_W),    
        .IMG_HEIGHT_IDX_W       (IMG_HEIGHT_IDX_W),    
        .RSZ_IMG_WIDTH_SIZE     (RSZ_IMG_WIDTH_SIZE),    
        .RSZ_IMG_HEIGHT_SIZE    (RSZ_IMG_HEIGHT_SIZE),        
        .RSZ_IMG_WIDTH_IDX_W    (RSZ_IMG_WIDTH_IDX_W),        
        .RSZ_IMG_HEIGHT_IDX_W   (RSZ_IMG_HEIGHT_IDX_W),        
        .PXL_PRIM_COLOR_NUM     (PXL_PRIM_COLOR_NUM),    
        .PXL_PRIM_COLOR_W       (PXL_PRIM_COLOR_W),    
        .BLK_MAX_SZ_W           (BLK_MAX_SZ_W),
        .BLK_SUM_MAX_W          (BLK_SUM_MAX_W),
        .FC_RSZ_PXL_TYPE        (FcRszPxlData_t),    
        .FC_BLK_VAL_TYPE        (FcBlkVal_t),    
        .FC_BLK_BUF_TYPE        (FcBlkBuf_t) 
    ) Bbf (
        .Clk                    (Clk),
        .Reset                  (Reset),
        .PxlData_d1             (PxlData_d1),
        .PxlX_d1                (PxlX_d1),
        .PxlY_d1                (PxlY_d1),
        .PxlVld_d1              (PxlVld_d1),
        .PxlRdy_d1              (PxlRdy_d1),
        .ProcImgWidth           (ProcImgWidth),
        .ProcImgHeight          (ProcImgHeight),
        .BlkIsEnough            (BlkIsEnough),
        .CompBlkData            (CompBlkData),
        .CompBlkXMsk            (CompBlkXMsk),
        .CompBlkYMsk            (CompBlkYMsk),
        .CompBlkEn              (CompBlkEn),
        .ProcBlkSz              (ProcBlkSz),
        .CompEngRdy             (CompEngRdy),
        .CeRszPxlData           (CeRszPxlData),
        .CeRszPxlXMsk           (CeRszPxlXMsk),
        .CeRszPxlYMsk           (CeRszPxlYMsk),
        .CeCompVld              (CeCompVld),
        .BlkIsExec              (BlkIsExec),
        .FlushBlkXMsk           (FlushBlkXMsk),
        .FlushBlkYMsk           (FlushBlkYMsk),
        .FlushVld               (FlushVld),
        .FcBlkBuf               (FcBlkBuf)
    );

    ImgRszBlkCompSer #(
        .RSZ_IMG_WIDTH_SIZE     (RSZ_IMG_WIDTH_SIZE),
        .RSZ_IMG_HEIGHT_SIZE    (RSZ_IMG_HEIGHT_SIZE),
        .RSZ_IMG_WIDTH_IDX_W    (RSZ_IMG_WIDTH_IDX_W),
        .RSZ_IMG_HEIGHT_IDX_W   (RSZ_IMG_HEIGHT_IDX_W)
    ) Bcs (
        .Clk                    (Clk),
        .Reset                  (Reset),
        .BlkIsEnough            (BlkIsEnough),
        .CompBlkXMsk            (CompBlkXMsk),
        .CompBlkYMsk            (CompBlkYMsk),
        .CompBlkEn              (CompBlkEn),
        .CompBlkXIdx            (CompBlkXIdx),
        .CompBlkYIdx            (CompBlkYIdx),
        .CompBlkVld             (CompBlkVld),
        .CompBlkRdy             (CompBlkRdy)
    );

    ImgRszCompEng #(
        .RSZ_ALGORITHM          (RSZ_ALGORITHM),
        .RSZ_IMG_WIDTH_SIZE     (RSZ_IMG_WIDTH_SIZE),
        .RSZ_IMG_HEIGHT_SIZE    (RSZ_IMG_HEIGHT_SIZE),
        .PXL_PRIM_COLOR_NUM     (PXL_PRIM_COLOR_NUM),
        .PXL_PRIM_COLOR_W       (PXL_PRIM_COLOR_W),
        .RSZ_AVR_DIV_TYPE       (RSZ_AVR_DIV_TYPE),
        .BLK_WIDTH_MAX_SZ_W     (BLK_WIDTH_MAX_SZ_W),
        .BLK_HEIGHT_MAX_SZ_W    (BLK_HEIGHT_MAX_SZ_W),
        .BLK_MAX_SZ_W           (BLK_MAX_SZ_W),
        .BLK_SUM_MAX_W          (BLK_SUM_MAX_W),
        .FC_RSZ_PXL_TYPE        (FcRszPxlData_t),
        .FC_BLK_VAL_TYPE        (FcBlkVal_t)
    ) Ceg (
        .Clk                    (Clk),
        .Reset                  (Reset),
        .IsFstPxl               (IsFstPxl),
        .PxlCap                 (PxlCap),
        .BlkSzHor               (BlkSzHor),
        .BlkSzVer               (BlkSzVer),
        .CompBlkData            (CompBlkData),
        .CompBlkXMsk            (CompBlkXMsk),
        .CompBlkYMsk            (CompBlkYMsk),
        .CompBlkVld             (CompBlkVld),
        .CompBlkRdy             (CompBlkRdy),
        .CeRszPxlData           (CeRszPxlData),
        .CeRszPxlXMsk           (CeRszPxlXMsk),
        .CeRszPxlYMsk           (CeRszPxlYMsk),
        .CeCompVld              (CeCompVld),
        .ProcBlkSz              (ProcBlkSz),
        .CompEngRdy             (CompEngRdy),
        .RszImgComp             (RszImgComp)
    );

    ImgRszFwd #(
        .RSZ_IMG_WIDTH_SIZE     (RSZ_IMG_WIDTH_SIZE),
        .RSZ_IMG_HEIGHT_SIZE    (RSZ_IMG_HEIGHT_SIZE),
        .RSZ_IMG_WIDTH_IDX_W    (RSZ_IMG_WIDTH_IDX_W),
        .RSZ_IMG_HEIGHT_IDX_W   (RSZ_IMG_HEIGHT_IDX_W),    
        .PXL_PRIM_COLOR_W       (PXL_PRIM_COLOR_W),
        .PXL_PRIM_COLOR_NUM     (PXL_PRIM_COLOR_NUM),
        .RSZ_PXL_FWD_SER        (RSZ_PXL_FWD_SER),
        .RSZ_PXL_FWD_TYP        (RSZ_PXL_FWD_TYP),
        .RSZ_PXL_FWD_VLD_W      (RSZ_PXL_FWD_VLD_W),
        .RSZ_PXL_FWD_RDY_W      (RSZ_PXL_FWD_RDY_W),
        .RSZ_PXL_FWD_CNT_W      (RSZ_PXL_FWD_CNT_W),
        .FC_RSZ_PXL_TYPE        (FcRszPxlData_t),
        .FC_RSZ_ROW_TYPE        (FcRszPxlRow_t),
        .FC_RSZ_COL_TYPE        (FcRszPxlCol_t),
        .FC_BLK_VAL_TYPE        (FcBlkVal_t),
        .FC_RSZ_BUF_TYPE        (FcRszPxlBuf_t)
    ) Fwd (
        .Clk                    (Clk),
        .Reset                  (Reset),
        .FwdRszPxlDat           (IntFwdRszPxlDat),
        .FwdRszRowDat           (IntFwdRszRowDat),
        .FwdRszColDat           (IntFwdRszColDat),
        .FwdRszPosX             (FwdRszPosX),
        .FwdRszPosY             (FwdRszPosY),
        .FwdRszVld              (FwdRszVld),
        .FwdRszRdy              (FwdRszRdy),
        .FcRszPxlBuf            (FcRszPxlBuf),
        .BlkIsExec              (BlkIsExec),
        .FlushBlkXMsk           (FlushBlkXMsk),
        .FlushBlkYMsk           (FlushBlkYMsk),
        .FlushVld               (FlushVld),
        .FwdNum                 (FwdNum)
    );
endmodule