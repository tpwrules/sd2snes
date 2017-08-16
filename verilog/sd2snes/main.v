`timescale 1 ns / 1 ns
//////////////////////////////////////////////////////////////////////////////////
// Company: Rehkopf
// Engineer: Rehkopf
//
// Create Date:    01:13:46 05/09/2009
// Design Name:
// Module Name:    main
// Project Name:
// Target Devices:
// Tool versions:
// Description: Master Control FSM
//
// Dependencies: address
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module main(
  /* input clock */
  input CLKIN,

  /* SNES signals */
  input [23:0] SNES_ADDR_IN,
  input SNES_READ_IN,
  input SNES_WRITE_IN,
  input SNES_ROMSEL_IN,
  inout [7:0] SNES_DATA,
  input SNES_CPU_CLK_IN,
  input SNES_REFRESH,
  output SNES_IRQ,
  output SNES_DATABUS_OE,
  output SNES_DATABUS_DIR,
  input SNES_SYSCLK,

  input [7:0] SNES_PA_IN,
  input SNES_PARD_IN,
  input SNES_PAWR_IN,

  /* SRAM signals */
  /* Bus 1: PSRAM, 128Mbit, 16bit, 70ns */
  inout [15:0] ROM_DATA,
  output [22:0] ROM_ADDR,
  output ROM_CE,
  output ROM_OE,
  output ROM_WE,
  output ROM_BHE,
  output ROM_BLE,

  /* Bus 2: SRAM, 4Mbit, 8bit, 45ns */
  inout [7:0] RAM_DATA,
  output [18:0] RAM_ADDR,
  output RAM_CE,
  output RAM_OE,
  output RAM_WE,

  /* MCU signals */
  input SPI_MOSI,
  inout SPI_MISO,
  input SPI_SS,
  inout SPI_SCK,
  input MCU_OVR,
  output MCU_RDY,

  output DAC_MCLK,
  output DAC_LRCK,
  output DAC_SDOUT,

  /* SD signals */
  input [3:0] SD_DAT,
  inout SD_CMD,
  inout SD_CLK,

  /* debug */
  output p113_out
);

wire CLK2;

wire dspx_dp_enable;

wire [7:0] spi_cmd_data;
wire [7:0] spi_param_data;
wire [7:0] spi_input_data;
wire [31:0] spi_byte_cnt;
wire [2:0] spi_bit_cnt;
wire [23:0] MCU_ADDR;
wire [2:0] MAPPER;
wire [23:0] SAVERAM_MASK;
wire [23:0] ROM_MASK;
wire [7:0] SD_DMA_SRAM_DATA;
wire [1:0] SD_DMA_TGT;
wire [10:0] SD_DMA_PARTIAL_START;
wire [10:0] SD_DMA_PARTIAL_END;

wire [10:0] dac_addr;
wire [2:0] dac_vol_select_out;
wire [8:0] dac_ptr_addr;
//wire [7:0] dac_volume;
wire [7:0] msu_volumerq_out;
wire [7:0] msu_status_out;
wire [31:0] msu_addressrq_out;
wire [15:0] msu_trackrq_out;
wire [13:0] msu_write_addr;
wire [13:0] msu_ptr_addr;
wire [7:0] MSU_SNES_DATA_IN;
wire [7:0] MSU_SNES_DATA_OUT;
wire [5:0] msu_status_reset_bits;
wire [5:0] msu_status_set_bits;

wire [7:0] USB_SNES_DATA_IN;
wire [7:0] USB_SNES_DATA_OUT;
wire [7:0] usb_status_reset_bits;
wire [7:0] usb_status_set_bits;

wire [14:0] bsx_regs;
wire [7:0] BSX_SNES_DATA_IN;
wire [7:0] BSX_SNES_DATA_OUT;
wire [7:0] bsx_regs_reset_bits;
wire [7:0] bsx_regs_set_bits;

wire [59:0] rtc_data;
wire [55:0] rtc_data_in;
wire [59:0] srtc_rtc_data_out;
wire [3:0] SRTC_SNES_DATA_IN;
wire [7:0] SRTC_SNES_DATA_OUT;

wire [7:0] DSPX_SNES_DATA_IN;
wire [7:0] DSPX_SNES_DATA_OUT;

wire [23:0] dspx_pgm_data;
wire [10:0] dspx_pgm_addr;
wire dspx_pgm_we;

wire [15:0] dspx_dat_data;
wire [10:0] dspx_dat_addr;
wire dspx_dat_we;

wire [7:0] featurebits;

wire [23:0] MAPPED_SNES_ADDR;
wire ROM_ADDR0;

wire [9:0] bs_page;
wire [8:0] bs_page_offset;
wire bs_page_enable;

wire [4:0] DBG_srtc_state;
wire DBG_srtc_we_rising;
wire [3:0] DBG_srtc_ptr;
wire [5:0] DBG_srtc_we_sreg;
wire [13:0] DBG_msu_address;
wire DBG_msu_reg_oe_rising;
wire DBG_msu_reg_oe_falling;
wire DBG_msu_reg_we_rising;
wire [2:0] SD_DMA_DBG_clkcnt;
wire [10:0] SD_DMA_DBG_cyclecnt;

wire [8:0] snescmd_addr_mcu;
wire [7:0] snescmd_data_out_mcu;
wire [7:0] snescmd_data_in_mcu;

reg [7:0] SNES_PARDr;
reg [7:0] SNES_PAWRr;
reg [7:0] SNES_READr;
reg [7:0] SNES_WRITEr;
reg [7:0] SNES_CPU_CLKr;
reg [7:0] SNES_ROMSELr;
reg [23:0] SNES_ADDRr [6:0];
reg [7:0] SNES_PAr [6:0];
reg [7:0] SNES_DATAr [4:0];

reg SNES_DEADr = 1;
reg SNES_reset_strobe = 0;

reg free_strobe = 0;

reg [3:0] SNES_PAWR_count;
reg [3:0] SNES_PARD_count;

wire SNES_PARD_start = ((SNES_PARDr[6:1] | SNES_PARDr[7:2]) == 6'b111110);
wire SNES_PARD_end = SNES_PARD_count == 5; // 5
wire SNES_PAWR_start = ((SNES_PAWRr[4:1] | SNES_PAWRr[5:2]) == 4'b1110);
wire SNES_PAWR_end   = SNES_PAWR_count == 5; // 5
wire SNES_RD_start = ((SNES_READr[6:1] | SNES_READr[7:2]) == 6'b111100);
wire SNES_RD_end = ((SNES_READr[6:1] & SNES_READr[7:2]) == 6'b000001);
wire SNES_WR_start = ((SNES_WRITEr[6:1] & SNES_WRITEr[7:2]) == 6'b111000);
wire SNES_WR_end = ((SNES_WRITEr[6:1] & SNES_WRITEr[7:2]) == 6'b000001);
wire SNES_cycle_start = ((SNES_CPU_CLKr[7:2] & SNES_CPU_CLKr[6:1]) == 6'b000011);
wire SNES_cycle_end = ((SNES_CPU_CLKr[7:2] | SNES_CPU_CLKr[6:1]) == 6'b111000);
wire SNES_cycle_end_early = ((SNES_CPU_CLKr[6:2] | SNES_CPU_CLKr[5:1]) == 5'b11100);
wire SNES_WRITE = SNES_WRITEr[2] & SNES_WRITEr[1];
wire SNES_READ = SNES_READr[2] & SNES_READr[1];
wire SNES_CPU_CLK = SNES_CPU_CLKr[2] & SNES_CPU_CLKr[1];
wire SNES_PARD = SNES_PARDr[2] & SNES_PARDr[1];
wire SNES_PAWR = SNES_PAWRr[2] & SNES_PAWRr[1];
wire SNES_ROMSEL_EARLY = (SNES_ROMSELr[2] & SNES_ROMSELr[1]);

wire SNES_ROMSEL = (SNES_ROMSELr[5] & SNES_ROMSELr[4]);
wire [23:0] SNES_ADDR = (SNES_ADDRr[6] & SNES_ADDRr[5]);
wire [7:0] SNES_PA = (SNES_PAr[6] & SNES_PAr[5]);
wire [7:0] SNES_DATA_IN = (SNES_DATAr[3] & SNES_DATAr[2]);

reg [7:0] BUS_DATA;

always @(posedge CLK2) begin
  if(~SNES_READ) BUS_DATA <= SNES_DATA;
  else if(~SNES_WRITE) BUS_DATA <= SNES_DATA_IN;
end

wire free_slot = SNES_cycle_end | free_strobe;

wire ROM_HIT;

assign DCM_RST=0;

always @(posedge CLK2) begin
  free_strobe <= 1'b0;
  if(SNES_cycle_start) free_strobe <= ~ROM_HIT;
end

integer j;
always @(posedge CLK2) begin
  SNES_PARDr <= {SNES_PARDr[6:0], SNES_PARD_IN};
  SNES_PAWRr <= {SNES_PAWRr[6:0], SNES_PAWR_IN};
  SNES_READr <= {SNES_READr[6:0], SNES_READ_IN};
  SNES_WRITEr <= {SNES_WRITEr[6:0], SNES_WRITE_IN};
  SNES_CPU_CLKr <= {SNES_CPU_CLKr[6:0], SNES_CPU_CLK_IN};
  SNES_ROMSELr <= {SNES_ROMSELr[6:0], SNES_ROMSEL_IN};
  SNES_ADDRr[6] <= SNES_ADDRr[5];
  SNES_ADDRr[5] <= SNES_ADDRr[4];
  SNES_ADDRr[4] <= SNES_ADDRr[3];
  SNES_ADDRr[3] <= SNES_ADDRr[2];
  SNES_ADDRr[2] <= SNES_ADDRr[1];
  SNES_ADDRr[1] <= SNES_ADDRr[0];
  SNES_ADDRr[0] <= SNES_ADDR_IN;
  SNES_PAr[6] <= SNES_PAr[5];
  SNES_PAr[5] <= SNES_PAr[4];
  SNES_PAr[4] <= SNES_PAr[3];
  SNES_PAr[3] <= SNES_PAr[2];
  SNES_PAr[2] <= SNES_PAr[1];
  SNES_PAr[1] <= SNES_PAr[0];
  SNES_PAr[0] <= SNES_PA_IN;
  
  //for (j = 1; j < 32; j = j + 1) SNES_DATAr[j] <= SNES_DATAr[j - 1];
  
  SNES_DATAr[4] <= SNES_DATAr[3];
  SNES_DATAr[3] <= SNES_DATAr[2];
  SNES_DATAr[2] <= SNES_DATAr[1];
  SNES_DATAr[1] <= SNES_DATAr[0];
  SNES_DATAr[0] <= SNES_DATA;
  
  // count of write low
  if (SNES_reset_strobe | SNES_PAWR_end) begin
    SNES_PAWR_count <= 0;
  end
  else if (SNES_PAWR_start/* & SNES_READ*/) begin 
    // ignore DMAs which also seem to assert under certain conditions when they are reading WRAM  
    SNES_PAWR_count <= 1;
  end
  else if (|SNES_PAWR_count) begin
    SNES_PAWR_count <= SNES_PAWR_count + 1;
  end

  // count of write low
  if (SNES_reset_strobe | SNES_PARD_end) begin
    SNES_PARD_count <= 0;
  end
  else if (SNES_PARD_start) begin 
    // ignore DMAs which also seem to assert under certain conditions when they are reading WRAM  
    SNES_PARD_count <= 1;
  end
  else if (|SNES_PARD_count) begin
    SNES_PARD_count <= SNES_PARD_count + 1;
  end

end

parameter ST_IDLE        = 7'b0000001;
parameter ST_MCU_RD_ADDR = 7'b0000010;
parameter ST_MCU_RD_END  = 7'b0000100;
parameter ST_MCU_WR_ADDR = 7'b0001000;
parameter ST_MCU_WR_END  = 7'b0010000;
parameter ST_CTX_WR_ADDR = 7'b0100000;
parameter ST_CTX_WR_END  = 7'b1000000;

parameter SNES_DEAD_TIMEOUT = 17'd96000; // 1ms

parameter ROM_CYCLE_LEN = 4'd7;

reg [6:0] STATE;
initial STATE = ST_IDLE;

assign DSPX_SNES_DATA_IN = BUS_DATA;
assign SRTC_SNES_DATA_IN = BUS_DATA[3:0];
assign MSU_SNES_DATA_IN = BUS_DATA;
assign USB_SNES_DATA_IN = BUS_DATA;
assign BSX_SNES_DATA_IN = BUS_DATA;

sd_dma snes_sd_dma(
  .CLK(CLK2),
  .SD_DAT(SD_DAT),
  .SD_CLK(SD_CLK),
  .SD_DMA_EN(SD_DMA_EN),
  .SD_DMA_STATUS(SD_DMA_STATUS),
  .SD_DMA_SRAM_WE(SD_DMA_SRAM_WE),
  .SD_DMA_SRAM_DATA(SD_DMA_SRAM_DATA),
  .SD_DMA_NEXTADDR(SD_DMA_NEXTADDR),
  .SD_DMA_PARTIAL(SD_DMA_PARTIAL),
  .SD_DMA_PARTIAL_START(SD_DMA_PARTIAL_START),
  .SD_DMA_PARTIAL_END(SD_DMA_PARTIAL_END),
  .SD_DMA_START_MID_BLOCK(SD_DMA_START_MID_BLOCK),
  .SD_DMA_END_MID_BLOCK(SD_DMA_END_MID_BLOCK),
  .DBG_cyclecnt(SD_DMA_DBG_cyclecnt),
  .DBG_clkcnt(SD_DMA_DBG_clkcnt)
);

wire SD_DMA_TO_ROM = (SD_DMA_STATUS && (SD_DMA_TGT == 2'b00));

dac snes_dac(
  .clkin(CLK2),
  .sysclk(SNES_SYSCLK),
  .mclk_out(DAC_MCLK),
  .lrck_out(DAC_LRCK),
  .sdout(DAC_SDOUT),
  .we(SD_DMA_TGT==2'b01 ? SD_DMA_SRAM_WE : 1'b1),
  .pgm_address(dac_addr),
  .pgm_data(SD_DMA_SRAM_DATA),
  .DAC_STATUS(DAC_STATUS),
  .volume(msu_volumerq_out),
  .vol_latch(msu_volume_latch_out),
  .vol_select(dac_vol_select_out),
  .palmode(dac_palmode_out),
  .play(dac_play),
  .reset(dac_reset),
  .dac_address_ext(dac_ptr_addr)
);

srtc snes_srtc (
  .clkin(CLK2),
  .addr_in(SNES_ADDR[0]),
  .data_in(SRTC_SNES_DATA_IN),
  .data_out(SRTC_SNES_DATA_OUT),
  .rtc_data_in(rtc_data),
  .enable(srtc_enable),
  .rtc_data_out(srtc_rtc_data_out),
  .reg_oe_falling(SNES_RD_start),
  .reg_oe_rising(SNES_RD_end),
  .reg_we_rising(SNES_WR_end),
  .rtc_we(srtc_rtc_we),
  .reset(srtc_reset),
  .srtc_state(DBG_srtc_state),
  .srtc_reg_we_rising(DBG_srtc_we_rising),
  .srtc_rtc_ptr(DBG_srtc_ptr),
  .srtc_we_sreg(DBG_srtc_we_sreg)
);

rtc snes_rtc (
  .clkin(CLKIN),
  .rtc_data(rtc_data),
  .rtc_data_in(rtc_data_in),
  .pgm_we(rtc_pgm_we),
  .rtc_data_in1(srtc_rtc_data_out),
  .we1(srtc_rtc_we)
);

msu snes_msu (
  .clkin(CLK2),
  .enable(msu_enable),
  .pgm_address(msu_write_addr),
  .pgm_data(SD_DMA_SRAM_DATA),
  .pgm_we(SD_DMA_TGT==2'b10 ? SD_DMA_SRAM_WE : 1'b1),
  .reg_addr(SNES_ADDR[2:0]),
  .reg_data_in(MSU_SNES_DATA_IN),
  .reg_data_out(MSU_SNES_DATA_OUT),
  .reg_oe_falling(SNES_RD_start),
  .reg_oe_rising(SNES_RD_end),
  .reg_we_rising(SNES_WR_end),
  .status_out(msu_status_out),
  .volume_out(msu_volumerq_out),
  .volume_latch_out(msu_volume_latch_out),
  .addr_out(msu_addressrq_out),
  .track_out(msu_trackrq_out),
  .status_reset_bits(msu_status_reset_bits),
  .status_set_bits(msu_status_set_bits),
  .status_reset_we(msu_status_reset_we),
  .msu_address_ext(msu_ptr_addr),
  .msu_address_ext_write(msu_addr_reset),
  .DBG_msu_reg_oe_rising(DBG_msu_reg_oe_rising),
  .DBG_msu_reg_oe_falling(DBG_msu_reg_oe_falling),
  .DBG_msu_reg_we_rising(DBG_msu_reg_we_rising),
  .DBG_msu_address(DBG_msu_address),
  .DBG_msu_address_ext_write_rising(DBG_msu_address_ext_write_rising)
);

usb snes_usb (
  .clkin(CLK2),
  .enable(usb_enable),
  .reg_addr(SNES_ADDR[2:0]),
  .reg_data_in(USB_SNES_DATA_IN),
  .reg_data_out(USB_SNES_DATA_OUT),
  .reg_oe_falling(SNES_RD_start),
  .reg_oe_rising(SNES_RD_end),
  .reg_we_rising(SNES_WR_end),
  .status_reset_bits(usb_status_reset_bits),
  .status_set_bits(usb_status_set_bits),
  .status_reset_we(usb_status_reset_we)
);

wire [23:0] CTX_ADDR;
wire [7:0] CTX_DOUT;

ctx snes_ctx (
  .clkin(CLK2),
  .reset(SNES_reset_strobe),

  .SNES_ADDR(SNES_ADDR),
  .SNES_PA(SNES_PA),
  .SNES_RD_end(SNES_RD_end),
  .SNES_WR_end(SNES_WR_end),
  .SNES_PARD_end(SNES_PARD_end),
  .SNES_PAWR_end(SNES_PAWR_end),
  .SNES_DATA_IN(SNES_DATA), // needs to handle PA accesses, too

  .OE_WR_ENABLE(ctx_wr_enable),
  .OE_PAWR_ENABLE(ctx_pawr_enable),

  .BUS_WRQ(CTX_WRQ),
  .BUS_RDY(CTX_RDY),

  .ROM_ADDR(CTX_ADDR),
  .ROM_DATA(CTX_DOUT)
);

bsx snes_bsx(
  .clkin(CLK2),
  .use_bsx(use_bsx),
  .pgm_we(bsx_regs_reset_we),
  .snes_addr(SNES_ADDR),
  .reg_data_in(BSX_SNES_DATA_IN),
  .reg_data_out(BSX_SNES_DATA_OUT),
  .reg_oe_falling(SNES_RD_start),
  .reg_oe_rising(SNES_RD_end),
  .reg_we_rising(SNES_WR_end),
  .regs_out(bsx_regs),
  .reg_reset_bits(bsx_regs_reset_bits),
  .reg_set_bits(bsx_regs_set_bits),
  .data_ovr(bsx_data_ovr),
  .flash_writable(IS_FLASHWR),
  .rtc_data(rtc_data[59:0]),
  .bs_page_out(bs_page), // support only page 0000-03ff
  .bs_page_enable(bs_page_enable),
  .bs_page_offset(bs_page_offset)

);

spi snes_spi(
  .clk(CLK2),
  .MOSI(SPI_MOSI),
  .MISO(SPI_MISO),
  .SSEL(SPI_SS),
  .SCK(SPI_SCK),
  .cmd_ready(spi_cmd_ready),
  .param_ready(spi_param_ready),
  .cmd_data(spi_cmd_data),
  .param_data(spi_param_data),
  .endmessage(spi_endmessage),
  .startmessage(spi_startmessage),
  .input_data(spi_input_data),
  .byte_cnt(spi_byte_cnt),
  .bit_cnt(spi_bit_cnt)
);

wire [15:0] dsp_feat;

upd77c25 snes_dspx (
  .DI(DSPX_SNES_DATA_IN),
  .DO(DSPX_SNES_DATA_OUT),
  .A0(DSPX_A0),
  .enable(dspx_enable),
  .reg_oe_falling(SNES_RD_start),
  .reg_oe_rising(SNES_RD_end),
  .reg_we_rising(SNES_WR_end),
  .RST(~dspx_reset),
  .CLK(CLK2),
  .PGM_WR(dspx_pgm_we),
  .PGM_DI(dspx_pgm_data),
  .PGM_WR_ADDR(dspx_pgm_addr),
  .DAT_WR(dspx_dat_we),
  .DAT_DI(dspx_dat_data),
  .DAT_WR_ADDR(dspx_dat_addr),
  .DP_enable(dspx_dp_enable),
  .DP_ADDR(SNES_ADDR[10:0]),
  .dsp_feat(dsp_feat)
);

reg [7:0] MCU_DINr;
wire [7:0] MCU_DOUT;
wire [31:0] cheat_pgm_data;
wire [7:0] cheat_data_out;
wire [2:0] cheat_pgm_idx;

wire feat_cmd_unlock = featurebits[5];

mcu_cmd snes_mcu_cmd(
  .clk(CLK2),
  .snes_sysclk(SNES_SYSCLK),
  .cmd_ready(spi_cmd_ready),
  .param_ready(spi_param_ready),
  .cmd_data(spi_cmd_data),
  .param_data(spi_param_data),
  .mcu_mapper(MAPPER),
  .mcu_write(MCU_WRITE),
  .mcu_data_in(MCU_DINr),
  .mcu_data_out(MCU_DOUT),
  .spi_byte_cnt(spi_byte_cnt),
  .spi_bit_cnt(spi_bit_cnt),
  .spi_data_out(spi_input_data),
  .addr_out(MCU_ADDR),
  .saveram_mask_out(SAVERAM_MASK),
  .rom_mask_out(ROM_MASK),
  .SD_DMA_EN(SD_DMA_EN),
  .SD_DMA_STATUS(SD_DMA_STATUS),
  .SD_DMA_NEXTADDR(SD_DMA_NEXTADDR),
  .SD_DMA_SRAM_DATA(SD_DMA_SRAM_DATA),
  .SD_DMA_SRAM_WE(SD_DMA_SRAM_WE),
  .SD_DMA_TGT(SD_DMA_TGT),
  .SD_DMA_PARTIAL(SD_DMA_PARTIAL),
  .SD_DMA_PARTIAL_START(SD_DMA_PARTIAL_START),
  .SD_DMA_PARTIAL_END(SD_DMA_PARTIAL_END),
  .SD_DMA_START_MID_BLOCK(SD_DMA_START_MID_BLOCK),
  .SD_DMA_END_MID_BLOCK(SD_DMA_END_MID_BLOCK),
  .dac_addr_out(dac_addr),
  .DAC_STATUS(DAC_STATUS),
  .dac_play_out(dac_play),
  .dac_reset_out(dac_reset),
  .dac_vol_select_out(dac_vol_select_out),
  .dac_palmode_out(dac_palmode_out),
  .dac_ptr_out(dac_ptr_addr),
  .msu_addr_out(msu_write_addr),
  .MSU_STATUS(msu_status_out),
  .msu_status_reset_out(msu_status_reset_bits),
  .msu_status_set_out(msu_status_set_bits),
  .msu_status_reset_we(msu_status_reset_we),
  .msu_volumerq(msu_volumerq_out),
  .msu_addressrq(msu_addressrq_out),
  .msu_trackrq(msu_trackrq_out),
  .msu_ptr_out(msu_ptr_addr),
  .msu_reset_out(msu_addr_reset),
  .usb_status_reset_out(usb_status_reset_bits),
  .usb_status_set_out(usb_status_set_bits),
  .usb_status_reset_we(usb_status_reset_we),
  .bsx_regs_set_out(bsx_regs_set_bits),
  .bsx_regs_reset_out(bsx_regs_reset_bits),
  .bsx_regs_reset_we(bsx_regs_reset_we),
  .rtc_data_out(rtc_data_in),
  .rtc_pgm_we(rtc_pgm_we),
  .srtc_reset(srtc_reset),
  .dspx_pgm_data_out(dspx_pgm_data),
  .dspx_pgm_addr_out(dspx_pgm_addr),
  .dspx_pgm_we_out(dspx_pgm_we),
  .dspx_dat_data_out(dspx_dat_data),
  .dspx_dat_addr_out(dspx_dat_addr),
  .dspx_dat_we_out(dspx_dat_we),
  .dspx_reset_out(dspx_reset),
  .featurebits_out(featurebits),
  .mcu_rrq(MCU_RRQ),
  .mcu_wrq(MCU_WRQ),
  .mcu_rq_rdy(MCU_RDY),
  .region_out(mcu_region),
  .snescmd_addr_out(snescmd_addr_mcu),
  .snescmd_we_out(snescmd_we_mcu),
  .snescmd_data_out(snescmd_data_out_mcu),
  .snescmd_data_in(snescmd_data_in_mcu),
  .cheat_pgm_idx_out(cheat_pgm_idx),
  .cheat_pgm_data_out(cheat_pgm_data),
  .cheat_pgm_we_out(cheat_pgm_we),
  .dsp_feat_out(dsp_feat)
);

wire [7:0] DCM_STATUS;
// dcm1: dfs 4x
my_dcm snes_dcm(
  .CLKIN(CLKIN),
  .CLKFX(CLK2),
  .LOCKED(DCM_LOCKED),
  .RST(DCM_RST),
  .STATUS(DCM_STATUS)
);

address snes_addr(
  .CLK(CLK2),
  .MAPPER(MAPPER),
  .featurebits(featurebits),
  .SNES_ADDR(SNES_ADDR), // requested address from SNES
  .SNES_PA(SNES_PA),
  .SNES_ROMSEL(SNES_ROMSEL),
  .ROM_ADDR(MAPPED_SNES_ADDR),   // Address to request from SRAM (active low)
  .ROM_HIT(ROM_HIT),     // want to access RAM0
  .IS_SAVERAM(IS_SAVERAM),
  .IS_ROM(IS_ROM),
  .IS_WRITABLE(IS_WRITABLE),
  .SAVERAM_MASK(SAVERAM_MASK),
  .ROM_MASK(ROM_MASK),
  .map_unlock(map_unlock),
  //MSU-1
  .msu_enable(msu_enable),
  //BS-X
  .use_bsx(use_bsx),
  .bsx_regs(bsx_regs),
  .bs_page_offset(bs_page_offset),
  .bs_page(bs_page),
  .bs_page_enable(bs_page_enable),
  .bsx_tristate(bsx_tristate),
  //SRTC
  .srtc_enable(srtc_enable),
  //uPD77C25
  .dspx_enable(dspx_enable),
  .dspx_dp_enable(dspx_dp_enable),
  .dspx_a0(DSPX_A0),
  .r213f_enable(r213f_enable),
  .snescmd_enable(snescmd_enable),
  .snescmd_reg_enable(snescmd_reg_enable),
  .nmicmd_enable(nmicmd_enable),
  .return_vector_enable(return_vector_enable),
  .branch1_enable(branch1_enable),
  .branch2_enable(branch2_enable)
);

reg pad_latch = 0;
reg [4:0] pad_cnt = 0;

reg snes_ajr = 0;

cheat snes_cheat(
  .clk(CLK2),
  .SNES_ADDR(SNES_ADDR),
  .SNES_PA(SNES_PA),
  .SNES_DATA(SNES_DATA),
  .SNES_reset_strobe(SNES_reset_strobe),
  .SNES_wr_strobe(SNES_WR_end),
  .SNES_rd_strobe(SNES_RD_start),
  .snescmd_enable(snescmd_enable),
  .nmicmd_enable(nmicmd_enable),
  .return_vector_enable(return_vector_enable),
  .branch1_enable(branch1_enable),
  .branch2_enable(branch2_enable),
  .pad_latch(pad_latch),
  .snes_ajr(snes_ajr),
  .SNES_cycle_start(SNES_cycle_start),
  .pgm_idx(cheat_pgm_idx),
  .pgm_we(cheat_pgm_we),
  .pgm_in(cheat_pgm_data),
  .data_out(cheat_data_out),
  .cheat_hit(cheat_hit),
  .snescmd_unlock(snescmd_unlock),
  .map_unlock(map_unlock)
);

wire [7:0] snescmd_dout;

reg [7:0] r213fr;
reg r213f_forceread;
reg [2:0] r213f_delay;
reg [1:0] r213f_state;
initial r213fr = 8'h55;
initial r213f_forceread = 0;
initial r213f_state = 2'b01;
initial r213f_delay = 3'b000;

wire snoop_4200_enable = {SNES_ADDR[22], SNES_ADDR[15:0]} == 17'h04200;
wire r4016_enable = {SNES_ADDR[22], SNES_ADDR[15:0]} == 17'h04016;

always @(posedge CLK2) begin
  if(SNES_WR_end & snoop_4200_enable) begin
    snes_ajr <= SNES_DATA[0];
  end
end

always @(posedge CLK2) begin
  if(SNES_WR_end & r4016_enable) begin
    pad_latch <= 1'b1;
    pad_cnt <= 5'h0;
  end
  if(SNES_RD_start & r4016_enable) begin
    pad_cnt <= pad_cnt + 1;
    if(&pad_cnt[3:0]) begin
      pad_latch <= 1'b0;
    end
  end
end

// map a portion of the snescmd address space to support reading of the registers
reg [7:0] r21XX [0:63][1:0]; // $2100-$213F
reg [63:0]r21XX_readIndex;
reg [7:0] r420X [0:15]; // $4200-$420F

reg [7:0] r21XX_BG_latch;
reg [7:0] r21XX_M7_latch;

integer i;

wire snoop_21XX_enable = SNES_PA <= 8'h33;
wire snoop_420X_enable = ({SNES_ADDR[22], SNES_ADDR[15:4], 4'h0} == 17'h04200) && ~(&SNES_ADDR[3:1]);
wire snoop_2140_enable = SNES_PA == 8'h40;
wire SNES_PAWR_DATA_OE = |SNES_PAWR_count;
wire SNES_PARD_DATA_OE = |SNES_PARD_count;

reg r21XX_dual_active;

reg       r21XX_val;
reg [7:0] r21XX_PA;
reg [7:0] r21XX_DATA;
reg       r21XX_cgram_toggle;
reg       r21XX_oam_toggle;

always @(posedge CLK2) begin
  if (SNES_reset_strobe) begin
    for (i = 0; i < 64; i = i + 1) r21XX_readIndex[i] <= 0;
	 r21XX_val <= 1'b0;
    r21XX_cgram_toggle <= 1'b0;
    r21XX_oam_toggle <= 1'b0;
    r420X[4'hF] <= 0;
  end
  else begin
    if (SNES_PAWR_end & snoop_21XX_enable) begin
	   r21XX_val <= 1'b1;
		r21XX_PA <= SNES_PA;
		r21XX_DATA <= SNES_DATA;
	 end
    else if (r21XX_val) begin
	   r21XX_val <= 1'b0;
		
	   if (r21XX_PA >= 8'h0D && r21XX_PA <= 8'h0E) begin
			r21XX[r21XX_PA[5:0]][1] <= r21XX_DATA[7:0];
			r21XX[r21XX_PA[5:0]][0] <= r21XX_BG_latch;
			r21XX_BG_latch         <= r21XX_DATA[7:0];
			r21XX_M7_latch         <= r21XX_DATA[7:0];
		end	 
	   else if (r21XX_PA >= 8'h0F && r21XX_PA <= 8'h14) begin
			r21XX[r21XX_PA[5:0]][1] <= r21XX_DATA[7:0];
			r21XX[r21XX_PA[5:0]][0] <= r21XX_BG_latch;
			r21XX_BG_latch         <= r21XX_DATA[7:0];
		end
		else if (r21XX_PA >= 8'h1B && r21XX_PA <= 8'h20) begin
			r21XX[r21XX_PA[5:0]][1] <= r21XX_DATA[7:0];
			r21XX[r21XX_PA[5:0]][0] <= r21XX_M7_latch;
			r21XX_M7_latch         <= r21XX_DATA[7:0];
		end
		else if (r21XX_PA[7:6] == 2'b00) begin
			r21XX[r21XX_PA[5:0]][1] <= r21XX_DATA[7:0];
			r21XX[r21XX_PA[5:0]][0] <= r21XX_DATA[7:0];
			
			if (r21XX_PA == 8'h21) begin
           r21XX_cgram_toggle <= 1'b0;
			end
			else if (r21XX_PA == 8'h22) begin
				// increment cgram address on write
				if (r21XX_cgram_toggle) begin
				  r21XX_cgram_toggle <= 1'b0;
				  r21XX[6'h21][0] <= r21XX[6'h21][0] + 1'b1;
				  r21XX[6'h21][1] <= r21XX[6'h21][1] + 1'b1;
				end
				else begin
				  r21XX_cgram_toggle <= 1'b1;
				end
			end
			else if (((r21XX_PA == 8'h18) & ~r21XX[6'h15][0][7]) | ((r21XX_PA == 8'h19) & r21XX[6'h15][0][7])) begin
				// increment vram address on write
				// TODO: handle reads, too
				{r21XX[6'h17][0], r21XX[6'h16][0]} <= {r21XX[6'h17][0], r21XX[6'h16][0]} + (r21XX[6'h15][0][1] ? 16'h80 : r21XX[6'h15][0][0] ? 16'h20 : 16'h1);
				{r21XX[6'h17][1], r21XX[6'h16][1]} <= {r21XX[6'h17][1], r21XX[6'h16][1]} + (r21XX[6'h15][1][1] ? 16'h80 : r21XX[6'h15][1][0] ? 16'h20 : 16'h1);
			end
			else if (r21XX_PA == 8'h04) begin
				// increment oam address on write
				if (r21XX_oam_toggle) begin
				  r21XX_oam_toggle <= 1'b0;
				  {r21XX[6'h03][0], r21XX[6'h02][0]} <= {r21XX[6'h03][0], r21XX[6'h02][0]} + 1'b1;
				  {r21XX[6'h03][1], r21XX[6'h02][1]} <= {r21XX[6'h03][1], r21XX[6'h02][1]} + 1'b1;
				end
				else begin
				  r21XX_oam_toggle <= 1'b1;
				end
			end
		end
    end

    if (SNES_WR_end & snoop_420X_enable) begin
      r420X[SNES_ADDR[3:0]] <= SNES_DATA[7:0];
    end
	 else if (SNES_PAWR_end & snoop_2140_enable) begin
	   // save mirror of audio write
      r420X[4'hE] <= SNES_DATA;
	 end
	 
    if (snescmd_reg_enable & ~SNES_ADDR[6] & SNES_RD_end) begin
      r21XX_readIndex[SNES_ADDR[5:0]] <= ~r21XX_readIndex[SNES_ADDR[5:0]];
	 end

  end
end

wire [7:0] snescmd_reg_out;

assign snescmd_reg_out = ({SNES_ADDR[22], SNES_ADDR[15:6], 6'h0} == 17'h02B00) ? r21XX[SNES_ADDR[5:0]][r21XX_readIndex[SNES_ADDR[5:0]]]
                                                                               : r420X[SNES_ADDR[3:0]];


// FIXME: Cleanup read equation.  Currently this matches DIR in order to snoop.  Just looking at ~SNES_READ corrupts SNES_DATA when we are trying to snoop data from the bus.
assign SNES_DATA = (r213f_enable & ~SNES_PARD & ~r213f_forceread) ? r213fr
                   :((~SNES_READ & ((~SNES_PAWR_DATA_OE & ~SNES_PARD_DATA_OE) | ~SNES_ROMSEL_EARLY)) ^ (r213f_forceread & r213f_enable & ~SNES_PARD))
                                ? (srtc_enable ? SRTC_SNES_DATA_OUT
                                  :dspx_enable ? DSPX_SNES_DATA_OUT
                                  :dspx_dp_enable ? DSPX_SNES_DATA_OUT
                                  :msu_enable ? MSU_SNES_DATA_OUT
											 :usb_enable ? USB_SNES_DATA_OUT
                                  :bsx_data_ovr ? BSX_SNES_DATA_OUT
                                  :(cheat_hit & ~feat_cmd_unlock) ? cheat_data_out
                                  :((snescmd_unlock | feat_cmd_unlock) & snescmd_reg_enable) ? snescmd_reg_out
                                  :((snescmd_unlock | feat_cmd_unlock) & snescmd_enable) ? snescmd_dout
                                  :(ROM_ADDR0 ? ROM_DATA[7:0] : ROM_DATA[15:8])
                                  ) : 8'bZ;

reg [3:0] ST_MEM_DELAYr;
reg MCU_RD_PENDr = 0;
reg MCU_WR_PENDr = 0;
reg [23:0] ROM_ADDRr;
// CTX
reg CTX_WR_PENDr;
initial CTX_WR_PENDr = 0;
reg [23:0] CTX_ROM_ADDRr;
initial CTX_ROM_ADDRr = 24'h0;
reg [7:0] CTX_ROM_DATAr;
initial CTX_ROM_DATAr = 8'h0;

reg RQ_MCU_RDYr;
initial RQ_MCU_RDYr = 1'b1;
assign MCU_RDY = RQ_MCU_RDYr;
// CTX
reg RQ_CTX_RDYr;
initial RQ_CTX_RDYr = 1'b1;
assign CTX_RDY = RQ_CTX_RDYr;

wire MCU_WR_HIT = |(STATE & ST_MCU_WR_ADDR);
wire MCU_RD_HIT = |(STATE & ST_MCU_RD_ADDR);
wire MCU_HIT = MCU_WR_HIT | MCU_RD_HIT;
// CTX
wire CTX_WR_HIT = |(STATE & ST_CTX_WR_ADDR);
wire CTX_HIT = CTX_WR_HIT;

// Map audio to ROM
reg [7:0] rAudio[3:0];

wire snoop_audio_enable = {SNES_PA[7:6],6'b000000} == 8'h40;

always @(posedge CLK2) begin
  if (SNES_PAWR_end & snoop_audio_enable) begin
    rAudio[SNES_PA[1:0]] <= SNES_DATA;
  end
end

assign ROM_ADDR  = (SD_DMA_TO_ROM) ? MCU_ADDR[23:1] : CTX_HIT ? CTX_ROM_ADDRr[23:1] : MCU_HIT ? ROM_ADDRr[23:1] : MAPPED_SNES_ADDR[23:1];
assign ROM_ADDR0 = (SD_DMA_TO_ROM) ? MCU_ADDR[0] : CTX_HIT ? CTX_ROM_ADDRr[0] : MCU_HIT ? ROM_ADDRr[0] : MAPPED_SNES_ADDR[0];

reg[17:0] SNES_DEAD_CNTr;
initial SNES_DEAD_CNTr = 0;

// context engine request
always @(posedge CLK2) begin
  // FIXME: workaround for spurious writes is to include pending
  if(CTX_WRQ & ~CTX_WR_PENDr) begin
    CTX_WR_PENDr <= 1'b1;
	 RQ_CTX_RDYr <= 1'b0;
	 CTX_ROM_ADDRr <= CTX_ADDR;
	 CTX_ROM_DATAr <= CTX_DOUT;
  end 
  else if(STATE & ST_CTX_WR_END) begin
    CTX_WR_PENDr <= 1'b0;
	 RQ_CTX_RDYr <= 1'b1;
  end
end

always @(posedge CLK2) begin
  if(MCU_RRQ) begin
    MCU_RD_PENDr <= 1'b1;
    RQ_MCU_RDYr <= 1'b0;
    ROM_ADDRr <= MCU_ADDR;
  end else if(MCU_WRQ) begin
    MCU_WR_PENDr <= 1'b1;
    RQ_MCU_RDYr <= 1'b0;
    ROM_ADDRr <= MCU_ADDR;
  end else if(STATE & (ST_MCU_RD_END | ST_MCU_WR_END)) begin
    MCU_RD_PENDr <= 1'b0;
    MCU_WR_PENDr <= 1'b0;
    RQ_MCU_RDYr <= 1'b1;
  end
end

always @(posedge CLK2) begin
  if(~SNES_CPU_CLKr[1]) SNES_DEAD_CNTr <= SNES_DEAD_CNTr + 1;
  else SNES_DEAD_CNTr <= 17'h0;
end

always @(posedge CLK2) begin
  SNES_reset_strobe <= 1'b0;
  if(SNES_CPU_CLKr[1]) begin
    SNES_DEADr <= 1'b0;
    if(SNES_DEADr) SNES_reset_strobe <= 1'b1;
  end
  else if(SNES_DEAD_CNTr > SNES_DEAD_TIMEOUT) SNES_DEADr <= 1'b1;
end

always @(posedge CLK2) begin
  if(SNES_DEADr & SNES_CPU_CLKr[1]) STATE <= ST_IDLE; // interrupt+restart an ongoing MCU access when the SNES comes alive
  else
  case(STATE)
    ST_IDLE: begin
      STATE <= ST_IDLE;
      if(free_slot | SNES_DEADr) begin
		  if(CTX_WR_PENDr) begin
          STATE <= ST_CTX_WR_ADDR;
          ST_MEM_DELAYr <= ROM_CYCLE_LEN;
		  end
        else if(MCU_RD_PENDr) begin
          STATE <= ST_MCU_RD_ADDR;
          ST_MEM_DELAYr <= ROM_CYCLE_LEN;
        end
        else if(MCU_WR_PENDr) begin
          STATE <= ST_MCU_WR_ADDR;
          ST_MEM_DELAYr <= ROM_CYCLE_LEN;
        end
      end
    end
    ST_MCU_RD_ADDR: begin
      STATE <= ST_MCU_RD_ADDR;
      ST_MEM_DELAYr <= ST_MEM_DELAYr - 1;
      if(ST_MEM_DELAYr == 0) STATE <= ST_MCU_RD_END;
      MCU_DINr <= (ROM_ADDR0 ? ROM_DATA[7:0] : ROM_DATA[15:8]);
    end
    ST_MCU_WR_ADDR: begin
      STATE <= ST_MCU_WR_ADDR;
      ST_MEM_DELAYr <= ST_MEM_DELAYr - 1;
      if(ST_MEM_DELAYr == 0) STATE <= ST_MCU_WR_END;
    end
    ST_CTX_WR_ADDR: begin
      STATE <= ST_CTX_WR_ADDR;
      ST_MEM_DELAYr <= ST_MEM_DELAYr - 1;
      if(ST_MEM_DELAYr == 0) STATE <= ST_CTX_WR_END;
    end
    ST_MCU_RD_END, ST_MCU_WR_END, ST_CTX_WR_END: begin
      STATE <= ST_IDLE;
    end
  endcase
end

always @(posedge CLK2) begin
  if(SNES_cycle_end) r213f_forceread <= 1'b1;
  else if(SNES_PARD_start & r213f_enable) begin
//    r213f_delay <= 3'b000;
//    r213f_state <= 2'b10;
//  end else if(r213f_state == 2'b10) begin
//    r213f_delay <= r213f_delay - 1;
//    if(r213f_delay == 3'b000) begin
      r213f_forceread <= 1'b0;
      r213f_state <= 2'b01;
      r213fr <= {SNES_DATA[7:5], mcu_region, SNES_DATA[3:0]};
//    end
  end
end

reg MCU_WRITE_1;
always @(posedge CLK2) MCU_WRITE_1<= MCU_WRITE;

assign ROM_DATA[7:0] = ROM_ADDR0
                       ?(SD_DMA_TO_ROM ? (!MCU_WRITE_1 ? MCU_DOUT : 8'bZ)
                                        : CTX_WR_HIT ? CTX_ROM_DATAr
                                        : (ROM_HIT & ~SNES_WRITE) ? SNES_DATA
                                        : MCU_WR_HIT ? MCU_DOUT
													 : 8'bZ
                        )
                       :8'bZ;

assign ROM_DATA[15:8] = ROM_ADDR0 ? 8'bZ
                        :(SD_DMA_TO_ROM ? (!MCU_WRITE_1 ? MCU_DOUT : 8'bZ)
                                        : CTX_WR_HIT ? CTX_ROM_DATAr
                                        : (ROM_HIT & ~SNES_WRITE) ? SNES_DATA
                                        : MCU_WR_HIT ? MCU_DOUT
                                        : 8'bZ
                         );

assign ROM_WE = SD_DMA_TO_ROM
                ?MCU_WRITE
					 : CTX_WR_HIT ? 1'b0
                : (ROM_HIT & (IS_WRITABLE | IS_FLASHWR) & SNES_CPU_CLK) ? SNES_WRITE
                : MCU_WR_HIT ? 1'b0
                : 1'b1;

// OE always active. Overridden by WE when needed.
assign ROM_OE = 1'b0;

assign ROM_CE = 1'b0;

assign ROM_BHE = ROM_ADDR0;
assign ROM_BLE = !ROM_ADDR0;

wire cart_read_oe = ( (IS_ROM & SNES_ROMSEL)
                    | (!IS_ROM & !IS_SAVERAM & !IS_WRITABLE & !IS_FLASHWR)
                    | (SNES_READ & SNES_WRITE)
                    | (bsx_tristate)
                    );

assign SNES_DATABUS_OE = (dspx_enable | dspx_dp_enable) ? 1'b0 :
                         msu_enable ? 1'b0 :
								 usb_enable ? 1'b0 :
                         bsx_data_ovr ? (SNES_READ & SNES_WRITE) :
                         srtc_enable ? (SNES_READ & SNES_WRITE) :
                         snescmd_enable ? (~(snescmd_unlock | feat_cmd_unlock) | (SNES_READ & SNES_WRITE)) :
                         bs_page_enable ? (SNES_READ) :
                         r213f_enable & !SNES_PARD ? 1'b0 :
                         snoop_4200_enable ? SNES_WRITE :
								 snoop_420X_enable ? SNES_WRITE :
								 (ctx_wr_enable & ~SNES_WRITE) ? 1'b0 :
								 (ctx_pawr_enable & SNES_PAWR_DATA_OE)? 1'b0 :
								 (snoop_21XX_enable & SNES_PAWR_DATA_OE)? 1'b0 :
								 (snoop_2140_enable & SNES_PARD_DATA_OE)? 1'b0 : 
								 cart_read_oe;

assign SNES_DATABUS_DIR = ((~SNES_READ & ((~SNES_PAWR_DATA_OE & ~SNES_PARD_DATA_OE) | ~SNES_ROMSEL_EARLY)) | (~SNES_PARD & (r213f_enable)))
                           ? 1'b1 ^ (r213f_forceread & r213f_enable & ~SNES_PARD)
                           : 1'b0;

assign SNES_IRQ = 1'b0;

//assign p113_out = 1'b0;
assign p113_out = CTX_WR_PENDr;

snescmd_buf snescmd (
  .clka(CLK2), // input clka
  .wea(SNES_WR_end & ((snescmd_unlock | feat_cmd_unlock) & snescmd_enable)), // input [0 : 0] wea
  .addra(SNES_ADDR[8:0]), // input [8 : 0] addra
  .dina(SNES_DATA), // input [7 : 0] dina
  .douta(snescmd_dout), // output [7 : 0] douta
  .clkb(CLK2), // input clkb
  .web(snescmd_we_mcu), // input [0 : 0] web
  .addrb(snescmd_addr_mcu), // input [8 : 0] addrb
  .dinb(snescmd_data_out_mcu), // input [7 : 0] dinb
  .doutb(snescmd_data_in_mcu) // output [7 : 0] doutb
);

/*
wire [35:0] CONTROL0;

chipscope_icon icon (
    .CONTROL0(CONTROL0) // INOUT BUS [35:0]
);

chipscope_ila ila (
    .CONTROL(CONTROL0), // INOUT BUS [35:0]
    .CLK(CLK2), // IN
    .TRIG0(SNES_ADDR), // IN BUS [23:0]
    .TRIG1(SNES_DATA), // IN BUS [7:0]
    .TRIG2({SNES_READ, SNES_WRITE, SNES_CPU_CLK, SNES_cycle_start, SNES_cycle_end, SNES_DEADr, MCU_RRQ, MCU_WRQ, MCU_RDY, ROM_WEr, ROM_WE, ROM_DOUT_ENr, ROM_SA, DBG_mcu_nextaddr, SNES_DATABUS_DIR, SNES_DATABUS_OE}),   // IN BUS [15:0]
    .TRIG3({bsx_data_ovr, r213f_forceread, r213f_enable, SNES_PARD, spi_cmd_ready, spi_param_ready, spi_input_data, SD_DAT}), // IN BUS [17:0]
    .TRIG4(ROM_ADDRr), // IN BUS [23:0]
    .TRIG5(ROM_DATA), // IN BUS [15:0]
    .TRIG6(MCU_DINr), // IN BUS [7:0]
   .TRIG7(spi_byte_cnt[3:0])
);

/*
ila_srtc ila (
    .CONTROL(CONTROL0), // INOUT BUS [35:0]
    .CLK(CLK2), // IN
    .TRIG0(SD_DMA_DBG_cyclecnt), // IN BUS [23:0]
    .TRIG1(SD_DMA_SRAM_DATA), // IN BUS [7:0]
    .TRIG2({SPI_SCK, SPI_MOSI, SPI_MISO, spi_cmd_ready, SD_DMA_SRAM_WE, SD_DMA_EN, SD_CLK, SD_DAT, SD_DMA_NEXTADDR, SD_DMA_STATUS, 3'b000}),   // IN BUS [15:0]
    .TRIG3({spi_cmd_data, spi_param_data}), // IN BUS [17:0]
    .TRIG4(ROM_ADDRr), // IN BUS [23:0]
    .TRIG5(ROM_DATA), // IN BUS [15:0]
    .TRIG6(MCU_DINr), // IN BUS [7:0]
   .TRIG7(ST_MEM_DELAYr)
);
*/

endmodule
