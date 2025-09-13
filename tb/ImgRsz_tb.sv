
`timescale 1ns/1ps

module ImgRsz_tb;
    import ImgRszPkg::*;

    // Testbench configuration
    localparam PXL_ST_I_STALL_MIN   = 0;
    localparam PXL_ST_I_STALL_MAX   = 2;

    localparam PXL_ST_O_STALL_MIN   = 0;
    localparam PXL_ST_O_STALL_MAX   = 2;

    localparam DT_IMG_WIDTH  = 129;
    localparam DT_IMG_HEIGHT = 65;
    
    logic                                   Clk;
    logic                                   Reset;
    logic        [IMG_WIDTH_IDX_W-1:0]      ImgWidth;
    logic        [IMG_HEIGHT_IDX_W-1:0]     ImgHeight;
    logic        [PXL_PRIM_COLOR_W-1:0]     PxlData     [PXL_PRIM_COLOR_NUM-1:0];
    logic        [IMG_WIDTH_IDX_W-1:0]      PxlX;
    logic        [IMG_HEIGHT_IDX_W-1:0]     PxlY;
    logic                                   PxlVld;
    logic                                   PxlRdy;
    FcRszPxlData_t                          RszPxlData;
    logic        [RSZ_IMG_WIDTH_IDX_W-1:0]  RszPxlX;
    logic        [RSZ_IMG_HEIGHT_IDX_W-1:0] RszPxlY;
    logic                                   RszPxlVld;
    logic                                   RszPxlRdy;
    FcRszPxlBuf_t                           FcRszPxlBuf; // Block accumulated value
    logic       [RSZ_IMG_HEIGHT_SIZE-1:0]   [RSZ_IMG_WIDTH_SIZE-1:0]  RszPxlParVld;  // Block is executed by Compute Engine
    
    typedef struct packed {
        logic   [15:0]  PosX;
        logic   [15:0]  PosY;
        logic   [7:0]   Data;
    } PxlInfo_s;


    PxlInfo_s           PxlInfoMem      [0:IMG_WIDTH_MAX_SIZE*IMG_HEIGHT_MAX_SIZE-1];
    logic       [15:0]  ImgInfo         [0:1];
    PxlInfo_s           RszPxlInfoMem   [0:RSZ_IMG_WIDTH_SIZE*RSZ_IMG_HEIGHT_SIZE-1];
    
    ImgRsz dut (.*);

    initial begin
        Clk         <= '0;
        Reset       <= '1;

        ImgWidth    <= '0;
        ImgHeight   <= '0;
        PxlX        <= '0;
        PxlY        <= '0;
        PxlVld      <= '0;

        RszPxlRdy   <= '0;

        #10;
        Reset       <= '0;
    end

    initial begin
        forever #1 Clk <= ~Clk;
    end
    
    
    initial begin
        #1000000; 
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
        FcRszPxlData_t                          RszPxlDataTemp;
        logic        [RSZ_IMG_WIDTH_IDX_W-1:0]  RszPxlXTemp;
        logic        [RSZ_IMG_HEIGHT_IDX_W-1:0] RszPxlYTemp;
        int                                     RandStall;
        #20;
        Cl;
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
        output FcRszPxlData_t                          SampRszPxlData,
        output logic        [RSZ_IMG_WIDTH_IDX_W-1:0]  SampRszPxlX,
        output logic        [RSZ_IMG_HEIGHT_IDX_W-1:0] SampRszPxlY
    );
        RszPxlRdy       = 1'b1;
        wait(RszPxlVld == 1'b1) #0.1;
        SampRszPxlData  = RszPxlData;
        SampRszPxlX     = RszPxlX;
        SampRszPxlY     = RszPxlY;
        // Wait for handshaking
        Cl;
        RszPxlRdy       = 1'b0;
    endtask : RszPxlSamp
    
    // Calib 1 cycle
    task Cl;
        @(posedge Clk) #0.1;
    endtask : Cl
    
endmodule