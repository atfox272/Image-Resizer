module ImgRszCegDiv #(   
   // N/D = (Q,R)
   // This module is not well-tested, the author DOES NOT guarantee it produced correct outputs when it had to deal with negative N, D
   parameter NUMINATOR_W = 40,
   parameter DENOMINATOR_W = 32,
   parameter QUOTIENT_W = 8,     // MAKE SURE THE QUOTIENT IS SUSTAINABLE WITH ANY STIMULUS

   localparam DIGIT_COUNTER_W = $clog2(QUOTIENT_W),
   localparam EXTEND_W = ((NUMINATOR_W+1) > (DENOMINATOR_W+QUOTIENT_W)) ? NUMINATOR_W+2 : DENOMINATOR_W+QUOTIENT_W+2
)(
   // --- Glob --- //
   // Active-high Synchronous Reset
   input    logic                   Clk, Rst,

   // --- Backward Interface --- //
   input    logic [NUMINATOR_W-1:0]    Numinator,
   input    logic [DENOMINATOR_W-1:0]  Denominator,
   input    logic                      BwVld,
   output   logic                      BwRdy,

   // --- Forward Interface --- //
   output   logic [QUOTIENT_W-1:0]     Quotient,
   output   logic                      FwVld,
   input    logic                      FwRdy
);
   // --- Data Registered --- //
   logic          [NUMINATOR_W-1:0]    Numinator_reg;
   logic          [DENOMINATOR_W-1:0]  Denominator_reg;
   logic                               OprandEn;

   always_ff @(posedge Clk) begin
      if (OprandEn) begin
         Numinator_reg     <= Numinator;
         Denominator_reg   <= Denominator;
      end
   end

   // --- Restoring Division Accelerator --- //
   logic signed   [EXTEND_W-1:0]    N_ext, D_ext;
   logic signed   [EXTEND_W-1:0]    Remainder, RemainderShiftLeft;
   logic signed   [EXTEND_W-1:0]    DenominatorMul;
   logic signed   [EXTEND_W-1:0]    RemainderTrial;
   logic signed   [EXTEND_W-1:0]    RemainderRestore_d;
   logic signed   [EXTEND_W-1:0]    RemainderRestore_q;
   logic                            StillDiv;
   logic                            Remainder_isZero, Remainder_isPos, Remainder_isNeg;

   assign N_ext               = Numinator_reg;
   assign D_ext               = Denominator_reg;
   assign Remainder           = StillDiv ? RemainderRestore_q : N_ext;
   assign RemainderShiftLeft  = Remainder << 1;     //2R
   assign DenominatorMul      = D_ext << QUOTIENT_W;    //D*(2^n)
   assign RemainderTrial      = RemainderShiftLeft - DenominatorMul;
   
   assign Remainder_isZero = (RemainderTrial == 0);
   assign Remainder_isPos  = (RemainderTrial >= 0);   // Troll
   assign Remainder_isNeg  = (RemainderTrial < 0);

   assign RemainderRestore_d = Remainder_isNeg ? RemainderShiftLeft : RemainderTrial;

   always_ff @(posedge Clk)   RemainderRestore_q <= RemainderRestore_d;

   // --- Quotient controller --- //
   logic [QUOTIENT_W-1:0]        QuotientMem;
   logic [DIGIT_COUNTER_W-1:0]   DigitIdx;
   logic                         Digit;
   logic                         QuotientMemClr, QuotientMemEn;
   logic                         DigitCounterClr, DigitCounterEn;

   assign Quotient = QuotientMem;
   assign Digit = Remainder_isPos;

   always_ff @(posedge Clk) begin
      if (Rst) begin
         QuotientMem <= '0;
      end
      else begin
         if       (QuotientMemClr)  QuotientMem <= '0;
         else if  (QuotientMemEn)   QuotientMem[DigitIdx] <= Digit; 
      end
   end

   always_ff @(posedge Clk) begin
      if (Rst) begin
         DigitIdx <= QUOTIENT_W-1;
      end
      else begin
         if       (DigitCounterClr)  DigitIdx <= QUOTIENT_W-1;
         else if  (DigitCounterEn)   DigitIdx <= DigitIdx - 1'b1;        
      end
   end


   // --- Restoring Division Controller (RDC) --- // 
   // --- Recurrence Equation: R_(j+1) = BxR_j - q_(n-(j+1))xD
   typedef enum {
      Idle_s,
      Div_s,
      DivStill_s,
      DivDone_s
   }  RDCFsm_t;

   RDCFsm_t State, NextState;
   
   always_ff @(posedge Clk) begin
      if (Rst) begin
         State <= Idle_s;
      end
      else begin
         State <= NextState;
      end
   end

   always_comb begin
      NextState = State;
      case (State)
         Idle_s:
         begin
            if (BwVld)  NextState = Div_s;
            else        NextState = Idle_s;
         end
         Div_s:
         begin
            if (Remainder_isZero)   NextState = DivDone_s;
            else                    NextState = DivStill_s;
         end
         DivStill_s:
         begin
            if (Remainder_isZero)   NextState = DivDone_s;
            else begin
               if (DigitIdx != 0)   NextState = DivStill_s;
               else                 NextState = DivDone_s;
            end
         end
         DivDone_s:
         begin
            if (FwRdy)  NextState = Idle_s;
            else        NextState = DivDone_s;
         end
      default: NextState = Idle_s;
      endcase
   end

   always_comb begin
      case (State)
         Idle_s      : {BwRdy, OprandEn, StillDiv, DigitCounterEn, DigitCounterClr, QuotientMemEn, QuotientMemClr, FwVld} = 8'b1100_1010;
         Div_s       : {BwRdy, OprandEn, StillDiv, DigitCounterEn, DigitCounterClr, QuotientMemEn, QuotientMemClr, FwVld} = 8'b0001_0100;
         DivStill_s  : {BwRdy, OprandEn, StillDiv, DigitCounterEn, DigitCounterClr, QuotientMemEn, QuotientMemClr, FwVld} = 8'b0011_0100;
         DivDone_s   : {BwRdy, OprandEn, StillDiv, DigitCounterEn, DigitCounterClr, QuotientMemEn, QuotientMemClr, FwVld} = 8'b0000_0001; //00x0_x001
         default     : {BwRdy, OprandEn, StillDiv, DigitCounterEn, DigitCounterClr, QuotientMemEn, QuotientMemClr, FwVld} = 8'b1100_1010;
      endcase
   end

endmodule