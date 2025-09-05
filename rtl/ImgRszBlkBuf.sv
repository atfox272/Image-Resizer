module ImgRszBlkBuf 
    import ImgRszPkg::*;
    (
    input   logic                                   Clk,
    input   logic                                   Reset,
    // Pipelined (Delay) Pixel
    input   FcRszPxlData_t                          PxlData_d1,
    input   logic       [IMG_WIDTH_IDX_W-1:0]       PxlX_d1,        
    input   logic       [IMG_HEIGHT_IDX_W-1:0]      PxlY_d1,
    input   logic                                   PxlVld_d1,
    output  logic                                   PxlRdy_d1,
    // Processed Image information
    input   logic       [IMG_WIDTH_IDX_W-1:0]       ProcImgWidth,   // Processed Image's width
    input   logic       [IMG_HEIGHT_IDX_W-1:0]      ProcImgHeight,  // Processed Image's height
    // Block Compute Serialization 
    output  logic       [RSZ_IMG_WIDTH_SIZE-1:0]    BlkIsEnough     [RSZ_IMG_HEIGHT_SIZE-1:0],  // The block collected all corresponding pixels
    output  FcBlkVal_t                              CompBlkData,    // Computed Block data
    input   logic       [RSZ_IMG_WIDTH_SIZE-1:0]    CompBlkXMsk,    // Used to flush the block counter (X position of the interest block)
    input   logic       [RSZ_IMG_HEIGHT_SIZE-1:0]   CompBlkYMsk,    // Used to flush the block counter (Y position of the interest block)
    input   logic                                   CompBlkEn,      // Compute a block
    // Resizing Compute Engine (CE)
    input   logic       [BLK_MAX_SZ_W-1:0]          ProcBlkSz,      // Processed Block size
    input   logic                                   CompEngRdy,     // Compute Engine is ready (BlkSz is valid now)
    input   FcRszPxlData_t                          CeRszPxlData,   // Resized pixel data from Compute Engine
    input   logic       [RSZ_IMG_WIDTH_SIZE-1:0]    CeRszPxlXMsk,   
    input   logic       [RSZ_IMG_HEIGHT_SIZE-1:0]   CeRszPxlYMsk,
    input   logic                                   CeCompVld,      // The Payload of Compute Engine is valid
    // Resized Pixel Forwarder
    output  logic       [RSZ_IMG_WIDTH_SIZE-1:0]    BlkIsExec       [RSZ_IMG_HEIGHT_SIZE-1:0], // Block is executed by Compute Engine 
    output  FcRszPxlData_t                          FlushRszPxlData,// Flushed Resized Pixel data
    input   logic       [RSZ_IMG_WIDTH_SIZE-1:0]    FlushBlkXMsk,   // Used to flush the block executed flag (X position of the interest block)
    input   logic       [RSZ_IMG_HEIGHT_SIZE-1:0]   FlushBlkYMsk,   // Used to flush the block executed flag (Y position of the interest block)
    input   logic                                   FlushVld,
    // Common use
    output  FcBlkBuf_t                              FcBlkBuf    // Full Color Block accumulated value
    );
    genvar c, x, y;

    localparam U_TIME_X_W = IMG_WIDTH_IDX_W + RSZ_IMG_WIDTH_IDX_W;
    localparam V_TIME_Y_W = IMG_HEIGHT_IDX_W + RSZ_IMG_HEIGHT_IDX_W;

    typedef logic [BLK_MAX_SZ_W-1:0]    IntPxlCnt_t;    // Internal pixel counter type

    // Block base address (horizontal) = floor(u*X/U)
    // With
    //      + u is Block Index (0 -> RSZ_IMG_WIDTH_SIZE)
    //      + X is original image's width
    //      + U is resised image's width
    // Block base address (vertical) = floor(v*Y/V)
    // With
    //      + v is Block Index (0 -> RSZ_IMG_HEIGHT_SIZE)
    //      + Y is original image's height
    //      + V is resised image's height
    logic   [U_TIME_X_W-1:0]            uTimeXSeq       [RSZ_IMG_WIDTH_SIZE-1:0];  // u*X sequence          (u runs from 0 -> RSZ_IMG_WIDTH_SIZE)
    logic   [IMG_WIDTH_IDX_W-1:0]       BlkBaseAddrHor  [RSZ_IMG_WIDTH_SIZE-1:0];  // u*X/U sequence        (u runs from 0 -> RSZ_IMG_WIDTH_SIZE)
    logic   [IMG_WIDTH_IDX_W-1:0]       BlkOffsetHor    [RSZ_IMG_WIDTH_SIZE-1:0];  // u*X/U + X/U sequence  (u runs from 0 -> RSZ_IMG_WIDTH_SIZE)
    logic   [RSZ_IMG_WIDTH_SIZE-1:0]    PxlInBlkHor;    // Coming pixel is in block (horizontally)
    logic   [V_TIME_Y_W-1:0]            vTimeYSeq       [RSZ_IMG_HEIGHT_SIZE-1:0]; // v*Y sequence          (v runs from 0 -> RSZ_IMG_HEIGHT_SIZE)
    logic   [IMG_HEIGHT_IDX_W-1:0]      BlkBaseAddrVer  [RSZ_IMG_HEIGHT_SIZE-1:0]; // v*Y/V sequence        (v runs from 0 -> RSZ_IMG_HEIGHT_SIZE)
    logic   [IMG_HEIGHT_IDX_W-1:0]      BlkOffsetVer    [RSZ_IMG_HEIGHT_SIZE-1:0]; // v*Y/V + Y/V sequence  (v runs from 0 -> RSZ_IMG_HEIGHT_SIZE)
    logic   [RSZ_IMG_HEIGHT_SIZE-1:0]   PxlInBlkVer;    // Coming pixel is in block (vertically)
    MulSeq #(   // Calculate multiplcation sequence u*X (with u from 0 -> RSZ_IMG_WIDTH_SIZE)
        .DATA_IN_W  (IMG_WIDTH_IDX_W),
        .SEQ_LEN    (RSZ_IMG_WIDTH_SIZE)
    ) uTimeXSeqCalc (
        .DataIn     (ProcImgWidth),
        .DataOut    (uTimeXSeq)
    );
    MulSeq #(   // Calculate multiplcation sequence v*Y (with u from 0 -> RSZ_IMG_HEIGHT_SIZE)
        .DATA_IN_W  (IMG_HEIGHT_IDX_W),
        .SEQ_LEN    (RSZ_IMG_HEIGHT_SIZE)
    ) vTimeYSeqCalc (
        .DataIn     (ProcImgHeight),
        .DataOut    (vTimeYSeq)
    );
    // Note: Use MulSeq module to share resources (shared Adder) across successive elements in sequence -> Do not remove it
