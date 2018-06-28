`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    06:32:24 04/24/2018 
// Design Name: 
// Module Name:    sa1 
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

//`define CSRAM

module sa1(
  input         RST,
  input         CLK,

  input  [23:0] SAVERAM_MASK,
  input  [23:0] ROM_MASK,

  // MMIO interface
  //input         ENABLE,
  input         SNES_READ,
  input         SNES_RD_start,
  input         SNES_RD_end,
  input         SNES_WR_start,
  input         SNES_WR_end,
  input  [23:0] SNES_ADDR,
  input  [7:0]  DATA_IN,
  output        DATA_ENABLE,
  output [7:0]  DATA_OUT,
  
  // ROM interface
  input         ROM_BUS_RDY,
  output        ROM_BUS_RRQ,
  output        ROM_BUS_WRQ,
  output        ROM_BUS_WORD,
  output [23:0] ROM_BUS_ADDR,
  input  [15:0] ROM_BUS_RDDATA,
  output [15:0] ROM_BUS_WRDATA,

  output        ROM_HIT,

`ifdef CSRAM
  // RAM interface
  input         RAM_BUS_RDY,
  output        RAM_BUS_RRQ,
  output        RAM_BUS_WRQ,
  output        RAM_BUS_WORD,
  output [23:0] RAM_BUS_ADDR,
  input  [7:0]  RAM_BUS_RDDATA,
  output [7:0]  RAM_BUS_WRDATA,

  output        RAM_HIT,
`endif

  // address map
  output [4:0]  BMAPS_SBM,
  output [15:0] SNV,
  output [15:0] SIV,
  output        SCNT_NVSW,
  output        SCNT_IVSW,

  output        IRQ,

  input         SPEED,
  
  // State debug read interface
  input  [11:0] PGM_ADDR, // [11:0]
  output [7:0]  PGM_DATA, // [7:0]

  // config interface
  input  [7:0]  reg_group_in,
  input  [7:0]  reg_index_in,
  input  [7:0]  reg_value_in,
  input  [7:0]  reg_invmask_in,
  input         reg_we_in,
  input  [7:0]  reg_read_in,
  output [7:0]  config_data_out,
  // config interface

  output        DBG
);

//-------------------------------------------------------------------
// NOTES
//-------------------------------------------------------------------
// This is a cycle-approximate implementation of the sa1 chip.  The sa1
// is a 65c816 core running at ~10.74 MHz.  It can serve as an off-load
// engine/accelerator or a peer to the host snes cpu.
//
// There are base 65c816 as well as custom features available to the sa1
// with varying levels of implementation.  Several features have been left
// out in order to make development easier and fit basic functionality on
// the fpga.
// 
// [x] full native 65c816 instruction set. (not fully debugged)
// [x] host and slave mmio support for reset and other basic functionality
// [x] host and slave access to bram (cart ram) and iram.
// [_] emulation support.  (known holes in emulation state execution)
// [_] dma/normal
// [_] dma/cc
// [x] host interrupts
// [x] host interrupt vectors
// [x] sa1 interrupts (untested)
// [_] counters
// [_] bcd mode/math
// [_] rom address mapping
// [x] ram address mapping
// [x] multiply/divide
// [x] mac support for multiply
// [_] full mdr support

//-------------------------------------------------------------------
// DEFINES
//-------------------------------------------------------------------

`define DEBUG
//`define DEBUG_EXT
//`define DEBUG_MMC
//`define DEBUG_EXE

// address map tests
`define IS_ROM(a)  ((&a[23:22]) | (~a[22] & a[15]))                                     // 00-3F/80-BF:8000-FFFF, C0-FF:0000-FFFF
`define IS_BRAM(a) ((~a[22] & ~a[15] & &a[14:13]) | (~a[23] & a[22] & ~a[21] & ~a[20])) // 00-3F/80-BF:6000-7FFF, 40-4F:0000-FFFF
`define IS_SA1_IRAM(a) (~a[22] & ~a[15] & ~a[14] & ~^a[13:12] & ~a[11])                 // 00-3F/80-BF:0/3000-0/37FF
`define IS_CPU_IRAM(a) (~a[22] & ~a[15] & ~a[14] & &a[13:12] & ~a[11])                 // 00-3F/80-BF:3000-37FF
`define IS_MMIO(a) (~a[22] & ~a[15] & ~a[14] & a[13] & ~a[12] & ~a[11] & ~a[10] & a[9]) // 00-3F/80-BF:2200-23FF
`define IS_SA1_PRAM(a) (~a[23] & a[22] & a[21] & ~a[20])                                // 60-6F:0000-FFFF

// address mapping
wire       sw46;
wire [6:0] cbm;
// TODO: add MMC support to both here and addr module
`define MAP_ROM(a)  ((a[22] ? {2'b00, a[21:0]} : {3'b000, a[21:16], a[14:0]}) & ROM_MASK)
// TODO: handle CBM projection
`define MAP_BRAM(a) (24'hE00000 | ((a[22] ? a[19:0] : {(sw46 ? cbm[6:5] : 2'h0),cbm[4:0],a[12:0]}) & SAVERAM_MASK))
`define MAP_IRAM(a) (a[10:0])
`define MAP_MMIO(a) (a[8:0])
`define MAP_PRAM(a) (24'hE00000 | (a[19:0] & SAVERAM_MASK))

// temporaries
integer i;
wire pipeline_advance;
wire fetch_advance;
wire op_complete;

function integer clog2;
  input integer value;
  begin
    value = value-1;
    for (clog2=0; value>0; clog2=clog2+1)
      value = value>>1;
  end
endfunction

//-------------------------------------------------------------------
// INPUTS
//-------------------------------------------------------------------
reg [7:0]  data_in_r;
reg [23:0] addr_in_r;
//reg        enable_r;
reg [11:0]  pgm_addr_r;

always @(posedge CLK) begin
  data_in_r  <= DATA_IN;
  addr_in_r  <= SNES_ADDR;
  //enable_r   <= ENABLE;
  pgm_addr_r <= PGM_ADDR;
end

//-------------------------------------------------------------------
// PARAMETERS
//-------------------------------------------------------------------

parameter
  // write
  ADDR_CCNT  = 8'h00,
  ADDR_SIE   = 8'h01,
  ADDR_SIC   = 8'h02,
  ADDR_CRV   = 8'h03, // $2
  //
  ADDR_CNV   = 8'h05, // $2
  //
  ADDR_CIV   = 8'h07, // $2
  //
  ADDR_SCNT  = 8'h09,
  ADDR_CIE   = 8'h0A,
  ADDR_CIC   = 8'h0B,
  ADDR_SNV   = 8'h0C, // $2
  //
  ADDR_SIV   = 8'h0E, // $2
  //
  
  ADDR_TMC   = 8'h10,
  ADDR_CTR   = 8'h11,
  ADDR_HCNT  = 8'h12, // $2
  //
  ADDR_VCNT  = 8'h14, // $2
  //
  ADDR_CXB   = 8'h20,
  ADDR_DXB   = 8'h21,
  ADDR_EXB   = 8'h22,
  ADDR_FXB   = 8'h23,
  ADDR_BMAPS = 8'h24,
  ADDR_BMAP  = 8'h25,
  ADDR_SWBE  = 8'h26,
  ADDR_CWBE  = 8'h27,
  ADDR_BWPA  = 8'h28,
  ADDR_SIWP  = 8'h29,
  ADDR_CIWP  = 8'h2A,
  //
  ADDR_DCNT  = 8'h30,
  ADDR_CDMA  = 8'h31,
  ADDR_SDA   = 8'h32, // $3
  //
  //
  ADDR_DDA   = 8'h35, // $3
  //
  //
  ADDR_DTC   = 8'h38,
  //
  ADDR_BBF   = 8'h3F,
  ADDR_BRF   = 8'h40, // $10
  ADDR_BRF0  = 8'h40,
  ADDR_BRF1  = 8'h41,
  ADDR_BRF2  = 8'h42,
  ADDR_BRF3  = 8'h43,
  ADDR_BRF4  = 8'h44,
  ADDR_BRF5  = 8'h45,
  ADDR_BRF6  = 8'h46,
  ADDR_BRF7  = 8'h47,
  ADDR_BRF8  = 8'h48,
  ADDR_BRF9  = 8'h49,
  ADDR_BRFA  = 8'h4A,
  ADDR_BRFB  = 8'h4B,
  ADDR_BRFC  = 8'h4C,
  ADDR_BRFD  = 8'h4D,
  ADDR_BRFE  = 8'h4E,
  ADDR_BRFF  = 8'h4F,
  
  ADDR_MCNT  = 8'h50,
  ADDR_MA    = 8'h51, // $2
  //
  ADDR_MB    = 8'h53, // $2
  //
  ADDR_VBD   = 8'h58,
  ADDR_VDA   = 8'h59  // $3
  ;

parameter
  ADDR_SFR   = 8'h00,
  ADDR_CFR   = 8'h01,
  ADDR_HCR   = 8'h02, // $2
  ADDR_VCR   = 8'h04, // $2
  ADDR_MR    = 8'h06, // $5
  ADDR_OF    = 8'h0B,
  ADDR_VDP   = 8'h0C, // $2
  ADDR_VC    = 8'h0E
  ;

//-------------------------------------------------------------------
// CONFIG
//-------------------------------------------------------------------

// C0 Control
// 0 - Go (1) 
// 1 - MatchFullInst

// C1 StepControl
// [7:0] StepCount

// C2 BreakpointControl
// 0 - BreakOnInstRdByteWatch
// 1 - BreakOnDataRdByteWatch
// 2 - BreakOnDataWrByteWatch
// 3 - BreakOnInstRdAddrWatch
// 4 - BreakOnDataRdAddrWatch
// 5 - BreakOnDataWrAddrWatch
// 6 - BreakOnStop
// 7 - BreakOnError

// C3 ???

// C4 DataWatch
// [7:0] DataWatch

// C5-C7 AddrWatch (little endian)
// [23:0] AddrWatch

// breakpoint state
`ifdef DEBUG
reg         brk_inst_rd_byte; initial brk_inst_rd_byte = 0;
reg         brk_data_rd_byte; initial brk_data_rd_byte = 0;
reg         brk_data_wr_byte; initial brk_data_wr_byte = 0;
reg         brk_inst_rd_addr; initial brk_inst_rd_addr = 0;
reg         brk_data_rd_addr; initial brk_data_rd_addr = 0;
reg         brk_data_wr_addr; initial brk_data_wr_addr = 0;
reg         brk_stop;         initial brk_stop = 0;
reg         brk_error;        initial brk_error = 0;

parameter CONFIG_REGISTERS = 8;
reg [7:0] config_r[CONFIG_REGISTERS-1:0]; initial for (i = 0; i < CONFIG_REGISTERS; i = i + 1) config_r[i] = 8'h00;

