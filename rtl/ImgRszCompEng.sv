module ImgRszCompEng 
    import ImgRszPkg::*;
    (
    input   logic                               Clk,
    input   logic                               Reset,
    // Image Capture
    input   logic                               IsFstPxl,       // The current pixel is the first
    input   logic                               PxlCap,         // Pixel is captured
    input   logic   [BLK_WIDTH_MAX_SZ_W-1:0]    BlkSzHor,       // Horizontal Block Size
    input   logic   [BLK_HEIGHT_MAX_SZ_W-1:0]   BlkSzVer,       // Vertical Block Size
    // Prev pipeline stage: Gather the pixels
    input   FcBlkVal_t                          CompBlkData,    // Computed Block data
    input   logic   [RSZ_IMG_WIDTH_SIZE-1:0]    CompBlkXMsk,    // Used to flush the block counter (X position of the interest block)
    input   logic   [RSZ_IMG_HEIGHT_SIZE-1:0]   CompBlkYMsk,    // Used to flush the block counter (Y position of the interest block)
    input   logic                               CompBlkVld,     // Request to compute a block
    output  logic                               CompBlkRdy,     // Computing Block is ready
    // Next pipeline stage: Buffer resized pixel
    output  FcRszPxlData_t                      CeRszPxlData,   // Resized pixel data from Compute Engine
    output  logic   [RSZ_IMG_WIDTH_SIZE-1:0]    CeRszPxlXMsk,   
    output  logic   [RSZ_IMG_HEIGHT_SIZE-1:0]   CeRszPxlYMsk,
    output  logic                               CeCompVld,      // The Payload of Compute Engine is valid
    // Common 
    output  logic   [BLK_MAX_SZ_W-1:0]          ProcBlkSz,      // Processed Block size
    output  logic                               CompEngRdy,     // Compute Engine is ready (BlkSz is valid now)
    input   logic                               RszImgComp      // Resizing image is completed
    );

    // Block Size computing
    /* Note: 
       In calculating block size (BlkSzHor * BlkSzVer), the Compute Engine will have many idle cycle in waiting for gathering pixels into 1 block.
       Therefore, Compute Engine does not need to use complex approaches to multiply BlkSzHor with BlkSzVer in 1 cycle,
       just accumulate in many cycles to calculate block size
       -> Use multi-cycle approach to calculate (BlkSzHor*BlkSzVer) with closer timing and less resource
    */      
    typedef enum { 
        IDLE,
        ACC,    // Accumulating
        DONE    // Calculation is done
    } CalcBlkSzSt_e;
    
    CalcBlkSzSt_e                               CalcBlkSzSt;    // Calculate Block Size state
    logic           [BLK_HEIGHT_MAX_SZ_W-1:0]   AccTime;        // Accumulation times

    always_ff @(posedge Clk) begin
        if(Reset) begin
            CalcBlkSzSt <= IDLE;
        end
        else begin
            unique casez (CalcBlkSzSt)
                IDLE: begin
                    ProcBlkSz   <= '0;
                    AccTime     <= '0;
                    CalcBlkSzSt <= ACC;
                end
                ACC: begin
                    ProcBlkSz <= ProcBlkSz + BlkSzHor;
                    AccTime   <= AccTime + 1'b1;
                    if(AccTime == (BlkSzVer-1'b1)) begin
                        CalcBlkSzSt <= DONE;
                    end
                end
                DONE: begin
                    if(RszImgComp) begin    // Resizing image is completed
                        CalcBlkSzSt <= IDLE;
                    end
                end
                default: begin
                    
                end
            endcase
        end
    end
    assign CompEngRdy = CalcBlkSzSt == DONE;

    // Resized pixel computing
    /* 
    1st approach: Using divider of synthesis tool (only 1 cycle)
        - This approach has only 1 latency
        - However, it has very bad timing
    */ 
    assign CompBlkRdy = CompEngRdy; // Always ready when the block size is calculated
    always_ff @(posedge Clk) begin
        if(Reset) begin
            CeCompVld <= '0;
        end
        else begin
            for (int c = 0; c < PXL_PRIM_COLOR_NUM; c++) begin
                CeRszPxlData[c] <= CompBlkData[c] / ProcBlkSz;    // FIXME: Potential critical path
            end
            CeRszPxlXMsk <= CompBlkXMsk;
            CeRszPxlYMsk <= CompBlkYMsk;
            CeCompVld    <= CompBlkVld & CompBlkRdy;
        end
    end
    /*
    2nd approach: Using lookup table, which can be pipelined
        - Flexible in timing (can balance between latency and timing by adding pipeline stages)
        - However, it consumes a lot of resouces
    TODO:
    */
endmodule