generate
    for (x = 0; x < RSZ_IMG_WIDTH_SIZE; x++) begin  : Gen_BlkHorInCond
        if((RSZ_IMG_WIDTH_SIZE  & (RSZ_IMG_WIDTH_SIZE-1))  == 0) begin  // RSZ_IMG_WIDTH_SIZE is a power-of-2
            assign BlkBaseAddrHor[x]= uTimeXSeq[x] >> RSZ_IMG_WIDTH_IDX_W; // u*X/U (U is 2**RSZ_IMG_WIDTH_IDX_W)
            assign BlkOffsetHor[x]  = BlkBaseAddrHor[x] + ((ProcImgWidth >> RSZ_IMG_WIDTH_IDX_W) + |ProcImgWidth[RSZ_IMG_WIDTH_IDX_W-1:0]); // u*X/U + ceil(X/U)
        end
        else begin
            $warning("[WARN]: The RSZ_IMG_WIDTH_SIZE is not a power-of-2");
        end
        assign PxlInBlkHor[x]       = (PxlX_d1 >= BlkBaseAddrHor[x]) & (PxlX_d1 < BlkOffsetHor[x]); // u*X/U <= x < u*X/U + ceil(X/U)
    end
    for (y = 0; y < RSZ_IMG_HEIGHT_SIZE; y++) begin : Gen_BlkVerInCond
        if((RSZ_IMG_HEIGHT_SIZE & (RSZ_IMG_HEIGHT_SIZE-1)) == 0) begin  // RSZ_IMG_HEIGHT_SIZE is a power-of-2
            assign BlkBaseAddrVer[y]= vTimeYSeq[y] >> RSZ_IMG_HEIGHT_IDX_W; // v*Y/V (V is 2**RSZ_IMG_HEIGHT_IDX_W)
            assign BlkOffsetVer[y]  = BlkBaseAddrVer[y] + ((ProcImgHeight >> RSZ_IMG_HEIGHT_IDX_W) + |ProcImgHeight[RSZ_IMG_HEIGHT_IDX_W-1:0]); // v*Y/V + ceil(Y/V)
        end
        else begin
            $warning("[WARN]: The RSZ_IMG_HEIGHT_SIZE is not a power-of-2");
        end
        assign PxlInBlkVer[y]       = (PxlY_d1 >= BlkBaseAddrVer[y]) & (PxlY_d1 < BlkOffsetVer[y]); // v*Y/V <= y < v*Y/V + ceil(Y/V)
    end
endgenerate   
    
    // Block Value Buffer
    assign PxlRdy_d1 = 1'b1;    // Always ready
