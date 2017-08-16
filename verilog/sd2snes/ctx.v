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

  output OE_WR_ENABLE,
  output OE_PAWR_ENABLE,
  output OE_PARD_ENABLE,

  output BUS_WRQ,
  input BUS_RDY,

  output [23:0] ROM_ADDR,   // Address to request from SRAM0
  output [7:0] ROM_DATA     // Data to write to SRAM0
);

//-------------------
// handle WRAM writes - upper 7b ignored
//-------------------
reg [23:0] WRAM_ADDR;

// bank $00-$3F,$80-$BF
assign IS_WRAM_SHADOW = SNES_WR_end && ~SNES_ADDR[22] && (SNES_ADDR[15:13] == 3'h0);
assign IS_WRAM_BANK = SNES_WR_end && ({SNES_ADDR[23:17],1'b0} == 8'h7E);
assign IS_WRAM_PA = SNES_PAWR_end && (SNES_PA == 8'h80);

assign IS_WRAM = IS_WRAM_SHADOW | IS_WRAM_BANK | IS_WRAM_PA;

// flop register state
always @(posedge clkin) begin
  if (SNES_PAWR_end | SNES_PARD_end) begin
    if      (SNES_PA == 8'h80) WRAM_ADDR[16: 0] <= WRAM_ADDR[16:0] + 1'b1;
  end
  
  if (SNES_PAWR_end) begin
    if      (SNES_PA == 8'h81) WRAM_ADDR[ 7: 0] <= SNES_DATA_IN;
	 else if (SNES_PA == 8'h82) WRAM_ADDR[15: 8] <= SNES_DATA_IN;
	 else if (SNES_PA == 8'h83) WRAM_ADDR[23:16] <= SNES_DATA_IN;
  end
end

//-------------------
// handle VRAM writes
//-------------------
reg [7:0] r2115;
reg [15:0] VRAM_ADDR;

assign IS_VRAM = SNES_PAWR_end && (SNES_PA == 8'h18 || SNES_PA == 8'h19);

// flop register state
always @(posedge clkin) begin
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

//-------------------
// handle CGRAM writes
//-------------------
// FIXME: need to model the internal flop to handle mid-word address changes
reg [8:0] CGRAM_ADDR;

assign IS_CGRAM = SNES_PAWR_end && (SNES_PA == 8'h22);

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

assign IS_OAM = SNES_PAWR_end && (SNES_PA == 8'h04);

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
// generate address
//-------------------
wire [23:0] SRAM_SNES_ADDR;
assign SRAM_SNES_ADDR[23:0] = IS_WRAM
                            ? (24'hF50000 + ( IS_WRAM_SHADOW ? SNES_ADDR[15:0]
								                    : IS_WRAM_BANK ? SNES_ADDR[16:0]
									 			        : WRAM_ADDR[16:0]))
								    : IS_VRAM
								    ? (24'hF70000 + ( (r2115[3:2] == 2'h0) ? ({VRAM_ADDR[14:0],                               SNES_PA[0]})
                                            : (r2115[3:2] == 2'h1) ? ({VRAM_ADDR[14: 8],VRAM_ADDR[4:0],VRAM_ADDR[7:5],SNES_PA[0]})
                                            : (r2115[3:2] == 2'h2) ? ({VRAM_ADDR[14: 9],VRAM_ADDR[5:0],VRAM_ADDR[8:6],SNES_PA[0]})
                                            :                        ({VRAM_ADDR[14:10],VRAM_ADDR[6:0],VRAM_ADDR[9:7],SNES_PA[0]})))
                            : IS_CGRAM
									 ? (24'hF90000 + CGRAM_ADDR[8:0])
                            : IS_OAM
									 ? (24'hF90200 + ( OAM_ADDR[9] ? (OAM_ADDR[9:0] & 10'h21F)
									                 :               (OAM_ADDR[9:0])))
								    : 24'hF98000;

assign IS_WRITE = IS_WRAM | IS_VRAM | IS_CGRAM | IS_OAM;

// flop request
reg REQ;
initial REQ = 1'b0;
reg [23:0] ADDR;
initial ADDR = 24'h0;
reg [7:0] DATA;
initial DATA = 8'h0;
always @(posedge clkin) begin
  if (IS_WRITE) begin
	 // this is only asserted once as the main code flops it
    REQ <= 1;
    ADDR[23:0] <= SRAM_SNES_ADDR[23:0];
	 DATA[7:0] <= SNES_DATA_IN[7:0];
  end
  else if (REQ) begin
    REQ <= 0;
  end
end

// assign outputs
assign BUS_WRQ = REQ;
assign ROM_ADDR[23:0] = ADDR[23:0];
assign ROM_DATA[7:0] = DATA[7:0];

assign OE_WR_ENABLE = (~SNES_ADDR[22] && (SNES_ADDR[15:13] == 3'h0)) || ({SNES_ADDR[23:17],1'b0} == 8'h7E);
assign OE_PAWR_ENABLE = ({SNES_PA[7:2],2'b00} == 8'h80) || (SNES_PA == 8'h15) || ({SNES_PA[7:1],1'b0} == 8'h16) || ({SNES_PA[7:1],1'b0} == 8'h18) || (SNES_PA[7:0] == 8'h21) || (SNES_PA[7:0] == 8'h22) || (SNES_PA[7:0] == 8'h02) || (SNES_PA[7:0] == 8'h03) || (SNES_PA[7:0] == 8'h04);

endmodule