always @(posedge CLK) begin
  if (RST) begin
    //for (i = 0; i < CONFIG_REGISTERS; i = i + 1) config_r[i] <= 8'h00;
  end
  else if (reg_we_in && (reg_group_in == 8'h03)) begin
    if (reg_index_in < CONFIG_REGISTERS) config_r[reg_index_in] <= (config_r[reg_index_in] & reg_invmask_in) | (reg_value_in & ~reg_invmask_in);
  end
  else begin
    config_r[0][0] <= config_r[0][0] & ~|(config_r[2] & {brk_error,brk_stop,brk_data_wr_addr,brk_data_rd_addr,brk_inst_rd_addr,brk_data_wr_byte,brk_data_rd_byte,brk_inst_rd_byte});
  end
end

assign config_data_out = config_r[reg_read_in];

assign      CONFIG_CONTROL_ENABLED       = config_r[0][0];
assign      CONFIG_CONTROL_MATCHPARTINST = config_r[0][1];

wire [7:0]  CONFIG_STEP_COUNT   = config_r[1];
wire [7:0]  CONFIG_DATA_WATCH   = config_r[4];
wire [23:0] CONFIG_ADDR_WATCH   = {config_r[7],config_r[6],config_r[5]};
`else
wire [7:0] CONFIG_STEP_COUNT = 0;
assign CONFIG_CONTROL_ENABLED = 1;
assign CONFIG_CONTROL_MATCHPARTINST = 0;
`endif

//-------------------------------------------------------------------
// FLOPS
//-------------------------------------------------------------------
reg [23:0] debug_inst_addr_r;
reg [23:0] debug_inst_addr_prev_r;

reg [2:0]  sa1_cycle_r; initial sa1_cycle_r = 0;
reg        sa1_clock_en; initial sa1_clock_en = 0;

// step counter for pipelines
reg [7:0] stepcnt_r; initial stepcnt_r = 0;
reg       step_r; initial step_r = 0;

wire      sa1_clock_en_pre = sa1_cycle_r == 6;

always @(posedge CLK) begin
  if (RST) begin
    sa1_cycle_r <= 0;
    sa1_clock_en <= 0;
  end
  else begin
    sa1_cycle_r  <= sa1_cycle_r + 1;
    sa1_clock_en <= sa1_clock_en_pre;
  end
end

reg [31:0] sa1_cycle_cnt_r; initial sa1_cycle_cnt_r = 0;

//-------------------------------------------------------------------
// STATE
//-------------------------------------------------------------------
// register state
reg [7:0]   PBR_r;  initial PBR_r  = 0;
reg [15:0]  PC_r;   initial PC_r   = 0;
reg [15:0]  A_r;    initial A_r    = 0;
reg [15:0]  X_r;    initial X_r    = 0;
reg [15:0]  Y_r;    initial Y_r    = 0;
reg [15:0]  S_r;    initial S_r    = 16'h01FF;
reg [15:0]  D_r;    initial D_r    = 0;
reg [7:0]   DBR_r;   initial DBR_r   = 0;
reg [7:0]   P_r;    initial P_r    = 8'h34;
reg         E_r;    initial E_r    = 1;
reg         WAI_r;  initial WAI_r  = 0;

// write-only MMIO
reg [7:0]   CCNT_r; initial CCNT_r = 8'h20;
reg [7:0]   SIE_r;  initial SIE_r  = 0;
reg [7:0]   SIC_r;  initial SIC_r  = 0;
reg [15:0]  CRV_r;  initial CRV_r  = 0;
reg [15:0]  CNV_r;  initial CNV_r  = 0;
reg [15:0]  CIV_r;  initial CIV_r  = 0;
reg [7:0]   SCNT_r; initial SCNT_r = 0;
reg [7:0]   CIE_r;  initial CIE_r  = 0;
reg [7:0]   CIC_r;  initial CIC_r  = 0;
reg [15:0]  SNV_r;  initial SNV_r  = 0;
reg [15:0]  SIV_r;  initial SIV_r  = 0;
reg [7:0]   TMC_r;  initial TMC_r  = 0;
reg [7:0]   CTR_r;  initial CTR_r  = 0;
reg [15:0]  HCNT_r; initial HCNT_r = 0;
reg [15:0]  VCNT_r; initial VCNT_r = 0;
reg [7:0]   CXB_r;  initial CXB_r  = 0;
reg [7:0]   DXB_r;  initial DXB_r  = 1;
reg [7:0]   EXB_r;  initial EXB_r  = 2;
reg [7:0]   FXB_r;  initial FXB_r  = 3;
reg [7:0]   BMAPS_r;initial BMAPS_r= 0;
reg [7:0]   BMAP_r; initial BMAP_r = 0;
reg [7:0]   SWBE_r; initial SWBE_r = 0;
reg [7:0]   CWBE_r; initial CWBE_r = 0;
reg [7:0]   BWPA_r; initial BWPA_r = 8'hFF;
reg [7:0]   SIWP_r; initial SIWP_r = 0;
reg [7:0]   CIWP_r; initial CIWP_r = 0;
reg [7:0]   DCNT_r; initial DCNT_r = 0;
reg [7:0]   CDMA_r; initial CDMA_r = 0;
reg [23:0]  SDA_r;  initial SDA_r  = 0;
reg [23:0]  DDA_r;  initial DDA_r  = 0;
reg [15:0]  DTC_r;  initial DTC_r  = 0;
reg [7:0]   BBF_r;  initial BBF_r  = 0;
reg [15:0]  BRF_r[7:0]; initial for (i = 0; i < 8; i = i + 1) BRF_r[i] = 0;
reg [7:0]   MCNT_r; initial MCNT_r = 0;
reg [15:0]  MA_r;   initial MA_r   = 0;
reg [15:0]  MB_r;   initial MB_r   = 0;
reg [7:0]   VBD_r;  initial VBD_r  = 0;
reg [23:0]  VDA_r;  initial VDA_r  = 0;
reg         VDA_VBIT_r; initial VDA_VBIT_r = 0;

// read-only through MMIO
reg [7:0]   SFR_r;  initial SFR_r  = 0;
reg [7:0]   CFR_r;  initial CFR_r  = 0;
reg [15:0]  HCR_r;  initial HCR_r  = 0;
reg [15:0]  VCR_r;  initial VCR_r  = 0;
reg [39:0]  MR_r;   initial MR_r   = 0;
reg [7:0]   OF_r;   initial OF_r   = 0;
reg [15:0]  VDP_r;  initial VDP_r  = 0;
reg [7:0]   VC_r;   initial VC_r   = 0;

// internal state
reg [15:0]  hcounter_r; initial hcounter_r = 0;
reg [15:0]  vcounter_r; initial vcounter_r = 0;

// Important parameters
`define P_C           0
`define P_Z           1
`define P_I           2
`define P_D           3
`define P_X           4
`define P_M           5
`define P_V           6
`define P_N           7
`define P_B           4

`define CCNT_SMEG     3:0  
`define CCNT_SA1_NMI  4
`define CCNT_SA1_RESB 5
`define CCNT_SA1_RDYB 6
`define CCNT_SA1_IRQ  7
  
`define SIE_DMA_IRQEN 5
`define SIE_CPU_IRQEN 7

`define SIC_DMA_IRQCL 5
`define SIC_CPU_IRQCL 7

`define SCNT_CMEG     3:0
`define SCNT_NVSW     4
`define SCNT_IVSW     6
`define SCNT_CPU_IRQ  7

`define CIE_SA1_NMIEN 4
`define CIE_DMA_IRQEN 5
`define CIE_TMR_IRQEN 6
`define CIE_SA1_IRQEN 7

`define CIC_SA1_NMICL 4
`define CIC_DMA_IRQCL 5
`define CIC_TMR_IRQCL 6
`define CIC_SA1_IRQCL 7

`define TMC_HEN       0
`define TMC_VEN       1
`define TMC_HVSELB    7

`define CXB_CB        2:0
`define CXB_CBMODE    7

`define DXB_DB        2:0
`define DXB_DBMODE    7

`define EXB_EB        2:0
`define EXB_EBMODE    7

`define FXB_FB        2:0
`define FXB_FBMODE    7

`define BMAPS_SBM     4:0

`define BMAP_CBM      6:0
`define BMAP_SW46     7

`define SWBE_SWEN     7

`define CWBE_CWEN     7

`define BWPA_BWP      3:0

`define DCNT_SD       1:0
`define DCNT_DD       2
`define DCNT_CDSEL    4
`define DCNT_CDEN     5
`define DCNT_DPRIO    6
`define DCNT_DMAEN    7

`define CDMA_DMACB    1:0
`define CDMA_DMASIZE  4:2
`define CDMA_CHDEND   7

`define BBF_BBF       7

`define MCNT_MD       0
`define MCNT_ACM      1

`define VBD_VB        3:0
`define VBD_HL        7

`define SFR_DMA_IRQFL 5
`define SFR_CPU_IRQFL 7

`define CFR_SA1_NMIFL 4
`define CFR_DMA_IRQFL 5
`define CFR_TMR_IRQFL 6
`define CFR_SA1_IRQFL 7
  
`define DCNT_SRC      1:0

assign sw46 = BMAP_r[`BMAP_SW46];
assign cbm  = BMAP_r[`BMAP_CBM];

//-------------------------------------------------------------------
// PIPELINE IO
//-------------------------------------------------------------------
wire waitcnt_zero;

// mmc interface
reg        exe_mmc_rd_r; initial exe_mmc_rd_r = 0;
reg        exe_mmc_wr_r; initial exe_mmc_wr_r = 0;
reg        exe_mmc_dpe_r; initial exe_mmc_dpe_r = 0;
reg [1:0]  exe_mmc_byte_total_r; initial exe_mmc_byte_total_r = 0;
reg        exe_mmc_long_r; initial exe_mmc_long_r = 0;
reg [31:0] exe_mmc_data_r;

reg        dma_mmc_rd_r; initial dma_mmc_rd_r = 0;
reg        dma_mmc_wr_r; initial dma_mmc_wr_r = 0;
reg [23:0] dma_mmc_addr_r;
reg [7:0]  dma_mmc_data_r;

reg        vdp_mmc_rd_r; initial vdp_mmc_rd_r = 0;
reg [23:0] vdp_mmc_addr_r;

//-------------------------------------------------------------------
// REGISTER/MMIO ACCESS
//-------------------------------------------------------------------
reg        data_enable_r; initial data_enable_r = 0;
reg [7:0]  data_out_r;
reg [7:0]  data_flop_r; initial data_flop_r = 0;

reg        snes_write_r; initial snes_write_r = 0;
reg        snes_writereg_r; initial snes_writereg_r = 0;

reg        snes_writebuf_val_r; initial snes_writebuf_val_r = 0;
reg        snes_writebuf_iram_r; initial snes_writebuf_iram_r = 0;
reg [10:0] snes_writebuf_addr_r;
reg [7:0]  snes_writebuf_data_r;

reg        snes_readbuf_val_r; initial snes_readbuf_val_r = 0;
reg        snes_readbuf_iram_r; initial snes_readbuf_iram_r = 0;
reg        snes_readbuf_active_r; initial snes_readbuf_active_r = 0;
reg [10:0] snes_readbuf_addr_r;

reg        idle_r; initial idle_r = 0;

wire [7:0] snes_iram_out;

wire [7:0] sa1_mmio_addr;
wire [7:0] sa1_mmio_data;
wire       sa1_mmio_write;
wire       sa1_mmio_read;
reg  [1:0] sa1_mmio_read_r; initial sa1_mmio_read_r = 0;

always @(posedge CLK) begin
  if (RST) begin
    // TODO: reset all register state
    
    data_enable_r <= 0;
    data_out_r <= 0;
    data_flop_r <= 0;
    
    snes_writebuf_val_r <= 0;
    snes_writebuf_iram_r <= 0;
    snes_readbuf_val_r <= 0;
    snes_readbuf_iram_r <= 0;
    snes_readbuf_active_r <= 0;
    
    sa1_mmio_read_r <= 0;
    
    // initialize registers on cart reset    
    CCNT_r <= 8'h20;
    SIE_r  <= 0;
    SIC_r  <= 0;
    CRV_r  <= 0;
    CNV_r  <= 0;
    CIV_r  <= 0;
    SCNT_r <= 0;
    CIE_r  <= 0;
    CIC_r  <= 0;
    SNV_r  <= 0;
    SIV_r  <= 0;
    TMC_r  <= 0;
    CTR_r  <= 0;
    HCNT_r <= 0;
    VCNT_r <= 0;
    CXB_r  <= 0;
    DXB_r  <= 1;
    EXB_r  <= 2;
    FXB_r  <= 3;
    BMAPS_r<= 0;
    BMAP_r <= 0;
    SWBE_r <= 0;
    CWBE_r <= 0;
    BWPA_r <= 8'hFF;
    SIWP_r <= 0;
    CIWP_r <= 0;
    DCNT_r <= 0;
    CDMA_r <= 0;
    SDA_r  <= 0;
    DDA_r  <= 0;
    DTC_r  <= 0;
    BBF_r  <= 0;
    for (i = 0; i < 8; i = i + 1) BRF_r[i] <= 0;
    MCNT_r <= 0;
    MA_r   <= 0;
    MB_r   <= 0;
    VBD_r  <= 0;
    VDA_r  <= 0;
    
    // DMA bit handled by DMA state machine
    {SFR_r[7:6],SFR_r[4:0]} <= 0;
    {CFR_r[7:6],CFR_r[4:0]} <= 0;
    HCR_r  <= 0;
    VCR_r  <= 0;
    //MR_r   <= 0;
    //OF_r   <= 0;
    VDP_r  <= 0;
    VC_r   <= 0;
  end
  else begin
    sa1_mmio_read_r <= {sa1_mmio_read_r[0], sa1_mmio_read};
  
    // Register Read
    // FIXME interrupt clear?
    if (~SNES_READ & snes_readbuf_active_r) begin
      snes_readbuf_val_r <= `IS_MMIO(addr_in_r);
      snes_readbuf_iram_r <= `IS_CPU_IRAM(addr_in_r);
      snes_readbuf_addr_r <= addr_in_r[10:0];
    end
    else if (~snes_readbuf_active_r) begin
      snes_readbuf_val_r  <= sa1_mmio_read;
      snes_readbuf_iram_r <= 0;

      snes_readbuf_addr_r <= sa1_mmio_addr;
    end

    snes_readbuf_active_r <= `IS_MMIO(addr_in_r) | `IS_CPU_IRAM(addr_in_r);
    data_enable_r <= snes_readbuf_active_r & (snes_readbuf_val_r | snes_readbuf_iram_r);

    if (snes_readbuf_val_r) begin
      casex (snes_readbuf_addr_r[7:0])
        // FIXME: some registers need aggregation from other sources
        ADDR_SFR  : data_out_r <= {SCNT_r[7:6],1'b0,SCNT_r[4:0]}; // SCNT[5] is always 0
        ADDR_CFR  : data_out_r <= {CFR_r[7:4],CCNT_r[`CCNT_SMEG]};
        ADDR_HCR  : if (~data_enable_r) begin data_out_r <= hcounter_r[9:2]; HCR_r <= {2'h0,hcounter_r[15:2]}; VCR_r <= vcounter_r; end
        ADDR_HCR+1: data_out_r <= HCR_r[15:8];
        ADDR_VCR  : data_out_r <= VCR_r[7:0];
        ADDR_VCR+1: data_out_r <= VCR_r[15:8];
        ADDR_MR   : data_out_r <= MR_r[7:0];
        ADDR_MR+1 : data_out_r <= MR_r[15:8];
        ADDR_MR+2 : data_out_r <= MR_r[23:16];
        ADDR_MR+3 : data_out_r <= MR_r[31:24];
        ADDR_MR+4 : data_out_r <= MR_r[39:32];
        ADDR_OF   : data_out_r <= OF_r;
        ADDR_VDP  : data_out_r <= VDP_r[7:0];
        ADDR_VDP+1: data_out_r <= VDP_r[15:8];
        ADDR_VC   : data_out_r <= VC_r;
      endcase
    end
    else if (snes_readbuf_iram_r) begin
      data_out_r <= snes_iram_out;
    end
  
    // Register Write Buffer.
    if (SNES_WR_end & `IS_MMIO(addr_in_r)) begin
      snes_writebuf_val_r  <= 1;
      snes_writebuf_iram_r <= 0;
      snes_writebuf_addr_r <= {2'h0,addr_in_r[8:0]};
      snes_writebuf_data_r <= data_in_r;
    end
    else if (SNES_WR_end & `IS_CPU_IRAM(addr_in_r)) begin
      snes_writebuf_val_r  <= 0;
      snes_writebuf_iram_r <= 1;
      snes_writebuf_addr_r <= addr_in_r[10:0];
      snes_writebuf_data_r <= data_in_r;
    end
    else begin
      snes_writebuf_val_r  <= sa1_mmio_write;
      snes_writebuf_iram_r <= 0;
      
      snes_writebuf_addr_r <= sa1_mmio_addr;
      snes_writebuf_data_r <= sa1_mmio_data;
    end
            
    // FIXME: can we move the interrupt controller logic outside of the MMIO operations to reduce code size and complexity?
    // TODO: is it better to write the whole register, but only read correct subset?  May reduce fpga requirements.
    if (snes_writebuf_val_r) begin
      case (snes_writebuf_addr_r[7:0])
        ADDR_CCNT  : begin  // 8'h00,
          CCNT_r <= snes_writebuf_data_r;
          
          if (snes_writebuf_data_r[`CCNT_SA1_IRQ]) begin
            CFR_r[`CFR_SA1_IRQFL] <= 1;
            if (CIE_r[`CIE_SA1_IRQEN]) CIC_r[`CIC_SA1_IRQCL] <= 0;
          end

          if (snes_writebuf_data_r[`CCNT_SA1_NMI]) begin
            CFR_r[`CFR_SA1_NMIFL] <= 1;
            if (CIE_r[`CIE_SA1_NMIEN]) CIC_r[`CIC_SA1_NMICL] <= 0;
          end
        end
        ADDR_SIE   : begin  // 8'h01,
          {SIE_r[`SIE_DMA_IRQEN], SIE_r[`SIE_CPU_IRQEN]} <= {snes_writebuf_data_r[`SIE_DMA_IRQEN],snes_writebuf_data_r[`SIE_CPU_IRQEN]};
          
          if (~SIE_r[`SIE_CPU_IRQEN] & snes_writebuf_data_r[`SIE_CPU_IRQEN] & SFR_r[`SFR_CPU_IRQFL]) begin
            SIC_r[`SIC_CPU_IRQCL] <= 0;
          end
          
          if (~SIE_r[`SIE_DMA_IRQEN] & snes_writebuf_data_r[`SIE_DMA_IRQEN] & SFR_r[`SFR_DMA_IRQFL]) begin
            SIC_r[`SIC_DMA_IRQCL] <= 0;
          end
        end
        ADDR_SIC   : begin  // 8'h02,
          {SIC_r[`SIC_DMA_IRQCL],SIC_r[`SIC_CPU_IRQCL]} <= {snes_writebuf_data_r[`SIC_DMA_IRQCL],snes_writebuf_data_r[`SIC_CPU_IRQCL]};
          
          //if (snes_writebuf_data_r[`SIC_DMA_IRQCL]) SFR_r[`SFR_DMA_IRQFL] <= 0;
          if (snes_writebuf_data_r[`SIC_CPU_IRQCL]) SFR_r[`SFR_CPU_IRQFL] <= 0;
        end
        ADDR_CRV   : CRV_r[7:0]  <= snes_writebuf_data_r;  // 8'h03, // $2
        ADDR_CRV+1 : CRV_r[15:8] <= snes_writebuf_data_r;  // 8'h03, // $2
        ADDR_CNV   : CNV_r[7:0]  <= snes_writebuf_data_r;  // 8'h05, // $2
        ADDR_CNV+1 : CNV_r[15:8] <= snes_writebuf_data_r;  // 8'h05, // $2
        ADDR_CIV   : CIV_r[7:0]  <= snes_writebuf_data_r;  // 8'h07, // $2
        ADDR_CIV+1 : CIV_r[15:8] <= snes_writebuf_data_r;  // 8'h07, // $2
        ADDR_SCNT  : begin  // 8'h09,
          {SCNT_r[7:6],SCNT_r[4:0]} <= {snes_writebuf_data_r[7:6],snes_writebuf_data_r[4:0]};
          
          if (snes_writebuf_data_r[`SCNT_CPU_IRQ]) begin
            SFR_r[`SFR_CPU_IRQFL] <= 1;
            if (SIE_r[`SIE_CPU_IRQEN]) begin
              SIC_r[`SIC_CPU_IRQCL] <= 0;
            end
          end
        end
        ADDR_CIE   : begin  // 8'h0A,
          CIE_r[7:4] <= snes_writebuf_data_r[7:4];
          
          if (~CIE_r[`CIE_SA1_IRQEN] & snes_writebuf_data_r[`CIE_SA1_IRQEN] & CFR_r[`CFR_SA1_IRQFL]) CIC_r[`CIC_SA1_IRQCL] <= 0;
          if (~CIE_r[`CIE_TMR_IRQEN] & snes_writebuf_data_r[`CIE_TMR_IRQEN] & CFR_r[`CFR_TMR_IRQFL]) CIC_r[`CIC_TMR_IRQCL] <= 0;
          if (~CIE_r[`CIE_DMA_IRQEN] & snes_writebuf_data_r[`CIE_DMA_IRQEN] & CFR_r[`CFR_DMA_IRQFL]) CIC_r[`CIC_DMA_IRQCL] <= 0;
          if (~CIE_r[`CIE_SA1_NMIEN] & snes_writebuf_data_r[`CIE_SA1_NMIEN] & CFR_r[`CFR_SA1_NMIFL]) CIC_r[`CIC_SA1_NMICL] <= 0;
        end
        ADDR_CIC   : begin  // 8'h0B,
          CIC_r[7:4] <= snes_writebuf_data_r[7:4];
          
          if (snes_writebuf_data_r[`CIC_SA1_IRQCL]) CFR_r[`CFR_SA1_IRQFL] <= 0;
          if (snes_writebuf_data_r[`CIC_TMR_IRQCL]) CFR_r[`CFR_TMR_IRQFL] <= 0;
          //if (snes_writebuf_data_r[`CIC_DMA_IRQCL]) CFR_r[`CFR_DMA_IRQFL] <= 0;
          if (snes_writebuf_data_r[`CIC_SA1_NMICL]) CFR_r[`CFR_SA1_NMIFL] <= 0;
        end
        ADDR_SNV   : SNV_r[7:0]          <= snes_writebuf_data_r;  // 8'h0C, // $2
        ADDR_SNV+1 : SNV_r[15:8]         <= snes_writebuf_data_r;  // 8'h0C, // $2
        ADDR_SIV   : SIV_r[7:0]          <= snes_writebuf_data_r;  // 8'h0E, // $2
        ADDR_SIV+1 : SIV_r[15:8]         <= snes_writebuf_data_r;  // 8'h0E, // $2
        ADDR_TMC   : {TMC_r[`TMC_HVSELB],TMC_r[`TMC_VEN],TMC_r[`TMC_HEN]} <= {snes_writebuf_data_r[`TMC_HVSELB],snes_writebuf_data_r[`TMC_VEN],snes_writebuf_data_r[`TMC_HEN]};  // 8'h10,
        //ADDR_CTR   : // TODO: reset counters.  Probably needs to be moved outside of this code  // 8'h11,
        ADDR_HCNT  : HCNT_r[7:0]         <= snes_writebuf_data_r;  // 8'h12, // $2
        ADDR_HCNT+1: HCNT_r[15:8]        <= snes_writebuf_data_r;  // 8'h12, // $2
        ADDR_VCNT  : VCNT_r[7:0]         <= snes_writebuf_data_r;  // 8'h14, // $2
        ADDR_VCNT+1: VCNT_r[15:8]        <= snes_writebuf_data_r;  // 8'h14, // $2
        ADDR_CXB   : {CXB_r[`CXB_CBMODE],CXB_r[`CXB_CB]} <= {snes_writebuf_data_r[`CXB_CBMODE],snes_writebuf_data_r[`CXB_CB]};  // 8'h20,
        ADDR_DXB   : {DXB_r[`DXB_DBMODE],DXB_r[`DXB_DB]} <= {snes_writebuf_data_r[`DXB_DBMODE],snes_writebuf_data_r[`DXB_DB]};  // 8'h21,
        ADDR_EXB   : {EXB_r[`EXB_EBMODE],EXB_r[`EXB_EB]} <= {snes_writebuf_data_r[`EXB_EBMODE],snes_writebuf_data_r[`EXB_EB]};  // 8'h22,
        ADDR_FXB   : {FXB_r[`FXB_FBMODE],FXB_r[`FXB_FB]} <= {snes_writebuf_data_r[`FXB_FBMODE],snes_writebuf_data_r[`FXB_FB]};  // 8'h23,
        ADDR_BMAPS : BMAPS_r[`BMAPS_SBM] <= snes_writebuf_data_r[`BMAPS_SBM];  // 8'h24,
        ADDR_BMAP  : BMAP_r              <= snes_writebuf_data_r;  // 8'h25,
        ADDR_SWBE  : SWBE_r[`SWBE_SWEN]  <= snes_writebuf_data_r[`SWBE_SWEN];  // 8'h26,
        ADDR_CWBE  : CWBE_r[`CWBE_CWEN]  <= snes_writebuf_data_r[`CWBE_CWEN];  // 8'h27,
        ADDR_BWPA  : BWPA_r[`BWPA_BWP]   <= snes_writebuf_data_r[`BWPA_BWP];  // 8'h28,
        ADDR_SIWP  : SIWP_r              <= snes_writebuf_data_r;  // 8'h29,
        ADDR_CIWP  : CIWP_r              <= snes_writebuf_data_r;  // 8'h2A,
        // TODO: decide if we need to reset the DMA line counter here
        ADDR_DCNT  : {DCNT_r[7:4],DCNT_r[2:0]} <= {snes_writebuf_data_r[7:4],snes_writebuf_data_r[2:0]};  // 8'h30,
        ADDR_CDMA  : {CDMA_r[`CDMA_CHDEND],CDMA_r[`CDMA_DMASIZE],CDMA_r[`CDMA_DMACB]} <= {snes_writebuf_data_r[`CDMA_CHDEND],snes_writebuf_data_r[`CDMA_DMASIZE],snes_writebuf_data_r[`CDMA_DMACB]};  // 8'h31,
        ADDR_SDA   : SDA_r[7:0]          <= snes_writebuf_data_r;  // 8'h32, // $3
        ADDR_SDA+1 : SDA_r[15:8]         <= snes_writebuf_data_r;  // 8'h32, // $3
        ADDR_SDA+2 : SDA_r[23:16]        <= snes_writebuf_data_r;  // 8'h32, // $3
        // TODO: need to trigger DMA on appropriate write of DDA
        ADDR_DDA   : DDA_r[7:0]          <= snes_writebuf_data_r;  // 8'h35, // $3
        ADDR_DDA+1 : DDA_r[15:8]         <= snes_writebuf_data_r;  // 8'h35, // $3
        ADDR_DDA+2 : DDA_r[23:16]        <= snes_writebuf_data_r;  // 8'h35, // $3
        ADDR_DTC   : DTC_r[7:0]          <= snes_writebuf_data_r;  // 8'h38, // $2
        ADDR_DTC+1 : DTC_r[15:8]         <= snes_writebuf_data_r;  // 8'h38, // $2
        ADDR_BBF   : BBF_r[`BBF_BBF]     <= snes_writebuf_data_r[`BBF_BBF];  // 8'h3F,
        ADDR_BRF+0 : BRF_r[0][7:0]       <= snes_writebuf_data_r;  // 8'h40,
        ADDR_BRF+1 : BRF_r[0][15:8]      <= snes_writebuf_data_r;  // 8'h41,
        ADDR_BRF+2 : BRF_r[1][7:0]       <= snes_writebuf_data_r;  // 8'h42,
        ADDR_BRF+3 : BRF_r[1][15:8]      <= snes_writebuf_data_r;  // 8'h43,
        ADDR_BRF+4 : BRF_r[2][7:0]       <= snes_writebuf_data_r;  // 8'h44,
        ADDR_BRF+5 : BRF_r[2][15:8]      <= snes_writebuf_data_r;  // 8'h45,
        ADDR_BRF+6 : BRF_r[3][7:0]       <= snes_writebuf_data_r;  // 8'h46,
        // TODO: highest address 7/F BRF writes can cause a DMA
        ADDR_BRF+7 : BRF_r[3][15:8]      <= snes_writebuf_data_r;  // 8'h47,
        ADDR_BRF+8 : BRF_r[4][7:0]       <= snes_writebuf_data_r;  // 8'h48,
        ADDR_BRF+9 : BRF_r[4][15:8]      <= snes_writebuf_data_r;  // 8'h49,
        ADDR_BRF+10: BRF_r[5][7:0]       <= snes_writebuf_data_r;  // 8'h4A,
        ADDR_BRF+11: BRF_r[5][15:8]      <= snes_writebuf_data_r;  // 8'h4B,
        ADDR_BRF+12: BRF_r[6][7:0]       <= snes_writebuf_data_r;  // 8'h4C,
        ADDR_BRF+13: BRF_r[6][15:8]      <= snes_writebuf_data_r;  // 8'h4D,
        ADDR_BRF+14: BRF_r[7][7:0]       <= snes_writebuf_data_r;  // 8'h4E,
        // TODO: highest address 7/F BRF writes can cause a DMA
        ADDR_BRF+15: BRF_r[7][15:8]      <= snes_writebuf_data_r;  // 8'h4F,  
        ADDR_MCNT  : {MCNT_r[`MCNT_ACM],MCNT_r[`MCNT_MD]} <= {snes_writebuf_data_r[`MCNT_ACM],snes_writebuf_data_r[`MCNT_MD]}; // 8'h50,
        ADDR_MA    : MA_r[7:0]           <= snes_writebuf_data_r;  // 8'h51, // $2
        ADDR_MA+1  : MA_r[15:8]          <= snes_writebuf_data_r;  // 8'h51, // $2
        ADDR_MB    : MB_r[7:0]           <= snes_writebuf_data_r;  // 8'h53, // $2
        // TODO: perform multiply
        ADDR_MB+1  : begin // 8'h53, // $2
          MB_r <= 0;
          if (MCNT_r[`MCNT_MD]) MA_r <= 0;
          
          //MB_r[15:8]          <= snes_writebuf_data_r;
        end
        ADDR_VBD   : begin  // 8'h58,
          {VBD_r[`VBD_HL],VBD_r[`VBD_VB]} <= {snes_writebuf_data_r[`VBD_HL],snes_writebuf_data_r[`VBD_VB]};
          
          // TODO: perform side effects
          if (~snes_writebuf_data_r[`VBD_HL]) begin
            
          end
        end
        ADDR_VDA   : VDA_r[7:0]          <= snes_writebuf_data_r;  // 8'h59  // $3
        ADDR_VDA+1 : VDA_r[15:8]         <= snes_writebuf_data_r;  // 8'h59  // $3
        // TODO: trigger the data read
        ADDR_VDA+2 : VDA_r[23:16]        <= snes_writebuf_data_r;  // 8'h59  // $3
        default: begin end
      endcase
    end
    else if (snes_readbuf_val_r) begin
      // TODO: clear interrupt and other side affects
    end
  end
end

//-------------------------------------------------------------------
// Math
//-------------------------------------------------------------------
wire [31:0] mult_out;
wire [15:0] divq_out;
wire [15:0] divr_out;
wire        div_by_zero;

reg  [1:0]  math_md_r; initial math_md_r = 0;
reg  [15:0] math_ma_r; initial math_ma_r = 0;
reg  [15:0] math_mb_r; initial math_mb_r = 0;

reg         math_val_r; initial math_val_r = 0;

sa1_mult mult(
  .clk(CLK),
  .a(math_ma_r),
  .b(math_mb_r),
  .p(mult_out)
);

sa1_div div(
  .clk(CLK),
  .dividend(math_ma_r),
  .divisor(math_mb_r),
  .quotient(divq_out),
  .fractional(divr_out)
);

reg  [40:0] math_result;

always @(posedge CLK) begin   
  if (RST) begin
    math_md_r <= 0;
    math_ma_r <= 0;
    math_mb_r <= 0;
    
    MR_r      <= 0;
    OF_r      <= 0;
  end
  else begin
    if (snes_writebuf_val_r) begin
      if (~math_val_r) begin
        if (snes_writebuf_addr_r[7:0] == ADDR_MB+1) begin
          // flop all inputs
          math_md_r <= MCNT_r[1:0];
          math_ma_r <= MA_r;
          math_mb_r <= {snes_writebuf_data_r,MB_r[7:0]};
        
          math_val_r <= 1;
        end
        else if (snes_writebuf_addr_r[7:0] == ADDR_MCNT) begin
          if (snes_writebuf_data_r[`MCNT_ACM]) MR_r <= 0;
        end
      end
    end
    else begin
      math_val_r <= 0;
    end
  
    if      (math_md_r[`MCNT_ACM]) begin
      math_result[40:0] = {1'b0,MR_r} + {17'h000,mult_out};
      MR_r <= math_result[39:0];
      // set overflow
      OF_r <= math_result[40];
    end
    else if (math_md_r[`MCNT_MD]) begin
      MR_r[39:32] <= 0;
      MR_r[31:0] <= |math_mb_r ? {divr_out,divq_out} : 0;
    end
    else begin
      MR_r[39:32] <= 0;
      MR_r[31:0] <= mult_out;
    end
  end
