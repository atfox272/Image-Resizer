// Image Capturer ULM
module ImgRszImgCap 
    import ImgRszPkg::*;
    (
    input   logic                                   Clk,
    input   logic                                   Reset,
    // Image information
    input   logic   [IMG_WIDTH_IDX_W-1:0]           ImgWidth,
    input   logic   [IMG_HEIGHT_IDX_W-1:0]          ImgHeight,
    // Input Pixel
    input   logic   [PXL_PRIM_COLOR_W-1:0]          PxlData     [PXL_PRIM_COLOR_NUM-1:0],
    input   logic   [IMG_WIDTH_IDX_W-1:0]           PxlX,
    input   logic   [IMG_HEIGHT_IDX_W-1:0]          PxlY,
    input   logic                                   PxlVld,
    output  logic                                   PxlRdy,
    // Pipelined (Delay) Pixel
    output  FcRszPxlData_t                          PxlData_d1,
    output  logic   [IMG_WIDTH_IDX_W-1:0]           PxlX_d1,
    output  logic   [IMG_HEIGHT_IDX_W-1:0]          PxlY_d1,
    output  logic                                   PxlVld_d1,
    input   logic                                   PxlRdy_d1,
    // Resized Pixel Forwarder
    input   logic                                   FwdRszEn,       // Resizer just forwarded   
    // Processed Image information
    output  logic   [IMG_WIDTH_IDX_W-1:0]           ProcImgWidth,   // Processed Image's width
    output  logic   [IMG_HEIGHT_IDX_W-1:0]          ProcImgHeight,  // Processed Image's height
    // Resizer Compute Engine
    output  logic                                   IsFstPxl,       // The current pixel is the first
    output  logic                                   PxlCap,         // Pixel is captured
    output  logic   [BLK_WIDTH_MAX_SZ_W-1:0]        BlkSzHor,       // Horizontal Block Size
    output  logic   [BLK_HEIGHT_MAX_SZ_W-1:0]       BlkSzVer,       // Vertical Block Size
    output  logic                                   RszImgComp      // Resizing image is completed
    );
    /* 
    TODO: We can reduce the resource by merging PxlX, PxlY and PxlData to 1 FIFO.
    However, the above approach will have a problem when PXL_PRIM_COLOR_NUM is greater 
    than 1 and we need flattern the PxlData to 1 flatterned array and push it in FIFO, 
    which is more difficult to debug.
    Therefore, in the early version of Design, I separated them into multiple FIFOs 
    */
    
    localparam PXL_INFO_W   = IMG_WIDTH_IDX_W + IMG_HEIGHT_IDX_W;

    // Wire declaration
    logic                               CapEntImg;  // Captured the entire image already, used for back-pressure
    logic                               ConvPxlVld;
    logic                               PxlInfoRdy;
    logic   [PXL_PRIM_COLOR_NUM-1:0]    PxlPayldRdy;
    logic                               ConvPxlRdy_d1;
    logic                               PxlInfoVld_d1;
    logic   [PXL_PRIM_COLOR_NUM-1:0]    PxlPayldVld_d1;
    // Reg declaration
    logic   [IMG_WIDTH_IDX_W-1:0]       PxlCntHor;      // Horizontal Pixel Counter
    logic   [IMG_HEIGHT_IDX_W-1:0]      PxlCntVer;      // Vertical Pixel Counter
    logic   [IMG_WIDTH_IDX_W-1:0]       PopPxlCntHor;   // Horizontal Pixel Counter
    logic   [IMG_HEIGHT_IDX_W-1:0]      PopPxlCntVer;   // Vertical Pixel Counter

    // Handshake control
    assign PxlRdy           = (PxlInfoRdy & &PxlPayldRdy) & ~CapEntImg; // All FIFOs are ready to be pushed and the all pixels in 1 image has not captured yet
    assign ConvPxlVld       = PxlVld & PxlRdy; 
    assign PxlVld_d1        = PxlInfoVld_d1 & &PxlPayldVld_d1;
    assign ConvPxlRdy_d1    = PxlRdy_d1 & PxlVld_d1; // All FIFOs are ready to be popped
    // Block calculation
generate
    if( ((RSZ_IMG_WIDTH_SIZE  & (RSZ_IMG_WIDTH_SIZE-1))  == 0) &      // Resized width is power-of-2
        ((RSZ_IMG_HEIGHT_SIZE & (RSZ_IMG_HEIGHT_SIZE-1)) == 0)) begin // Resized height is power-of-2
        
        assign BlkSzHor         = ProcImgWidth[IMG_WIDTH_IDX_W-1-:BLK_WIDTH_MAX_SZ_W];    // = ProcImgWidth / ResizedImgWidth
        assign BlkSzVer         = ProcImgHeight[IMG_HEIGHT_IDX_W-1-:BLK_HEIGHT_MAX_SZ_W]; // = ProcImgHeight / ResizedImgHeight
    end
    else begin
        $warning("[WARN]: The resized width or height is not a power-of-2");
        /* 
        TODO: Find a solution to handle the case where the resized width or height is not power-of-2
        -> Use lookup table for division operator
        */
    end
