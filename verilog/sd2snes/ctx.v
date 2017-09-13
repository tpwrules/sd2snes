`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    06:25:58 08/12/2017 
// Design Name: 
// Module Name:    ctx
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module ctx(
  input clkin,
  input reset,
  input [23:0] SNES_ADDR,   // requested address from SNES
  input [7:0] SNES_PA,      // peripheral address from SNES
  input SNES_RD_end,        // READ from SNES
  input SNES_WR_end,        // WRITE from SNES
  input SNES_PARD_end,      // PARD from SNES
  input SNES_PAWR_end,      // PAWR from SNES
  input [7:0] SNES_DATA_IN,

  output OE_RD_ENABLE,
  output OE_WR_ENABLE,
  output OE_PAWR_ENABLE,
  output OE_PARD_ENABLE,

  output BUS_WRQ,
  input BUS_RDY,

  input snescmd_unlock,

  output [23:0] ROM_ADDR,   // Address to request from SRAM0
  output [15:0] ROM_DATA,    // Data to write to SRAM0
  output        ROM_WORD_ENABLE,

  //output [23:0] ROM_SNESCAST_ADDR,
  //output [15:0] ROM_SNESCAST_DATA,
  //output        ROM_SNESCAST_ENABLE,
  
  output        DBG
);

//-------------------
// handle WRAM writes - upper 7b ignored
//-------------------
reg [23:0] WRAM_ADDR;

// bank $00-$3F,$80-$BF
assign IS_WRAM_SHADOW_ADDR = !SNES_ADDR[22] && (SNES_ADDR[15:13] == 3'h0);
assign IS_WRAM_SHADOW = SNES_WR_end && IS_WRAM_SHADOW_ADDR;
assign IS_WRAM_BANK_ADDR = ({SNES_ADDR[23:17],1'b0} == 8'h7E);
assign IS_WRAM_BANK = SNES_WR_end && IS_WRAM_BANK_ADDR;
assign IS_WRAM_PA_ADDR = (SNES_PA == 8'h80);
assign IS_WRAM_PA = SNES_PAWR_end && IS_WRAM_PA_ADDR;

assign IS_WRAM_ADDR = IS_WRAM_SHADOW_ADDR | IS_WRAM_BANK_ADDR | IS_WRAM_PA_ADDR;
assign IS_WRAM = IS_WRAM_SHADOW | IS_WRAM_BANK | IS_WRAM_PA;

// flop register state
always @(posedge clkin) begin
  if (reset) begin
    WRAM_ADDR <= 0;
  end
  else begin
    if (SNES_PAWR_end | SNES_PARD_end) begin
      if      (SNES_PA == 8'h80) WRAM_ADDR[16: 0] <= WRAM_ADDR[16:0] + 1'b1;
    end
    if (SNES_PAWR_end) begin
      if      (SNES_PA == 8'h81) WRAM_ADDR[ 7: 0] <= SNES_DATA_IN;
      else if (SNES_PA == 8'h82) WRAM_ADDR[15: 8] <= SNES_DATA_IN;
      else if (SNES_PA == 8'h83) WRAM_ADDR[23:16] <= SNES_DATA_IN;
    end
  end
end

//-------------------
// handle VRAM writes
//-------------------
reg [7:0] r2115;
reg [15:0] VRAM_ADDR;

reg VRAM_ADDR_r; initial VRAM_ADDR_r = 0;
assign IS_VRAM_ADDR = VRAM_ADDR_r;
assign IS_VRAM = SNES_PAWR_end && IS_VRAM_ADDR;

// flop register state
always @(posedge clkin) begin
  if (reset) begin
    VRAM_ADDR_r <= 0;
  end
  else begin
    VRAM_ADDR_r <= (SNES_PA == 8'h18 || SNES_PA == 8'h19);
  end

  if (SNES_PARD_end) begin
    if      (SNES_PA == 8'h39 && ~r2115[7]) VRAM_ADDR[15:0] <= VRAM_ADDR[15:0] + ({r2115[1],1'b0,(~r2115[1] & r2115[0]),4'b0000,(~r2115[1] & ~r2115[0])});
    else if (SNES_PA == 8'h3A &&  r2115[7]) VRAM_ADDR[15:0] <= VRAM_ADDR[15:0] + ({r2115[1],1'b0,(~r2115[1] & r2115[0]),4'b0000,(~r2115[1] & ~r2115[0])});
  end
  else if (SNES_PAWR_end) begin
    if      (SNES_PA == 8'h15) r2115    [ 7: 0] <= SNES_DATA_IN;
    else if (SNES_PA == 8'h16) VRAM_ADDR[ 7: 0] <= SNES_DATA_IN;
    else if (SNES_PA == 8'h17) VRAM_ADDR[15: 8] <= SNES_DATA_IN;
    else if (SNES_PA == 8'h18 && ~r2115[7]) VRAM_ADDR[15:0] <= VRAM_ADDR[15:0] + ({r2115[1],1'b0,(~r2115[1] & r2115[0]),4'b0000,(~r2115[1] & ~r2115[0])});
    else if (SNES_PA == 8'h19 &&  r2115[7]) VRAM_ADDR[15:0] <= VRAM_ADDR[15:0] + ({r2115[1],1'b0,(~r2115[1] & r2115[0]),4'b0000,(~r2115[1] & ~r2115[0])});
  end
end

//-------------------
// handle APU writes
//-------------------
reg [7:0] r214x[3:0];
reg [15:0] APU_ADDR;
initial APU_ADDR = 0;
reg [2:0] APU_STATE;
initial APU_STATE = 0;

wire [7:0] APU_STATUS_COMPARE = (r214x[0] + 1) - SNES_DATA_IN;
wire [7:0] APU_SNES_PA = ({SNES_PA[7:6],4'b0000,SNES_PA[1:0]});

parameter APU_STATE_INIT = 0;
parameter APU_STATE_INIT_BB = 1;
parameter APU_STATE_INIT_AA = 2;
parameter APU_STATE_INIT_IDLE = 3;
parameter APU_STATE_IDLE = 4;
parameter APU_STATE_DATA_INIT = 5;
parameter APU_STATE_DATA = 6;
parameter APU_STATE_DONE = 7;

assign IS_APU_RAM = ((APU_STATE == APU_STATE_DATA_INIT) && (SNES_PAWR_end && (APU_SNES_PA == 8'h40) && (SNES_DATA_IN == 0)))
                  | ((APU_STATE == APU_STATE_DATA) && (SNES_PAWR_end && (APU_SNES_PA == 8'h40) && (APU_STATUS_COMPARE == 8'h00)));
// ignore writes when in done state
// ignore $2140 writes since we don't need that state and it frees up a slot for RAM writes
assign IS_APU_PORT = SNES_PAWR_end && ({SNES_PA[7:6],6'b000000} == 8'h40) && (|SNES_PA[1:0]) && (APU_STATE != APU_STATE_DONE);
assign IS_APU = IS_APU_RAM | IS_APU_PORT;

assign IS_APU_PORT_ADDR = {SNES_PA[7:6],6'b000000} == 8'h40;

always @(posedge clkin) begin
  if (reset) begin
    APU_STATE <= 0;
	  APU_ADDR <= 0;
	 
	  r214x[0] <= 0;
	  r214x[1] <= 0;
	  r214x[2] <= 0;
	  r214x[3] <= 0;
  end
  else begin
    // update register state on register write
    if (SNES_PAWR_end && IS_APU_PORT_ADDR) r214x[SNES_PA[1:0]] <= SNES_DATA_IN;

    // increment addresses on ram write
    if (IS_APU_RAM) APU_ADDR <= APU_ADDR + 1;

    case (APU_STATE)
      APU_STATE_INIT: begin
        // INIT wait for read of AA or BB
	     if (SNES_PARD_end && (APU_SNES_PA == 8'h40)) begin
          if (SNES_DATA_IN == 8'hAA) APU_STATE <= APU_STATE_INIT_BB;
		  end
  	     else if (SNES_PARD_end && (APU_SNES_PA == 8'h41)) begin
		    if (SNES_DATA_IN == 8'hBB) APU_STATE <= APU_STATE_INIT_AA;
		  end
	   end
	   APU_STATE_INIT_BB: begin
        if (SNES_PARD_end && (APU_SNES_PA == 8'h41)) begin
          // INIT wait for read of BB
          if (SNES_DATA_IN == 8'hBB) APU_STATE <= APU_STATE_INIT_IDLE;
		  end
	   end
	   APU_STATE_INIT_AA: begin
        if (SNES_PARD_end && (APU_SNES_PA == 8'h40)) begin
          // INIT wait for read of AA
		    if (SNES_DATA_IN == 8'hAA) APU_STATE <= APU_STATE_INIT_IDLE;
		  end
	   end
      APU_STATE_INIT_IDLE: begin
        if (SNES_PAWR_end && (APU_SNES_PA == 8'h40) && (SNES_DATA_IN == 8'hCC)) begin
		    // exiting init, wait for write of CC
		    if   (r214x[1] == 8'h00) APU_STATE <= APU_STATE_DONE;
		    else                     APU_STATE <= APU_STATE_DATA_INIT;
			 
			 APU_ADDR <= {r214x[3],r214x[2]};
		  end
	   end
	   APU_STATE_DATA_INIT: begin
		  if (SNES_PAWR_end && (APU_SNES_PA == 8'h40) && (SNES_DATA_IN == 8'h00)) begin
          // wait for init of the offset field.  this is also the first write
		    APU_STATE <= APU_STATE_DATA;
		  end
	   end
	   APU_STATE_DATA: begin
		  // check for write that isn't +1
		  if (SNES_PAWR_end && (APU_SNES_PA == 8'h40) && APU_STATUS_COMPARE[7]) begin
		    if   (r214x[1] == 8'h00) APU_STATE <= APU_STATE_DONE;
		    else                     APU_STATE <= APU_STATE_DATA_INIT;
			 
			 APU_ADDR <= {r214x[3],r214x[2]};
		  end
		end
		APU_STATE_DONE: begin
		  // nothing to do here.  wait for reset
		end
    endcase
	 
  end
end


//-------------------
// handle CGRAM writes
//-------------------
// FIXME: need to model the internal flop to handle mid-word address changes
reg [8:0] CGRAM_ADDR;

assign IS_CGRAM_ADDR = (SNES_PA == 8'h22);
assign IS_CGRAM = SNES_PAWR_end && IS_CGRAM_ADDR;

// flop register state
always @(posedge clkin) begin
  if (SNES_PARD_end) begin
    if      (SNES_PA == 8'h3B) CGRAM_ADDR[8:0] <= CGRAM_ADDR[8:0] + 1'b1;
  end
  else if (SNES_PAWR_end) begin
    if      (SNES_PA == 8'h21) CGRAM_ADDR[8:0] <= {SNES_DATA_IN,1'b0};
    else if (SNES_PA == 8'h22) CGRAM_ADDR[8:0] <= CGRAM_ADDR[8:0] + 1'b1;
  end
end

//-------------------
// handle OAM writes
//-------------------
// FIXME: need to model the internal flop to handle mid-word address changes
reg [9:0] OAM_ADDR;

assign IS_OAM_ADDR = (SNES_PA == 8'h04);
assign IS_OAM = SNES_PAWR_end && IS_OAM_ADDR;

// flop register state
always @(posedge clkin) begin
  if (SNES_PARD_end) begin
	 if      (SNES_PA == 8'h38) OAM_ADDR[9:0] <= OAM_ADDR[9:0] + 1'b1;
  end
  else if (SNES_PAWR_end) begin
	 if      (SNES_PA == 8'h02) OAM_ADDR[9:0] <= {OAM_ADDR[9],SNES_DATA_IN,1'b0};
	 else if (SNES_PA == 8'h03) OAM_ADDR[9:0] <= {SNES_DATA_IN[0],OAM_ADDR[8:1],1'b0};
	 else if (SNES_PA == 8'h04) OAM_ADDR[9:0] <= OAM_ADDR[9:0] + 1'b1;
  end
end

//-------------------
// handle $21XX accesses
//-------------------

// WRITES
// $00-$03 // skip data $04
// $05-$17 // skip data $18-$19
// $1A-$21 // skip data $22
// $23-$33
// $81-$83 // skip data $80

// READ
// $34-$36 // skip latch and data registers
// $3C-$3F
reg [7:0] rBG, rM7;
reg PPUREG_WRITE_ADDR_r; initial PPUREG_WRITE_ADDR_r = 0;
reg PPUREG_READ_ADDR_r; initial PPUREG_READ_ADDR_r = 0;

assign IS_PPUREG_WRITE_ADDR = PPUREG_WRITE_ADDR_r;
assign IS_PPUREG_WRITE = SNES_PAWR_end && IS_PPUREG_WRITE_ADDR;

assign IS_PPUREG_READ_ADDR = PPUREG_READ_ADDR_r;
assign IS_PPUREG_READ = SNES_PARD_end && IS_PPUREG_READ_ADDR;

assign IS_PPUREG_ADDR = IS_PPUREG_WRITE_ADDR | IS_PPUREG_READ_ADDR;
assign IS_PPUREG = IS_PPUREG_WRITE | IS_PPUREG_READ;

// double
assign IS_BG0_DOUBLE_ADDR = (SNES_PA >= 8'h0D && SNES_PA <= 8'h0E);
assign IS_BGN_DOUBLE_ADDR = (SNES_PA >= 8'h0F && SNES_PA <= 8'h14);
assign IS_M7_DOUBLE_ADDR = (SNES_PA >= 8'h1B && SNES_PA <= 8'h20);

assign IS_BG_DOUBLE = SNES_PAWR_end && (IS_BG0_DOUBLE_ADDR || IS_BGN_DOUBLE_ADDR);
assign IS_M7_DOUBLE = SNES_PAWR_end && (IS_BG0_DOUBLE_ADDR || IS_M7_DOUBLE_ADDR);

always @(posedge clkin) begin
  if (reset) begin
    rBG <= 0;
    rM7 <= 0;
    
    PPUREG_WRITE_ADDR_r <= 0;
    PPUREG_READ_ADDR_r <= 0;
  end
  else begin
    if (IS_BG_DOUBLE) rBG <= SNES_DATA_IN;
    if (IS_M7_DOUBLE) rM7 <= SNES_DATA_IN;

    PPUREG_WRITE_ADDR_r <= ((SNES_PA <= 8'h33) || (SNES_PA > 8'h80)) && (SNES_PA != 8'h04) && (SNES_PA != 8'h18) && (SNES_PA != 8'h19) && (SNES_PA != 8'h22);
    PPUREG_READ_ADDR_r <= ((SNES_PA > 8'h33) && (SNES_PA <= 8'h3F)) && (SNES_PA != 8'h37) && (SNES_PA != 8'h38) && (SNES_PA != 8'h39) && (SNES_PA != 8'h3A) && (SNES_PA != 8'h3B);
  end
end

// handle double registers

//-------------------
// handle $42XX accesses.  Covers DMA
//-------------------
// WRITES
// $4200-$420F
// $4300-$43FF

// READ
// $4210-$421F
reg [7:0] r421x[15:0];
reg [2:0] CPUREG_STATE;
reg [3:0] CPUREG_ADDR;
reg       CPUREG_DOUBLE;
reg [7:0] CPUREG_INST[3:0];
reg [29:0] CPUREG_COUNTER;

integer i;
initial for (i = 0; i < 16; i = i + 1) r421x[i] = 0;
initial CPUREG_STATE = 0;

reg CPUREG_WRITE_ADDR_r; initial CPUREG_WRITE_ADDR_r = 0;
reg CPUREG_READ_ADDR_r; initial CPUREG_READ_ADDR_r = 0;

assign IS_CPUREG_WRITE_ADDR = CPUREG_WRITE_ADDR_r;
assign IS_CPUREG_WRITE = SNES_WR_end && IS_CPUREG_WRITE_ADDR;

assign IS_CPUREG_READ_ADDR = CPUREG_READ_ADDR_r;
assign IS_CPUREG_READ = SNES_RD_end && IS_CPUREG_READ_ADDR;

assign IS_CPUREG_ADDR = IS_CPUREG_WRITE_ADDR | IS_CPUREG_READ_ADDR;
assign IS_CPUREG = IS_CPUREG_WRITE | IS_CPUREG_READ;

always @(posedge clkin) begin
  if (reset) begin
    CPUREG_WRITE_ADDR_r <= 0;
    CPUREG_READ_ADDR_r <= 0;
  end
  else begin
    CPUREG_WRITE_ADDR_r <= ({1'b0,SNES_ADDR[22],6'b000000, SNES_ADDR[15:4], 4'b0000} == 24'h04200) || ({1'b0,SNES_ADDR[22],6'b000000, SNES_ADDR[15:8], 8'b00000000} == 24'h04300);
    CPUREG_READ_ADDR_r <= {1'b0,SNES_ADDR[22],6'b000000, SNES_ADDR[15:4], 4'b0000} == 24'h04210;
  end
end

always @(posedge clkin) begin
  if (reset || (~|CPUREG_COUNTER)) begin
    // don't zero out the non-counter state outside of reset
    if (reset) for (i = 0; i < 8; i = i + 1) r421x[i] <= 0;
    for (i = 8; i < 16; i = i + 1) r421x[i] <= 0;
    CPUREG_STATE <= 0;
    CPUREG_COUNTER <= 30'd24000000;
  end
  else begin
    if (|CPUREG_COUNTER) begin
      CPUREG_COUNTER <= CPUREG_COUNTER - 1;
    end

    if (SNES_RD_end) begin
      CPUREG_INST[3] <= CPUREG_INST[2];
      CPUREG_INST[2] <= CPUREG_INST[1];
      CPUREG_INST[1] <= CPUREG_INST[0];
      CPUREG_INST[0] <= SNES_DATA_IN;
    end
  
    case (CPUREG_STATE)
      0: begin
        // watch for read of $18
        // ignore read during NMI hook since it usually gets prelatched data (00 or other)
        // ignore AND in capcom games which is trying to capture differences from the previous frame
        if (!snescmd_unlock && IS_CPUREG_READ && ({CPUREG_INST[2][7:5],1'h0,CPUREG_INST[2][3:0],CPUREG_INST[1][7:4],4'h0,CPUREG_INST[0]} != 24'h2D1042)) begin
          CPUREG_STATE <= 1;
          CPUREG_ADDR <= SNES_ADDR[3:0];
          CPUREG_DOUBLE <= 0;
        end
      end      
      1: begin
        // watch for read of +1
        if (IS_CPUREG_READ && (SNES_ADDR[3:0] == CPUREG_ADDR[3:0] + 1)) begin
          CPUREG_STATE <= 2;
          CPUREG_DOUBLE <= 1;
        end
        else if (SNES_RD_end && ({SNES_DATA_IN[7:5],1'b0} == 4'h8) && ({1'b0,SNES_DATA_IN[2],1'b0,SNES_DATA_IN[0]} != 4'h0) && (SNES_DATA_IN[3:0] != 4'hB) && (SNES_DATA_IN[7:0] != 8'h99)) begin
          // single
          CPUREG_STATE <= 3;
        end
        else if (SNES_RD_end | SNES_WR_end | SNES_PARD_end | SNES_PAWR_end) begin
          // reset
          CPUREG_STATE <= 0;
        end
      end
      2: begin
        // watch for immediate ST opcode
        if (SNES_RD_end && ({SNES_DATA_IN[7:5],1'b0} == 4'h8) && ({1'b0,SNES_DATA_IN[2],1'b0,SNES_DATA_IN[0]} != 4'h0) && (SNES_DATA_IN[3:0] != 4'hB) && (SNES_DATA_IN[7:0] != 8'h99)) begin
          CPUREG_STATE <= 3;
        end
        else if (SNES_RD_end | SNES_WR_end | SNES_PARD_end | SNES_PAWR_end) begin
          // reset
          CPUREG_STATE <= 0;
        end
      end
      3: begin
        // watch for data write low
        if (SNES_RD_end) begin
          // ok to read rest of opcode
          CPUREG_STATE <= 3;
        end
        else if (SNES_WR_end) begin
          // capture data
          r421x[CPUREG_ADDR] <= SNES_DATA_IN;
          CPUREG_STATE <= CPUREG_DOUBLE ? 4 : 0;
          // reset counter for zeroing out stale writes.  Only allow controller writes to do this.
          if (CPUREG_ADDR[3]) CPUREG_COUNTER <= 30'd24000000;
        end
        else if (SNES_RD_end | SNES_WR_end | SNES_PARD_end | SNES_PAWR_end) begin
          // reset
          CPUREG_STATE <= 0;
        end
      end
      4: begin
        // watch for data write high
        if (SNES_WR_end) begin
          // capture data
          r421x[CPUREG_ADDR + 1] <= SNES_DATA_IN;
          CPUREG_STATE <= 0;
        end
        else if (SNES_RD_end | SNES_WR_end | SNES_PARD_end | SNES_PAWR_end) begin
          // reset
          CPUREG_STATE <= 0;
        end
      end
    endcase
  end
end

//-------------------
// handle MISC accesses.
//-------------------
// This space has $E0 bytes for random crap

// gamepad is a hack.  the read happens at the start of the NMI which is likely to get invalid data.  it needs to be filtered.
assign IS_GAMEPAD_WRITE_ADDR = ({SNES_ADDR[23:1],1'b0} == 24'h002BF0);
assign IS_GAMEPAD_WRITE = SNES_WR_end && IS_GAMEPAD_WRITE_ADDR;

assign IS_MISC_ADDR = IS_GAMEPAD_WRITE_ADDR;
assign IS_MISC = IS_GAMEPAD_WRITE;

////-------------------
//// handle SNESCAST accesses.
////-------------------
//// This is a queued region where PPU writes reflected to for an external reader to parse
//reg [13:0] SNESCAST_ADDR;
//
//assign IS_SNESCAST_WRITE = IS_VRAM | IS_APU_PORT | IS_CGRAM | IS_OAM | IS_PPUREG_WRITE;
//assign IS_SNESCAST_NMI_ADDR_START = (SNES_ADDR == 24'h00FFEA);
//assign IS_SNESCAST_NMI_ADDR_END = (SNES_ADDR == 24'h00FFEB);
//assign IS_SNESCAST_NMI_END = SNES_RD_end && IS_SNESCAST_NMI_ADDR_END;
//assign IS_SNESCAST_NMI_START = SNES_RD_end && IS_SNESCAST_NMI_ADDR_START;
//assign IS_SNESCAST_NMI = IS_SNESCAST_NMI_START | IS_SNESCAST_NMI_END;
//assign IS_SNESCAST = IS_SNESCAST_WRITE | IS_SNESCAST_NMI;
//
//always @(posedge clkin) begin
//  if (reset) begin
//    SNESCAST_ADDR <= 0;
//  end
//  else begin
//    if (IS_SNESCAST_WRITE | IS_SNESCAST_NMI_START) begin
//      SNESCAST_ADDR <= SNESCAST_ADDR + 1;
//    end
//    else if (IS_SNESCAST_NMI_END) begin
//      // advance to the next buffer for the frame
//      SNESCAST_ADDR <= {SNESCAST_ADDR[13:8]+1,8'h00};
//    end
//  end
//end

//-------------------
// generate address
//-------------------
wire [23:0] SRAM_SNES_ADDR;
assign SRAM_SNES_ADDR[23:0] = IS_WRAM
                            ? (24'hF50000 + ( IS_WRAM_SHADOW ? SNES_ADDR[12:0]
								                            : IS_WRAM_BANK   ? SNES_ADDR[16:0]
									 			                    :                  WRAM_ADDR[16:0]))
								            : IS_VRAM
								            ? (24'hF70000 + ( (r2115[3:2] == 2'h0) ? ({VRAM_ADDR[14: 0],                              SNES_PA[0]})
                                            : (r2115[3:2] == 2'h1) ? ({VRAM_ADDR[14: 8],VRAM_ADDR[4:0],VRAM_ADDR[7:5],SNES_PA[0]})
                                            : (r2115[3:2] == 2'h2) ? ({VRAM_ADDR[14: 9],VRAM_ADDR[5:0],VRAM_ADDR[8:6],SNES_PA[0]})
                                            :                        ({VRAM_ADDR[14:10],VRAM_ADDR[6:0],VRAM_ADDR[9:7],SNES_PA[0]})))
                            : IS_APU
									          ? (24'hF80000 + ( IS_APU_RAM ? (APU_ADDR[15:0])
									                          :              (8'hF4 + SNES_PA[1:0])))
                            : IS_CGRAM
									          ? (24'hF90000 + CGRAM_ADDR[8:0])
                            : IS_OAM
									          ? (24'hF90200 + ( OAM_ADDR[9] ? (OAM_ADDR[9:0] & 10'h21F)
									                          :               (OAM_ADDR[9:0])))
				                    : IS_PPUREG
									          ? (24'hF90500 + {SNES_PA[7:0],1'b0})
				                    : IS_CPUREG
									          ? (24'hF90700 + SNES_ADDR[8:0])
									          : IS_MISC
									          ? (24'hF90420 + ( IS_GAMEPAD_WRITE ? ({7'h00,SNES_ADDR[0]})
									                          :                    (8'hDF)))
				                    //: IS_SNESCAST_NMI // SNESCAST temporary to not clobber other memory
									          //? (24'hFA0000 + SNESCAST_ADDR)
								            : 24'hF98000;

assign IS_WRITE = IS_WRAM | IS_VRAM | IS_CGRAM | IS_OAM | IS_APU | IS_PPUREG | IS_CPUREG | IS_MISC; // | IS_SNESCAST_NMI; // NMI for SNESCAST
assign IS_WORD = IS_PPUREG;

//// SNESCAST
//wire [23:0] SRAM_SNESCAST_ADDR;
//assign SRAM_SNESCAST_ADDR[23:0] = 24'hFA0000 + SNESCAST_ADDR;

// flop request
reg REQ;
initial REQ = 1'b0;
reg [23:0] ADDR;
initial ADDR = 24'h0;
reg [15:0] DATA;
initial DATA = 16'h0000;
reg WORD;
initial WORD = 0;

//reg [23:0] SC_ADDR;
//initial SC_ADDR = 24'h0;
//reg [15:0] SC_DATA;
//initial SC_DATA = 16'h0000;
//reg SC_ENABLE;
//initial SC_ENABLE = 0;

// doubles
wire [7:0] DATA_SINGLE_IN = IS_CPUREG_READ ? r421x[SNES_ADDR[3:0]] : IS_APU_RAM ? r214x[1] : SNES_DATA_IN[7:0];

always @(posedge clkin) begin
  if (IS_WRITE) begin
	 // this is only asserted once as the main code flops it
    REQ <= 1;
    ADDR[23:0] <= SRAM_SNES_ADDR[23:0];
    // The following handles double writes.  This approximates the data value used to assign
    // the register by assigning the lower byte based on a past write.  Note that M7 double 
    // overlaps with BG so BG should have priority when assigning data
    DATA[15:0] <= { DATA_SINGLE_IN, (IS_BG_DOUBLE ? rBG : IS_M7_DOUBLE ? rM7 : DATA_SINGLE_IN) };
    WORD <= IS_WORD;
    
//    // SNESCAST
//    SC_ADDR <= SRAM_SNESCAST_ADDR;
//    SC_DATA <= IS_SNESCAST_NMI_START ? {8'hFF,8'h01} : IS_SNESCAST_NMI_END ? {8'hFF,8'h00} : {SNES_PA, SNES_DATA_IN};
//    SC_ENABLE <= IS_SNESCAST;
  end
  else if (REQ && BUS_RDY) begin
    REQ <= 0;
  end
end

// assign outputs
assign BUS_WRQ = REQ && BUS_RDY;
assign ROM_ADDR[23:0] = ADDR[23:0];
assign ROM_DATA[15:0] = DATA[15:0];
assign ROM_WORD_ENABLE = WORD;
//assign ROM_SNESCAST_ADDR = SC_ADDR[23:0];
//assign ROM_SNESCAST_DATA = SC_DATA[15:0];
//assign ROM_SNESCAST_ENABLE = SC_ENABLE;

// TODO: add assigns for these per group
assign OE_RD_ENABLE = IS_CPUREG_READ_ADDR;
assign OE_WR_ENABLE = IS_WRAM_SHADOW_ADDR || IS_WRAM_BANK_ADDR || IS_CPUREG_WRITE_ADDR || IS_MISC_ADDR;
assign OE_PAWR_ENABLE = IS_WRAM_PA_ADDR || (SNES_PA == 8'h15) || ({SNES_PA[7:1],1'b0} == 8'h16) || ({SNES_PA[7:1],1'b0} == 8'h18) || (SNES_PA[7:0] == 8'h21) || (SNES_PA[7:0] == 8'h22) || (SNES_PA[7:0] == 8'h02) || (SNES_PA[7:0] == 8'h03) || (SNES_PA[7:0] == 8'h04) || IS_APU_PORT_ADDR || IS_PPUREG_WRITE_ADDR;
assign OE_PARD_ENABLE = IS_APU_PORT_ADDR || IS_PPUREG_READ_ADDR;

assign DBG = |CPUREG_STATE;

endmodule
