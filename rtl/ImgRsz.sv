module ImgRsz 
    import ImgRszPkg::*;
    (
    input   logic                                   Clk,
    input   logic                                   Reset,
    // Image information
    input   logic        [IMG_WIDTH_IDX_W-1:0]      ImgWidth,
    input   logic        [IMG_HEIGHT_IDX_W-1:0]     ImgHeight,
    // Pixel information
    input   logic        [PXL_PRIM_COLOR_W-1:0]     PxlData     [PXL_PRIM_COLOR_NUM-1:0],
    input   logic        [IMG_WIDTH_IDX_W-1:0]      PxlX,
    input   logic        [IMG_HEIGHT_IDX_W-1:0]     PxlY,
    input                                           PxlVld,
    output                                          PxlRdy,
    // Resized Pixel
    output  FcRszPxlData_t                          RszPxlData,
    output  logic        [RSZ_IMG_WIDTH_IDX_W-1:0]  RszPxlX,
    output  logic        [RSZ_IMG_HEIGHT_IDX_W-1:0] RszPxlY,
    output  logic                                   RszPxlVld,
    input   logic                                   RszPxlRdy,
    // Optional
    output  FcRszPxlBuf_t                           FcRszPxlBuf, // Block accumulated value
    output  logic       [RSZ_IMG_HEIGHT_SIZE-1:0]  [RSZ_IMG_WIDTH_SIZE-1:0]  RszPxlParVld  // Block is executed by Compute Engine
    );

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
    logic   [RSZ_IMG_WIDTH_IDX_W-1:0]   CompBlkXIdx;  // Used to compute the block out and flush the block counter (X position of the interest block)
    logic   [RSZ_IMG_HEIGHT_IDX_W-1:0]  CompBlkYIdx;  // Used to compute the block out and flush the block counter (Y position of the interest block)
    logic                               CompBlkVld;   // Request to compute a block
    logic                               CompBlkRdy;   // Computing Block is ready
    // Image Capture <-> Compute Engine
    logic                               IsFstPxl;
    logic                               PxlCap;
    logic   [BLK_WIDTH_MAX_SZ_W-1:0]    BlkSzHor;
    logic   [BLK_HEIGHT_MAX_SZ_W-1:0]   BlkSzVer;
    logic                               RszImgComp;
    // Image Capture <-> Forwarder
    logic                               FwdRszEn;   
    // Block Buffer <-> Forwarder
    logic    [RSZ_IMG_WIDTH_SIZE-1:0]   BlkIsExec   [RSZ_IMG_HEIGHT_SIZE-1:0]; // Block is executed by Compute Engine 
    FcRszPxlData_t                      FlushRszPxlData;// Flushed Resized Pixel data
    logic    [RSZ_IMG_WIDTH_SIZE-1:0]   FlushBlkXMsk;   // Used to flush the block executed flag (X position of the interest block)
    logic    [RSZ_IMG_HEIGHT_SIZE-1:0]  FlushBlkYMsk;   // Used to flush the block executed flag (Y position of the interest block)
    logic                               FlushVld;
    // Common use
    FcBlkBuf_t                          FcBlkBuf;    // Block accumulated value
    
    for(genvar y = 0; y < RSZ_IMG_HEIGHT_SIZE; y++) begin           : Gen_MapY
        for(genvar x = 0; x < RSZ_IMG_WIDTH_SIZE; x++) begin        : Gen_MapX
            for (genvar c = 0; c < PXL_PRIM_COLOR_NUM; c++) begin   : Gen_MapColor
                assign FcRszPxlBuf[c][y][x]          = RszPxlData_t'(FcBlkBuf[c][y][x]);
            end
            assign RszPxlParVld[y][x]   = BlkIsExec[y][x];
        end
    end

    ImgRszImgCap Igc (
        .Clk            (Clk),
        .Reset          (Reset),
        .ImgWidth       (ImgWidth),
        .ImgHeight      (ImgHeight),
        .PxlData        (PxlData),
        .PxlX           (PxlX),
        .PxlY           (PxlY),
        .PxlVld         (PxlVld),
        .PxlRdy         (PxlRdy),
        .PxlData_d1     (PxlData_d1),
        .PxlX_d1        (PxlX_d1),
        .PxlY_d1        (PxlY_d1),
        .PxlVld_d1      (PxlVld_d1),
        .PxlRdy_d1      (PxlRdy_d1),
        .FwdRszEn       (FwdRszEn),
        .ProcImgWidth   (ProcImgWidth),
        .ProcImgHeight  (ProcImgHeight),
        .IsFstPxl       (IsFstPxl),
        .PxlCap         (PxlCap),
        .BlkSzHor       (BlkSzHor),
        .BlkSzVer       (BlkSzVer),
        .RszImgComp     (RszImgComp)
    );

    ImgRszBlkBuf Bbf (
        .Clk            (Clk),
        .Reset          (Reset),
        .PxlData_d1     (PxlData_d1),
        .PxlX_d1        (PxlX_d1),
        .PxlY_d1        (PxlY_d1),
        .PxlVld_d1      (PxlVld_d1),
        .PxlRdy_d1      (PxlRdy_d1),
        .ProcImgWidth   (ProcImgWidth),
        .ProcImgHeight  (ProcImgHeight),
        .BlkIsEnough    (BlkIsEnough),
        .CompBlkData    (CompBlkData),
        .CompBlkXMsk    (CompBlkXMsk),
        .CompBlkYMsk    (CompBlkYMsk),
        .CompBlkEn      (CompBlkEn),
        .ProcBlkSz      (ProcBlkSz),
        .CompEngRdy     (CompEngRdy),
        .CeRszPxlData   (CeRszPxlData),
        .CeRszPxlXMsk   (CeRszPxlXMsk),
        .CeRszPxlYMsk   (CeRszPxlYMsk),
        .CeCompVld      (CeCompVld),
        .BlkIsExec      (BlkIsExec),
        .FlushRszPxlData(FlushRszPxlData),
        .FlushBlkXMsk   (FlushBlkXMsk),
        .FlushBlkYMsk   (FlushBlkYMsk),
        .FlushVld       (FlushVld),
        .FcBlkBuf       (FcBlkBuf)
    );

    ImgRszBlkCompSer Bcs (
        .Clk            (Clk),
        .Reset          (Reset),
        .BlkIsEnough    (BlkIsEnough),
        .CompBlkXMsk    (CompBlkXMsk),
        .CompBlkYMsk    (CompBlkYMsk),
        .CompBlkEn      (CompBlkEn),
        .CompBlkXIdx    (CompBlkXIdx),
        .CompBlkYIdx    (CompBlkYIdx),
        .CompBlkVld     (CompBlkVld),
        .CompBlkRdy     (CompBlkRdy)
    );

    ImgRszCompEng Ceg (
        .Clk            (Clk),
        .Reset          (Reset),
        .IsFstPxl       (IsFstPxl),
        .PxlCap         (PxlCap),
        .BlkSzHor       (BlkSzHor),
        .BlkSzVer       (BlkSzVer),
        .CompBlkData    (CompBlkData),
        .CompBlkXMsk    (CompBlkXMsk),
        .CompBlkYMsk    (CompBlkYMsk),
        .CompBlkVld     (CompBlkVld),
        .CompBlkRdy     (CompBlkRdy),
        .CeRszPxlData   (CeRszPxlData),
        .CeRszPxlXMsk   (CeRszPxlXMsk),
        .CeRszPxlYMsk   (CeRszPxlYMsk),
        .CeCompVld      (CeCompVld),
        .ProcBlkSz      (ProcBlkSz),
        .CompEngRdy     (CompEngRdy),
        .RszImgComp     (RszImgComp)
    );

    ImgRszFwd Fwd (
        .RszPxlData     (RszPxlData),
        .RszPxlX        (RszPxlX),
        .RszPxlY        (RszPxlY),
        .RszPxlVld      (RszPxlVld),
        .RszPxlRdy      (RszPxlRdy),
        .BlkIsExec      (BlkIsExec),
        .FlushRszPxlData(FlushRszPxlData),
        .FlushBlkXMsk   (FlushBlkXMsk),
        .FlushBlkYMsk   (FlushBlkYMsk),
        .FlushVld       (FlushVld),
        .FwdEn          (FwdRszEn)
    );
endmodule