end

//-------------------------------------------------------------------
// COMMON EXE STATE
//-------------------------------------------------------------------
`define GRP_PRI     0
`define GRP_RMW     1
`define GRP_CBR     2
`define GRP_JMP     3
`define GRP_PHS     4
`define GRP_PLL     5
`define GRP_CMP     6
`define GRP_STS     7
`define GRP_MOV     8
`define GRP_TXR     9
`define GRP_SPC     10
`define GRP_SMP     11
`define GRP_STK     12
`define GRP_XCH     13
`define GRP_TST     14

`define ADD_O16     0
`define ADD_DPR     1
`define ADD_PCR     2
`define ADD_SPL     3
`define ADD_SMI     4
`define ADD_SPR     5

`define BNK_PBR     0
`define BNK_DBR     1
`define BNK_ZRO     2
`define BNK_O24     3

`define MOD_X16     0
`define MOD_Y16     1
`define MOD_YPT     2
`define MOD_INV     3

`define ADD_STK     31:31
`define ADD_LNG     30:30
`define ADD_IND     29:29
`define ADD_IMM     28:28
`define ADD_MOD     27:26
`define ADD_ADD     25:23
`define ADD_BNK     22:21
`define DEC_GROUP   20:17
`define DEC_SIZE    16:15
`define DEC_LATENCY 14:11
`define DEC_PRC     10:9
`define DEC_SRC      8:6
`define DEC_DST      5:3
`define DEC_LOAD     2:2
`define DEC_STORE    1:1
`define DEC_CONTROL  0:0

`define PRC_B        0
`define PRC_M        1
`define PRC_X        2
`define PRC_W        3

`define REG_Z        0
`define REG_A        1
`define REG_X        2
`define REG_Y        3
`define REG_S        4
`define REG_D        5
`define REG_B        6
`define REG_P        7

parameter
  ST_EXE_IDLE        = 8'b00000001,
  ST_EXE_FETCH       = 8'b00000010,
  ST_EXE_FETCH_END   = 8'b00000100,
  ST_EXE_ADDRESS     = 8'b00001000,
  ST_EXE_ADDRESS_END = 8'b00010000,
  ST_EXE_EXECUTE     = 8'b00100000,
  ST_EXE_EXECUTE_END = 8'b01000000,
  ST_EXE_WAIT        = 8'b10000000,
  ST_EXE_ALL         = 8'b11111111;

reg [7:0]  EXE_STATE; initial EXE_STATE = ST_EXE_IDLE;
reg [23:0] exe_fetch_addr_r; initial exe_fetch_addr_r = 0;
reg [31:0] exe_decode_r; initial exe_decode_r = 0;

wire       exe_dec_add_stk  = exe_decode_r[`ADD_STK];
wire       exe_dec_add_imm  = exe_decode_r[`ADD_IMM];
wire [1:0] exe_dec_add_bank = exe_decode_r[`ADD_BNK];
wire [2:0] exe_dec_add_base = exe_decode_r[`ADD_ADD];
wire [1:0] exe_dec_add_mod  = exe_decode_r[`ADD_MOD];
wire       exe_dec_add_indirect = exe_decode_r[`ADD_IND];
wire       exe_dec_add_long = exe_decode_r[`ADD_LNG];
wire [3:0] exe_dec_grp      = exe_decode_r[`DEC_GROUP];
//wire [6:0] exe_dec_inst  = exe_decode_r[`DEC_OPCODE];
wire [1:0] exe_dec_size  = exe_decode_r[`DEC_SIZE];
wire [3:0] exe_dec_lat   = exe_decode_r[`DEC_LATENCY];
wire [1:0] exe_dec_prc   = exe_decode_r[`DEC_PRC];
wire [2:0] exe_dec_src   = exe_decode_r[`DEC_SRC];
wire [2:0] exe_dec_dst   = exe_decode_r[`DEC_DST];
wire       exe_dec_load  = exe_decode_r[`DEC_LOAD];
wire       exe_dec_store = exe_decode_r[`DEC_STORE];
wire       exe_dec_ctl   = exe_decode_r[`DEC_CONTROL];

reg        exe_wai_r; initial exe_wai_r = 0;

wire       exe_mmc_int;

//-------------------------------------------------------------------
// COMMON PIPELINE
//-------------------------------------------------------------------
reg [3:0] exe_waitcnt_r; initial exe_waitcnt_r = 0;
reg [3:0] e2c_waitcnt_r; initial e2c_waitcnt_r = 0;

always @(posedge CLK) begin
  if (RST) begin
    exe_waitcnt_r <= 0;
    
    step_r <= 0;
  end
  else begin
    if (sa1_clock_en & |exe_waitcnt_r) exe_waitcnt_r <= exe_waitcnt_r + e2c_waitcnt_r - 1;
    else                               exe_waitcnt_r <= exe_waitcnt_r + e2c_waitcnt_r;
    
    // ok to advance to next instruction byte
    step_r <= CONFIG_CONTROL_ENABLED || (!op_complete & !CONFIG_CONTROL_MATCHPARTINST) || (stepcnt_r != CONFIG_STEP_COUNT);
    
    if (pipeline_advance & (op_complete | CONFIG_CONTROL_MATCHPARTINST)) stepcnt_r <= CONFIG_STEP_COUNT;
  end
end

//-------------------------------------------------------------------
// IRAM
//-------------------------------------------------------------------
wire         iram_wren;
wire [10:0]  iram_addr;
wire [7:0]   iram_din;
wire [7:0]   iram_dout;

// TDP macro simplifies abritration between the snes and sa1.  Also use
// spare cycles for debug reads.
wire         snes_iram_wren = snes_writebuf_iram_r;
wire [10:0]  snes_iram_addr = snes_writebuf_iram_r ? snes_writebuf_addr_r
                            : snes_readbuf_iram_r  ? snes_readbuf_addr_r
                            : pgm_addr_r[10:0];
wire [7:0]   snes_iram_din  = snes_writebuf_data_r;
wire [7:0]   snes_iram_dout;

