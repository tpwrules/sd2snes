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
  input [14:0] pgm_address,
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
  input [14:0] msu_address_ext,
  input msu_address_ext_write,

  input feature_enable,
  input SNES_RD_end,
  input SNES_WR_end,
  input SNES_PARD_end,
  input SNES_PAWR_end,
  input [23:0] SNES_ADDR,
  input [7:0] SNES_PA,
  input [7:0] SNES_DATA,
  output [7:0] msu_data_out,
  output [31:0] msu_scaddr_out,

  output DBG_msu_reg_oe_rising,
  output DBG_msu_reg_oe_falling,
  output DBG_msu_reg_we_rising,
  output [14:0] DBG_msu_address,
  output DBG_msu_address_ext_write_rising,

  input SNES_SNOOPRD_end,
  output OE_RD_ENABLE,

  // trace
  input SNES_RD,
  input SNES_WR,
  input SNES_PARD,
  input SNES_PAWR,
  input SNES_ROMSEL,

  input SNES_RD_start,
  input SNES_WR_start,
  input SNES_PARD_start,
  input SNES_PAWR_start,  
  
  // config interface
  input [7:0] reg_group_in,
  input [7:0] reg_index_in,
  input [7:0] reg_value_in,
  input [7:0] reg_invmask_in,
  input       reg_we_in,
  input [7:0] reg_read_in,
  output[7:0] trc_config_data_out,
  
  output DBG
);

integer i;

// flopped inputs
reg [23:0] SNES_ADDR_r;
always @(posedge clkin) SNES_ADDR_r <= SNES_ADDR;
reg [7:0] SNES_PA_r;
always @(posedge clkin) SNES_PA_r <= SNES_PA;
reg [7:0] SNES_DATA_r;
always @(posedge clkin) SNES_DATA_r <= SNES_DATA;

// Buffer writes
wire buf_we;
wire [7:0] buf_data;
wire [14:0] buf_addr;

// TRACE
reg trace_we;
reg [7:0] trace_data;
reg [14:0] trace_addr;

// SNESCAST
reg snescast_we;
reg [7:0] snescast_data;
reg [14:0] snescast_addr;
// TODO implement DMA compression
reg snescast_wr_multibyte;

