
`timescale 1ns/1ps

module ImgRsz_tb;

    // Testbench configuration
    localparam PXL_ST_I_STALL_MIN   = 0;
    localparam PXL_ST_I_STALL_MAX   = 2;

    localparam PXL_ST_O_STALL_MIN   = 0;
    localparam PXL_ST_O_STALL_MAX   = 2;

    localparam DT_IMG_WIDTH  = 129;
    localparam DT_IMG_HEIGHT = 65;

    // Original Image configuration
    localparam IMG_WIDTH_MAX_SIZE    = 1024;
    localparam IMG_HEIGHT_MAX_SIZE   = 1024;
    localparam IMG_WIDTH_IDX_W       = $clog2(IMG_WIDTH_MAX_SIZE);
    localparam IMG_HEIGHT_IDX_W      = $clog2(IMG_HEIGHT_MAX_SIZE);
    // Resized Image configuration
    localparam RSZ_ALGORITHM         = "AVR-POOLING";    // Resizing Type: "AVR-POOLING" || "MAX-POOLING"
    localparam RSZ_IMG_WIDTH_SIZE    = 32;
    localparam RSZ_IMG_HEIGHT_SIZE   = 32;
    localparam RSZ_IMG_WIDTH_IDX_W   = $clog2(RSZ_IMG_WIDTH_SIZE);
    localparam RSZ_IMG_HEIGHT_IDX_W  = $clog2(RSZ_IMG_HEIGHT_SIZE);
    // Pixel configuration
    localparam PXL_PRIM_COLOR_NUM    = 1;    // Number of primary colors in 1 pixel  (Ex: RGB-3; YCbCr-3)
    localparam PXL_PRIM_COLOR_W      = 8;    // Width of each primary color element  (Ex: R-8;   Cb-8)
    // Forwarding configuartion
    localparam RSZ_PXL_FWD_SER       = 0;    // 1: Serial forwarding          || 0: Parallel forwarding
    localparam RSZ_PXL_FWD_TYP       = "ROW";// "PXL": Forwarding pixel mode  || "ROW": Forwarding row mode  || "COL": Forwarding column mode
    localparam RSZ_PXL_FWD_VLD_W     = (RSZ_PXL_FWD_SER == 1    ) ? 1                                       :   // For parallel forwarding; just need 1 handshaking port                                        :
                                      (RSZ_PXL_FWD_TYP == "ROW") ? RSZ_IMG_HEIGHT_SIZE                      :   // For row forwarding; need RSZ_IMG_HEIGHT_SIZE valid pins; associated to each row
                                      (RSZ_PXL_FWD_TYP == "COL") ? RSZ_IMG_WIDTH_SIZE                       :   // For row forwarding; need RSZ_IMG_WIDTH_SIZE valid pins; associated to each column
                                      (RSZ_PXL_FWD_SER == "PXL") ? RSZ_IMG_WIDTH_SIZE*RSZ_IMG_HEIGHT_SIZE   :   // For pixel forwarding; need all resized pixel valid pins
                                                                   0;                                           // Unsed
    localparam RSZ_PXL_FWD_RDY_W     = RSZ_PXL_FWD_VLD_W;                                                       // Same as Valid port (for handhshaking)
    // Compute Engine type
    localparam RSZ_AVR_DIV_TYPE      = 1;   // Used for frequence target - 0: Using combinational divider || 1: Using multi-cycle divider

    
    logic                                   Clk;
    logic                                   Reset;
    logic        [IMG_WIDTH_IDX_W-1:0]      ImgWidth;
    logic        [IMG_HEIGHT_IDX_W-1:0]     ImgHeight;
    logic        [PXL_PRIM_COLOR_W-1:0]     PxlData     [PXL_PRIM_COLOR_NUM-1:0];
    logic        [IMG_WIDTH_IDX_W-1:0]      PxlX;
    logic        [IMG_HEIGHT_IDX_W-1:0]     PxlY;
    logic                                   PxlVld;
    logic                                   PxlRdy;
    
    logic                                                       [PXL_PRIM_COLOR_W-1:0]      FwdRszPxlDat    [PXL_PRIM_COLOR_NUM-1:0];   // For serial pixel forwarding 
    logic                           [RSZ_IMG_WIDTH_SIZE-1:0]    [PXL_PRIM_COLOR_W-1:0]      FwdRszRowDat    [PXL_PRIM_COLOR_NUM-1:0];   // For serial row forwarding
    logic                           [RSZ_IMG_HEIGHT_SIZE-1:0]   [PXL_PRIM_COLOR_W-1:0]      FwdRszColDat    [PXL_PRIM_COLOR_NUM-1:0];   // For serial column forwarding
    logic [RSZ_IMG_HEIGHT_SIZE-1:0] [RSZ_IMG_WIDTH_SIZE-1:0]    [PXL_PRIM_COLOR_W-1:0]      FwdRszPxlBuf    [PXL_PRIM_COLOR_NUM-1:0];   // For parallel forwarding
    logic                                                       [RSZ_IMG_WIDTH_IDX_W-1:0]   FwdRszPosX;
    logic                                                       [RSZ_IMG_HEIGHT_IDX_W-1:0]  FwdRszPosY;
    logic                                                       [RSZ_PXL_FWD_VLD_W-1:0]     FwdRszVld;
    logic                                                       [RSZ_PXL_FWD_RDY_W-1:0]     FwdRszRdy;
    
    typedef struct packed {
        logic   [15:0]  PosX;
        logic   [15:0]  PosY;
        logic   [7:0]   Data;
    } PxlInfo_s;


    PxlInfo_s           PxlInfoMem      [0:IMG_WIDTH_MAX_SIZE*IMG_HEIGHT_MAX_SIZE-1];
    logic       [15:0]  ImgInfo         [0:1];
    PxlInfo_s           RszPxlInfoMem   [0:RSZ_IMG_WIDTH_SIZE*RSZ_IMG_HEIGHT_SIZE-1];
    
    ImgRsz #(
        .IMG_WIDTH_MAX_SIZE   (IMG_WIDTH_MAX_SIZE),  
        .IMG_HEIGHT_MAX_SIZE  (IMG_HEIGHT_MAX_SIZE),      
        .IMG_WIDTH_IDX_W      (IMG_WIDTH_IDX_W),  
        .IMG_HEIGHT_IDX_W     (IMG_HEIGHT_IDX_W),  
        .RSZ_ALGORITHM        (RSZ_ALGORITHM),
        .RSZ_IMG_WIDTH_SIZE   (RSZ_IMG_WIDTH_SIZE),  
        .RSZ_IMG_HEIGHT_SIZE  (RSZ_IMG_HEIGHT_SIZE),      
        .RSZ_IMG_WIDTH_IDX_W  (RSZ_IMG_WIDTH_IDX_W),      
        .RSZ_IMG_HEIGHT_IDX_W (RSZ_IMG_HEIGHT_IDX_W),      
        .PXL_PRIM_COLOR_NUM   (PXL_PRIM_COLOR_NUM),  
        .PXL_PRIM_COLOR_W     (PXL_PRIM_COLOR_W),  
        .RSZ_PXL_FWD_SER      (RSZ_PXL_FWD_SER),  
        .RSZ_PXL_FWD_TYP      (RSZ_PXL_FWD_TYP),  
        .RSZ_PXL_FWD_VLD_W    (RSZ_PXL_FWD_VLD_W),  
        .RSZ_PXL_FWD_RDY_W    (RSZ_PXL_FWD_RDY_W),  
        .RSZ_AVR_DIV_TYPE     (RSZ_AVR_DIV_TYPE)
    ) dut (
        .*
    );
    

    initial begin
        Clk         <= '0;
        Reset       <= '1;

        ImgWidth    <= '0;
        ImgHeight   <= '0;
        PxlX        <= '0;
        PxlY        <= '0;
        PxlVld      <= '0;

        FwdRszRdy   <= '0;

        #10;
        Reset       <= '0;
    end

    initial begin
        forever #1 Clk <= ~Clk;
    end
    
    
    initial begin
        #10000000; 
        $writememh("L:/Projects/ImageResizer/sim/env/RszPxlInfo.txt", RszPxlInfoMem);
        $finish; 
    end

    initial begin
        $readmemh("L:/Projects/ImageResizer/sim/env/PxlInfo.txt", PxlInfoMem);
        $readmemh("L:/Projects/ImageResizer/sim/env/ImgInfo.txt", ImgInfo);
    end

    initial begin
        logic [PXL_PRIM_COLOR_W-1:0] PxlDataTemp [PXL_PRIM_COLOR_NUM-1:0];
        int                          RandStall;
        #20;
        Cl;
        for (int y=0; y<ImgInfo[1]; y++) begin
            for (int x=0; x<ImgInfo[0]; x++) begin
                PxlStDrv(.Data  (PxlInfoMem[y*ImgInfo[0] + x].Data),
                         .X     (PxlInfoMem[y*ImgInfo[0] + x].PosX),
                         .Y     (PxlInfoMem[y*ImgInfo[0] + x].PosY),
                         .Width (ImgInfo[0]),
                         .Height(ImgInfo[1]));
            end
            // Random bubbles
            RandStall =  $urandom_range(PXL_ST_I_STALL_MIN, PXL_ST_I_STALL_MAX);
            repeat(RandStall) Cl;
        end
    end
    
    initial begin
        logic        [PXL_PRIM_COLOR_W-1:0]     RszPxlDataTemp [PXL_PRIM_COLOR_NUM-1:0];
        logic        [RSZ_IMG_WIDTH_IDX_W-1:0]  RszPxlXTemp;
        logic        [RSZ_IMG_HEIGHT_IDX_W-1:0] RszPxlYTemp;
        int                                     RandStall;
        #20;
        Cl;
        if(RSZ_PXL_FWD_SER == 1) begin  // Serial mode
            if(RSZ_PXL_FWD_TYP == "PXL") begin
                for (int y=0; y<RSZ_IMG_HEIGHT_SIZE; y++) begin
                    for (int x=0; x<RSZ_IMG_WIDTH_SIZE; x++) begin
                        RszPxlSamp( .SampRszPxlData (RszPxlDataTemp),
                                    .SampRszPxlX    (RszPxlXTemp),
                                    .SampRszPxlY    (RszPxlYTemp));
                        $display("[INFO]: Resized Pixel     |   Data-%d  |    X-%d   |   Y-%d    |", RszPxlDataTemp[0], RszPxlXTemp, RszPxlYTemp);
                        // Store the resized pixel
                        RszPxlInfoMem[y*RSZ_IMG_WIDTH_SIZE + x].Data = RszPxlDataTemp[0];
                        RszPxlInfoMem[y*RSZ_IMG_WIDTH_SIZE + x].PosX = (16)'(RszPxlXTemp);
                        RszPxlInfoMem[y*RSZ_IMG_WIDTH_SIZE + x].PosY = (16)'(RszPxlYTemp);
                        // Random bubbles
                        RandStall =  $urandom_range(PXL_ST_O_STALL_MIN, PXL_ST_O_STALL_MAX);
                        repeat(RandStall) Cl;
                    end
                end
            end
        end
        else if(RSZ_PXL_FWD_SER == 0) begin // Parallel mode
            if(RSZ_PXL_FWD_TYP == "ROW") begin
                $display("[INFO]: Start waiting ...");
                wait((&FwdRszVld) == 1); #1; Cl; // All rows is valid
                $display("[INFO]: Resizing image completed");
                for (int y=0; y<RSZ_IMG_HEIGHT_SIZE; y++) begin
                    for (int x=0; x<RSZ_IMG_WIDTH_SIZE; x++) begin
                        // Store the resized pixel
                        RszPxlInfoMem[y*RSZ_IMG_WIDTH_SIZE + x].Data = FwdRszPxlBuf[0][y][x];
                        RszPxlInfoMem[y*RSZ_IMG_WIDTH_SIZE + x].PosX = (16)'(x);
                        RszPxlInfoMem[y*RSZ_IMG_WIDTH_SIZE + x].PosY = (16)'(y);
                    end
                end
                
                // Handshake all rows
                FwdRszRdy = '1;
                Cl; 
            end
        end
        // $writememh("L:/Projects/ImageResizer/sim/env/RszPxlInfo.txt", RszPxlInfoMem);
    end

    // Pixel Streaming Driver
    task PxlStDrv(
        input [PXL_PRIM_COLOR_W-1:0]    Data,
        input [IMG_WIDTH_IDX_W-1:0]     X,
        input [IMG_HEIGHT_IDX_W-1:0]    Y,
        input [IMG_WIDTH_IDX_W-1:0]     Width,
        input [IMG_HEIGHT_IDX_W-1:0]    Height
    );
        for (int i=0; i<PXL_PRIM_COLOR_NUM; i++) begin
            PxlData[i] = Data;
        end
        PxlX        = X;
        PxlY        = Y;
        ImgWidth    = Width;
        ImgHeight   = Height;
        PxlVld      = 1'b1;
        wait(PxlRdy == 1'b1) #0.1;
        // Waiting for handshaking
        Cl;
        PxlVld      = 1'b0;
    endtask : PxlStDrv

    task RszPxlSamp(
        output logic        [PXL_PRIM_COLOR_W-1:0]     SampRszPxlData   [PXL_PRIM_COLOR_NUM-1:0],
        output logic        [RSZ_IMG_WIDTH_IDX_W-1:0]  SampRszPxlX,
        output logic        [RSZ_IMG_HEIGHT_IDX_W-1:0] SampRszPxlY
    );
        FwdRszRdy       = 1'b1;
        wait(|FwdRszVld == 1'b1) #0.1;
        for (int c = 0; c < PXL_PRIM_COLOR_NUM; c++) begin
            SampRszPxlData[c]  = FwdRszPxlDat[c];
        end
        SampRszPxlX     = FwdRszPosX;
        SampRszPxlY     = FwdRszPosY;
        // Wait for handshaking
        Cl;
        FwdRszRdy       = 1'b0;
    endtask : RszPxlSamp
    
    // Calib 1 cycle
    task Cl;
        @(posedge Clk) #0.1;
    endtask : Cl
    
endmodule