sa1_iram iram (
  .clka(CLK), // input clka
  .wea(iram_wren), // input [0 : 0] wea
  .addra(iram_addr), // input [10 : 0] addra
  .dina(iram_din), // input [7 : 0] dina
  .douta(iram_dout), // output [7 : 0] douta

  .clkb(CLK), // input clkb
  .web(snes_iram_wren), // input [0 : 0] web
  .addrb(snes_iram_addr), // input [10 : 0] addrb
  .dinb(snes_iram_din), // input [7 : 0] dinb
  .doutb(snes_iram_dout) // output [7 : 0] doutb
);

assign snes_iram_out = snes_iram_dout;

//-------------------------------------------------------------------
// MMC PIPELINE
//-------------------------------------------------------------------
// Unified memory access.  All requests are serialized and allowed
// to access as fast as the associated pipeline supports.  This covers
// the following:
//  sources: sa1, dma, vdp (TBD may be moved to main.v)
//  targets: rom, bram, iram, mmio
//
// The unified state machine supports: single MDR, consolidated address map logic,
// priority scheduling.
//
// It's not clear whether there is a store buffer in the sa1 to overlap post store commit with
// instruction fetch (likely to rom) and other operations.
// To simplify the design don't support a store buffer unless we need the performance.
// The MDR and priority gets more complicated if we need to do parallel accesses to the different
// targets.  NOTE: The ready check blocks all operations.  The pipe is strictly in-order.
//
parameter
  ST_MMC_IDLE      = 8'b00000001,
  ST_MMC_ROM       = 8'b00000010,
  ST_MMC_BRAM      = 8'b00000100,
  ST_MMC_IRAM      = 8'b00001000,
  ST_MMC_MMIO      = 8'b00010000,
  ST_MMC_INV       = 8'b00100000,
  ST_MMC_EXE_END   = 8'b01000000,
  ST_MMC_DMA_END   = 8'b10000000,
  ST_MMC_ALL       = 8'b11111111;
  
reg [7:0]  MMC_STATE; initial MMC_STATE = ST_MMC_IDLE;
reg [7:0]  MDR_r;  initial MDR_r  = 0;
reg [23:0] mmc_addr_r;
reg [31:0] mmc_data_r; initial mmc_data_r = 0;
reg        mmc_wr_r; initial mmc_wr_r = 0;
reg        mmc_dpe_r; initial mmc_dpe_r = 0;
reg [1:0]  mmc_byte_r; initial mmc_byte_r = 0;
reg [1:0]  mmc_byte_total_r; initial mmc_byte_total_r = 0;
reg        mmc_long_r; initial mmc_long_r = 0;
reg [7:0]  mmc_state_end_r;

// rom
reg rom_bus_rrq_r; initial rom_bus_rrq_r = 0;
reg rom_bus_wrq_r; initial rom_bus_wrq_r = 0;
reg [23:0] rom_bus_addr_r;
reg [15:0] rom_bus_data_r;
reg        rom_bus_word_r;

// bram
reg ram_bus_rrq_r; initial ram_bus_rrq_r = 0;
reg ram_bus_wrq_r; initial ram_bus_wrq_r = 0;
reg [23:0] ram_bus_addr_r;
reg [15:0] ram_bus_data_r;
reg        ram_bus_word_r;

// iram
reg        mmc_iram_state_r;

// mmio
// -

wire [23:0] exe_mmc_addr;

