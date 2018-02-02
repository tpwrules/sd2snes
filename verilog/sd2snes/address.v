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
  input [7:0] featurebits,  // peripheral enable/disable
  input [2:0] MAPPER,       // MCU detected mapper
  input [23:0] SNES_ADDR_in,   // requested address from SNES
  input [7:0] SNES_PA,      // peripheral address from SNES
  input SNES_ROMSEL,        // ROMSEL from SNES
  output [23:0] ROM_ADDR,   // Address to request from SRAM0
  output ROM_HIT,           // enable SRAM0
  output IS_SAVERAM,        // address/CS mapped as SRAM?
  output IS_ROM,            // address mapped as ROM?
  output IS_WRITABLE,       // address somehow mapped as writable area?
  input [23:0] SAVERAM_MASK,
  input [23:0] ROM_MASK,
  output msu_enable,
  // config interface
  input [7:0] reg_group_in,
  input [7:0] reg_index_in,
  input [7:0] reg_value_in,
  input [7:0] reg_invmask_in,
  input       reg_we_in,
  input [7:0] reg_read_in,
  output[7:0] config_data_out,
  // config interface
  output srtc_enable,
  output use_bsx,
  output bsx_tristate,
  input [14:0] bsx_regs,
  output dspx_enable,
  output dspx_dp_enable,
  output dspx_a0,
  output r213f_enable,
  output snescmd_enable,
  output nmicmd_enable,
  output return_vector_enable,
  output branch1_enable,
  output branch2_enable,
  input [8:0] bs_page_offset,
  input [9:0] bs_page,
  input bs_page_enable
);

integer i;

parameter [2:0]
  FEAT_DSPX = 0,
  FEAT_ST0010 = 1,
  FEAT_SRTC = 2,
  FEAT_MSU1 = 3,
  FEAT_213F = 4
;

//wire [23:0] SNES_ADDR; assign SNES_ADDR = SNES_ADDR_in;
reg [23:0] SNES_ADDR_d0; always @(posedge CLK) SNES_ADDR_d0 <= SNES_ADDR_in;
reg [23:0] SNES_ADDR_d1; always @(posedge CLK) SNES_ADDR_d1 <= SNES_ADDR_d0;
reg [23:0] SNES_ADDR_d2; always @(posedge CLK) SNES_ADDR_d2 <= SNES_ADDR_d1;
reg [23:0] SNES_ADDR;    always @(posedge CLK) SNES_ADDR <= SNES_ADDR_d2;

wire [23:0] SRAM_SNES_ADDR;

// configuration state
parameter [3:0] ADDRMAP_REGISTERS = 8;

// Generic Address Map Support
parameter [3:0]
  ADDRMAP_MODE_64K = 4'h0,
  ADDRMAP_MODE_32K = 4'h1,
  ADDRMAP_MODE_16K = 4'h2,
  ADDRMAP_MODE_08K = 4'h3,
  ADDRMAP_MODE_04K = 4'h4,
  ADDRMAP_MODE_02K = 4'h5,
  ADDRMAP_MODE_01K = 4'h6
  //ADDRMAP_MODE_008 = 3'h7
;

parameter [3:0]
  ADDRMAP_TYPE_ROM = 4'h0,
  ADDRMAP_TYPE_RAM = 4'h2,
  
  ADDRMAP_TYPE_NOP = 4'hE,
  ADDRMAP_TYPE_DIS = 4'hF
;

reg [7:0] addrmap_r[ADDRMAP_REGISTERS*8-1:0]; initial for (i = 0; i < (ADDRMAP_REGISTERS*8); i = i + 1) addrmap_r[i] = 8'hFF;

