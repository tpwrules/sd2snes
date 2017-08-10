`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    07:15:31 08/05/2017 
// Design Name: 
// Module Name:    usb 
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
module usb(
  input clkin,
  input enable,
  input [2:0] reg_addr,
  input [7:0] reg_data_in,
  output [7:0] reg_data_out,
  input reg_oe_falling,
  input reg_oe_rising,
  input reg_we_rising,
  input [7:0] status_reset_bits,
  input [7:0] status_set_bits,
  input status_reset_we

  //output DBG_usb_status
);

reg [1:0] status_reset_we_r;
always @(posedge clkin) status_reset_we_r = {status_reset_we_r[0], status_reset_we};
wire status_reset_en = (status_reset_we_r == 2'b01);

//assign DBG_usb_status = status_out;

// Register bank
reg [7:0] usb_r[7:0];

initial begin
  usb_r[0] = 8'h00;
  usb_r[1] = 8'h00;
  usb_r[2] = 8'h53;
  usb_r[3] = 8'h2D;
  usb_r[4] = 8'h55;
  usb_r[5] = 8'h53;
  usb_r[6] = 8'h42;
  usb_r[7] = 8'h31;
end

reg [7:0] data_out_r;
assign reg_data_out = data_out_r;

always @(posedge clkin) begin
  if(reg_oe_falling & enable)
    data_out_r <= usb_r[reg_addr];
end

always @(posedge clkin) begin
  if(reg_we_rising & enable) begin
    case(reg_addr)
	   // only support writes to REG1
      3'h1: usb_r[reg_addr] <= reg_data_in;
		default: begin
      end
    endcase
  end else if (status_reset_en) begin
    usb_r[0] <= (usb_r[0] | status_set_bits) & ~status_reset_bits;
  end
end

endmodule