always @(posedge CLK) begin
  if (RST) begin
    MMC_STATE <= ST_MMC_IDLE;
    MDR_r <= 0;
    mmc_long_r <= 0;
  end
  else begin
    case (MMC_STATE)
      ST_MMC_IDLE: begin
        // priority
        // - vdp
        // - dma (high pri)
        // - exe
        // - dma (low pri)
        mmc_byte_r <= 0;

        if (vdp_mmc_rd_r) begin
        end
        // TODO: assign priority conditions
        else if ((dma_mmc_rd_r | dma_mmc_wr_r)) begin
          mmc_byte_total_r<= 0;
          mmc_dpe_r       <= 0;
          mmc_wr_r        <= dma_mmc_wr_r;
          mmc_long_r      <= 0;
          mmc_data_r[7:0] <= dma_mmc_data_r;

          // NOTE: could move this decode to DMA
          if      (`IS_ROM(dma_mmc_addr_r) & ROM_BUS_RDY) begin
            rom_bus_rrq_r  <= ~dma_mmc_wr_r;
            rom_bus_addr_r <= `MAP_ROM(dma_mmc_addr_r);
            rom_bus_word_r <= 1;
            mmc_addr_r     <= `MAP_ROM(dma_mmc_addr_r);

            MMC_STATE      <= dma_mmc_wr_r ? ST_MMC_INV : ST_MMC_ROM;
          end
          else if (`IS_BRAM(dma_mmc_addr_r) & ROM_BUS_RDY) begin
            rom_bus_rrq_r  <= ~dma_mmc_wr_r;
            rom_bus_wrq_r  <=  dma_mmc_wr_r;
            rom_bus_addr_r <= `MAP_BRAM(dma_mmc_addr_r);
            rom_bus_data_r <= dma_mmc_data_r[7:0];
            rom_bus_word_r <= 0;

            mmc_addr_r     <= `MAP_BRAM(dma_mmc_addr_r);
            MMC_STATE      <= ST_MMC_BRAM;
          end
          else if (`IS_SA1_IRAM(dma_mmc_addr_r)) begin
            mmc_iram_state_r <= 0;
            mmc_addr_r     <= `MAP_IRAM(dma_mmc_addr_r);
            MMC_STATE      <= ST_MMC_IRAM;
          end
//          else if (`IS_SA1_PRAM(exe_mmc_addr) & ROM_BUS_RDY) begin
//            rom_bus_rrq_r  <= ~exe_mmc_wr_r;
//            rom_bus_addr_r <= `MAP_PRAM(exe_mmc_addr);
//            rom_bus_data_r <= exe_mmc_data_r[7:0];
//            rom_bus_word_r <= 0;
//            
//            mmc_addr_r     <= `MAP_PRAM(exe_mmc_addr);
//            mmc_busy_r <= 1;
//            MMC_STATE <= exe_mmc_wr_r ? ST_MMC_INV : ST_MMC_BRAM;
//          end
          else begin
            rom_bus_rrq_r <= 0;
            rom_bus_wrq_r <= 0;
            MMC_STATE <= ST_MMC_INV;
          end

          mmc_state_end_r <= ST_MMC_DMA_END;
        end
        // save a cycle in fetch if we are going to rom.
        else if (EXE_STATE[clog2(ST_EXE_FETCH)]) begin
          mmc_byte_total_r <= exe_mmc_byte_total_r;
          mmc_dpe_r <= exe_mmc_dpe_r;
          mmc_wr_r <= 0;
          mmc_long_r <= exe_mmc_long_r;

          if (`IS_ROM(exe_fetch_addr_r) & ROM_BUS_RDY) begin
            rom_bus_rrq_r <= ~(exe_mmc_wr_r | exe_mmc_int);
            rom_bus_addr_r <= `MAP_ROM(exe_fetch_addr_r);
            rom_bus_word_r <= 1;

            MMC_STATE <= (exe_mmc_wr_r | exe_mmc_int) ? ST_MMC_INV : ST_MMC_ROM;

            mmc_state_end_r <= ST_MMC_EXE_END;
          end
          
        end
        else if (exe_mmc_rd_r | exe_mmc_wr_r) begin
          mmc_byte_total_r <= exe_mmc_byte_total_r;
          mmc_dpe_r <= exe_mmc_dpe_r;
          mmc_wr_r <= exe_mmc_wr_r;
          mmc_long_r <= exe_mmc_long_r;
          mmc_data_r <= exe_mmc_data_r;

          if      (`IS_ROM(exe_mmc_addr) & ROM_BUS_RDY) begin
            rom_bus_rrq_r  <= ~exe_mmc_wr_r;
            rom_bus_addr_r <= `MAP_ROM(exe_mmc_addr);
            rom_bus_word_r <= 1;
            mmc_addr_r     <= `MAP_ROM(exe_mmc_addr);

            MMC_STATE <= exe_mmc_wr_r ? ST_MMC_INV : ST_MMC_ROM;
          end
          else if (`IS_BRAM(exe_mmc_addr) & ROM_BUS_RDY) begin
            rom_bus_rrq_r  <= ~exe_mmc_wr_r;
            rom_bus_wrq_r  <=  exe_mmc_wr_r;
            rom_bus_addr_r <= `MAP_BRAM(exe_mmc_addr);
            rom_bus_data_r <= exe_mmc_data_r[7:0];
            rom_bus_word_r <= 0;

            mmc_addr_r     <= `MAP_BRAM(exe_mmc_addr);
            MMC_STATE <= ST_MMC_BRAM;
          end
          else if (`IS_SA1_IRAM(exe_mmc_addr)) begin
            mmc_iram_state_r <= 0;
            mmc_addr_r    <= `MAP_IRAM(exe_mmc_addr);
            MMC_STATE <= ST_MMC_IRAM;
          end
          else if (`IS_MMIO(exe_mmc_addr)) begin
            mmc_addr_r    <= `MAP_MMIO(exe_mmc_addr);
            MMC_STATE <= ST_MMC_MMIO;
          end
          else if (`IS_SA1_PRAM(exe_mmc_addr) & ROM_BUS_RDY) begin
            rom_bus_rrq_r  <= ~exe_mmc_wr_r;
            rom_bus_addr_r <= `MAP_PRAM(exe_mmc_addr);
            rom_bus_data_r <= exe_mmc_data_r[7:0];
            rom_bus_word_r <= 0;
            
            mmc_addr_r     <= `MAP_PRAM(exe_mmc_addr);
            MMC_STATE <= exe_mmc_wr_r ? ST_MMC_INV : ST_MMC_BRAM;
          end
          else begin
            rom_bus_rrq_r <= 0;
            MMC_STATE <= ST_MMC_INV;
          end
          
          mmc_state_end_r <= ST_MMC_EXE_END;
        end
        // TODO: assign priority conditions
        else if ((dma_mmc_rd_r | dma_mmc_wr_r) & 1) begin
        
        end
        
      end
      ST_MMC_ROM: begin
        rom_bus_rrq_r <= 0;

        if (~rom_bus_rrq_r & ROM_BUS_RDY) begin
          mmc_byte_r[1] <= 1;

          case (mmc_byte_r[1])
            0: mmc_data_r[15: 0] <= ROM_BUS_RDDATA[15:0];
            1: mmc_data_r[31:16] <= ROM_BUS_RDDATA[15:0];
          endcase
          
          if (mmc_byte_r[1] != mmc_byte_total_r[1]) begin
            rom_bus_rrq_r <= 1;

            // FIXME: we could cross into a new memory region...
            if      (mmc_dpe_r)  rom_bus_addr_r[7:0]  <= rom_bus_addr_r[7:0]  + 2;
            else if (mmc_long_r) rom_bus_addr_r[23:0] <= rom_bus_addr_r[23:0] + 2;
            else                 rom_bus_addr_r[15:0] <= rom_bus_addr_r[15:0] + 2;
          end
          else begin
            MMC_STATE <= mmc_state_end_r;
          end
        end
      end
      ST_MMC_BRAM: begin
        rom_bus_rrq_r <= 0;
        rom_bus_wrq_r <= 0;

        if (~rom_bus_rrq_r & ~rom_bus_wrq_r & ROM_BUS_RDY) begin
          mmc_byte_r <= mmc_byte_r + 1;

          if (~mmc_wr_r) begin
            case (mmc_byte_r)
              0: mmc_data_r[ 7: 0] <= ROM_BUS_RDDATA[7:0];
              1: mmc_data_r[15: 8] <= ROM_BUS_RDDATA[7:0];
              2: mmc_data_r[23:16] <= ROM_BUS_RDDATA[7:0];
              3: mmc_data_r[31:24] <= ROM_BUS_RDDATA[7:0];
            endcase
          end
          else begin
            mmc_data_r <= {mmc_data_r[7:0],mmc_data_r[31:24],mmc_data_r[23:16],mmc_data_r[15:8]};
          end
          
          if (mmc_byte_r != mmc_byte_total_r) begin
            // stay in the same state and make a new request
            rom_bus_rrq_r  <= ~mmc_wr_r;
            rom_bus_wrq_r  <=  mmc_wr_r;
            
            if      (mmc_dpe_r)  rom_bus_addr_r[7:0]  <= rom_bus_addr_r[7:0]  + 1;
            else if (mmc_long_r) rom_bus_addr_r[23:0] <= rom_bus_addr_r[23:0] + 1;
            else                 rom_bus_addr_r[15:0] <= rom_bus_addr_r[15:0] + 1;
            
            rom_bus_data_r <= mmc_data_r[15:8];
          end
          else begin
            MMC_STATE <= mmc_state_end_r;
          end
        end
      end
      ST_MMC_IRAM: begin
        mmc_iram_state_r <= ~mmc_iram_state_r;
      
        if (mmc_iram_state_r) begin
          mmc_byte_r <= mmc_byte_r + 1;
          
          if (~mmc_wr_r) begin
            case (mmc_byte_r)
              0: mmc_data_r[ 7: 0] <= iram_dout[7:0];
              1: mmc_data_r[15: 8] <= iram_dout[7:0];
              2: mmc_data_r[23:16] <= iram_dout[7:0];
              3: mmc_data_r[31:24] <= iram_dout[7:0];
            endcase
          end
          else begin
            mmc_data_r <= {mmc_data_r[7:0],mmc_data_r[31:24],mmc_data_r[23:16],mmc_data_r[15:8]};
          end

          if (mmc_byte_r != mmc_byte_total_r) begin
            if (mmc_dpe_r) mmc_addr_r[7:0]  <= mmc_addr_r[7:0] + 1;
            else           mmc_addr_r[10:0] <= mmc_addr_r[10:0] + 1;
          end
          else begin
            MMC_STATE <= mmc_state_end_r;
          end
        end
      end
      ST_MMC_MMIO: begin       
        if ((mmc_wr_r & sa1_mmio_write) | (~mmc_wr_r & sa1_mmio_read_r[1])) begin
          mmc_byte_r <= mmc_byte_r + 1;

          if (~mmc_wr_r) begin
            case (mmc_byte_r)
              0: mmc_data_r[ 7: 0] <= data_out_r[7:0];
              1: mmc_data_r[15: 8] <= data_out_r[7:0];
              2: mmc_data_r[23:16] <= data_out_r[7:0];
              3: mmc_data_r[31:23] <= data_out_r[7:0];
            endcase
          end
          else begin
            mmc_data_r <= {mmc_data_r[7:0],mmc_data_r[31:24],mmc_data_r[23:16],mmc_data_r[15:8]};
          end
          
          if (mmc_byte_r != mmc_byte_total_r) begin
            mmc_addr_r[7:0] <= mmc_addr_r[7:0] + 1;
          end
          else begin
            MMC_STATE <= mmc_state_end_r;
          end
        end
      end
      ST_MMC_INV: begin
        // interrupt returns BRK instruction
        mmc_data_r <= {MDR_r,MDR_r,MDR_r,(exe_mmc_int ? 8'h00 : MDR_r)};
        MMC_STATE <= mmc_state_end_r;
      end
      ST_MMC_EXE_END,
      ST_MMC_DMA_END: begin
        MMC_STATE <= ST_MMC_IDLE;
      end
    endcase
  end
end

// support misaligned access to upper region
assign ROM_BUS_RRQ = rom_bus_rrq_r;
assign ROM_BUS_WRQ = rom_bus_wrq_r;
assign ROM_BUS_WORD = rom_bus_word_r;
assign ROM_BUS_ADDR = {rom_bus_addr_r[23] | (rom_bus_addr_r[0] & rom_bus_word_r), rom_bus_addr_r[22:1], (rom_bus_addr_r[23] | ~rom_bus_word_r) & rom_bus_addr_r[0]};
assign ROM_BUS_WRDATA = rom_bus_data_r;

`ifdef CSRAM
assign RAM_BUS_RRQ = ram_bus_rrq_r;
assign RAM_BUS_WRQ = ram_bus_wrq_r;
assign RAM_BUS_WORD = ram_bus_word_r;
assign RAM_BUS_ADDR = ram_bus_addr_r;
assign RAM_BUS_WRDATA = ram_bus_data_r;
`endif

assign iram_wren = MMC_STATE[clog2(ST_MMC_IRAM)] & mmc_wr_r;
assign iram_addr = mmc_addr_r[10:0];
assign iram_din  = mmc_data_r[7:0];

assign sa1_mmio_addr  = mmc_addr_r[7:0];
assign sa1_mmio_data  = mmc_data_r[7:0];
assign sa1_mmio_write = ~SNES_WR_end & ~snes_writebuf_iram_r & ~snes_writebuf_val_r & MMC_STATE[clog2(ST_MMC_MMIO)] & mmc_wr_r;
assign sa1_mmio_read  = ~|sa1_mmio_read_r & ~snes_readbuf_active_r & MMC_STATE[clog2(ST_MMC_MMIO)] & ~mmc_wr_r;

//-------------------------------------------------------------------
// DMA Pipeline
//-------------------------------------------------------------------
// The DMA controller supports 2 general modes of operation: normal
// and character conversion (CC).  CC can be broken down into type1
// (fully automatic) and type2 (semi-automatic).  In an attempt to
// get this to fit in the fpga, as much code as re-used as possible.
// The main differences between the 2 modes are addressing/dataswizzle
// and triggers.
//
// normal - no character conversion.  can trigger interrupt.  dtc holds count.  triggered by dda write.
// type1  - bram->iram character conversion.  planar to pixel.  8x8 character.  triggered by snes reads.
// type2  - brf->iram character conversion.  pixel to planar. 8 pixels in lower or upper brf.  triggered by brf writes.
//
// TODO:
// - type1
// - check interrupt mechanism
// - stall execute pipe for type1/type2 while busy.  type2 will be fast.  type1 will require up to 8x8 bram reads and 8x8 iram writes.
parameter
  ST_DMA_IDLE        = 8'b00000001,
  ST_DMA_NORMAL_READ = 8'b00000010,
  ST_DMA_TYPE1_READ  = 8'b00000100,
  ST_DMA_TYPE2_READ  = 8'b00001000,
  ST_DMA_READ_END    = 8'b00010000,
  ST_DMA_TYPE1_WRITE = 8'b00100000,
  ST_DMA_WRITE       = 8'b01000000,
  ST_DMA_WRITE_END   = 8'b10000000,
  ST_DMA_ALL         = 8'b11111111;
  
reg [7:0]  DMA_STATE; initial DMA_STATE = ST_DMA_IDLE;
reg [7:0]  dma_next_readstate_r; initial dma_next_readstate_r = 0;
reg [7:0]  dma_next_writestate_r; initial dma_next_writestate_r = 0;

reg        dma_active_r; initial dma_active_r = 0;
reg [23:0] dma_write_addr_r; initial dma_write_addr_r = 0;
reg [7:0]  dma_data_r; initial dma_data_r = 0;

reg [7:0]  dma_cc1_data_r[7:0];
reg [5:0]  dma_cc1_mask_r;
reg        dma_cc1_int_r;
reg [23:0] dma_cc1_addr_rd_r;

reg        dma_trigger_normal_r; initial dma_trigger_normal_r = 0;
reg        dma_start_type1_r; initial dma_start_type1_r = 0;
reg        dma_trigger_type1_r; initial dma_trigger_type1_r = 0;
reg        dma_trigger_type2_r; initial dma_trigger_type2_r = 0;

reg [3:0]  dma_line_r; initial dma_line_r = 0;
reg [2:0]  dma_byte_r; initial dma_byte_r = 0;
reg [2:0]  dma_comp_r; initial dma_comp_r = 0;

reg [15:0] dma_dtc_r; initial dma_dtc_r = 0;
reg [23:0] dma_sda_r; initial dma_sda_r = 0;
reg [23:0] dma_dda_r; initial dma_dda_r = 0;

always @(posedge CLK) begin
  if (RST) begin
    DMA_STATE             <= ST_DMA_IDLE;
    dma_next_readstate_r  <= ST_DMA_IDLE;
    dma_next_writestate_r <= ST_DMA_IDLE;
    
    dma_mmc_rd_r <= 0;
    dma_mmc_wr_r <= 0;
    
    dma_trigger_normal_r <= 0;
    dma_start_type1_r    <= 0;
    dma_trigger_type1_r  <= 0;
    dma_trigger_type2_r  <= 0;

    dma_line_r <= 0;
    
    SFR_r[`SFR_DMA_IRQFL] <= 0;
    CFR_r[`CFR_DMA_IRQFL] <= 0;
  end
  else begin
    // watch for triggers
    dma_trigger_normal_r <= (   DCNT_r[`DCNT_DMAEN]
                            && ~DCNT_r[`DCNT_CDEN]
                            && (  (~DCNT_r[1] && ~DCNT_r[`DCNT_DD]) // iram
                               || (~DCNT_r[0] &&  DCNT_r[`DCNT_DD]) // bram
                               )
                            && (  (snes_writebuf_val_r && snes_writebuf_addr_r[7:0] == (ADDR_DDA+1) && ~DCNT_r[`DCNT_DD]) // iram
                               || (snes_writebuf_val_r && snes_writebuf_addr_r[7:0] == (ADDR_DDA+2) &&  DCNT_r[`DCNT_DD]) // bram
                               )
                            );
    dma_start_type1_r    <= (   DCNT_r[`DCNT_DMAEN]
                            &&  DCNT_r[`DCNT_CDEN]
                            &&  DCNT_r[`DCNT_CDSEL]
                            && (  (snes_writebuf_val_r && snes_writebuf_addr_r[7:0] == (ADDR_DDA+1))
                               )
                            );
    dma_trigger_type1_r  <= (   CDMA_r[`CDMA_CHDEND]
                            &&  `IS_BRAM(addr_in_r)
                            &&  SNES_RD_start
                            &&  ((addr_in_r[5:0] & dma_cc1_mask_r) == 0)
                            );
    dma_trigger_type2_r  <= (   DCNT_r[`DCNT_DMAEN]
                            &&  DCNT_r[`DCNT_CDEN]
                            && ~DCNT_r[`DCNT_CDSEL]
                            && (  (snes_writebuf_val_r && snes_writebuf_addr_r[7:0] == ADDR_BRF7)
                               || (snes_writebuf_val_r && snes_writebuf_addr_r[7:0] == ADDR_BRFF)
                               )
                            );
                            
    dma_cc1_addr_rd_r <= 0;
    
    dma_comp_r     <= {~|CDMA_r,~CDMA_r[1],1'b1};
    dma_cc1_mask_r <= {dma_comp_r,3'b111};
  
    if      (DMA_STATE[clog2(ST_DMA_IDLE)] & dma_cc1_int_r)                                                        SFR_r[`SFR_DMA_IRQFL] <= 1;
    else if (snes_writebuf_val_r && snes_writebuf_addr_r[7:0] == ADDR_SIC && snes_writebuf_data_r[`SIC_DMA_IRQCL]) SFR_r[`SFR_DMA_IRQFL] <= 0;
  
    case (DMA_STATE)
      ST_DMA_IDLE: begin
        if      (dma_trigger_normal_r)                     DMA_STATE <= ST_DMA_NORMAL_READ;
        else if (dma_start_type1_r | dma_trigger_type1_r)  DMA_STATE <= ST_DMA_TYPE1_READ;
        else if (dma_trigger_type2_r)                      DMA_STATE <= ST_DMA_TYPE2_READ;

        // clear interrupt
        if (snes_writebuf_val_r && snes_writebuf_addr_r[7:0] == ADDR_CIC  &&  snes_writebuf_data_r[`CIC_DMA_IRQCL]) CFR_r[`CFR_DMA_IRQFL] <= 0;
        if (snes_writebuf_val_r && snes_writebuf_addr_r[7:0] == ADDR_SIC  &&  snes_writebuf_data_r[`SIC_DMA_IRQCL]) SFR_r[`SFR_DMA_IRQFL] <= 0;
        if (snes_writebuf_val_r && snes_writebuf_addr_r[7:0] == ADDR_DCNT && ~snes_writebuf_data_r[`DCNT_DMAEN])    dma_line_r            <= 0;
        
        dma_dtc_r <= DTC_r;
        dma_sda_r <= SDA_r;
        dma_dda_r <= DDA_r;
        
        dma_byte_r <= 0;
        
        dma_cc1_int_r <= dma_start_type1_r;       
        // line should always be zero at end
      end
      // normal
      ST_DMA_NORMAL_READ: begin
        if (|dma_dtc_r) begin
          dma_mmc_rd_r <= 1;
          
          dma_dtc_r <= dma_dtc_r - 1;
          dma_sda_r <= dma_sda_r + 1;
          dma_dda_r <= dma_dda_r + 1;

          DMA_STATE <= ST_DMA_READ_END;
        end
        else begin
          CFR_r[`CFR_DMA_IRQFL] <= 1;

          DMA_STATE <= ST_DMA_IDLE;
        end
        
        dma_mmc_addr_r   <= {(dma_sda_r[23:11] & {13{~DCNT_r[1]}}),      dma_sda_r[10:0]};
        dma_write_addr_r <= {(dma_dda_r[23:11] & {13{DCNT_r[`DCNT_DD]}}),dma_dda_r[10:0]};
        
        dma_next_readstate_r  <= ST_DMA_WRITE;
        dma_next_writestate_r <= ST_DMA_NORMAL_READ;
      end

      // type1
      ST_DMA_TYPE1_READ: begin
        // only perform memory read for valid byte
        dma_mmc_rd_r <= (dma_byte_r <= dma_comp_r);
      
        // TODO: calculate address
        dma_mmc_addr_r <= dma_cc1_addr_rd_r;

        dma_byte_r <= dma_byte_r + 1;
        if (&dma_byte_r) dma_line_r <= dma_line_r + 1;
        
        // test for transition to write state
        dma_next_readstate_r <= &dma_byte_r ? ST_DMA_TYPE1_WRITE : ST_DMA_TYPE1_READ;
        
        DMA_STATE <= ST_DMA_READ_END;
      end
      ST_DMA_TYPE1_WRITE: begin
        dma_mmc_wr_r <= (dma_byte_r <= dma_comp_r);
        
        // calculate address
        dma_write_addr_r <= {13'h0000, DDA_r[10:6],dma_byte_r[2:1],dma_line_r[2:0],dma_byte_r[0]};
        
        // perform transpose
        dma_data_r <= {dma_cc1_data_r[7][dma_byte_r],
                       dma_cc1_data_r[6][dma_byte_r],
                       dma_cc1_data_r[5][dma_byte_r],
                       dma_cc1_data_r[4][dma_byte_r],
                       dma_cc1_data_r[3][dma_byte_r],
                       dma_cc1_data_r[2][dma_byte_r],
                       dma_cc1_data_r[1][dma_byte_r],
                       dma_cc1_data_r[0][dma_byte_r]};
        
        dma_next_writestate_r <= &dma_byte_r ? (&dma_line_r ? ST_DMA_IDLE : ST_DMA_TYPE1_READ) : ST_DMA_TYPE1_WRITE;

        DMA_STATE <= ST_DMA_WRITE;
      end
      
      // type2
      ST_DMA_TYPE2_READ: begin
        // compose BRF to iram write
        dma_write_addr_r <= {13'h0000,
                             DDA_r[10:7],
                             (|CDMA_r[`CDMA_DMACB] ? DDA_r[6]                                  : dma_line_r[3]),
                             (CDMA_r[1]            ? DDA_r[5]      : CDMA_r[0] ? dma_line_r[3] : dma_byte_r[2]),
                             (CDMA_r[1]            ? dma_line_r[3] :             dma_byte_r[1]                ),
                             dma_line_r[2:0],
                             dma_byte_r[0]
                            };

        dma_byte_r  <= dma_byte_r + 1;
        
        dma_data_r <= {BRF_r[{dma_line_r[3],3'h7}][dma_byte_r[2:0]],
                       BRF_r[{dma_line_r[3],3'h6}][dma_byte_r[2:0]],
                       BRF_r[{dma_line_r[3],3'h5}][dma_byte_r[2:0]],
                       BRF_r[{dma_line_r[3],3'h4}][dma_byte_r[2:0]],
                       BRF_r[{dma_line_r[3],3'h3}][dma_byte_r[2:0]],
                       BRF_r[{dma_line_r[3],3'h2}][dma_byte_r[2:0]],
                       BRF_r[{dma_line_r[3],3'h1}][dma_byte_r[2:0]],
                       BRF_r[{dma_line_r[3],3'h0}][dma_byte_r[2:0]]};

        if (dma_byte_r == dma_comp_r) dma_line_r <= dma_line_r + 1;
        dma_next_writestate_r <= (dma_byte_r == dma_comp_r) ? ST_DMA_IDLE : ST_DMA_TYPE2_READ;
        
        DMA_STATE <= ST_DMA_WRITE;
      end
      ST_DMA_READ_END: begin
        if (~dma_mmc_rd_r) begin
          DMA_STATE <= dma_next_readstate_r;
        end
        else if (MMC_STATE[clog2(ST_MMC_DMA_END)]) begin
          dma_mmc_rd_r <= 0;
          dma_data_r <= mmc_data_r[7:0];
          
          DMA_STATE <= dma_next_readstate_r;
        end
        
        if (~dma_mmc_rd_r | MMC_STATE[clog2(ST_MMC_DMA_END)]) begin
          // buffer data for transpose
          dma_cc1_data_r[7] <= dma_mmc_rd_r ? mmc_data_r[7:0] : 8'h00;
          for (i = 0; i < 7; i = i + 1) dma_cc1_data_r[i] <= dma_cc1_data_r[i+1];
        end
      end
      ST_DMA_WRITE: begin
        dma_mmc_wr_r   <= 1;
        dma_mmc_addr_r <= dma_write_addr_r;
        dma_mmc_data_r <= dma_data_r;
        
        DMA_STATE <= ST_DMA_WRITE_END;
      end
      ST_DMA_WRITE_END: begin
        if (MMC_STATE[clog2(ST_MMC_DMA_END)]) begin
          dma_mmc_wr_r <= 0;
          
          DMA_STATE <= dma_next_writestate_r;
        end
      end
    endcase
  end
end

//-------------------------------------------------------------------
// DECODER
//-------------------------------------------------------------------

reg [15:0] REG[7:0];
reg [15:0] REGS[7:0];

always @(*) begin
  REG[`REG_Z] = 16'h0000;
  REG[`REG_A] = A_r;
  REG[`REG_X] = X_r;
  REG[`REG_Y] = Y_r;
  REG[`REG_S] = S_r;
  REG[`REG_D] = D_r;
  REG[`REG_B] = {8'h00,DBR_r};
  REG[`REG_P] = {8'h00,P_r};
end

always @(*) begin
  REGS[`REG_Z] = 16'h0000;
  REGS[`REG_A] = A_r;
  REGS[`REG_X] = X_r;
  REGS[`REG_Y] = Y_r;
  REGS[`REG_S] = {8'h00,PBR_r};
  REGS[`REG_D] = D_r;
  REGS[`REG_B] = {8'h00,DBR_r};
  REGS[`REG_P] = {8'h00,P_r};
end

// need to take from the input so we get a clock
wire [7:0]  dec_addr = MMC_STATE[clog2(ST_MMC_ROM)] ? ROM_BUS_RDDATA[7:0] : mmc_data_r[7:0];
wire [31:0] dec_data;

dec_table dec (
  .clka(CLK),       // input clka
  .addra(dec_addr), // input [7 : 0] addra
  .douta(dec_data)  // output [31 : 0] douta
);

//-------------------------------------------------------------------
// Interrupt Controller
//-------------------------------------------------------------------
// The interrupt controller handles sa1 irq and nmi interrupts.
// Interrupts can be observed at cycle boundaries and can't be
// interrupted with the exception of a nmi interrupting a irq.

// TODO: make this a more general state machine?
reg        int_pending_r; initial int_pending_r = 0;
reg        int_nmi_r; initial int_nmi_r = 0;
reg [15:0] int_vector_r; initial int_vector_r = 0;

//sa1_irq_r       <= (CIE_r[`CIE_SA1_IRQEN] & CFR_r[`CFR_SA1_IRQFL]) | (CIE_r[`CIE_TMR_IRQEN] & CFR_r[`CFR_TMR_IRQFL]) | (CIE_r[`CIE_DMA_IRQEN] & CFR_r[`CFR_DMA_IRQFL]);
//sa1_nmi_r       <= (CIE_r[`CIE_SA1_NMIEN] & CFR_r[`CFR_SA1_NMIFL]);

// lots of races to handle:
// - RTI needs to clear nmi interrupt
// - WAI write from execute and clear from interrupt edge (while in WAI state).  Should have common support in mmc for interrupt active.
// - Set/Clear interrupt flag in register state.  Probably move from register stage to here.
always @(posedge CLK) begin
  if (RST) begin
    int_pending_r <= 0;
    int_nmi_r     <= 0;
    
    WAI_r         <= 0;
  end
  else begin
    if ((EXE_STATE[clog2(ST_EXE_WAIT)] & pipeline_advance) | WAI_r) begin
      // check current pending.  taking an interrupt will block nmi and avoid duplicate irq.
      // TODO: this flag needs to control idle, fetch, and execute.
      if (int_pending_r) begin
        int_pending_r <= 0;
      end
      else if (exe_dec_grp == `GRP_SPC && exe_dec_add_stk && !exe_dec_store) begin
        // clear current nmi on rti.  this is either already zero or must be a nmi so unconditionally clear
        int_nmi_r <= 0;
      end
      // check NMI
      else if (CIE_r[`CIE_SA1_NMIEN] & CFR_r[`CFR_SA1_NMIFL] & ~int_nmi_r) begin
        int_pending_r <= 1;
        int_nmi_r     <= 1;
        int_vector_r  <= CNV_r;
      end
      // check IRQ
      else if (~P_r[`P_I]) begin
        // TODO: timer
        // TODO: dma
        // register        
        if (CIE_r[`CIE_SA1_IRQEN] & CFR_r[`CFR_SA1_IRQFL]) begin
          int_pending_r <= 1;
          int_nmi_r     <= 0;
          int_vector_r  <= CIV_r;
        end
      end
    end
    
    // WAI set/clear
    if (WAI_r & int_pending_r) begin
      // will always get cleared on a non-sa1 cycle.
      WAI_r <= 0;
    end
    else if (EXE_STATE[clog2(ST_EXE_WAIT)] & pipeline_advance & exe_wai_r) begin
      WAI_r <= 1;
    end
  end
end

assign exe_mmc_int = int_pending_r;

//-------------------------------------------------------------------
// EXECUTION PIPELINE
//-------------------------------------------------------------------

reg [31:0] exe_data_r;
reg [23:0] exe_addr_r; initial exe_addr_r = 0;
reg [23:0] exe_mmc_addr_r; initial exe_mmc_addr_r = 0;

reg [1:0]  exe_opsize_r; initial exe_opsize_r = 0;
reg [7:0]  exe_opcode_r; initial exe_opcode_r = 0;
reg [23:0] exe_operand_r; initial exe_operand_r = 0;

reg [15:0] exe_src_r; initial exe_src_r = 16'h0BAD;
reg [15:0] exe_dst_r; initial exe_dst_r = 16'h0BAD;

reg        exe_control_r; initial exe_control_r = 0;
reg        exe_load_r; initial exe_load_r = 0;
reg        exe_store_r; initial exe_store_r = 0;
reg        exe_data_word_r; initial exe_data_word_r = 0;
reg [15:0] exe_nextpc_r; initial exe_nextpc_r = 0;
reg [15:0] exe_nextpc_addr_r; initial exe_nextpc_addr_r = 0;
reg [15:0] exe_add_post_r; initial exe_add_post_r = 0;
reg        exe_dst_p_r; initial exe_dst_p_r = 0;
reg [23:0] exe_target_r; initial exe_target_r = 0;
reg [15:0] exe_mod_r; initial exe_mod_r = 0;

reg [15:0] exe_a_r; initial exe_a_r = 0;
reg [15:0] exe_x_r; initial exe_x_r = 0;
reg [15:0] exe_y_r; initial exe_y_r = 0;
reg [15:0] exe_s_r; initial exe_s_r = 16'h01FF;
reg [15:0] exe_d_r; initial exe_d_r = 0;
reg [7:0]  exe_dbr_r; initial exe_dbr_r = 0;
reg [7:0]  exe_pbr_r; initial exe_pbr_r = 0;
reg [7:0]  exe_p_r; initial exe_p_r = 0;
reg        exe_e_r; initial exe_e_r = 1;

reg        exe_active_r; initial exe_active_r = 0;

wire       exe_dpe       = ~|D_r[7:0] & E_r;
wire       exe_data_word = |({~P_r[`P_X],~P_r[`P_M]}&dec_data[`DEC_PRC]) | &dec_data[`DEC_PRC];

assign     exe_mmc_addr = EXE_STATE[clog2(ST_EXE_FETCH_END)] ? exe_fetch_addr_r : EXE_STATE[clog2(ST_EXE_ADDRESS_END)] ? exe_addr_r : exe_mmc_addr_r;

// temporary
reg [16:0] exe_result;

always @(posedge CLK) begin
  if (RST) begin
    EXE_STATE <= ST_EXE_IDLE;
    
    PBR_r         <= 0;
    PC_r          <= 0;
    A_r           <= 0;
    X_r           <= 0;
    Y_r           <= 0;
    S_r[15:8]     <= 1; // TODO: figure out if this is the right place to only clear upper portion
    D_r           <= 0;
    DBR_r         <= 0;
    P_r           <= 8'h34;
    E_r           <= 1;

    exe_fetch_addr_r <= 0;
    exe_addr_r       <= 0;
    exe_mmc_addr_r   <= 0;
    
    exe_opsize_r  <= 0;
    exe_opcode_r  <= 0;
    exe_operand_r <= 0;
    exe_decode_r  <= 0;
    
    exe_src_r     <= 16'h0BAD;
    exe_dst_r     <= 16'h0BAD;
    
    exe_control_r <= 0;
    exe_pbr_r     <= 0;
    exe_nextpc_r  <= 0;
    exe_nextpc_addr_r <= 0;
    exe_add_post_r <= 0;
    
//    exe_a_r       <= 0;
//    exe_x_r       <= 0;
//    exe_y_r       <= 0;
//    exe_s_r       <= 1;
//    exe_d_r       <= 0;
//    exe_dbr_r     <= 0;
//    exe_p_r       <= 8'h34;
//    exe_e_r       <= 1;
//    exe_wai_r     <= 0;

    exe_mmc_rd_r  <= 0;
    exe_mmc_wr_r  <= 0;
    exe_mmc_data_r<= 0;
    exe_mmc_long_r<= 0;
    exe_mmc_byte_total_r <= 0;

    exe_active_r <= 0;
    
    e2c_waitcnt_r <= 0;
  end
  else begin
    case (EXE_STATE)
      ST_EXE_IDLE: begin
        if (~CCNT_r[`CCNT_SA1_RESB] & sa1_clock_en) begin
          {PBR_r,PC_r} <= {8'h00,CRV_r};
          exe_fetch_addr_r <= {8'h00,CRV_r};
          exe_mmc_byte_total_r <= 1;
          e2c_waitcnt_r  <= 1;
          exe_data_word_r <= 0;
          exe_mmc_long_r <= 0;
          exe_mmc_dpe_r <= 0;
          
          exe_active_r <= 1;

          EXE_STATE <= ST_EXE_FETCH;
        end
        else begin
          e2c_waitcnt_r  <= 0;
        end
      end
      
      // FETCH
      ST_EXE_FETCH: begin
        exe_mmc_rd_r   <= 1;
        exe_mmc_byte_total_r <= 1;
        e2c_waitcnt_r  <= 0;

        EXE_STATE <= ST_EXE_FETCH_END;
      end
      ST_EXE_FETCH_END: begin
        if (MMC_STATE[clog2(ST_MMC_EXE_END)]) begin
          exe_mmc_rd_r <= 0;
          exe_data_r <= mmc_data_r;
          // TODO: predecode and data flop
          
          if (~|exe_opsize_r) begin
            exe_opcode_r       <= mmc_data_r[7:0];
            exe_operand_r[7:0] <= mmc_data_r[15:8];
            // word size only affects immediate for fetch
            exe_opsize_r       <= dec_data[`DEC_SIZE] | (|({~P_r[`P_X],~P_r[`P_M]}&dec_data[`DEC_PRC]) & dec_data[`ADD_IMM]);
            exe_control_r      <= dec_data[`DEC_CONTROL];
            exe_load_r         <= dec_data[`DEC_LOAD];
            exe_store_r        <= dec_data[`DEC_STORE];
            exe_decode_r       <= dec_data;
            exe_data_word_r    <= exe_data_word;

            exe_nextpc_addr_r  <= PC_r + dec_data[`DEC_SIZE] + ((|({~P_r[`P_X],~P_r[`P_M]}&dec_data[`DEC_PRC]) & dec_data[`ADD_IMM]) ? 2 : 1);
  
            exe_a_r            <= A_r;
            exe_x_r            <= X_r;
            exe_y_r            <= Y_r;
            exe_s_r            <= S_r;
            exe_d_r            <= D_r;
            exe_dbr_r          <= DBR_r;
            exe_pbr_r          <= PBR_r;
            exe_p_r            <= P_r;
            exe_e_r            <= E_r;
            exe_wai_r          <= WAI_r;

            // TODO: hide the -1 in the decoder
            e2c_waitcnt_r <= dec_data[`DEC_LATENCY] - 1;
            
            // `define ADD_MOD     27:26
            exe_mod_r <= dec_data[27] ? 16'h0000 : dec_data[26] ? Y_r[15:0] : X_r[15:0];

            // record the current PC and previous PC
            debug_inst_addr_r <= {PBR_r,PC_r};
            debug_inst_addr_prev_r <= debug_inst_addr_r;
            
            // TODO: support multiple instruction decode to avoid extra cycle for 2 instructions sharing a line
            if (dec_data[`DEC_SIZE] > 1 || (|({~P_r[`P_X],~P_r[`P_M]}&dec_data[`DEC_PRC]) & dec_data[`ADD_IMM])) begin
              // fetch the remainder of the instruction
              exe_fetch_addr_r[15:0] <= exe_fetch_addr_r[15:0] + 2;
              EXE_STATE <= ST_EXE_FETCH;
            end
            else begin
              EXE_STATE <= ST_EXE_ADDRESS;
            end
          end
          else begin
            exe_operand_r[23:8] <= mmc_data_r[15:0];
            
            EXE_STATE <= ST_EXE_ADDRESS;
          end
          
        end
        // TODO: fill in other data sources
      end
      
      // ADDRESSING MODE
      ST_EXE_ADDRESS: begin
        e2c_waitcnt_r <= 0;

        exe_mmc_rd_r         <= exe_dec_add_indirect;
        exe_mmc_long_r       <= exe_dec_add_long;
        exe_mmc_byte_total_r <= {exe_dec_add_long,~exe_dec_add_long};
        exe_mmc_dpe_r        <= 0;

        exe_dst_r <= REG[exe_dec_dst];
        exe_src_r <= REG[exe_dec_src];

        case (exe_dec_add_bank)
          `BNK_PBR: exe_addr_r[23:16] <= PBR_r;
          `BNK_DBR: exe_addr_r[23:16] <= DBR_r;
          `BNK_ZRO: exe_addr_r[23:16] <= 8'h00;
          `BNK_O24: exe_addr_r[23:16] <= exe_operand_r[23:16];
        endcase

        case (exe_dec_add_base)
          `ADD_O16: exe_addr_r[15:0] <= exe_operand_r[15:0]                                            + exe_mod_r;
          `ADD_DPR: exe_addr_r[15:0] <= D_r + {8'h00,exe_operand_r[7:0]}                               + exe_mod_r;
          `ADD_PCR: exe_addr_r[15:0] <= exe_nextpc_addr_r + {(exe_dec_add_long ? exe_operand_r[15:8] : {8{exe_operand_r[7]}}),exe_operand_r[7:0]} + exe_mod_r;
          `ADD_SPL: exe_addr_r[15:0] <= S_r + 1                                                        + exe_mod_r;
          `ADD_SMI: exe_addr_r[15:0] <= S_r - exe_data_word_r                                          + exe_mod_r;
          `ADD_SPR: exe_addr_r[15:0] <= S_r + {8'h00,exe_operand_r[7:0]}                               + exe_mod_r;
        endcase

        // initialize the operand data as the immediate field.
        exe_data_r[15:0] <= exe_dec_add_imm ? exe_operand_r[15:0] : REGS[exe_dec_src];
        
        exe_add_post_r <= (exe_dec_add_mod == `MOD_YPT ? Y_r[15:0] : 0);
        exe_dst_p_r <= exe_dec_dst == `REG_P;

        exe_nextpc_r <= exe_nextpc_addr_r;

        EXE_STATE <= exe_dec_add_indirect ? ST_EXE_ADDRESS_END : ST_EXE_EXECUTE;

      end
      ST_EXE_ADDRESS_END: begin
        if (MMC_STATE[clog2(ST_MMC_EXE_END)]) begin
          exe_mmc_rd_r <= 0;
          // [3:2] catches the two JMP/JSR indirects which use PBR.  All other indirects are long (full 24b address) or use DBR.
          exe_addr_r[23:16] <= exe_dec_add_long ? mmc_data_r[23:16] : (&exe_opcode_r[3:2]) ? PBR_r : DBR_r;
          exe_addr_r[15:0] <= mmc_data_r[15:0] + exe_add_post_r;
        
          EXE_STATE <= ST_EXE_EXECUTE;
        end
      end
      
      // EXECUTE
      ST_EXE_EXECUTE: begin
        e2c_waitcnt_r <= 0;

        // generic handler for load/store
        if (exe_load_r | exe_store_r) begin
          exe_mmc_rd_r   <=  exe_load_r;
          exe_mmc_wr_r   <= ~exe_load_r;
          exe_mmc_addr_r <= exe_addr_r;
          exe_mmc_byte_total_r <= exe_data_word_r;
          EXE_STATE <= ST_EXE_EXECUTE_END;
        end
        else begin
          EXE_STATE <= ST_EXE_WAIT;
        end

        // save target address since it will be overwritten by JSL/JSR
        exe_target_r <= exe_addr_r;

        case (exe_dec_grp)
          `GRP_PRI: begin
            // TODO: deal with D bit
            exe_result[16] = 0;
            case (exe_opcode_r[7:5])
              0: exe_result[15:0] = exe_src_r | exe_data_r; // ORA
              1: exe_result[15:0] = exe_src_r & exe_data_r; // AND
              2: exe_result[15:0] = exe_src_r ^ exe_data_r; // EOR
              3: exe_result[16:0] = exe_data_word_r ? {1'b0,exe_src_r[15:0]} + {1'b0,exe_data_r[15:0]} + P_r[`P_C] : {9'h000,exe_src_r[7:0]} + {9'h000,exe_data_r[7:0]} + P_r[`P_C]; // ADC
              //4: // STA
              5: exe_result[15:0] = exe_data_r; // LDA
              //6: // CMP
              //7: exe_result[16:0] = exe_data_word_r ? {1'b0,exe_src_r[15:0]} + ~{1'b0,exe_data_r[15:0]} + P_r[`P_C] : {9'h000,exe_src_r[7:0]} + ~{9'h000,exe_data_r[7:0]} + P_r[`P_C];// SBC
              7: exe_result[16:0] = exe_data_word_r ? {1'b0,exe_src_r[15:0]} + {1'b0,~exe_data_r[15:0]} + P_r[`P_C] : {9'h000,exe_src_r[7:0]} + {9'h000,~exe_data_r[7:0]} + P_r[`P_C];// SBC
              default: exe_result[15:0] = 0;
            endcase
              
            exe_a_r <= {exe_data_word_r ? exe_result[15:8] : exe_src_r[15:8], exe_result[7:0]};
            exe_p_r[`P_N] <= exe_data_word_r ? exe_result[15]     : exe_result[7];
            exe_p_r[`P_Z] <= exe_data_word_r ? ~|exe_result[15:0] : ~|exe_result[7:0];
              
            if (&exe_opcode_r[6:5]) begin
              exe_p_r[`P_V] <= exe_data_word_r ? (~(exe_src_r[15] ^ exe_data_r[15]) & (exe_src_r[15] ^ exe_result[15])) : (~(exe_src_r[7] ^ exe_data_r[7]) & (exe_src_r[7] ^ exe_result[7]));
              // SBC sets carry when no borrow required...
              //exe_p_r[`P_C] <= exe_opcode_r[7] ^ (exe_data_word_r ? exe_result[16] : exe_result[8]);
              exe_p_r[`P_C] <= exe_data_word_r ? exe_result[16] : exe_result[8];
            end
          end
          `GRP_RMW: begin
            exe_result[16] = 0;
            case (exe_opcode_r[7:5])
              0: exe_result[16:0] = {exe_data_r[15:0],1'b0}; // ASL
              1: exe_result[16:0] = exe_data_word_r ? {exe_data_r[15:0],P_r[`P_C]}                  : {8'h00,exe_data_r[7:0],P_r[`P_C]}; // ROL
              2: exe_result[16:0] = exe_data_word_r ? {exe_data_r[0],1'b0,exe_data_r[15:1]}         : {8'h00,exe_data_r[0],1'b0,exe_data_r[7:1]}; // LSR
              3: exe_result[16:0] = exe_data_word_r ? {exe_data_r[0],P_r[`P_C],exe_data_r[15:1]}    : {8'h00,exe_data_r[0],P_r[`P_C],exe_data_r[7:1]}; // ROR
              //4: // STX,STY
              //5: // -
              6: exe_result[15:0] = exe_data_word_r ? (exe_data_r[15:0]-1) : (exe_data_r[7:0]-1); // DEC
              7: exe_result[15:0] = exe_data_word_r ? (exe_data_r[15:0]+1) : (exe_data_r[7:0]+1); // INC
              default: exe_result[15:0] = 0;
            endcase
            
            if (~exe_store_r) begin
              exe_a_r <= {exe_data_word_r ? exe_result[15:8] : exe_src_r[15:8], exe_result[7:0]};
            end
            
            // data for store
            exe_mmc_data_r[15:0] <= exe_result[15:0];
            
            exe_p_r[`P_N] <= exe_data_word_r ? exe_result[15]     : exe_result[7];
            exe_p_r[`P_Z] <= exe_data_word_r ? ~|exe_result[15:0] : ~|exe_result[7:0];
            if (~exe_opcode_r[7]) begin
              exe_p_r[`P_C] <= exe_data_word_r ? exe_result[16] : exe_result[8];
            end
          end
          `GRP_CBR: begin
            exe_control_r <= exe_dec_src[2] ? ~P_r[{{2{exe_dec_src[1]}},exe_dec_src[0]}] : P_r[{{2{exe_dec_src[1]}},exe_dec_src[0]}];
          end
          `GRP_JMP: begin
            if (exe_dec_add_stk) begin
              // stack
              if (exe_store_r) begin
                // JSR,JSL
                exe_mmc_addr_r <= {8'h00,(S_r - {exe_dec_add_long,~exe_dec_add_long})};
                exe_mmc_data_r[23:16] <= PBR_r;
                exe_mmc_data_r[15:0] <= exe_nextpc_r - 1;
                exe_mmc_byte_total_r <= {exe_dec_add_long,~exe_dec_add_long};
                exe_s_r <= S_r - {1'b1,exe_dec_add_long};
              end
              else begin
                // RTS,RTL
                exe_mmc_byte_total_r <= {exe_dec_add_long,~exe_dec_add_long};
                exe_s_r <= S_r + {1'b1,exe_dec_add_long};
                exe_target_r[23:16] <= exe_dec_add_long ? exe_data_r[23:16] : PBR_r;
                exe_target_r[15:0] <= exe_data_r[15:0] + 1;
              end
            end
          end
          `GRP_PHS: begin
            exe_mmc_data_r[15:0] <= exe_data_r[15:0];
            
            if (exe_dec_add_stk) exe_s_r <= S_r - (exe_data_word_r ? 2 : 1);
            
            EXE_STATE <= ST_EXE_EXECUTE_END;
          end
          `GRP_PLL: begin
            case (exe_dec_dst)
              //`REG_Z: if (P_r[`P_M]) exe_a_r[7:0] <= 0;               else exe_a_r[15:0] <= 0;
              `REG_A: if (exe_data_word_r) exe_a_r[15:0] <= exe_data_r[15:0]; else exe_a_r[7:0] <= exe_data_r[7:0];
              `REG_X: if (exe_data_word_r) exe_x_r[15:0] <= exe_data_r[15:0]; else exe_x_r[7:0] <= exe_data_r[7:0];
              `REG_Y: if (exe_data_word_r) exe_y_r[15:0] <= exe_data_r[15:0]; else exe_y_r[7:0] <= exe_data_r[7:0];
              `REG_S: exe_s_r <= exe_data_r[15:0];
              `REG_D: exe_d_r <= exe_data_r[15:0];
              `REG_B: exe_dbr_r <= exe_data_r[7:0];
              `REG_P: exe_p_r <= exe_data_r[7:0];
              default: begin end
            endcase
            
            // ok to write this even for P as it will just be the same values
            if (~exe_dst_p_r) begin
              exe_p_r[`P_N] <= exe_data_word_r ? exe_data_r[15]      : exe_data_r[7];
              exe_p_r[`P_Z] <= exe_data_word_r ? ~|exe_data_r[15:0] : ~|exe_data_r[7:0];
            end
            
            if (exe_dec_add_stk) exe_s_r <= S_r + (exe_data_word_r ? 2 : 1);
          end
          `GRP_CMP: begin
            if (~exe_opcode_r[6]) begin
              // BIT
              exe_result = exe_dst_r & exe_data_r;

              // BIT with immediate operand doesn't set N or V
              if (~exe_dec_add_imm) begin
                exe_p_r[`P_V] <= exe_data_word_r ? exe_data_r[14]      : exe_data_r[6];
                exe_p_r[`P_N] <= exe_data_word_r ? exe_data_r[15]      : exe_data_r[7];
              end
              
              exe_p_r[`P_Z] <= exe_data_word_r ? ~|exe_result[15:0] : ~|exe_result[7:0];
            end
            else begin
              // CMP, CPX, CPY
              if (exe_data_word_r) exe_result[16:0] = {1'b0,exe_dst_r[15:0]} - {1'b0,exe_data_r[15:0]};
              else                 exe_result[8:0]  = {1'b0,exe_dst_r[7:0]}  - {1'b0,exe_data_r[7:0]};
              
              exe_p_r[`P_N] <= exe_data_word_r ? exe_result[15]     : exe_result[7];
              exe_p_r[`P_Z] <= exe_data_word_r ? ~|exe_result[15:0] : ~|exe_result[7:0];
              exe_p_r[`P_C] <= exe_data_word_r ? ~exe_result[16]    : ~exe_result[8];
            end
          end
          `GRP_STS: begin
            if (exe_opcode_r[1]) begin
              if (exe_opcode_r[5]) begin
                // SEP
                exe_p_r <= exe_p_r | exe_operand_r[7:0];

                if (P_r[`P_X] | exe_operand_r[`P_X]) begin
                  exe_x_r[15:8] <= 0;
                  exe_y_r[15:8] <= 0;
                end
              end
              else begin
                // REP
                exe_p_r <= exe_p_r & {~exe_operand_r[7:6],(~exe_operand_r[5:4])|{2{E_r}},~exe_operand_r[3:0]};
              end
            end
            else begin
              case (exe_opcode_r[7:6])
                0: exe_p_r[`P_C] <= exe_opcode_r[5];
                1: exe_p_r[`P_I] <= exe_opcode_r[5];
                2: exe_p_r[`P_V] <= 0; // SEV does not exist and won't match with STS
                3: exe_p_r[`P_D] <= exe_opcode_r[5];
              endcase
            end
          end
          `GRP_MOV: begin
            // TODO: apply correct latency
            exe_dbr_r <= exe_operand_r[7:0];
          
            if (exe_load_r) begin
              exe_mmc_addr_r <= {exe_operand_r[15:8], exe_src_r[15:0]};
            end
            else begin
              exe_mmc_addr_r <= {exe_operand_r[7:0],  exe_dst_r[15:0]};              
            end
            
            exe_x_r             <= exe_src_r + (exe_opcode_r[4] ? 1 : -1);
            exe_y_r             <= exe_dst_r + (exe_opcode_r[4] ? 1 : -1);
            exe_a_r             <= A_r - 1;
            exe_control_r       <= |A_r;
            exe_target_r        <= {PBR_r,PC_r};
            
            exe_mmc_data_r[7:0] <= exe_data_r[7:0];

            // END takes care of exit
            EXE_STATE <= ST_EXE_EXECUTE_END;
          end
          `GRP_TXR: begin
            exe_result[15:0] = {exe_data_word_r ? exe_src_r[15:8] : exe_dst_r[15:8], exe_src_r[7:0]};
              
            // register output
            case (exe_dec_dst)
              `REG_A: exe_a_r[15:0] <= exe_result[15:0];
              `REG_X: exe_x_r[15:0] <= exe_result[15:0];
              `REG_Y: exe_y_r[15:0] <= exe_result[15:0];
              `REG_S: exe_s_r[15:0] <= {E_r ? 8'h01 : exe_result[15:8],exe_result[7:0]};
              `REG_D: exe_d_r[15:0] <= exe_result[15:0];
            endcase

            // condition codes
            if (exe_dec_dst != `REG_S) begin
              exe_p_r[`P_N] <= exe_data_word_r ? exe_result[15]     : exe_result[7];
              exe_p_r[`P_Z] <= exe_data_word_r ? ~|exe_result[15:0] : ~|exe_result[7:0];
            end
          end
          `GRP_SMP: begin
            if (~exe_data_word_r) begin
              exe_result[7:0] = ((exe_opcode_r[4] & ~exe_opcode_r[5]) | (~exe_opcode_r[4] & (exe_opcode_r[6] ^ exe_opcode_r[1]))) ? exe_src_r[7:0] + 1 : exe_src_r[7:0] - 1;
              
              // register output
              if      (exe_opcode_r[4])                   exe_a_r[7:0]  <= exe_result[7:0];
              else if (exe_opcode_r[5] ^ exe_opcode_r[1]) exe_x_r[7:0]  <= exe_result[7:0];
              else                                        exe_y_r[7:0]  <= exe_result[7:0];

              // condition codes
              exe_p_r[`P_N] <= exe_result[7];
              exe_p_r[`P_Z] <= ~|exe_result[7:0];
            end
            else begin
              exe_result[15:0] = ((exe_opcode_r[4] & ~exe_opcode_r[5]) | (~exe_opcode_r[4] & (exe_opcode_r[6] ^ exe_opcode_r[1]))) ? exe_src_r[15:0] + 1 :  (exe_src_r[15:0] - 1);
              
              // register output
              if      (exe_opcode_r[4])                   exe_a_r[15:0] <= exe_result[15:0];
              else if (exe_opcode_r[5] ^ exe_opcode_r[1]) exe_x_r[15:0] <= exe_result[15:0];
              else                                        exe_y_r[15:0] <= exe_result[15:0];

              // condition codes
              exe_p_r[`P_N] <= exe_result[15];
              exe_p_r[`P_Z] <= ~|exe_result[15:0];
            end
          end
          `GRP_SPC: begin
            // BRK, COP, STP, WAI, RTI

            if (exe_opcode_r[7]^exe_opcode_r[6]) begin
              // RTI
              exe_target_r <= {(E_r ? exe_pbr_r : exe_data_r[31:24]),exe_data_r[23:8]};
              exe_p_r      <= exe_data_r[7:0];
              exe_s_r <= S_r + {~E_r,E_r,E_r};
              
              exe_mmc_byte_total_r <= {1'b1,~E_r};
              
              if (mmc_data_r[`P_X]) begin
                exe_x_r[15:8] <= 0;
                exe_y_r[15:8] <= 0;
              end
            end
            else if (exe_opcode_r[6]) begin
              // STP,WAI
              exe_active_r <= 0;
              exe_wai_r <= exe_opcode_r[0];
            end
            else begin
              // COP/BRK
              if (exe_load_r) begin
                // interrupt will read BRK vector from memory
                exe_mmc_addr_r <= {16'h00FF,3'h7,E_r,E_r,1'b1,~exe_opcode_r[1],1'b0};
              end
              else begin
                if (~int_pending_r) exe_target_r <= {8'h00,exe_data_r[15:0]};
                else                exe_target_r <= {8'h00,int_vector_r};
                exe_s_r <= S_r - {~E_r,E_r,E_r};
                exe_p_r[`P_I] <= 1;
                exe_p_r[`P_D] <= 0;

                exe_mmc_addr_r <= {8'h00,S_r - {1'b1,~E_r}};
                exe_mmc_data_r <= {PBR_r,(int_pending_r ? PC_r[15:0] : exe_nextpc_r[15:0]),P_r};
                exe_mmc_byte_total_r <= {1'b1,~E_r};
              end
            end
          end
          `GRP_STK: begin
            // non-indirect will store data at stack address
            // direct will first load, return here, and update data to be stored
            exe_mmc_data_r[15:0] <= exe_opcode_r[1] ? (exe_nextpc_r[15:0] + exe_operand_r[15:0]) : exe_opcode_r[5] ? exe_operand_r[15:0] : exe_data_r[15:0];

            exe_s_r <= S_r - 2;
          end
          `GRP_XCH: begin
            if (exe_opcode_r[4]) begin
              exe_p_r[`P_C] <= E_r;
              exe_e_r       <= P_r[`P_C];
              
              if (P_r[`P_C]) begin
                exe_p_r[`P_M] <= 1;
                exe_p_r[`P_X] <= 1;
                exe_x_r[15:8] <= 0;
                exe_y_r[15:8] <= 0;
              end            
            end
            else begin
              exe_result[15:0] = {exe_src_r[7:0],exe_src_r[15:8]};
              
              // register output
              exe_a_r[15:0] <= exe_result[15:0];
              // condition codes
              exe_p_r[`P_N] <= exe_result[7];
              exe_p_r[`P_Z] <= ~|exe_result[7:0];            
            end
          end
          `GRP_TST: begin
            case (exe_opcode_r[4])
              0: exe_result = exe_data_r[15:0] | exe_src_r[15:0];
              1: exe_result = exe_data_r[15:0] & ~exe_src_r[15:0];
            endcase
            
            exe_mmc_data_r[15:0] <= exe_result[15:0];
            // TSB/TRB are unique in that the Z flag is only set based on the logical and of the memory location and A
            exe_p_r[`P_Z] <= exe_data_word_r ? ~|(exe_data_r[15:0] & exe_src_r[15:0]) : ~|(exe_data_r[7:0] & exe_src_r[7:0]);
          end
        endcase

      end
      ST_EXE_EXECUTE_END: begin
        e2c_waitcnt_r <= 0;

        if (MMC_STATE[clog2(ST_MMC_EXE_END)]) begin
          // TODO: handle long and upper address bits for indirects
          exe_mmc_rd_r <= 0;
          exe_mmc_wr_r <= 0;
          exe_load_r <= 0;
          if (exe_load_r) exe_data_r <= mmc_data_r;
        
          // return to EXECUTE if there are still work to do
          EXE_STATE <= exe_load_r ? ST_EXE_EXECUTE : ST_EXE_WAIT;
        end      
      end
      ST_EXE_WAIT: begin
        e2c_waitcnt_r <= 0;

        if (pipeline_advance) begin
          // TODO: figure out how to deal with the fetch address vs PC
          {PBR_r,PC_r}     <= exe_control_r ? exe_target_r : {exe_pbr_r,exe_nextpc_r};
          exe_fetch_addr_r <= exe_control_r ? exe_target_r : {exe_pbr_r,exe_nextpc_r};
          exe_mmc_byte_total_r <= 1;
          exe_opsize_r  <= 0;
          exe_opcode_r  <= 0;
          exe_operand_r <= 0;
          exe_mmc_long_r <= 0;
          exe_mmc_dpe_r <= 0;
          
          // write register state
          A_r           <= exe_a_r;
          X_r           <= exe_x_r;
          Y_r           <= exe_y_r;
          S_r           <= exe_s_r;
          D_r           <= exe_d_r;
          DBR_r         <= exe_dbr_r;
          P_r           <= exe_p_r;
          E_r           <= exe_e_r;
          //WAI_r         <= exe_wai_r;
          
          // reset internal PCs to help with debugging
          exe_nextpc_r   <= 0;

          EXE_STATE <= (exe_active_r & ~CCNT_r[`CCNT_SA1_RESB]) ? ST_EXE_FETCH : ST_EXE_IDLE;
        end
      end
    endcase
  end
end

`ifdef DEBUG
// breakpoints
reg      brk_inst_rd_rom_m1;
reg      brk_inst_rd_ram_m1;
reg      brk_data_rd_rom_m1;
reg      brk_data_rd_ram_m1;
reg      brk_data_wr_ram_m1;

reg [23:0] brk_addr_r;

always @(posedge CLK) begin
  if (RST) begin
    brk_inst_rd_rom_m1 <= 0;
    brk_inst_rd_ram_m1 <= 0;
    brk_data_rd_rom_m1 <= 0;
    brk_data_rd_ram_m1 <= 0;
    brk_data_wr_ram_m1 <= 0;

    brk_inst_rd_byte <= 0;
    brk_data_rd_byte <= 0;
    brk_data_wr_byte <= 0;

    brk_inst_rd_addr <= 0;
    brk_data_rd_addr <= 0;
    brk_data_wr_addr <= 0;
    brk_stop         <= 0;
    brk_error        <= 0;
    
    brk_addr_r       <= 0;
  end
  else begin
    //brk_inst_rd_rom_m1 <= (|(ROM_STATE & ST_ROM_FETCH_RD)) && !rom_bus_rrq_r && ROM_BUS_RDY;
    //brk_inst_rd_ram_m1 <= (|(RAM_STATE & ST_RAM_FETCH_RD)) && !ram_bus_rrq_r && RAM_BUS_RDY;
    //brk_data_rd_rom_m1 <= (|(ROM_STATE & ST_ROM_DATA_RD)) && !rom_bus_rrq_r && ROM_BUS_RDY;
    //brk_data_rd_ram_m1 <= (|(RAM_STATE & ST_RAM_DATA_RD)) && !ram_bus_rrq_r && RAM_BUS_RDY;
    //brk_data_wr_ram_m1 <= (|(RAM_STATE & ST_RAM_DATA_WR)) && !ram_bus_wrq_r && RAM_BUS_RDY;

    //brk_inst_rd_byte <= pipeline_advance ? 0 : brk_inst_rd_rom_m1 ? (rom_bus_data_r == CONFIG_DATA_WATCH) : brk_inst_rd_ram_m1 ? (ram_bus_data_r == CONFIG_DATA_WATCH) : brk_inst_rd_byte;
    //brk_data_rd_byte <= pipeline_advance ? 0 : brk_data_rd_rom_m1 ? (rom_bus_data_r == CONFIG_DATA_WATCH) : brk_data_rd_ram_m1 ? (ram_bus_data_r == CONFIG_DATA_WATCH) : brk_data_rd_byte;
    //brk_data_wr_byte <= pipeline_advance ? 0                                                              : brk_data_wr_ram_m1 ? (RAMWRBUF_r     == CONFIG_DATA_WATCH) : brk_data_wr_byte;
  
    brk_inst_rd_addr <= (debug_inst_addr_r == brk_addr_r);
    brk_data_rd_addr <= 0;//(  (exe_ram_rd_r   && (exe_addr_r   == brk_addr_r) || (prf_rom_rd_r && (prf_addr_r   == brk_addr_r)))
                          //|| (bmp_ram_rd_r   && (bmp_addr_r   == brk_addr_r)                                                  )
                          //);
    brk_data_wr_addr <= 0;//(  (stb_ram_wr_r   && (stb_addr_r   == brk_addr_r))
                          //|| (bmf_ram_wr_r   && (bmf_addr_r   == brk_addr_r))
                          //);
    brk_stop         <= EXE_STATE[clog2(ST_EXE_EXECUTE)] && (exe_opcode_r == 8'hDB || exe_opcode_r == 8'hCB || int_pending_r);
    brk_error        <= EXE_STATE[clog2(ST_EXE_EXECUTE)] && (exe_opcode_r == 8'h00);
    
  
    brk_addr_r <= CONFIG_ADDR_WATCH[23:0];
  end
end
`endif

assign pipeline_advance = sa1_clock_en & ~|exe_waitcnt_r & EXE_STATE[clog2(ST_EXE_WAIT)] & step_r;
assign op_complete = 1;

// performance counter
reg cycle_wait_r;

always @(posedge CLK) begin
  if (sa1_clock_en & ~|exe_waitcnt_r & EXE_STATE[clog2(ST_EXE_WAIT)] & ~step_r) cycle_wait_r <= 1;
  else if (pipeline_advance) cycle_wait_r <= 0;

  if (RST) begin
    sa1_cycle_cnt_r <= 0;
  end
  else if ((~EXE_STATE[clog2(ST_EXE_WAIT)] | ~cycle_wait_r) & ~EXE_STATE[clog2(ST_EXE_IDLE)]) begin
    sa1_cycle_cnt_r <= sa1_cycle_cnt_r + 1;
  end
end

//-------------------------------------------------------------------
// DEBUG OUTPUT
//-------------------------------------------------------------------
wire [7:0] dbg_reg_dout;

dbg_state state (
  .clka(CLK), // input clka
  //.wea(~addr_in_r[7] & SNES_WR_end & `IS_MMIO(addr_in_r)), // input [0 : 0] wea
  //.addra(addr_in_r[6:0]), // input [6 : 0] addra
  //.dina(data_in_r), // input [7 : 0] dina
  .wea(~snes_writebuf_addr_r[7] & snes_writebuf_val_r), // input [0 : 0] wea
  .addra(snes_writebuf_addr_r[6:0]), // input [6 : 0] addra
  .dina(snes_writebuf_data_r), // input [7 : 0] dina

  .clkb(CLK), // input clkb
  .addrb(pgm_addr_r[6:0]), // input [6 : 0] addrb
  .doutb(dbg_reg_dout) // output [7 : 0] doutb
);

reg [7:0]  pgmpre_out[3:0];
reg [7:0]  pgmdata_out; //initial pgmdata_out_r = 0;

`ifdef DEBUG
always @(posedge CLK) begin
  if      (~pgm_addr_r[11])                              pgmdata_out <= pgmpre_out[pgm_addr_r[9:8]];
  else if (~snes_writebuf_iram_r & ~snes_readbuf_iram_r) pgmdata_out <= snes_iram_dout;

  if (~pgm_addr_r[11]) begin
    case (pgm_addr_r[9:8])
      2'h0: case (pgm_addr_r[7:0])
        // 00-7F MMIO
        ADDR_CCNT  ,
        ADDR_SIE   ,
        ADDR_SIC   ,
        ADDR_CRV   ,
        ADDR_CRV+1 ,
        ADDR_CNV   ,
        ADDR_CNV+1 ,
        ADDR_CIV   ,
        ADDR_CIV+1 ,
        ADDR_SCNT  ,
        ADDR_CIE   ,
        ADDR_CIC   ,
        ADDR_SNV   ,
        ADDR_SNV+1 ,
        ADDR_SIV   ,
        ADDR_SIV+1 ,
        ADDR_TMC   ,
        ADDR_CTR   ,
        ADDR_HCNT  ,
        ADDR_HCNT+1,
        ADDR_VCNT  ,
        ADDR_VCNT+1,
        ADDR_CXB   ,
        ADDR_DXB   ,
        ADDR_EXB   ,
        ADDR_FXB   ,
        ADDR_BMAPS ,
        ADDR_BMAP  ,
        ADDR_SWBE  ,
        ADDR_CWBE  ,
        ADDR_BWPA  ,
        ADDR_SIWP  ,
        ADDR_CIWP  ,
        ADDR_DCNT  ,
        ADDR_CDMA  ,
        ADDR_SDA   ,
        ADDR_SDA+1 ,
        ADDR_SDA+2 ,
        ADDR_DDA   ,
        ADDR_DDA+1 ,
        ADDR_DDA+2 ,
        ADDR_DTC   ,
        ADDR_BBF   ,
        ADDR_BRF0  ,
        ADDR_BRF1  ,
        ADDR_BRF2  ,
        ADDR_BRF3  ,
        ADDR_BRF4  ,
        ADDR_BRF5  ,
        ADDR_BRF6  ,
        ADDR_BRF7  ,
        ADDR_BRF8  ,
        ADDR_BRF9  ,
        ADDR_BRFA  ,
        ADDR_BRFB  ,
        ADDR_BRFC  ,
        ADDR_BRFD  ,
        ADDR_BRFE  ,
        ADDR_BRFF  ,  
        ADDR_MCNT  ,
        ADDR_MA    ,
        ADDR_MA+1  ,
        ADDR_MB    ,
        ADDR_MB+1  ,
        ADDR_VBD   ,
        ADDR_VDA   ,
        ADDR_VDA+1 ,
        ADDR_VDA+2 : pgmpre_out[0] <= dbg_reg_dout;

`ifdef DEBUG_EXT
        8'h60+ADDR_SFR   : pgmpre_out[0] <= SFR_r;
        8'h60+ADDR_CFR   : pgmpre_out[0] <= CFR_r;
        8'h60+ADDR_HCR   : pgmpre_out[0] <= HCR_r[7:0]; // $2
        8'h60+ADDR_HCR+1 : pgmpre_out[0] <= HCR_r[15:8]; // $2
        8'h60+ADDR_VCR   : pgmpre_out[0] <= VCR_r[7:0]; // $2
        8'h60+ADDR_VCR+1 : pgmpre_out[0] <= VCR_r[15:8]; // $2
        8'h60+ADDR_MR    : pgmpre_out[0] <= MR_r[7:0]; // $5
        8'h60+ADDR_MR+1  : pgmpre_out[0] <= MR_r[15:8]; // $5
        8'h60+ADDR_MR+2  : pgmpre_out[0] <= MR_r[23:16]; // $5
        8'h60+ADDR_MR+3  : pgmpre_out[0] <= MR_r[31:24]; // $5
        8'h60+ADDR_MR+4  : pgmpre_out[0] <= MR_r[39:32]; // $5
        8'h60+ADDR_OF    : pgmpre_out[0] <= OF_r;
        8'h60+ADDR_VDP   : pgmpre_out[0] <= VDP_r[7:0]; // $2
        8'h60+ADDR_VDP+1 : pgmpre_out[0] <= VDP_r[15:8]; // $2
        8'h60+ADDR_VC    : pgmpre_out[0] <= VC_r;      
`endif
        
        // 80-9F ARCH STATE
        8'h80      : pgmpre_out[0] <= A_r[7:0];  
        8'h81      : pgmpre_out[0] <= A_r[15:8];  
        8'h82      : pgmpre_out[0] <= X_r[7:0];  
        8'h83      : pgmpre_out[0] <= X_r[15:8];  
        8'h84      : pgmpre_out[0] <= Y_r[7:0];  
        8'h85      : pgmpre_out[0] <= Y_r[15:8];  
        8'h86      : pgmpre_out[0] <= S_r[7:0];  
        8'h87      : pgmpre_out[0] <= S_r[15:8];  
        8'h88      : pgmpre_out[0] <= D_r[7:0];  
        8'h89      : pgmpre_out[0] <= D_r[15:8];  
        8'h8A      : pgmpre_out[0] <= PC_r[7:0];
        8'h8B      : pgmpre_out[0] <= PC_r[15:8];
        8'h8C      : pgmpre_out[0] <= PBR_r;
        8'h8D      : pgmpre_out[0] <= DBR_r; 
        8'h8E      : pgmpre_out[0] <= P_r;  
        8'h8F      : pgmpre_out[0] <= E_r;  
        8'h90      : pgmpre_out[0] <= MDR_r;
        8'h91      : pgmpre_out[0] <= WAI_r;

`ifdef DEBUG_MMC        
        // A0-BF MMC
        8'hA0           : pgmpre_out[0] <= MMC_STATE;
        8'hA1           : pgmpre_out[0] <= mmc_addr_r[7:0];
        8'hA2           : pgmpre_out[0] <= mmc_addr_r[15:8];
        8'hA3           : pgmpre_out[0] <= mmc_addr_r[23:16];
        8'hA4           : pgmpre_out[0] <= mmc_data_r[7:0];
        8'hA5           : pgmpre_out[0] <= mmc_data_r[15:8];
        8'hA6           : pgmpre_out[0] <= mmc_data_r[23:16];
        8'hA7           : pgmpre_out[0] <= mmc_data_r[31:24];
        8'hA8           : pgmpre_out[0] <= mmc_wr_r;        
        8'hA9           : pgmpre_out[0] <= mmc_byte_r;
        8'hAA           : pgmpre_out[0] <= mmc_byte_total_r;
        8'hAB           : pgmpre_out[0] <= mmc_long_r;
        8'hAC           : pgmpre_out[0] <= mmc_dpe_r;
        8'hAD           : pgmpre_out[0] <= mmc_state_end_r;

//        8'hB0           : pgmpre_out[0] <= exe_mmc_rd_r;
//        8'hB1           : pgmpre_out[0] <= exe_mmc_addr_r[7:0];
//        8'hB2           : pgmpre_out[0] <= exe_mmc_addr_r[15:8];
//        8'hB3           : pgmpre_out[0] <= exe_mmc_addr_r[23:16];
//        8'hB4           : pgmpre_out[0] <= exe_mmc_data_r[7:0];
//        8'hB5           : pgmpre_out[0] <= exe_mmc_data_r[15:8];
//        8'hB6           : pgmpre_out[0] <= exe_mmc_data_r[23:16];
//        8'hB7           : pgmpre_out[0] <= exe_mmc_data_r[31:24];
//        8'hB8           : pgmpre_out[0] <= exe_mmc_wr_r;
//        8'hB9           : pgmpre_out[0] <= exe_mmc_long_r;
//        8'hBA           : pgmpre_out[0] <= exe_mmc_byte_total_r;
`endif
        
        // C0-DF EXECUTE
        8'hC0           : pgmpre_out[0] <= EXE_STATE;
        8'hC1           : pgmpre_out[0] <= exe_opsize_r;
        8'hC2           : pgmpre_out[0] <= exe_opcode_r;
        8'hC3           : pgmpre_out[0] <= exe_operand_r[7:0];
        8'hC4           : pgmpre_out[0] <= exe_operand_r[15:8];
        8'hC5           : pgmpre_out[0] <= exe_operand_r[23:16];
        8'hC6           : pgmpre_out[0] <= exe_addr_r[7:0];
        8'hC7           : pgmpre_out[0] <= exe_addr_r[15:8];
        8'hC8           : pgmpre_out[0] <= exe_addr_r[23:16];
        8'hC9           : pgmpre_out[0] <= exe_data_r[7:0];
        8'hCA           : pgmpre_out[0] <= exe_data_r[15:8];
`ifdef DEBUG_EXE
        8'hCB           : pgmpre_out[0] <= exe_control_r;
        8'hCC           : pgmpre_out[0] <= exe_nextpc_r[7:0];
        8'hCD           : pgmpre_out[0] <= exe_nextpc_r[15:8];
        8'hCE           : pgmpre_out[0] <= exe_src_r[7:0];
        8'hCF           : pgmpre_out[0] <= exe_src_r[15:8];
        
        //8'hD0           : pgmpre_out[0] <= exe_dec_inst;
        8'hD0           : pgmpre_out[0] <= exe_dec_grp;
        8'hD1           : pgmpre_out[0] <= exe_dec_size;
        8'hD2           : pgmpre_out[0] <= exe_dec_lat;
        8'hD3           : pgmpre_out[0] <= exe_dec_prc;
        8'hD4           : pgmpre_out[0] <= exe_dec_src;
        8'hD5           : pgmpre_out[0] <= exe_dec_dst;
        8'hD6           : pgmpre_out[0] <= exe_dec_ctl;
        8'hD7           : pgmpre_out[0] <= exe_dec_add_bank;
        8'hD8           : pgmpre_out[0] <= exe_dec_add_base;
        8'hD9           : pgmpre_out[0] <= exe_dec_add_mod;
        8'hDA           : pgmpre_out[0] <= exe_dec_add_imm;        
        8'hDB           : pgmpre_out[0] <= exe_dec_add_indirect;
        8'hDC           : pgmpre_out[0] <= exe_dec_add_long;
        //8'hDD           : pgmpre_out[0] <= exe_dec_add_stk;
`endif
        8'hDD           : pgmpre_out[0] <= exe_target_r[7:0];
        8'hDE           : pgmpre_out[0] <= exe_target_r[15:8];
        8'hDF           : pgmpre_out[0] <= exe_target_r[23:16];
        
        //8'hC5           : pgmpre_out[0] <= exe_opindex_r;
        
        // E0-EF ???
`ifdef DEBUG_EXT
        8'hE0           : pgmpre_out[0] <= debug_inst_addr_prev_r[ 7: 0];
        8'hE1           : pgmpre_out[0] <= debug_inst_addr_prev_r[15: 8];
        8'hE2           : pgmpre_out[0] <= debug_inst_addr_prev_r[23:16];
      
        8'hF0           : pgmpre_out[0] <= config_r[0];
        8'hF1           : pgmpre_out[0] <= config_r[1];
        8'hF2           : pgmpre_out[0] <= config_r[2];
        8'hF3           : pgmpre_out[0] <= config_r[3];
        8'hF4           : pgmpre_out[0] <= config_r[4];
        8'hF5           : pgmpre_out[0] <= config_r[5];
        8'hF6           : pgmpre_out[0] <= config_r[6];
        8'hF7           : pgmpre_out[0] <= config_r[7];

        8'hF8           : pgmpre_out[0] <= stepcnt_r;
        8'hF9           : pgmpre_out[0] <= sa1_clock_en;
        
        // big endian to make debugging easier
        8'hFA           : pgmpre_out[0] <= sa1_cycle_cnt_r[31:24];
        8'hFB           : pgmpre_out[0] <= sa1_cycle_cnt_r[23:16];
        8'hFC           : pgmpre_out[0] <= sa1_cycle_cnt_r[15: 8];
        8'hFD           : pgmpre_out[0] <= sa1_cycle_cnt_r[ 7: 0];
`endif

        default         : pgmpre_out[0] <= 8'hFF;
      endcase
      default         : pgmpre_out[pgm_addr_r[9:8]] <= 8'hFF;
    endcase
  end
end
`endif

//-------------------------------------------------------------------
// MISC OUTPUTS
//-------------------------------------------------------------------
assign DBG         = 0;
assign PGM_DATA    = pgmdata_out;

assign DATA_ENABLE = data_enable_r;
assign DATA_OUT    = data_out_r;

reg cpu_irq_r; initial cpu_irq_r = 0;
always @(posedge CLK) cpu_irq_r <= (SIE_r[`SIE_DMA_IRQEN] & SFR_r[`SFR_DMA_IRQFL]) | (SIE_r[`SIE_CPU_IRQEN] & SFR_r[`SFR_CPU_IRQFL]);

assign IRQ         = cpu_irq_r;

assign BMAPS_SBM   = BMAPS_r[`BMAPS_SBM];
assign SNV         = SNV_r;
assign SIV         = SIV_r;
assign SCNT_NVSW   = SCNT_r[`SCNT_NVSW];
assign SCNT_IVSW   = SCNT_r[`SCNT_IVSW];

endmodule