reg [1:0] status_reset_we_r;
always @(posedge clkin) status_reset_we_r = {status_reset_we_r[0], status_reset_we};
wire status_reset_en = (status_reset_we_r == 2'b01);

reg [14:0] msu_address_r;
wire [14:0] msu_address = msu_address_r;
initial msu_address_r = 14'b0;

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
  .wea(feature_enable ? ~pgm_we : buf_we), // Bus [0 : 0]
  .addra(feature_enable ? pgm_address : buf_addr), // Bus [14 : 0]
  .dina(feature_enable ? pgm_data : buf_data), // Bus [7 : 0]
  .clkb(clkin),
  .addrb(feature_enable ? msu_address : pgm_address), // Bus [14 : 0]
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

//---------------------------
// WRAM
//---------------------------

// configuration state
reg [7:0] mode_r; initial mode_r = 0;
reg [7:0] cap_r[15:0]; initial for (i = 0; i < 16; i = i + 1) cap_r[i] = 0;

// cap_r == 0 : WRAM SNOOP
// cap_r == 1 : TRACE
// cap_r == 2 : WRAM TRACE
// cap_r == 3 : SNES CAST

always @(posedge clkin) begin
  if (reg_we_in && (reg_group_in == 8'h02)) begin
    if (reg_index_in == 16) mode_r <= (mode_r & reg_invmask_in) | (reg_value_in & ~reg_invmask_in);
    else cap_r[reg_index_in] <= (cap_r[reg_index_in] & reg_invmask_in) | (reg_value_in & ~reg_invmask_in);
  end
end

reg IS_WRAM_SHADOW_ADDR_r; initial IS_WRAM_SHADOW_ADDR_r = 0;
reg IS_WRAM_BANK_ADDR_r; initial IS_WRAM_BANK_ADDR_r = 0;
reg IS_WRAM_PA_ADDR_r; initial IS_WRAM_PA_ADDR_r = 0;
assign IS_WRAM_SHADOW_ADDR = !SNES_ADDR[22] && (SNES_ADDR[15:13] == 3'h0);
always @(posedge clkin) IS_WRAM_SHADOW_ADDR_r <= IS_WRAM_SHADOW_ADDR;
assign IS_WRAM_SHADOW = SNES_WR_end && IS_WRAM_SHADOW_ADDR_r;
assign IS_WRAM_BANK_ADDR = ({SNES_ADDR[23:17],1'b0} == 8'h7E);
always @(posedge clkin) IS_WRAM_BANK_ADDR_r <= IS_WRAM_BANK_ADDR;
assign IS_WRAM_BANK = SNES_WR_end && IS_WRAM_BANK_ADDR_r;
assign IS_WRAM_PA_ADDR = (SNES_PA == 8'h80);
always @(posedge clkin) IS_WRAM_PA_ADDR_r <= IS_WRAM_PA_ADDR;
assign IS_WRAM_PA = SNES_PAWR_end && IS_WRAM_PA_ADDR_r;

assign IS_WRAM_ADDR = IS_WRAM_SHADOW_ADDR_r | IS_WRAM_BANK_ADDR_r | IS_WRAM_PA_ADDR_r;
assign IS_WRAM = IS_WRAM_SHADOW | IS_WRAM_BANK | IS_WRAM_PA;

reg [23:0] WRAM_ADDR; initial WRAM_ADDR = 0;

wire [16:0] WRAM_OFFSET = ( IS_WRAM_SHADOW_ADDR ? {4'b0000,SNES_ADDR[12:0]}
								          : IS_WRAM_BANK_ADDR   ? SNES_ADDR[16:0]
									 			  :                       WRAM_ADDR[16:0]);
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
      if      (SNES_PA == 8'h81) WRAM_ADDR[ 7: 0] <= SNES_DATA_r;
      else if (SNES_PA == 8'h82) WRAM_ADDR[15: 8] <= SNES_DATA_r;
      else if (SNES_PA == 8'h83) WRAM_ADDR[23:16] <= SNES_DATA_r;
    end
  end
end

//---------------------------
// WRAM SNOOP
//---------------------------
reg wram_we_r; initial wram_we_r = 0;
reg [7:0] wram_data_r;
reg [14:0] wram_addr_r;

wire wram_we;
wire [7:0] wram_data;
wire [14:0] wram_addr;

assign wram_we = wram_we_r;
assign wram_data = wram_data_r;
assign wram_addr = wram_addr_r;

// for now, just capture the low order addresses.  programmability would require a SW (game reset) or HW coherence mechanism
always @(posedge clkin) begin
  wram_we_r   <= IS_WRAM && (WRAM_OFFSET < 17'h7800);
  wram_addr_r <= WRAM_OFFSET[14:0];
  wram_data_r <= SNES_DATA_r;
end

//---------------------------
// WRAM TRACE
//---------------------------

// compare the address against all of the configuration registers and flop matches
reg cap_enable_r;
reg [7:0] cap_match_r;
always @(posedge clkin) begin
  cap_enable_r <= |(cap_r[{0,1'b1}][7:5] | cap_r[{1,1'b1}][7:5] | cap_r[{2,1'b1}][7:5] | cap_r[{3,1'b1}][7:5] | cap_r[{4,1'b1}][7:5] | cap_r[{5,1'b1}][7:5] | cap_r[{6,1'b1}][7:5] | cap_r[{7,1'b1}][7:5]);

  for (i = 0; i < 8; i = i + 1) begin
    cap_match_r[i] <= ({4'b0000, cap_r[{i,1'b1}][4:0], cap_r[{i,1'b0}][7:0]} <= WRAM_OFFSET[16:0]) && (WRAM_OFFSET[16:0] < {4'b0000, cap_r[{i,1'b1}][4:0], cap_r[{i,1'b0}][7:0]}+cap_r[{i,1'b1}][7:5]);
  end
end

// priority decode for match
reg       cap_match_hit_r;
reg [2:0] cap_match_index_r;
reg [1:0] cap_match_offset_r;
always @(posedge clkin) begin
  cap_match_hit_r <= (|cap_match_r) && IS_WRAM_ADDR;

  for (i = 0; i < 8; i = i + 1) begin
    if (cap_match_r[i]) begin
      cap_match_index_r <= i;
      cap_match_offset_r <= WRAM_OFFSET[16:0] - {4'b0000, cap_r[{i,1'b1}][4:0], cap_r[{i,1'b0}][7:0]};
    end
  end
end

assign IS_CAP = ~mode_r[0] && IS_WRAM && cap_match_hit_r;

//---------------------------
// TRACE
//---------------------------
parameter TRACE_RECORD_SIZE = 6;

parameter TRACE_STATE_IDLE   = 2'b00;
parameter TRACE_STATE_ACTIVE = 2'b01;
parameter TRACE_STATE_DONE   = 2'b10;

// configuration state
reg [7:0] trc_r[15:0]; initial for (i = 0; i < 16; i = i + 1) trc_r[i] = 0;

// breakout registers
// reg0
wire trace_reg_control_enable = trc_r[0][0];
wire trace_reg_control_cpustate = trc_r[0][1];
wire trace_reg_control_multishot = trc_r[0][2];
// reg1
wire trace_reg_trigger_start_match0 = trc_r[1][0];
wire trace_reg_trigger_start_match1 = trc_r[1][1];
wire trace_reg_trigger_stop_match0  = trc_r[1][4];
wire trace_reg_trigger_stop_match1  = trc_r[1][5];
wire trace_reg_trigger_stop_full    = trc_r[1][6];
// match0
wire [23:0] trace_reg_match0_addr = {trc_r[4],trc_r[3],trc_r[2]};
wire [7:0]  trace_reg_match0_pa = trc_r[5];
wire [7:0]  trace_reg_match0_data = trc_r[6];
wire        trace_reg_match0_control_rd = trc_r[7][0];
wire        trace_reg_match0_control_wr = trc_r[7][1];
wire        trace_reg_match0_control_pard = trc_r[7][2];
wire        trace_reg_match0_control_pawr = trc_r[7][3];
wire        trace_reg_match0_control_data = trc_r[7][4];
// match1
wire [23:0] trace_reg_match1_addr = {trc_r[10],trc_r[9],trc_r[8]};
wire [7:0]  trace_reg_match1_pa = trc_r[11];
wire [7:0]  trace_reg_match1_data = trc_r[12];
wire        trace_reg_match1_control_rd = trc_r[13][0];
wire        trace_reg_match1_control_wr = trc_r[13][1];
wire        trace_reg_match1_control_pard = trc_r[13][2];
wire        trace_reg_match1_control_pawr = trc_r[13][3];
wire        trace_reg_match1_control_data = trc_r[13][4];

wire trace_start_now = ~|(trc_r[1][3:0]);

reg [1:0] trace_active;
reg [7:0] trace_record[TRACE_RECORD_SIZE:1];
reg [3:0] trace_counter;
reg [14:0] trace_write_addr;
reg [3:0] trace_mask;
reg [7:0] trace_control;

assign trace_addr_last_byte = trace_write_addr == 15'h77FF;

reg trace_buffer_full_r;
reg trace_stop_hit_r;

reg trace_match0_addr_hit_r;
reg trace_match0_pa_hit_r;
reg trace_match0_data_hit_r;
reg trace_match1_addr_hit_r;
reg trace_match1_pa_hit_r;
reg trace_match1_data_hit_r;

// trace trigger matches
assign trace_match0_hit = (~(trace_reg_match0_control_rd | trace_reg_match0_control_wr) | trace_match0_addr_hit_r)
                        & (~(trace_reg_match0_control_pard | trace_reg_match0_control_pawr) | trace_match0_pa_hit_r)
                        & (~(trace_reg_match0_control_data) | trace_match0_data_hit_r)
                        & (&({~trace_reg_match0_control_pawr,~trace_reg_match0_control_pard,~trace_reg_match0_control_wr,~trace_reg_match0_control_rd} | trace_mask))
                        ;
assign trace_match1_hit = (~(trace_reg_match1_control_rd | trace_reg_match1_control_wr) | trace_match1_addr_hit_r)
                        & (~(trace_reg_match1_control_pard | trace_reg_match1_control_pawr) | trace_match1_pa_hit_r)
                        & (~(trace_reg_match1_control_data) | trace_match1_data_hit_r)
                        & (&({~trace_reg_match1_control_pawr,~trace_reg_match1_control_pard,~trace_reg_match1_control_wr,~trace_reg_match1_control_rd} | trace_mask))
                        ;
reg trace_match0_hit_r;
reg trace_match1_hit_r;

always @(posedge clkin) begin
  trace_match0_hit_r <= trace_match0_hit;
  trace_match1_hit_r <= trace_match1_hit;
end
                        
assign trace_start_hit = trace_start_now
                       | ( (trace_reg_trigger_start_match0 & trace_match0_hit_r)
                         | (trace_reg_trigger_start_match1 & trace_match1_hit_r)
                         );
assign trace_stop_hit = ( (trace_reg_trigger_stop_match0 & trace_match0_hit_r)
                        | (trace_reg_trigger_stop_match1 & trace_match1_hit_r)
                        | (trace_reg_trigger_stop_full & trace_buffer_full_r)
                        );

// temporary enable based on filling buffer
assign trace_we_in = (mode_r == 1) && (trace_active == TRACE_STATE_ACTIVE) && (|trace_counter) && (!trace_reg_trigger_stop_full || !trace_buffer_full_r);
wire nmi_active;

// buffer inputs
always @(posedge clkin) begin
  trace_we <= trace_we_in;
  trace_data <= trace_record[trace_counter];
  trace_addr <= trace_write_addr;
end

// register interface
always @(posedge clkin) begin
  if (reg_we_in && (reg_group_in == 8'h01)) trc_r[reg_index_in] <= (trc_r[reg_index_in] & reg_invmask_in) | (reg_value_in & ~reg_invmask_in);
end

assign trc_config_data_out = reg_read_in == 0 ? {2'h0, trace_buffer_full_r, trace_start_hit, trace_stop_hit_r, trace_stop_hit, trace_active} : trc_r[reg_read_in];

// level shifter enables.
// FIXME: make sure we only record one transaction even if multiple signals are asserted.  Should just be a matter of covering a long enough window
// FIXME: we are using the context engine to enable everything else which is limited to only certain bus events.
// Ideally we would always enable the level shifter and cover everything (always look at the bus) but that may corrupt open bus state so be conservative for now.
//assign IS_WRAM_SHADOW_ADDR = !snes_addr_r[22] && (SNES_ADDR_r[15:13] == 3'h0);
//assign IS_WRAM_BANK_ADDR = ({SNES_ADDR_r[23:17],1'b0} == 8'h7E);
//assign IS_DMA_ADDR = (({1'b0,SNES_ADDR_r[22],6'b000000, SNES_ADDR_r[15:7], 7'b0000000} == 24'h04300)) && (SNES_ADDR_r[3:0] <= 4'hA);
//assign trace_rd_addr = IS_WRAM_SHADOW_ADDR | IS_WRAM_BANK_ADDR | IS_DMA_ADDR;

always @(posedge clkin) begin
  if (mode_r != 1) begin
    trace_counter <= 0;
    trace_write_addr <= 0;
    trace_buffer_full_r <= 0;
    trace_mask <= 0;
    trace_control <= 0;
    trace_active <= TRACE_STATE_IDLE;
    
    trace_stop_hit_r <= 0;

    trace_match0_addr_hit_r <= 0;
    trace_match0_pa_hit_r <= 0;
    trace_match0_data_hit_r <= 0;
    trace_match1_addr_hit_r <= 0;
    trace_match1_pa_hit_r <= 0;
    trace_match1_data_hit_r <= 0;
  end
  else begin
    // Write off captured data.
    if (|trace_counter) begin
      // countdown the writes 
      if (trace_counter == TRACE_RECORD_SIZE) begin
        trace_counter <= 0;
      end
      else begin
        trace_counter <= trace_counter + 1;
      end
      
      // advance trace buffer
      if (trace_addr_last_byte) trace_write_addr <= 0;
      else trace_write_addr <= trace_write_addr + 1;
    end
    // Find first start.  Assume nothing no start occurs after end that isn't a new transaction
    else if (~|trace_mask) begin
      trace_mask <= {SNES_PAWR_start, SNES_PARD_start, SNES_WR_start, SNES_RD_start};
    end
    // Capture at the first end.
    else if ((trace_mask & {SNES_PAWR_end, SNES_PARD_end, SNES_WR_end, SNES_RD_end}) != 0) begin
      // control
      trace_record[1] <= trace_control;
      trace_record[2] <= SNES_DATA;
      {trace_record[5],trace_record[4],trace_record[3]} <= SNES_ADDR_r;
      trace_record[6] <= SNES_PA;
      //trace_record[7] <= 0;
      //trace_record[8] <= 0;
      
      trace_counter <= 1;
      trace_mask <= 0;
      trace_control <= 0;
      
      // go to active on a start trigger.  stop active on a stop trigger.
      if (((trace_active == TRACE_STATE_IDLE) || ((trace_active == TRACE_STATE_DONE) && trace_reg_control_multishot)) && trace_start_hit) begin
        // reset state
        trace_write_addr <= 0;
        trace_buffer_full_r <= 0;
        trace_stop_hit_r <= 0;
        trace_active <= TRACE_STATE_ACTIVE;
      end
      else if (trace_stop_hit_r && (trace_active == TRACE_STATE_ACTIVE)) begin
        trace_active <= TRACE_STATE_DONE;
      end
      else if (trace_stop_hit) begin
        trace_stop_hit_r <= 1;
      end
    end
    // Sample control
    else if (trace_mask) begin
      trace_control <= trace_control | {2'h0, nmi_active, ~SNES_ROMSEL, ~SNES_PAWR, ~SNES_PARD, ~SNES_WR, ~SNES_RD};
    end
    
    trace_buffer_full_r <= trace_buffer_full_r | (trace_addr_last_byte & trace_we_in);

    trace_match0_addr_hit_r <= trace_reg_match0_addr == SNES_ADDR_r;
    trace_match0_pa_hit_r <= trace_reg_match0_pa == SNES_PA;
    trace_match0_data_hit_r <= trace_reg_match0_data == SNES_DATA;
    trace_match1_addr_hit_r <= trace_reg_match1_addr == SNES_ADDR_r;
    trace_match1_pa_hit_r <= trace_reg_match1_pa == SNES_PA;
    trace_match1_data_hit_r <= trace_reg_match1_data == SNES_DATA;
  end
end

//---------------------------
// SNESCAST
//---------------------------
reg [14:0] snescast_addr_r;
reg [14:0] snescast_addr_frame_r;
reg [14:0] snescast_addr_op_r;
reg snescast_wr_r;
reg [7:0] snescast_data_r;

assign snescast_addr_last_byte = snescast_addr_r == 15'h77FF;

reg snescast_nmi;
assign nmi_active = snescast_nmi;
reg [7:0] snescast_ram[3:0];
reg [23:0] snescast_ret;

reg snescast_irq;
assign irq_active = snescast_irq;
reg [23:0] snescast_irq_ret;

// HDMA
parameter HDMA_CHANNELS = 8;

reg [7:0] r43xx[HDMA_CHANNELS-1:0][10:0];
reg [7:0] r43xx_ch[10:0];
reg [7:0] r420C;
reg [2:0] snescast_hdma_state[HDMA_CHANNELS-1:0];
reg [7:0] snescast_hdma_pa[HDMA_CHANNELS-1:0];
reg [2:0] snescast_hdma_mode[HDMA_CHANNELS-1:0];
reg [2:0] snescast_hdma_state_ch;
reg [2:0] snescast_hdma_mode_ch;
reg       snescast_hdma_repeat_ch;
reg       snescast_hdma_indirect_ch;

parameter HDMA_STATE_IDLE           = 0;
parameter HDMA_STATE_READ_LC        = 1;
parameter HDMA_STATE_READ_INDIRECT0 = 2;
parameter HDMA_STATE_READ_INDIRECT1 = 3;
parameter HDMA_STATE_WRITE_DATA0    = 4;
parameter HDMA_STATE_WRITE_DATA1    = 5;
parameter HDMA_STATE_WRITE_DATA2    = 6;
parameter HDMA_STATE_WRITE_DATA3    = 7;

reg snescast_hdma_read_channel_found;
reg [HDMA_CHANNELS-1:0] snescast_hdma_read_active;
reg [HDMA_CHANNELS-1:0] snescast_hdma_pa_match;
reg [HDMA_CHANNELS-1:0] snescast_hdma_direct_addr_match;
reg [HDMA_CHANNELS-1:0] snescast_hdma_indirect_addr_match;
reg [HDMA_CHANNELS-1:0] snescast_hdma_indirect;
reg [2:0] snescast_hdma_read_channel;
reg       snescast_hdma_read_init;
reg       snescast_hdma_write;
reg       snescast_hdma_read_update;
reg       snescast_hdma_read_active2;
reg       snescast_hdma_read_wait;

//reg [7:0] snescast_hdma_table_read_addr; //= (SNES_ADDR_r == {r43xx[4][ch],r43xx[9][ch],r43xx[8][ch]});
//reg [7:0] snescast_hdma_indirect_read_addr; //= (SNES_ADDR_r == {r43xx[7][ch],r43xx[6][ch],r43xx[5][ch]});

//always @* begin
//  for (i = 0; i < HDMA_CHANNELS; i = i + 1) begin
//    snescast_hdma_table_read_addr = (SNES_ADDR_r == {r43xx[4][i],r43xx[9][i],r43xx[8][i]});
//    snescast_hdma_indirect_read_addr = (SNES_ADDR_r == {r43xx[7][i],r43xx[6][i],r43xx[5][i]});
//  end
//end

//wire [7:0] snescast_read_match = ({HDMA_CHANNELS{~r43xx[i][8'h0][6]}} & snescast_hdma_table_read_match) | ({HDMA_CHANNELS{r43xx[i][8'h0][6]}} & snescast_hdma_indirect_read_match);

// identify snooped operations
assign IS_PPUREG_WRITE_ADDR = (SNES_PA <= 8'h33);
assign IS_PPUREG_WRITE = !(snescast_hdma_read_wait) && SNES_PAWR_end && IS_PPUREG_WRITE_ADDR;
assign IS_PPUREG = IS_PPUREG_WRITE; // | IS_PPUREG_READ;

assign IS_CPUREG_WRITE_ADDR = {1'b0,SNES_ADDR_r[22],6'b000000, SNES_ADDR_r[15:4], 4'b0000} == 24'h04200;
reg IS_CPUREG_WRITE_ADDR_r;
always @(posedge clkin) IS_CPUREG_WRITE_ADDR_r <= IS_CPUREG_WRITE_ADDR;
assign IS_CPUREG_WRITE = SNES_WR_end && IS_CPUREG_WRITE_ADDR_r;
assign IS_CPUREG = IS_CPUREG_WRITE;

assign IS_CPUDMA_WRITE_ADDR = {1'b0,SNES_ADDR_r[22],6'b000000, SNES_ADDR_r[15:7], 7'b0000000} == 24'h04300;
reg IS_CPUDMA_WRITE_ADDR_r;
always @(posedge clkin) IS_CPUDMA_WRITE_ADDR_r <= IS_CPUDMA_WRITE_ADDR;
assign IS_CPUDMA_WRITE = SNES_WR_end && IS_CPUDMA_WRITE_ADDR_r;
assign IS_CPUDMA = IS_CPUDMA_WRITE;

assign IS_APU_WRITE_ADDR = {SNES_PA[7:6],6'b000000} == 8'h40;
assign IS_APU_WRITE = SNES_PAWR_end && IS_APU_WRITE_ADDR;
assign IS_APU = IS_APU_WRITE;

assign IS_NMI_START_ADDR = SNES_ADDR_r == 24'h00FFEA;
reg IS_NMI_START_ADDR_r; initial IS_NMI_START_ADDR_r = 0;
always @(posedge clkin) IS_NMI_START_ADDR_r <= IS_NMI_START_ADDR;
assign IS_NMI_START = !snescast_nmi && SNES_RD_end && IS_NMI_START_ADDR_r;
assign IS_NMI_END_ADDR = SNES_ADDR_r == snescast_ret;
reg IS_NMI_END_ADDR_r; initial IS_NMI_END_ADDR_r = 0;
always @(posedge clkin) IS_NMI_END_ADDR_r <= IS_NMI_END_ADDR;
assign IS_NMI_END = snescast_nmi && SNES_RD_end && IS_NMI_END_ADDR_r;
assign IS_NMI = IS_NMI_START | IS_NMI_END;

assign IS_IRQ_START_ADDR = SNES_ADDR_r == 24'h00FFEE;
reg IS_IRQ_START_ADDR_r; initial IS_IRQ_START_ADDR_r = 0;
always @(posedge clkin) IS_IRQ_START_ADDR_r <= IS_IRQ_START_ADDR;
assign IS_IRQ_START = !snescast_irq && SNES_RD_end && IS_IRQ_START_ADDR_r;
assign IS_IRQ_END_ADDR = SNES_ADDR_r == snescast_irq_ret;
reg IS_IRQ_END_ADDR_r; initial IS_IRQ_END_ADDR_r = 0;
always @(posedge clkin) IS_IRQ_END_ADDR_r <= IS_IRQ_END_ADDR;
assign IS_IRQ_END = snescast_irq && SNES_RD_end && IS_IRQ_END_ADDR_r;
assign IS_IRQ = IS_IRQ_START | IS_IRQ_END;

assign IS_SPECIAL = IS_NMI | IS_IRQ;

assign IS_HDMA_READ_ADDR = (snescast_hdma_read_wait) && (~snescast_hdma_state_ch[2]);
assign IS_HDMA_WRITE_ADDR = (snescast_hdma_read_wait) && (snescast_hdma_state_ch[2]);
assign IS_HDMA_READ = SNES_SNOOPRD_end && IS_HDMA_READ_ADDR;
assign IS_HDMA_WRITE = SNES_SNOOPRD_end && IS_HDMA_WRITE_ADDR;
assign IS_HDMA = IS_HDMA_READ | IS_HDMA_WRITE;

assign snescast_wr = (~cap_enable_r ? (IS_PPUREG | IS_CPUREG | IS_CPUDMA | IS_APU | IS_HDMA) : IS_CAP) | IS_SPECIAL;
assign snescast_we_in = snescast_wr | snescast_wr_r;

always @(posedge clkin) begin
  if (reset) begin
    snescast_we <= 0;
  end
  else begin
    snescast_we <= snescast_we_in;
    snescast_addr <= snescast_addr_r;
    snescast_data <= snescast_wr_r ? snescast_data_r
                   : IS_CAP        ? {4'h8|cap_match_index_r,2'b00,cap_match_offset_r}
                   : IS_HDMA_READ  ? {4'h8|snescast_hdma_read_channel,4'hB}
                   : IS_HDMA_WRITE ? {4'h8|snescast_hdma_read_channel,4'hC}
                   : IS_SPECIAL    ? 8'hFF
                   : IS_PPUREG     ? SNES_PA
                   : IS_CPUREG     ? 8'h70 | SNES_ADDR_r[3:0]
                   : IS_CPUDMA     ? 8'h80 | SNES_ADDR_r[6:0]
                   : IS_APU        ? {SNES_PA[7:6],4'h0,SNES_PA[1:0]}
                   :                 8'hFF;
  end
end

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
    
    snescast_irq <= 0;
    snescast_irq_ret <= 0;
    
    r420C <= 0;
    for (i = 0; i < HDMA_CHANNELS; i = i + 1) snescast_hdma_state[i] <= HDMA_STATE_IDLE;
    snescast_hdma_read_active <= 0;
    snescast_hdma_read_channel <= 0;
    snescast_hdma_read_wait <= 0;
    snescast_hdma_read_update <= 0;
    snescast_hdma_write <= 0;
    
    snescast_wr_multibyte <= 1;
  end

  else begin
    snescast_wr_r <= snescast_wr;
  
    // address calculations
    if (snescast_we_in) begin
      if (snescast_addr_last_byte) snescast_addr_r <= 0;
      else snescast_addr_r <= snescast_addr_r + 1;
      
      // FIXME this will break when not a multiple of 2
      // if not multibyte then we always advance op pointer else only on second write
      if (!snescast_wr_multibyte || snescast_wr_r) begin
        if (snescast_addr_last_byte) snescast_addr_op_r <= 0;
        else snescast_addr_op_r <= snescast_addr_r + 1;
      end
    end

    // NMIs are always multibyte
    if (IS_NMI_START) begin
      snescast_nmi <= 1;
      snescast_addr_frame_r <= snescast_addr_r;
      snescast_ret <= {snescast_ram[3],snescast_ram[2],snescast_ram[1]};
    end
    else if (IS_NMI_END) begin
      snescast_nmi <= 0;
    end

    if (IS_IRQ_START) begin
      snescast_irq <= 1;
      snescast_irq_ret <= {snescast_ram[3],snescast_ram[2],snescast_ram[1]};
    end
    else if (IS_IRQ_END) begin
      snescast_irq <= 0;
    end
    
    // data
    if (snescast_wr) begin
      snescast_data_r <= IS_NMI_START ? 8'h00
                       : IS_NMI_END   ? 8'h01
                       : IS_IRQ_START ? 8'h02
                       : IS_IRQ_END   ? 8'h03
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
//      if (r420C[ch] && ((~r43xx[8'h0][ch][6] || (snescast_hdma_state[ch] != HDMA_STATE_WRITE_DATA)) ? (SNES_ADDR_r == {r43xx[4][ch],r43xx[9][ch],r43xx[8][ch]}) : (SNES_ADDR_r == {r43xx[7][ch],r43xx[6][ch],r43xx[5][ch]}))) begin
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

    for (i = 0; i < HDMA_CHANNELS; i = i + 1) begin
      // check both SNES_ADDR and SNES_PA for a match.  Note that if two HDMAs use the same source and destination field this will still fail to order things properly.
      snescast_hdma_mode[i] <= r43xx[i][8'h0][2:0];
      snescast_hdma_pa[i] <= r43xx[i][1] + ((snescast_hdma_mode[i][2:0] == 4) ? snescast_hdma_state[i][1:0] : (snescast_hdma_mode[i][1:0] == 2'b01) ? snescast_hdma_state[i][0] : (snescast_hdma_mode[i][1:0] == 2'b11) ? snescast_hdma_state[i][1] : 0);
      snescast_hdma_pa_match[i] <= SNES_PA_r == snescast_hdma_pa[i];
      snescast_hdma_direct_addr_match[i] <= SNES_ADDR_r == {r43xx[i][4],r43xx[i][9],r43xx[i][8]};
      snescast_hdma_indirect_addr_match[i] <= SNES_ADDR_r == {r43xx[i][7],r43xx[i][6],r43xx[i][5]};
      snescast_hdma_indirect[i] <= r43xx[i][8'h0][6];
    end

    snescast_hdma_mode_ch <= r43xx_ch[8'h0][2:0];
    snescast_hdma_repeat_ch <= r43xx_ch[8'hA][7] & (|r43xx_ch[8'hA][6:1]);
    snescast_hdma_indirect_ch <= r43xx_ch[8'h0][6];

    if (SNES_RD_start) begin
      for (i = 0; i < HDMA_CHANNELS; i = i + 1) begin
        //snescast_hdma_read_active[i] <= r420C[i] && ((!snescast_hdma_indirect[i] || !snescast_hdma_state[i][2]) ? snescast_hdma_direct_addr_match[i] : snescast_hdma_indirect_addr_match[i]);
        snescast_hdma_read_active[i] <= r420C[i] & ((~snescast_hdma_state[i][2] & snescast_hdma_direct_addr_match[i]) | (snescast_hdma_state[i][2] & ~snescast_hdma_indirect[i] & snescast_hdma_pa_match[i] & snescast_hdma_direct_addr_match[i]) | (snescast_hdma_state[i][2] & snescast_hdma_indirect[i] & snescast_hdma_pa_match[i] & snescast_hdma_indirect_addr_match[i]));
      end
    end
    else if (|snescast_hdma_read_active) begin
      if      (snescast_hdma_read_active[0]) snescast_hdma_read_channel <= 0;
      else if (snescast_hdma_read_active[1]) snescast_hdma_read_channel <= 1;
      else if (snescast_hdma_read_active[2]) snescast_hdma_read_channel <= 2;
      else if (snescast_hdma_read_active[3]) snescast_hdma_read_channel <= 3;
      else if (snescast_hdma_read_active[4]) snescast_hdma_read_channel <= 4;
      else if (snescast_hdma_read_active[5]) snescast_hdma_read_channel <= 5;
      else if (snescast_hdma_read_active[6]) snescast_hdma_read_channel <= 6;
      else if (snescast_hdma_read_active[7]) snescast_hdma_read_channel <= 7;
      
      snescast_hdma_read_active <= 0;
      snescast_hdma_read_active2 <= 1;
    end
    else if (snescast_hdma_read_active2) begin
      snescast_hdma_state_ch <= snescast_hdma_state[snescast_hdma_read_channel]; //for (i = 0; i < 16; i = i + 1) r43xx_ch[i] <= r43xx[snescast_hdma_read_channel][i];
      r43xx_ch[8'h0] <= r43xx[snescast_hdma_read_channel][8'h0];
      r43xx_ch[8'h5] <= r43xx[snescast_hdma_read_channel][8'h5];
      r43xx_ch[8'h6] <= r43xx[snescast_hdma_read_channel][8'h6];
      r43xx_ch[8'h8] <= r43xx[snescast_hdma_read_channel][8'h8];
      r43xx_ch[8'h9] <= r43xx[snescast_hdma_read_channel][8'h9];
      r43xx_ch[8'hA] <= r43xx[snescast_hdma_read_channel][8'hA];
      
      snescast_hdma_read_active2 <= 0;
      snescast_hdma_read_wait <= 1;
    end
    else if (snescast_hdma_read_wait) begin
      if (SNES_SNOOPRD_end) begin
        snescast_hdma_read_wait <= 0;
        
        //if (snescast_hdma_state[ch] == HDMA_STATE_IDLE) begin
        //  {r43xx_ch[8'h9],r43xx_ch[8'h8]} <= {r43xx_ch[8'h3],r43xx_ch[8'h2]};
        //end
        if (snescast_hdma_indirect_ch && snescast_hdma_state_ch[2]) begin
          {r43xx_ch[8'h6],r43xx_ch[8'h5]} <= {r43xx_ch[8'h6],r43xx_ch[8'h5]} + 1;
        end
        else begin
          {r43xx_ch[8'h9],r43xx_ch[8'h8]} <= {r43xx_ch[8'h9],r43xx_ch[8'h8]} + 1;
        end
       
        case (snescast_hdma_state_ch)
          HDMA_STATE_IDLE: begin
          //  snescast_hdma_state[ch] <= HDMA_STATE_READ_LC;
          //  snescast_hdma_state_count[ch] <= 0;
          end
          HDMA_STATE_READ_LC: begin
            // record LC
            r43xx_ch[8'hA] <= SNES_DATA;

            // state transition
            // $00 terminates immediately
            if (~|SNES_DATA)                     snescast_hdma_state_ch <= HDMA_STATE_IDLE;
            // direct mode
            else if (~snescast_hdma_indirect_ch) snescast_hdma_state_ch <= HDMA_STATE_WRITE_DATA0;
            // indirect mode
            else                                 snescast_hdma_state_ch <= HDMA_STATE_READ_INDIRECT0;
          end
          HDMA_STATE_READ_INDIRECT0: begin
            // record IA0
            r43xx_ch[8'h5] <= SNES_DATA;
            
            snescast_hdma_state_ch <= HDMA_STATE_READ_INDIRECT1;
          end
          HDMA_STATE_READ_INDIRECT1: begin
            // record IA1
            r43xx_ch[8'h6] <= SNES_DATA;
            
            snescast_hdma_state_ch <= HDMA_STATE_WRITE_DATA0;
          end
          HDMA_STATE_WRITE_DATA0: begin
            // state transition
            // 1-7
            if (|snescast_hdma_mode_ch)             snescast_hdma_state_ch <= HDMA_STATE_WRITE_DATA1;
            else if (snescast_hdma_repeat_ch) begin r43xx_ch[8'hA] <= r43xx_ch[8'hA] - 1; snescast_hdma_state_ch <= HDMA_STATE_WRITE_DATA0; end
            else                                    snescast_hdma_state_ch <= HDMA_STATE_READ_LC;
          end
          HDMA_STATE_WRITE_DATA1: begin
            if ((snescast_hdma_mode_ch[2] & ~snescast_hdma_mode_ch[1]) | (snescast_hdma_mode_ch[1] & snescast_hdma_mode_ch[0]))    snescast_hdma_state_ch <= HDMA_STATE_WRITE_DATA2;
            else if (snescast_hdma_repeat_ch)                 begin r43xx_ch[8'hA]    <= r43xx_ch[8'hA] - 1; snescast_hdma_state_ch <= HDMA_STATE_WRITE_DATA0; end
            else                                                    snescast_hdma_state_ch <= HDMA_STATE_READ_LC;
          end
          HDMA_STATE_WRITE_DATA2: begin
            snescast_hdma_state_ch <= HDMA_STATE_WRITE_DATA3;
          end
          HDMA_STATE_WRITE_DATA3: begin
            if (snescast_hdma_repeat_ch) begin r43xx_ch[8'hA] <= r43xx_ch[8'hA] - 1; snescast_hdma_state_ch <= HDMA_STATE_WRITE_DATA0; end
            else                               snescast_hdma_state_ch <= HDMA_STATE_READ_LC;
          end
        endcase
      end
    end

    if (IS_CPUDMA_WRITE) begin
      snescast_hdma_write <= 1;
    end
    else if (IS_CPUREG_WRITE && SNES_ADDR_r[3:0] == 8'hC) begin
      r420C <= SNES_DATA;
      snescast_hdma_read_init <= 1;
    end
 
    if (snescast_hdma_read_update) begin
      // write new data
      snescast_hdma_state[snescast_hdma_read_channel] <= snescast_hdma_state_ch;
      r43xx[snescast_hdma_read_channel][8'h5] <= r43xx_ch[8'h5];
      r43xx[snescast_hdma_read_channel][8'h6] <= r43xx_ch[8'h6];
      r43xx[snescast_hdma_read_channel][8'h8] <= r43xx_ch[8'h8];
      r43xx[snescast_hdma_read_channel][8'h9] <= r43xx_ch[8'h9];
      r43xx[snescast_hdma_read_channel][8'hA] <= r43xx_ch[8'hA];
      
      snescast_hdma_read_update <= 0;        
    end
    else if (snescast_hdma_write) begin
      r43xx[SNES_ADDR_r[6:4]][SNES_ADDR_r[3:0]] <= SNES_DATA_r;

      snescast_hdma_write <= 0;
    end
    else if (snescast_hdma_read_init) begin
      for (i = 0; i < HDMA_CHANNELS; i = i + 1) begin
        if (r420C[i]) begin
          {r43xx[i][8'h9],r43xx[i][8'h8]} <= {r43xx[i][8'h3],r43xx[i][8'h2]};
          snescast_hdma_state[i] <= HDMA_STATE_READ_LC;
        end
      end
      snescast_hdma_read_init <= 0;
    end
    else if (snescast_hdma_read_wait) begin
      if (SNES_SNOOPRD_end) snescast_hdma_read_update <= 1;
    end
    else if (IS_NMI_START) begin
      for (i = 0; i < HDMA_CHANNELS; i = i + 1) begin
        // all active HDMA stopped at VBLANK
        snescast_hdma_state[i] <= HDMA_STATE_IDLE;
      end
      // FIXME: disable HDMA.  Technically, I don't think these are cleared but it looks like some games will set them up again
      // May be better to not clear and instead ignore accesses.  But the problem then becomes when do we stop ignoring.  The end of the NMI may be too late.
      //r420C <= 0;
    end
  end
end

// buffer inputs
assign buf_we   = mode_r[1] ? snescast_we   : mode_r[0] ? trace_we   : wram_we;
assign buf_data = mode_r[1] ? snescast_data : mode_r[0] ? trace_data : wram_data;
assign buf_addr = mode_r[1] ? snescast_addr : mode_r[0] ? trace_addr : wram_addr;

assign msu_data_out = msu_data;
assign msu_scaddr_out = {1'b0,snescast_addr_frame_r,1'b0,snescast_addr_op_r};
assign OE_RD_ENABLE = (|snescast_hdma_read_active) | snescast_hdma_read_active2 | snescast_hdma_read_wait;

assign DBG = |snescast_hdma_read_active;

endmodule