generate
    for (c = 0; c < PXL_PRIM_COLOR_NUM; c++) begin          : Gen_ColorBlkValMap
        for (y = 0; y < RSZ_IMG_HEIGHT_SIZE; y++) begin     : Gen_BlkValMapY
            for (x = 0; x < RSZ_IMG_WIDTH_SIZE; x++) begin  : Gen_BlkValMapX
                if(RSZ_ALGORITHM == "AVR-POOLING") begin
                    always_ff @(posedge Clk) begin
                        if(Reset) begin
                            FcBlkBuf[c][y][x] <= '0;
                        end
                        else begin
                            unique casez ({(PxlVld_d1 & PxlInBlkHor[x] & PxlInBlkVer[y]), (CeCompVld & CeRszPxlXMsk[x] & CeRszPxlYMsk[y])})
                                2'b10: begin // The coming pixel is in the current block
                                    FcBlkBuf[c][y][x] <= FcBlkBuf[c][y][x] + PxlData_d1[c];    
                                end 
                                2'b01: begin // The Compute Engine just completed computing resized value for the current block
                                    FcBlkBuf[c][y][x] <= {{(BLK_SUM_MAX_W-PXL_PRIM_COLOR_W){1'b0}}, CeRszPxlData[c]};
                                end
                                2'b00: begin
                                    FcBlkBuf[c][y][x] <= FcBlkBuf[c][y][x];
                                end
                                default: begin
                                    FcBlkBuf[c][y][x] <= 'x;
                                end
                            endcase
                        end
                    end
                end
                else if(RSZ_ALGORITHM == "MAX-POOLING") begin
                    always_ff @(posedge Clk) begin
                        if(Reset) begin
                            FcBlkBuf[c][y][x] <= '0;
                        end
                        else if (PxlInBlkHor[x] & PxlInBlkVer[y]) begin
                            FcBlkBuf[c][y][x] <= (FcBlkBuf[c][y][x] < PxlData_d1[c]) ? PxlData_d1[c] : FcBlkBuf[c][y][x];
                        end
                    end
                end
            end
        end
    end
endgenerate

    // Block status control
    IntPxlCnt_t [RSZ_IMG_HEIGHT_SIZE-1:0] [RSZ_IMG_WIDTH_SIZE-1:0] IntPxlCnt;  // Internal pixel counter in 1 block 
generate
    for (y = 0; y < RSZ_IMG_HEIGHT_SIZE; y++) begin     : Gen_BlkStausMapY
        for (x = 0; x < RSZ_IMG_WIDTH_SIZE; x++) begin  : Gen_BlkStausMapX
            // "Block is enough" flag
            always_ff @(posedge Clk) begin
                if(Reset) begin
                    IntPxlCnt[y][x] <= '0;
                end
                else begin
                    unique casez ({(PxlVld_d1 & PxlInBlkHor[x] & PxlInBlkVer[y]), (CompBlkEn & CompBlkXMsk[x] & CompBlkYMsk[y])})
                        2'b10: begin    // The coming pixel is in the current block
                            IntPxlCnt[y][x] <= IntPxlCnt[y][x] + 1'b1;
                        end 
                        2'b01: begin    // The Block is forwarded to Compute Stage -> Clear the counter to clear the BlkIsEnough flag
                            IntPxlCnt[y][x] <= '0;
                        end 
                        2'b00: begin
                            IntPxlCnt[y][x] <= IntPxlCnt[y][x];
                        end
                        default: begin
                            IntPxlCnt[y][x] <= IntPxlCnt[y][x];
                        end
                    endcase
                end
            end
            assign BlkIsEnough[y][x] = CompEngRdy & (IntPxlCnt[y][x] == (ProcBlkSz-1));
            // "Block is executed" flag
            always_ff @(posedge Clk) begin
                if(Reset) begin
                    BlkIsExec[y][x] <= '0;
                end
                else begin
                    unique casez ({(CeCompVld & CeRszPxlXMsk[x] & CeRszPxlYMsk[y]), (FlushVld & FlushBlkXMsk[x] & FlushBlkYMsk[y])})
                        2'b10: begin    // Compute Engine just computed the current block
                            BlkIsExec[y][x] <= 1'b1;
                        end 
                        2'b01: begin    // The current block is flushed
                            BlkIsExec[y][x] <= 1'b0;
                        end 
                        2'b00: begin
                            BlkIsExec[y][x] <= BlkIsExec[y][x];
                        end
                        default: begin
                            BlkIsExec[y][x] <= BlkIsExec[y][x];
                        end
                    endcase
                end
            end
        end
    end

    for (c = 0; c < PXL_PRIM_COLOR_NUM; c++) begin  : Gen_ColorCompMap
        // Map a corresponding buffer to Compute Engine
        OnehotMux2D #(
            .DATA_TYPE  (BlkVal_t),
            .SEL_X_NUM  (RSZ_IMG_WIDTH_SIZE),
            .SEL_Y_NUM  (RSZ_IMG_HEIGHT_SIZE)
        ) CompBlkSel (
            .DataIn     (FcBlkBuf[c]),
            .SelX       (CompBlkXMsk),
            .SelY       (CompBlkYMsk),
            .DataOut    (CompBlkData[c])
        );
        // Map a corresponding buffer to Serializer
        OnehotMux2D #(
            .DATA_TYPE  (RszPxlData_t),
            .SEL_X_NUM  (RSZ_IMG_WIDTH_SIZE),
            .SEL_Y_NUM  (RSZ_IMG_HEIGHT_SIZE)
        ) FlushBlkSel (
            .DataIn     (RszPxlBuf_t'(FcBlkBuf[c])), // Never overflow
            .SelX       (FlushBlkXMsk),
            .SelY       (FlushBlkYMsk),
            .DataOut    (FlushRszPxlData[c])
        );
    end
    
endgenerate
endmodule