always @(posedge CLK) begin
  if (reg_we_in && (reg_group_in == 8'h01)) begin
    if (reg_index_in < (ADDRMAP_REGISTERS*8)) addrmap_r[reg_index_in] <= (addrmap_r[reg_index_in] & reg_invmask_in) | (reg_value_in & ~reg_invmask_in);
  end
end

assign config_data_out = addrmap_r[reg_read_in];

// rename config register bytes
reg [2:0]  AddrMapMode[ADDRMAP_REGISTERS-1:0];
reg        AddrMapOutMaskMode[ADDRMAP_REGISTERS-1:0];
reg [3:0]  AddrMapType[ADDRMAP_REGISTERS-1:0];
reg [15:0] AddrMapBase[ADDRMAP_REGISTERS-1:0];
reg [7:0]  AddrMapOutBase[ADDRMAP_REGISTERS-1:0];
reg [15:0] AddrMapMask[ADDRMAP_REGISTERS-1:0];
reg [15:0] AddrMapOutMask[ADDRMAP_REGISTERS-1:0];

//reg [23:0] SpecialAddrMapBase[ADDRMAP_REGISTERS-1:0];
//reg [23:0] SpecialAddrMapMask[ADDRMAP_REGISTERS-1:0];

// workaround for problem with compiler
always @(addrmap_r[0],addrmap_r[1],addrmap_r[2],addrmap_r[3],addrmap_r[4],addrmap_r[5],addrmap_r[6],addrmap_r[7],
         addrmap_r[8],addrmap_r[9],addrmap_r[10],addrmap_r[11],addrmap_r[12],addrmap_r[13],addrmap_r[14],addrmap_r[15],
         addrmap_r[16],addrmap_r[17],addrmap_r[18],addrmap_r[19],addrmap_r[20],addrmap_r[21],addrmap_r[22],addrmap_r[23],
         addrmap_r[24],addrmap_r[25],addrmap_r[26],addrmap_r[27],addrmap_r[28],addrmap_r[29],addrmap_r[30],addrmap_r[31],
         addrmap_r[32],addrmap_r[33],addrmap_r[34],addrmap_r[35],addrmap_r[36],addrmap_r[37],addrmap_r[38],addrmap_r[39],
         addrmap_r[40],addrmap_r[41],addrmap_r[42],addrmap_r[43],addrmap_r[44],addrmap_r[45],addrmap_r[46],addrmap_r[47],
         addrmap_r[48],addrmap_r[49],addrmap_r[50],addrmap_r[51],addrmap_r[52],addrmap_r[53],addrmap_r[54],addrmap_r[55],
         addrmap_r[56],addrmap_r[57],addrmap_r[58],addrmap_r[59],addrmap_r[60],addrmap_r[61],addrmap_r[62],addrmap_r[63]
        ) begin
  for (i = 0; i < ADDRMAP_REGISTERS; i = i + 1) begin
    AddrMapMode[i] = addrmap_r[i*8+0][2:0];
    AddrMapOutMaskMode[i] = addrmap_r[i*8+0][3];
    AddrMapType[i] = addrmap_r[i*8+0][7:4];
    AddrMapBase[i] = {addrmap_r[i*8+2], addrmap_r[i*8+1]};
    AddrMapOutBase[i] = addrmap_r[i*8+3];
    AddrMapMask[i] = {addrmap_r[i*8+5], addrmap_r[i*8+4]};
    AddrMapOutMask[i] = {addrmap_r[i*8+7], addrmap_r[i*8+6]};

    //SpecialAddrMapBase[i][23:0] = {addrmap_r[i*8+3], addrmap_r[i*8+2], addrmap_r[i*8+1]};
    //SpecialAddrMapMask[i][23:0] = {addrmap_r[i*8+6], addrmap_r[i*8+5], addrmap_r[i*8+4]};
  end
end

// Check for AddrMapMatchValid 
reg        AddrMapMatchValid;
reg [2:0]  AddrMapModeMatch;
reg [3:0]  AddrMapTypeMatch;
reg [7:0]  AddrMapOutBaseMatch;
reg [15:0] AddrMapOutMaskMatch;
reg        AddrMapOutMaskModeMatch;

reg        AddrMapMatchValid_d2;
reg [2:0]  AddrMapModeMatch_d2;
reg [3:0]  AddrMapTypeMatch_d2;
reg [7:0]  AddrMapOutBaseMatch_d2;
reg [15:0] AddrMapOutMaskMatch_d2;
reg        AddrMapOutMaskModeMatch_d2;

reg [2:0]  AddrMapIndexMatch;
//always @(AddrMapMode[0], AddrMapType[0], AddrMapBase[0], AddrMapMask[0], AddrMapOutBase[0], AddrMapOutMask[0], AddrMapOutMaskMode[0],
//         AddrMapMode[1], AddrMapType[1], AddrMapBase[1], AddrMapMask[1], AddrMapOutBase[1], AddrMapOutMask[1], AddrMapOutMaskMode[1],
//         AddrMapMode[2], AddrMapType[2], AddrMapBase[2], AddrMapMask[2], AddrMapOutBase[2], AddrMapOutMask[2], AddrMapOutMaskMode[2],
//         AddrMapMode[3], AddrMapType[3], AddrMapBase[3], AddrMapMask[3], AddrMapOutBase[3], AddrMapOutMask[3], AddrMapOutMaskMode[3],
//         AddrMapMode[4], AddrMapType[4], AddrMapBase[4], AddrMapMask[4], AddrMapOutBase[4], AddrMapOutMask[4], AddrMapOutMaskMode[4],
//         AddrMapMode[5], AddrMapType[5], AddrMapBase[5], AddrMapMask[5], AddrMapOutBase[5], AddrMapOutMask[5], AddrMapOutMaskMode[5],
//         AddrMapMode[6], AddrMapType[6], AddrMapBase[6], AddrMapMask[6], AddrMapOutBase[6], AddrMapOutMask[6], AddrMapOutMaskMode[6],
//         AddrMapMode[7], AddrMapType[7], AddrMapBase[7], AddrMapMask[7], AddrMapOutBase[7], AddrMapOutMask[7], AddrMapOutMaskMode[7],
//         SNES_ADDR_d0
//        ) begin
always @(posedge CLK) begin
  if      ((AddrMapType[0] != ADDRMAP_TYPE_DIS) && (AddrMapBase[0] == (SNES_ADDR_d0[23:8] & AddrMapMask[0]))) begin
    AddrMapIndexMatch <= 0;
  end
  else if ((AddrMapType[1] != ADDRMAP_TYPE_DIS) && (AddrMapBase[1] == (SNES_ADDR_d0[23:8] & AddrMapMask[1]))) begin
    AddrMapIndexMatch <= 1;
  end
  else if ((AddrMapType[2] != ADDRMAP_TYPE_DIS) && (AddrMapBase[2] == (SNES_ADDR_d0[23:8] & AddrMapMask[2]))) begin
    AddrMapIndexMatch <= 2;
  end
  else if ((AddrMapType[3] != ADDRMAP_TYPE_DIS) && (AddrMapBase[3] == (SNES_ADDR_d0[23:8] & AddrMapMask[3]))) begin
    AddrMapIndexMatch <= 3;
  end
  else if ((AddrMapType[4] != ADDRMAP_TYPE_DIS) && (AddrMapBase[4] == (SNES_ADDR_d0[23:8] & AddrMapMask[4]))) begin
    AddrMapIndexMatch <= 4;
  end
  else if ((AddrMapType[5] != ADDRMAP_TYPE_DIS) && (AddrMapBase[5] == (SNES_ADDR_d0[23:8] & AddrMapMask[5]))) begin
    AddrMapIndexMatch <= 5;
  end
  else if ((AddrMapType[6] != ADDRMAP_TYPE_DIS) && (AddrMapBase[6] == (SNES_ADDR_d0[23:8] & AddrMapMask[6]))) begin
    AddrMapIndexMatch <= 6;
  end
  else if ((AddrMapType[7] != ADDRMAP_TYPE_DIS) && (AddrMapBase[7] == (SNES_ADDR_d0[23:8] & AddrMapMask[7]))) begin
    AddrMapIndexMatch <= 7;
  end
  else begin
    AddrMapIndexMatch <= 0;
  end
end

always @(posedge CLK) begin
    AddrMapMatchValid_d2 <= AddrMapType[AddrMapIndexMatch][3:1] != 3'b111;
    AddrMapModeMatch_d2 <= AddrMapMode[AddrMapIndexMatch];
    AddrMapOutMaskModeMatch_d2 <= AddrMapOutMaskMode[AddrMapIndexMatch];
    AddrMapTypeMatch_d2 <= AddrMapType[AddrMapIndexMatch];
    AddrMapOutBaseMatch_d2 <= AddrMapOutBase[AddrMapIndexMatch];
    AddrMapOutMaskMatch_d2 <= AddrMapOutMask[AddrMapIndexMatch];
end

// Generate address
reg [23:0] CalcAddr;
always @(posedge CLK) begin
  case (AddrMapModeMatch)
    0: CalcAddr <= {          SNES_ADDR_d2[23:16], SNES_ADDR_d2[15:0]};
    1: CalcAddr <= {1'b0,     SNES_ADDR_d2[23:16], SNES_ADDR_d2[14:0]};
    2: CalcAddr <= {2'b00,    SNES_ADDR_d2[23:16], SNES_ADDR_d2[13:0]};
    3: CalcAddr <= {3'b000,   SNES_ADDR_d2[23:16], SNES_ADDR_d2[12:0]};
    4: CalcAddr <= {4'b0000,  SNES_ADDR_d2[23:16], SNES_ADDR_d2[11:0]};
    5: CalcAddr <= {5'b00000, SNES_ADDR_d2[23:16], SNES_ADDR_d2[10:0]};
    default: CalcAddr <= 0;
  endcase

  AddrMapMatchValid <= AddrMapMatchValid_d2;
  AddrMapModeMatch <= AddrMapModeMatch_d2;
  AddrMapOutMaskModeMatch <= AddrMapOutMaskModeMatch_d2;
  AddrMapTypeMatch <= AddrMapTypeMatch_d2;
  AddrMapOutBaseMatch <= AddrMapOutBaseMatch_d2;
  AddrMapOutMaskMatch <= AddrMapOutMaskMatch_d2;
end

reg [23:0] AddrMapFinalAddress;
always @* begin
  AddrMapFinalAddress = ~AddrMapOutMaskModeMatch ? {AddrMapOutBaseMatch[7:0] + (CalcAddr[23:16] & AddrMapOutMaskMatch[15:8]), CalcAddr[15:8] & AddrMapOutMaskMatch[7:0], CalcAddr[7:0]} : {AddrMapOutBaseMatch[7:0] + CalcAddr[23:16], CalcAddr[15:0]} & {AddrMapOutMaskMatch, 8'hFF};
end


// Output IS bits

/* currently supported mappers:
   Index     Mapper
      000      HiROM
      001      LoROM
      010      ExHiROM (48-64Mbit)
      011      BS-X
      110      brainfuck interleaved 96MBit Star Ocean =)
      111      menu (ROM in upper SRAM)
*/

/* HiROM:   SRAM @ Bank 0x30-0x3f, 0xb0-0xbf
            Offset 6000-7fff */

assign IS_ROM = ((!SNES_ADDR[22] & SNES_ADDR[15])
                 |(SNES_ADDR[22]));

//assign IS_SAVERAM = SAVERAM_MASK[0]
//                    &(featurebits[FEAT_ST0010]
//                      ?((SNES_ADDR[22:19] == 4'b1101)
//                        & &(~SNES_ADDR[15:12])
//                        & SNES_ADDR[11])
//                      :((MAPPER == 3'b000
//                        || MAPPER == 3'b010
//                        || MAPPER == 3'b110)
//                      ? (!SNES_ADDR[22]
//                         & SNES_ADDR[21]
//                         & &SNES_ADDR[14:13]
//                         & !SNES_ADDR[15]
//                        )
///*  LoROM:   SRAM @ Bank 0x70-0x7d, 0xf0-0xff
// *  Offset 0000-7fff for ROM >= 32 MBit, otherwise 0000-ffff */
//                      :(MAPPER == 3'b001)
//                      ? (&SNES_ADDR[22:20]
//                         & (~SNES_ROMSEL)
//                         & (~SNES_ADDR[15] | ~ROM_MASK[21])
//                        )
///*  BS-X: SRAM @ Bank 0x10-0x17 Offset 5000-5fff */
//                      :(MAPPER == 3'b011)
//                      ? ((SNES_ADDR[23:19] == 5'b00010)
//                         & (SNES_ADDR[15:12] == 4'b0101)
//                        )
///*  Menu mapper: 8Mbit "SRAM" @ Bank 0xf0-0xff (entire banks!) */
//                      :(MAPPER == 3'b111)
//                      ? (&SNES_ADDR[23:20])
//                      : 1'b0));

// still support bs-x here
assign IS_SAVERAM = SAVERAM_MASK[0] && ((AddrMapMatchValid && AddrMapTypeMatch == ADDRMAP_TYPE_RAM) || (MAPPER == 3'b011 && SNES_ADDR[23:19] == 5'b00010 && SNES_ADDR[15:12] == 4'b0101) || (MAPPER == 3'b110 && (!SNES_ADDR[22] & SNES_ADDR[21] & &SNES_ADDR[14:13] & !SNES_ADDR[15])));

/* BS-X has 4 MBits of extra RAM that can be mapped to various places */
// LoROM: A23 = r03/r04  A22 = r06  A21 = r05  A20 = 0    A19 = d/c
// HiROM: A23 = r03/r04  A22 = d/c  A21 = r06  A20 = r05  A19 = 0

wire [2:0] BSX_PSRAM_BANK = {bsx_regs[6], bsx_regs[5], 1'b0};
wire [2:0] SNES_PSRAM_BANK = bsx_regs[2] ? SNES_ADDR[21:19] : SNES_ADDR[22:20];
wire BSX_PSRAM_LOHI = (bsx_regs[3] & ~SNES_ADDR[23]) | (bsx_regs[4] & SNES_ADDR[23]);
wire BSX_IS_PSRAM = BSX_PSRAM_LOHI
                     & (( IS_ROM & (SNES_PSRAM_BANK == BSX_PSRAM_BANK)
                         &(SNES_ADDR[15] | bsx_regs[2])
                         &(~(SNES_ADDR[19] & bsx_regs[2])))
                       | (bsx_regs[2]
                          ? (SNES_ADDR[22:21] == 2'b01 & SNES_ADDR[15:13] == 3'b011)
                          : (~SNES_ROMSEL & &SNES_ADDR[22:20] & ~SNES_ADDR[15]))
                       );

wire BSX_IS_CARTROM = ((bsx_regs[7] & (SNES_ADDR[23:22] == 2'b00))
                      |(bsx_regs[8] & (SNES_ADDR[23:22] == 2'b10)))
                      & SNES_ADDR[15];

wire BSX_HOLE_LOHI = (bsx_regs[9] & ~SNES_ADDR[23]) | (bsx_regs[10] & SNES_ADDR[23]);

wire BSX_IS_HOLE = BSX_HOLE_LOHI
                   & (bsx_regs[2] ? (SNES_ADDR[21:20] == {bsx_regs[11], 1'b0})
                                  : (SNES_ADDR[22:21] == {bsx_regs[11], 1'b0}));

assign bsx_tristate = (MAPPER == 3'b011) & ~BSX_IS_CARTROM & ~BSX_IS_PSRAM & BSX_IS_HOLE;

assign IS_WRITABLE = IS_SAVERAM
                     |((MAPPER == 3'b011) & BSX_IS_PSRAM);

wire [23:0] BSX_ADDR = bsx_regs[2] ? {1'b0, SNES_ADDR[22:0]}
                                   : {2'b00, SNES_ADDR[22:16], SNES_ADDR[14:0]};

/* BSX regs:
 Index  Function
    1   0=map flash to ROM area; 1=map PRAM to ROM area
    2   1=HiROM; 0=LoROM
    3   1=Mirror PRAM @60-6f:0000-ffff
    5   1=DO NOT mirror PRAM @40-4f:0000-ffff
    6   1=DO NOT mirror PRAM @50-5f:0000-ffff
    7   1=map BSX cartridge ROM @00-1f:8000-ffff
    8   1=map BSX cartridge ROM @80-9f:8000-ffff
*/

//assign SRAM_SNES_ADDR = (  (MAPPER == 3'b000)
//                          ?(IS_SAVERAM
//                            ? 24'hE00000 + ({SNES_ADDR[20:16], SNES_ADDR[12:0]}
//                                            & SAVERAM_MASK)
//                            : ({1'b0, SNES_ADDR[22:0]} & ROM_MASK))
//
//                          :(MAPPER == 3'b001)
//                          ?(IS_SAVERAM
//                            ? 24'hE00000 + ({SNES_ADDR[20:16], SNES_ADDR[14:0]}
//                                            & SAVERAM_MASK)
//                            : ({1'b0, ~SNES_ADDR[23], SNES_ADDR[22:16], SNES_ADDR[14:0]}
//                               & ROM_MASK))
//
//                          :(MAPPER == 3'b010)
//                          ?(IS_SAVERAM
//                            ? 24'hE00000 + ({SNES_ADDR[20:16], SNES_ADDR[12:0]}
//                                            & SAVERAM_MASK)
//                            : ({1'b0, !SNES_ADDR[23], SNES_ADDR[21:0]}
//                               & ROM_MASK))
//                          :(MAPPER == 3'b011)
//                          ?(  IS_SAVERAM
//                              ? 24'hE00000 + {SNES_ADDR[18:16], SNES_ADDR[11:0]}
//                              : BSX_IS_CARTROM
//                              ? (24'h800000 + ({SNES_ADDR[22:16], SNES_ADDR[14:0]} & 24'h0fffff))
//                              : BSX_IS_PSRAM
//                              ? (24'h400000 + (BSX_ADDR & 24'h07FFFF))
//                              : bs_page_enable
//                              ? (24'h900000 + {bs_page,bs_page_offset})
//                              : (BSX_ADDR & 24'h0fffff)
//                           )
//                           :(MAPPER == 3'b110)
//                           ?(IS_SAVERAM
//                             ? 24'hE00000 + ((SNES_ADDR[14:0] - 15'h6000)
//                                             & SAVERAM_MASK)
//                             :(SNES_ADDR[15]
//                               ?({1'b0, SNES_ADDR[23:16], SNES_ADDR[14:0]})
//                               :({2'b10,
//                                  SNES_ADDR[23],
//                                  SNES_ADDR[21:16],
//                                  SNES_ADDR[14:0]}
//                                )
//                              )
//                            )
//                           :(MAPPER == 3'b111)
//                           ?(IS_SAVERAM
//                             ? SNES_ADDR
//                             : (({1'b0, SNES_ADDR[22:0]} & ROM_MASK)
//                                + 24'hC00000)
//                            )
//                           :(MAPPER == 3'b100)
//                           ? AddrMapAddress                            
//                           : 24'b0);

// still support bs-x
assign SRAM_SNES_ADDR = AddrMapMatchValid  
                        ? AddrMapFinalAddress
                        :(MAPPER == 3'b011)
                        ?(  IS_SAVERAM
                            ? 24'hE00000 + {SNES_ADDR[18:16], SNES_ADDR[11:0]}
                            : BSX_IS_CARTROM
                            ? (24'h800000 + ({SNES_ADDR[22:16], SNES_ADDR[14:0]} & 24'h0fffff))
                            : BSX_IS_PSRAM
                            ? (24'h400000 + (BSX_ADDR & 24'h07FFFF))
                            : bs_page_enable
                            ? (24'h900000 + {bs_page,bs_page_offset})
                            : (BSX_ADDR & 24'h0fffff)
                         )
                         :(MAPPER == 3'b110)
                         ?(IS_SAVERAM
                           ? 24'hE00000 + ((SNES_ADDR[14:0] - 15'h6000)
                                           & SAVERAM_MASK)
                           :(SNES_ADDR[15]
                             ?({1'b0, SNES_ADDR[23:16], SNES_ADDR[14:0]})
                             :({2'b10,
                                SNES_ADDR[23],
                                SNES_ADDR[21:16],
                                SNES_ADDR[14:0]}
                              )
                            )
                          )
                         :0;

//assign ROM_ADDR = SRAM_SNES_ADDR_r;
assign ROM_ADDR = SRAM_SNES_ADDR;

assign ROM_HIT = IS_ROM | IS_WRITABLE | bs_page_enable;

assign msu_enable = featurebits[FEAT_MSU1] & (!SNES_ADDR[22] && ((SNES_ADDR[15:0] & 16'hfff8) == 16'h2000));
assign use_bsx = (MAPPER == 3'b011);
assign srtc_enable = featurebits[FEAT_SRTC] & (!SNES_ADDR[22] && ((SNES_ADDR[15:0] & 16'hfffe) == 16'h2800));

// DSP1 LoROM: DR=30-3f:8000-bfff; SR=30-3f:c000-ffff
//          or DR=60-6f:0000-3fff; SR=60-6f:4000-7fff
// DSP1 HiROM: DR=00-0f:6000-6fff; SR=00-0f:7000-7fff
assign dspx_enable =
  featurebits[FEAT_DSPX]
  ?((MAPPER == 3'b001)
    ?(ROM_MASK[20]
      ?(SNES_ADDR[22] & SNES_ADDR[21] & ~SNES_ADDR[20] & ~SNES_ADDR[15])
      :(~SNES_ADDR[22] & SNES_ADDR[21] & SNES_ADDR[20] & SNES_ADDR[15])
     )
    :(MAPPER == 3'b000)
      ?(~SNES_ADDR[22] & ~SNES_ADDR[21] & ~SNES_ADDR[20] & ~SNES_ADDR[15]
        & &SNES_ADDR[14:13])
    :1'b0)
  :featurebits[FEAT_ST0010]
  ?(SNES_ADDR[22] & SNES_ADDR[21] & ~SNES_ADDR[20] & &(~SNES_ADDR[19:16]) & ~SNES_ADDR[15])
  :1'b0;

assign dspx_dp_enable = featurebits[FEAT_ST0010]
                      &(SNES_ADDR[22:19] == 4'b1101
                     && SNES_ADDR[15:11] == 5'b00000);

assign dspx_a0 = featurebits[FEAT_DSPX]
                 ?((MAPPER == 3'b001) ? SNES_ADDR[14]
                   :(MAPPER == 3'b000) ? SNES_ADDR[12]
                   :1'b1)
                 : featurebits[FEAT_ST0010]
                 ? SNES_ADDR[0]
                 : 1'b1;

assign r213f_enable = featurebits[FEAT_213F] & (SNES_PA == 8'h3f);

assign snescmd_enable = ({SNES_ADDR[22], SNES_ADDR[15:9]} == 8'b0_0010101);
assign nmicmd_enable = (SNES_ADDR == 24'h002BF2);
assign return_vector_enable = (SNES_ADDR == 24'h002A5A);
assign branch1_enable = (SNES_ADDR == 24'h002A13);
assign branch2_enable = (SNES_ADDR == 24'h002A4D);
endmodule
