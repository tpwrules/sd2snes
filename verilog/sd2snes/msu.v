`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    14:55:04 12/14/2010
// Design Name:
// Module Name:    msu
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
module msu(
  input clkin,
  input enable,
  input reset,
  input [13:0] pgm_address,
  input [7:0] pgm_data,
  input pgm_we,
  input [2:0] reg_addr,
  input [7:0] reg_data_in,
  output [7:0] reg_data_out,
  input reg_oe_falling,
  input reg_oe_rising,
  input reg_we_rising,
  output [7:0] status_out,
  output [7:0] volume_out,
  output volume_latch_out,
  output [31:0] addr_out,
  output [15:0] track_out,
  input [5:0] status_reset_bits,
  input [5:0] status_set_bits,
  input status_reset_we,
  input [13:0] msu_address_ext,
  input msu_address_ext_write,

  input feature_enable,
  input SNES_RD_start,
  input SNES_RD_end,
  input SNES_WR_end,
  input SNES_PAWR_end,
  input [23:0] SNES_ADDR,
  input [7:0] SNES_PA,
  input [7:0] SNES_DATA,
  output [7:0] msu_data_out,
  output [31:0] msu_scaddr_out,

  output DBG_msu_reg_oe_rising,
  output DBG_msu_reg_oe_falling,
  output DBG_msu_reg_we_rising,
  output [13:0] DBG_msu_address,
  output DBG_msu_address_ext_write_rising,

  output OE_RD_ENABLE,
  
  output DBG
);

// SNESCAST
wire snescast_we;
wire [7:0] snescast_data;
wire [13:0] snescast_addr;

reg [1:0] status_reset_we_r;
always @(posedge clkin) status_reset_we_r = {status_reset_we_r[0], status_reset_we};
wire status_reset_en = (status_reset_we_r == 2'b01);

reg [13:0] msu_address_r;
wire [13:0] msu_address = msu_address_r;
initial msu_address_r = 13'b0;

wire [7:0] msu_data;
reg [7:0] msu_data_r;

reg [2:0] msu_address_ext_write_sreg;
always @(posedge clkin)
  msu_address_ext_write_sreg <= {msu_address_ext_write_sreg[1:0], msu_address_ext_write};
wire msu_address_ext_write_rising = (msu_address_ext_write_sreg[2:1] == 2'b01);

reg [31:0] addr_out_r;
assign addr_out = addr_out_r;

reg [15:0] track_out_r;
assign track_out = track_out_r;

reg [7:0] volume_r;
assign volume_out = volume_r;

reg volume_start_r;
assign volume_latch_out = volume_start_r;

reg audio_start_r;
reg audio_busy_r;
reg data_start_r;
reg data_busy_r;
reg ctrl_start_r;
reg audio_error_r;
reg [2:0] audio_ctrl_r;
reg [1:0] audio_status_r;

initial begin
  audio_busy_r = 1'b1;
  data_busy_r = 1'b1;
  audio_error_r = 1'b0;
  volume_r = 8'h00;
  addr_out_r = 32'h00000000;
  track_out_r = 16'h0000;
  data_start_r = 1'b0;
  audio_start_r = 1'b0;
end

assign DBG_msu_address = msu_address;
assign DBG_msu_reg_oe_rising = reg_oe_rising;
assign DBG_msu_reg_oe_falling = reg_oe_falling;
assign DBG_msu_reg_we_rising = reg_we_rising;
assign DBG_msu_address_ext_write_rising = msu_address_ext_write_rising;

assign status_out = {msu_address_r[13], // 7
                     audio_start_r,     // 6
                     data_start_r,      // 5
                     volume_start_r,    // 4
                     audio_ctrl_r,      // 3:1
                     ctrl_start_r};     // 0

initial msu_address_r = 14'h1234;

msu_databuf snes_msu_databuf (
  .clka(clkin),
  .wea(feature_enable ? ~pgm_we : snescast_we), // Bus [0 : 0]
  .addra(feature_enable ? pgm_address : snescast_addr), // Bus [13 : 0]
  .dina(feature_enable ? pgm_data : snescast_data), // Bus [7 : 0]
  .clkb(clkin),
  .addrb(feature_enable ? msu_address : pgm_address), // Bus [13 : 0]
  .doutb(msu_data)
); // Bus [7 : 0]

reg [7:0] data_out_r;
assign reg_data_out = data_out_r;

always @(posedge clkin) begin
  if(msu_address_ext_write_rising)
    msu_address_r <= msu_address_ext;
  else if(reg_oe_rising & enable & (reg_addr == 3'h1)) begin
    msu_address_r <= msu_address_r + 1;
  end
end

always @(posedge clkin) begin
  if(reg_oe_falling & enable)
    case(reg_addr)
      3'h0: data_out_r <= {data_busy_r, audio_busy_r, audio_status_r, audio_error_r, 3'b001};
      3'h1: data_out_r <= msu_data;
      3'h2: data_out_r <= 8'h53;
      3'h3: data_out_r <= 8'h2d;
      3'h4: data_out_r <= 8'h4d;
      3'h5: data_out_r <= 8'h53;
      3'h6: data_out_r <= 8'h55;
      3'h7: data_out_r <= 8'h31;
    endcase
end

always @(posedge clkin) begin
  if(reg_we_rising & enable) begin
    case(reg_addr)
      3'h0: addr_out_r[7:0] <= reg_data_in;
      3'h1: addr_out_r[15:8] <= reg_data_in;
      3'h2: addr_out_r[23:16] <= reg_data_in;
      3'h3: begin
        addr_out_r[31:24] <= reg_data_in;
        data_start_r <= 1'b1;
        data_busy_r <= 1'b1;
      end
      3'h4: begin
        track_out_r[7:0] <= reg_data_in;
      end
      3'h5: begin
        track_out_r[15:8] <= reg_data_in;
        audio_start_r <= 1'b1;
        audio_busy_r <= 1'b1;
      end
      3'h6: begin
        volume_r <= reg_data_in;
        volume_start_r <= 1'b1;
      end
      3'h7: begin
        if(!audio_busy_r) begin
          audio_ctrl_r <= reg_data_in[2:0];
          ctrl_start_r <= 1'b1;
        end
      end
    endcase
  end else if (status_reset_en) begin
    audio_busy_r <= (audio_busy_r | status_set_bits[5]) & ~status_reset_bits[5];
    if(status_reset_bits[5]) audio_start_r <= 1'b0;
    data_busy_r <= (data_busy_r | status_set_bits[4]) & ~status_reset_bits[4];
    if(status_reset_bits[4]) data_start_r <= 1'b0;
    audio_error_r <= (audio_error_r | status_set_bits[3]) & ~status_reset_bits[3];
    audio_status_r <= (audio_status_r | status_set_bits[2:1]) & ~status_reset_bits[2:1];
    ctrl_start_r <= (ctrl_start_r | status_set_bits[0]) & ~status_reset_bits[0];
  end else begin
    volume_start_r <= 1'b0;
  end
end

// SNESCAST
reg [13:0] snescast_addr_r = 0;
reg [13:0] snescast_addr_frame_r = 0;
reg [13:0] snescast_addr_op_r = 0;
reg snescast_wr_r = 0;
reg [7:0] snescast_data_r = 0;

reg snescast_nmi = 0;
reg [7:0] snescast_ram[3:0];
reg [23:0] snescast_ret;

// HDMA
parameter HDMA_CHANNELS             = 8;

reg [7:0] r43xx[15:0][HDMA_CHANNELS-1:0];
reg [7:0] r420C;
reg [2:0] snescast_hdma_state[HDMA_CHANNELS-1:0];

parameter HDMA_STATE_IDLE           = 0;
parameter HDMA_STATE_READ_LC        = 1;
parameter HDMA_STATE_READ_INDIRECT0 = 2;
parameter HDMA_STATE_READ_INDIRECT1 = 3;
parameter HDMA_STATE_WRITE_DATA0    = 4;
parameter HDMA_STATE_WRITE_DATA1    = 5;
parameter HDMA_STATE_WRITE_DATA2    = 6;
parameter HDMA_STATE_WRITE_DATA3    = 7;

reg       snescast_hdma_found = 0;
reg       snescast_hdma_read_active = 0;
reg [2:0] snescast_hdma_read_channel = 0;
reg       snescast_hdma_scan_active = 0;

reg        scan_hdma_enabled;
reg [23:0] scan_hdma_table_addr;
reg [23:0] scan_hdma_indirect_addr;

integer i;

//reg [7:0] snescast_hdma_table_read_addr; //= (SNES_ADDR == {r43xx[4][ch],r43xx[9][ch],r43xx[8][ch]});
//reg [7:0] snescast_hdma_indirect_read_addr; //= (SNES_ADDR == {r43xx[7][ch],r43xx[6][ch],r43xx[5][ch]});

//always @* begin
//  for (i = 0; i < HDMA_CHANNELS; i = i + 1) begin
//    snescast_hdma_table_read_addr = (SNES_ADDR == {r43xx[4][i],r43xx[9][i],r43xx[8][i]});
//    snescast_hdma_indirect_read_addr = (SNES_ADDR == {r43xx[7][i],r43xx[6][i],r43xx[5][i]});
//  end
//end

//wire [7:0] snescast_read_match = ({HDMA_CHANNELS{~r43xx[i][8'h0][6]}} & snescast_hdma_table_read_match) | ({HDMA_CHANNELS{r43xx[i][8'h0][6]}} & snescast_hdma_indirect_read_match);

// identify snooped operations
assign IS_PPUREG_WRITE_ADDR = (SNES_PA <= 8'h33);
assign IS_PPUREG_WRITE = !snescast_hdma_read_active && SNES_PAWR_end && IS_PPUREG_WRITE_ADDR;
assign IS_PPUREG = IS_PPUREG_WRITE; // | IS_PPUREG_READ;

assign IS_CPUREG_WRITE_ADDR = {1'b0,SNES_ADDR[22],6'b000000, SNES_ADDR[15:4], 4'b0000} == 24'h04200;
assign IS_CPUREG_WRITE = SNES_WR_end && IS_CPUREG_WRITE_ADDR;
assign IS_CPUREG = IS_CPUREG_WRITE;

assign IS_CPUDMA_WRITE_ADDR = {1'b0,SNES_ADDR[22],6'b000000, SNES_ADDR[15:7], 7'b0000000} == 24'h04300;
assign IS_CPUDMA_WRITE = SNES_WR_end && IS_CPUDMA_WRITE_ADDR;
assign IS_CPUDMA = IS_CPUDMA_WRITE;

assign IS_APU_WRITE_ADDR = {SNES_PA[7:6],6'b000000} == 8'h40;
assign IS_APU_WRITE = SNES_PAWR_end && IS_APU_WRITE_ADDR;
assign IS_APU = IS_APU_WRITE;

assign IS_NMI_START_ADDR = SNES_ADDR == 24'h00FFEA;
assign IS_NMI_START = !snescast_nmi && SNES_RD_end && IS_NMI_START_ADDR;
assign IS_NMI_END_ADDR = SNES_ADDR == snescast_ret;
assign IS_NMI_END = snescast_nmi && SNES_RD_end && IS_NMI_END_ADDR;
assign IS_NMI = IS_NMI_START | IS_NMI_END;
assign IS_SPECIAL = IS_NMI;

assign IS_HDMA_READ_ADDR = snescast_hdma_read_active && (~snescast_hdma_state[snescast_hdma_read_channel][2]);
assign IS_HDMA_WRITE_ADDR = snescast_hdma_read_active && (snescast_hdma_state[snescast_hdma_read_channel][2]);
assign IS_HDMA_READ = SNES_RD_end && IS_HDMA_READ_ADDR;
assign IS_HDMA_WRITE = SNES_RD_end && IS_HDMA_WRITE_ADDR;
assign IS_HDMA = IS_HDMA_READ | IS_HDMA_WRITE;

// TODO implement DMA compression
assign snescast_wr_multibyte = 1;
assign snescast_wr = IS_PPUREG | IS_CPUREG | IS_CPUDMA | IS_APU | IS_SPECIAL | IS_HDMA;
assign snescast_we = snescast_wr | snescast_wr_r;

// addr/data
assign snescast_addr = snescast_addr_r;
assign snescast_data = snescast_wr_r ? snescast_data_r
                     : IS_HDMA_READ  ? {4'h8+snescast_hdma_read_channel,4'hB}
                     : IS_HDMA_WRITE ? {4'h8+snescast_hdma_read_channel,4'hC}
                     : IS_SPECIAL    ? 8'hFF
                     : IS_PPUREG     ? SNES_PA
                     : IS_CPUREG     ? 8'h70 + SNES_ADDR[3:0]
                     : IS_CPUDMA     ? 8'h80 + SNES_ADDR[6:0]
                     : IS_APU        ? {SNES_PA[7:6],4'h0,SNES_PA[1:0]}
                     :                 8'hFF;

wire [2:0] ch;
assign ch[2:0] = snescast_hdma_read_channel[2:0];

always @(posedge clkin) begin
  if (reset) begin
    snescast_addr_r <= 0;
    snescast_addr_frame_r <= 0;
    snescast_addr_op_r <= 0;
    snescast_wr_r <= 0;
    snescast_data_r <= 0;
    
    snescast_ram[3] <= 0;
    snescast_ram[2] <= 0;
    snescast_ram[1] <= 0;
    snescast_ram[0] <= 0;
    
    snescast_nmi <= 0;
    snescast_ret <= 0;
    
    r420C <= 0;
    for (i = 0; i < HDMA_CHANNELS; i = i + 1) snescast_hdma_state[i] <= HDMA_STATE_IDLE;
    snescast_hdma_read_active <= 0;
    snescast_hdma_read_channel <= 0;
    snescast_hdma_scan_active <= 0;
    
  end

/*
  else begin
    snescast_wr_r <= snescast_wr;
  
    // address calculations
    if (snescast_we) snescast_addr_r <= snescast_addr_r + 1;
    
    if (snescast_wr_r) snescast_addr_op_r <= snescast_addr_op_r + 2;
    else if (snescast_wr && !snescast_wr_multibyte) snescast_addr_op_r <= snescast_addr_op_r + 1;

    // NMIs are always multibyte
    if (IS_NMI_START) begin
      snescast_nmi <= 1;
      snescast_addr_frame_r <= snescast_addr_r;
      snescast_ret <= {snescast_ram[3],snescast_ram[2],snescast_ram[1]};
    end
    else if (IS_NMI_END) begin
      snescast_nmi <= 0;
    end
    
    // data
    if (snescast_wr) begin
      snescast_data_r <= IS_NMI_START ? 8'h00
                       : IS_NMI_END   ? 8'h01
                       :                SNES_DATA;
    end
    
    // nmi end
    if (SNES_WR_end) begin
      snescast_ram[3] <= snescast_ram[2];
      snescast_ram[2] <= snescast_ram[1];
      snescast_ram[1] <= snescast_ram[0];
      snescast_ram[0] <= SNES_DATA;
    end

    // HDMA

    // scan for active channel
//    if (snescast_hdma_scan_active) begin
//      if (r420C[ch] && ((~r43xx[8'h0][ch][6] || (snescast_hdma_state[ch] != HDMA_STATE_WRITE_DATA)) ? (SNES_ADDR == {r43xx[4][ch],r43xx[9][ch],r43xx[8][ch]}) : (SNES_ADDR == {r43xx[7][ch],r43xx[6][ch],r43xx[5][ch]}))) begin
//         snescast_hdma_read_active <= 1;
//         snescast_hdma_scan_active <= 0;
//      end
//      else begin
//        snescast_hdma_read_channel <= snescast_hdma_read_channel + 1;
//      
//        if (&ch) begin
//          snescast_hdma_scan_active <= 0;
//        end
//      end
//    end
//    else if (SNES_RD_start) begin
//      snescast_hdma_scan_active <= 1;
//    end
    if (SNES_RD_start) begin
      snescast_hdma_found = 0;
      for (i = 0; i < HDMA_CHANNELS; i = i + 1) begin
        if (!snescast_hdma_found && r420C[i] && ((!r43xx[8'h0][i][6] || !snescast_hdma_state[i][2]) ? (SNES_ADDR == {r43xx[4][i],r43xx[9][i],r43xx[8][i]}) : (SNES_ADDR == {r43xx[7][i],r43xx[6][i],r43xx[5][i]}))) begin
          snescast_hdma_found = 1;
          snescast_hdma_read_active <= 1;
          snescast_hdma_read_channel <= i;
        end
      end
    end
    else if (SNES_RD_end) begin
      snescast_hdma_read_active <= 0;
    end
    
    if (IS_CPUDMA_WRITE) begin
      r43xx[SNES_ADDR[3:0]][SNES_ADDR[6:4]] <= SNES_DATA;
    end
    else if (IS_NMI_START) begin
      for (i = 0; i < HDMA_CHANNELS; i = i + 1) begin
        // all active HDMA stopped at VBLANK
        snescast_hdma_state[i] <= HDMA_STATE_IDLE;
      end
      // FIXME: disable HDMA.  Technically, I don't think these are cleared but it looks like some games will set them up again
      r420C <= 0;
    end
    else if (IS_CPUREG_WRITE && SNES_ADDR[3:0] == 8'hC) begin
      r420C <= SNES_DATA;
      
      for (i = 0; i < HDMA_CHANNELS; i = i + 1) begin
        if (SNES_DATA[i]) begin
          {r43xx[8'h9][i],r43xx[8'h8][i]} <= {r43xx[8'h3][i],r43xx[8'h2][i]};
          
          snescast_hdma_state[ch] <= HDMA_STATE_READ_LC;
        end
      end
    end
    else begin
      if (snescast_hdma_read_active) begin
        if (SNES_RD_end) begin
          //if (snescast_hdma_state[ch] == HDMA_STATE_IDLE) begin
          //  {r43xx[8'h9][ch],r43xx[8'h8][ch]} <= {r43xx[8'h3][ch],r43xx[8'h2][ch]};
          //end
          if (r43xx[8'h0][ch][6] && snescast_hdma_state[ch][2]) begin
            {r43xx[8'h6][ch],r43xx[8'h5][ch]} <= {r43xx[8'h6][ch],r43xx[8'h5][ch]} + 1;
          end
          else begin
            {r43xx[8'h9][ch],r43xx[8'h8][ch]} <= {r43xx[8'h9][ch],r43xx[8'h8][ch]} + 1;
          end
        
          case (snescast_hdma_state[ch])
          HDMA_STATE_IDLE: begin
          //  snescast_hdma_state[ch] <= HDMA_STATE_READ_LC;
          //  snescast_hdma_state_count[ch] <= 0;
          end
          HDMA_STATE_READ_LC: begin
            // record LC
            r43xx[8'hA][ch] <= SNES_DATA - 1;

            // state transition
            // $00 terminates immediately
            if (~|SNES_DATA)                  snescast_hdma_state[ch] <= HDMA_STATE_IDLE;
            // direct mode
            if (~r43xx[8'h0][ch][6])          snescast_hdma_state[ch] <= HDMA_STATE_WRITE_DATA0;
            // indirect mode
            else                              snescast_hdma_state[ch] <= HDMA_STATE_READ_INDIRECT0;
          end
          HDMA_STATE_READ_INDIRECT0: begin
            // record IA0
            r43xx[8'h5][ch] <= SNES_DATA;
            
            snescast_hdma_state[ch] <= HDMA_STATE_READ_INDIRECT1;
          end
          HDMA_STATE_READ_INDIRECT1: begin
            // record IA1
            r43xx[8'h6][ch] <= SNES_DATA;
            
            snescast_hdma_state[ch] <= HDMA_STATE_WRITE_DATA0;
          end
          HDMA_STATE_WRITE_DATA0: begin
            // state transition
            // 1-7
            if (|r43xx[8'h0][ch][2:0])                             snescast_hdma_state[ch] <= HDMA_STATE_WRITE_DATA1;
            else if (r43xx[8'hA][ch][7] & (|r43xx[8'hA][ch][6:0])) begin r43xx[8'hA][ch] <= r43xx[8'hA][ch] - 1; snescast_hdma_state[ch] <= HDMA_STATE_WRITE_DATA0; end
            else                                                   snescast_hdma_state[ch] <= HDMA_STATE_READ_LC;
          end
          HDMA_STATE_WRITE_DATA1: begin
            if (r43xx[8'h9][2][ch] | ~(r43xx[8'h9][ch][2] ^ r43xx[8'h9][ch][0])) snescast_hdma_state[ch] <= HDMA_STATE_WRITE_DATA2;
            else if (r43xx[8'hA][ch][7] & (|r43xx[8'hA][ch][6:0]))               begin r43xx[8'hA][ch] <= r43xx[8'hA][ch] - 1; snescast_hdma_state[ch] <= HDMA_STATE_WRITE_DATA0; end
            else                                                                 snescast_hdma_state[ch] <= HDMA_STATE_READ_LC;
          end
          HDMA_STATE_WRITE_DATA2: begin
            snescast_hdma_state[ch] <= HDMA_STATE_WRITE_DATA3;
          end
          HDMA_STATE_WRITE_DATA3: begin
            if (r43xx[8'hA][ch][7] & (|r43xx[8'hA][ch][6:0])) begin r43xx[8'hA][ch] <= r43xx[8'hA][ch] - 1; snescast_hdma_state[ch] <= HDMA_STATE_WRITE_DATA0; end
            else                                              snescast_hdma_state[ch] <= HDMA_STATE_READ_LC;
          end
          endcase

//          HDMA_STATE_WRITE_DATA2: begin
//            // 3(1),4(2),5(0),7(1)
//            if (snescast_read_match[i] && SNES_PAWR_end && (SNES_PA == r43xx[i][8'h1] + {~r43xx[i][8'h0][0],r43xx[i][8'h0][1]})) begin
//              // increment table counter
//              if (~r43xx[i][8'h0][6]) {r43xx[i][8'h9],r43xx[i][8'h8]} <= {r43xx[i][8'h9],r43xx[i][8'h8]} + 1;
//              else                    {r43xx[i][8'h6],r43xx[i][8'h5]} <= {r43xx[i][8'h6],r43xx[i][8'h5]} + 1;
//
//              // state transition
//              snescast_hdma_state[i] <= HDMA_STATE_WRITE_DATA3;
//            end
//          end
//          HDMA_STATE_WRITE_DATA3: begin
//            // 3(1),4(3),5(1),7(1)
//            if (snescast_read_match[i] && SNES_PAWR_end && (SNES_PA == r43xx[i][8'h1] + (r43xx[i][8'h0][0] ? 1 : 3))) begin
//              // increment table counter
//              if (~r43xx[i][8'h0][6]) {r43xx[i][8'h9],r43xx[i][8'h8]} <= {r43xx[i][8'h9],r43xx[i][8'h8]} + 1;
//              else                    {r43xx[i][8'h6],r43xx[i][8'h5]} <= {r43xx[i][8'h6],r43xx[i][8'h5]} + 1;
//
//              // state transition
//              if (r43xx[i][8'hA][7] & (|r43xx[i][8'hA][6:0])) begin r43xx[i][8'hA] <= r43xx[i][8'hA] - 1; snescast_hdma_state[i] <= HDMA_STATE_WRITE_DATA0; end
//              else                                                              snescast_hdma_state[i] <= HDMA_STATE_READ_LC;
//            end
//          end
        end
      end
    end
  end
*/
end

assign msu_data_out = msu_data;
assign msu_scaddr_out = {2'b0,snescast_addr_frame_r,2'b0,snescast_addr_op_r};
assign OE_RD_ENABLE = snescast_hdma_read_active;

assign DBG = snescast_hdma_read_active;

endmodule
