`timescale 1 ns / 1 ns
//////////////////////////////////////////////////////////////////////////////////
// Company: Rehkopf
// Engineer: Rehkopf
//
// Create Date:    01:13:46 05/09/2009
// Design Name:
// Module Name:    address
// Project Name:
// Target Devices:
// Tool versions:
// Description: Address logic w/ SaveRAM masking
//
// Dependencies:
//
// Revision:
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module address(
  input CLK,
  input [7:0] featurebits,
  input [2:0] MAPPER,       // MCU detected mapper
  input [23:0] SNES_ADDR,   // requested address from SNES
  input [7:0] SNES_PA,      // peripheral address from SNES
  input SNES_ROMSEL,        // ROMSEL from SNES
  output [23:0] ROM_ADDR,   // Address to request from SRAM0
  output ROM_HIT,           // want to access RAM0
  output IS_SAVERAM,        // address/CS mapped as SRAM?
  output IS_ROM,            // address mapped as ROM?
  output IS_WRITABLE,       // address somehow mapped as writable area?
  input [23:0] SAVERAM_MASK,
  input [23:0] ROM_MASK,
  input map_unlock,
  output msu_enable,
  output usb_enable,
  output cx4_enable,
  output cx4_vect_enable,
  output r213f_enable,
  output snescmd_enable,
  output snescmd_reg_enable,
  output nmicmd_enable,
  output return_vector_enable,
  output branch1_enable,
  output branch2_enable
);

parameter [2:0]
  FEAT_MSU1 = 3,
  FEAT_213F = 4,
  FEAT_USB1 = 6
;

wire [23:0] SRAM_SNES_ADDR;

/* Cx4 mapper:
   - LoROM (extended to 00-7d, 80-ff)
   - MMIO @ 6000-7fff
   - SRAM @ 70-77:0000-7fff
 */

assign IS_ROM = ((!SNES_ADDR[22] & SNES_ADDR[15])
                 |(SNES_ADDR[22]));

assign IS_SAVERAM = (~map_unlock & (|SAVERAM_MASK)) & (~SNES_ADDR[23] & &SNES_ADDR[22:20] & ~SNES_ADDR[19] & ~SNES_ADDR[15]);

assign IS_PATCH = map_unlock & (&SNES_ADDR[23:20]);

// $1E-$1F:5000-5FFF -> $F9:E000-FFFF
assign IS_USB = featurebits[FEAT_USB1] && ({SNES_ADDR[23:17],1'b0,SNES_ADDR[15:12],12'h000} == 24'h1E5000);

assign SRAM_SNES_ADDR = IS_PATCH
                        ? SNES_ADDR
								: IS_USB
								? (24'hF9E000 + {SNES_ADDR[16],SNES_ADDR[11:0]})
                        : (IS_SAVERAM
                          ? (24'hE00000 | ({SNES_ADDR[19:16], SNES_ADDR[14:0]}
                           & SAVERAM_MASK))
                          : ({2'b00, SNES_ADDR[22:16], SNES_ADDR[14:0]}
                           & ROM_MASK));

// when unlocked provide a bank at the top of SRAM.  Note that unlock has a delay after we exit the handler
// so there is a possibility we'll read these addresses instead of ROM.  It would be safer to put this in an
// unused address that is unmapped
assign ROM_ADDR = SRAM_SNES_ADDR;

assign ROM_HIT = IS_ROM | IS_WRITABLE;

// FIXME: this may break DMAs from ROM to WRAM
assign IS_WRITABLE = IS_SAVERAM | (map_unlock & ((&SNES_ADDR[23:20]) | ~SNES_ROMSEL)) | IS_USB; // IS_PATCH

wire msu_enable_w = featurebits[FEAT_MSU1] & (!SNES_ADDR[22] && ((SNES_ADDR[15:0] & 16'hfff8) == 16'h2000));
assign msu_enable = msu_enable_w;
assign usb_enable = featurebits[FEAT_USB1] & (!SNES_ADDR[22] && ((SNES_ADDR[15:0] & 16'hfff8) == 16'h2010));

wire cx4_enable_w = (!SNES_ADDR[22] && (SNES_ADDR[15:13] == 3'b011));
assign cx4_enable = cx4_enable_w;

assign cx4_vect_enable = &SNES_ADDR[15:5];

assign r213f_enable = featurebits[FEAT_213F] & (SNES_PA == 8'h3f);

assign snescmd_enable = ({SNES_ADDR[22], SNES_ADDR[15:9]} == 8'b0_0010101);
assign snescmd_reg_enable = ({SNES_ADDR[22], SNES_ADDR[15:7],7'h00} == 17'h02B00);
assign nmicmd_enable = (SNES_ADDR == 24'h002BF2);
assign return_vector_enable = (SNES_ADDR == 24'h002A5A);
assign branch1_enable = (SNES_ADDR == 24'h002A13);
assign branch2_enable = (SNES_ADDR == 24'h002A4D);
endmodule