endgenerate

    // Pixel Information (Width + Height)
    sync_fifo #(
        .FIFO_TYPE      (1),
        .DATA_WIDTH     (PXL_INFO_W),
        .FIFO_DEPTH     (2) // To keep 100% throughput
    ) PxlInfoBuf (
        .clk            (Clk),
        .data_i         ({PxlX,     PxlY}),
        .wr_valid_i     (ConvPxlVld),
        .wr_ready_o     (PxlInfoRdy),
        .data_o         ({PxlX_d1,  PxlY_d1}),
        .rd_ready_o     (PxlInfoVld_d1),
        .rd_valid_i     (ConvPxlRdy_d1),
        .empty_o        (),
        .full_o         (),
        .almost_empty_o (),
        .almost_full_o  (),
        .counter        (),
        .rst_n          (~Reset)
    );
    // Pixel Payload
    generate
    for (genvar i=0; i < PXL_PRIM_COLOR_NUM; i = i + 1) begin : Gen_PrimColorBuf
        sync_fifo #(
            .FIFO_TYPE      (1),
            .DATA_WIDTH     (PXL_PRIM_COLOR_W),
            .FIFO_DEPTH     (2) // To keep 100% throughput
        ) PxlPayldBuf (
            .clk            (Clk),
            .data_i         (PxlData[i]),
            .wr_valid_i     (ConvPxlVld),
            .wr_ready_o     (PxlPayldRdy[i]),
            .data_o         (PxlData_d1[i]),
            .rd_ready_o     (PxlPayldVld_d1[i]),
            .rd_valid_i     (ConvPxlRdy_d1),
            .empty_o        (),
            .full_o         (),
            .almost_empty_o (),
            .almost_full_o  (),
            .counter        (),
            .rst_n          (~Reset)
        );
    end
    endgenerate

    // Flip-flop
    always_ff @(posedge Clk) begin
        if(Reset) begin
            ProcImgWidth    <= '1;
            ProcImgHeight   <= '1;
        end
        else if(ConvPxlVld & IsFstPxl) begin // Capture only when the first pixel is accepted 
            ProcImgWidth    <= ImgWidth;
            ProcImgHeight   <= ImgHeight;
        end
    end

    // Capturing pixels from Backward of Resizer
    assign PxlCap   = ConvPxlVld;
    always_ff @(posedge Clk) begin
        if(Reset) begin
          PxlCntHor <= '0;
          PxlCntVer <= '0;
          CapEntImg <= '0;
        end
        else begin
          if(PxlCap) begin
            PxlCntHor <= PxlCntHor + 1'b1;
            if(PxlCntHor == (ProcImgWidth - 1'b1)) begin
              PxlCntHor <= '0;
              PxlCntVer <= PxlCntVer + 1'b1;
              CapEntImg <= PxlCntVer == (ProcImgHeight - 1'b1); // Back-pressure when Last pixel is sent
            end
          end
          if(RszImgComp) begin
            PxlCntHor <= '0;
            PxlCntVer <= '0;
            CapEntImg <= '0;
          end
        end
    end
    assign IsFstPxl     = (~|PxlCntHor & ~|PxlCntVer) & PxlCap; // (PxlCntHor == 0 and PxlCntVer == 0) and 1 pixel is captured
    
generate
    if(RSZ_PXL_FWD_SER == 1) begin : SerialFwdLogic
        // Sending resized pixels to Forward of Resizer
        always_ff @(posedge Clk) begin
            if(Reset) begin
                PopPxlCntHor  <= '0;
                PopPxlCntVer  <= '0;
            end
            else if(FwdRszEn) begin
                PopPxlCntHor <= PopPxlCntHor + 1'b1;
                if(PopPxlCntHor == (ProcImgWidth - 1'b1)) begin
                    PopPxlCntHor <= '0;
                    PopPxlCntVer <= PopPxlCntVer + 1'b1;
                    if(PopPxlCntVer == (ProcImgHeight - 1'b1)) begin
                        PopPxlCntVer <= '0;
                    end
                end
            end
        end
        assign RszImgComp = FwdRszEn &
                            (PopPxlCntHor == (ProcImgWidth - 1'b1)) &
                            (PopPxlCntVer == (ProcImgHeight - 1'b1)); // Last resized pixel is sent
    end
    else if(RSZ_PXL_FWD_SER == 0) begin : ParallelFwdLogic
        assign RszImgComp = FwdRszEn; // Entire image is forwarded        
    end
endgenerate
endmodule
