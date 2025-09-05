
`timescale 1ns/1ps

module ImgRsz_tb;
    import ImgRszPkg::*;

    parameter DT_IMG_WIDTH  = 128;
    parameter DT_IMG_HEIGHT = 64;
    
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
    logic           [RSZ_IMG_HEIGHT_SIZE-1:0]  [RSZ_IMG_WIDTH_SIZE-1:0]  RszPxlParVld;  // Block is executed by Compute Engine
    
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
        #100000; $finish; 
    end
    
    initial begin
        logic [PXL_PRIM_COLOR_W-1:0] PxlDataTemp [PXL_PRIM_COLOR_NUM-1:0];
        #20;
        Cl;
        for (int y=0; y<DT_IMG_HEIGHT; y++) begin
            for (int x=0; x<DT_IMG_WIDTH; x++) begin
                PxlDataTemp[0] = x;
                PxlStDrv(.Data(PxlDataTemp), .X(x), .Y(y),
                .Width(DT_IMG_WIDTH), .Height(DT_IMG_HEIGHT));
            end
        end
    end
    
    initial begin
        FcRszPxlData_t                          RszPxlDataTemp;
        logic        [RSZ_IMG_WIDTH_IDX_W-1:0]  RszPxlXTemp;
        logic        [RSZ_IMG_HEIGHT_IDX_W-1:0] RszPxlYTemp;
        while (1'b1) begin
            RszPxlSamp( .SampRszPxlData (RszPxlDataTemp),
                        .SampRszPxlX    (RszPxlXTemp),
                        .SampRszPxlY    (RszPxlYTemp));
            $display("[INFO]: Resized Pixel     |   Data-%d  |    X-%d   |   Y-%d    |", RszPxlDataTemp[0], RszPxlXTemp, RszPxlYTemp);
        end
        
    end

    // Pixel Streaming Driver
    task PxlStDrv(
        input [PXL_PRIM_COLOR_W-1:0]    Data     [PXL_PRIM_COLOR_NUM-1:0],
        input [IMG_WIDTH_IDX_W-1:0]     X,
        input [IMG_HEIGHT_IDX_W-1:0]    Y,
        input [IMG_WIDTH_IDX_W-1:0]     Width,
        input [IMG_HEIGHT_IDX_W-1:0]    Height
    );
        for (int i=0; i<PXL_PRIM_COLOR_NUM; i++) begin
            PxlData[i] = Data[i];
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