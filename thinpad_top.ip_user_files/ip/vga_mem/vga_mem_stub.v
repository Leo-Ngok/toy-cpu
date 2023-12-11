// Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
// Date        : Fri Dec  8 04:59:10 2023
// Host        : LAPTOP-92IKODO2 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub -rename_top vga_mem -prefix
//               vga_mem_ vga_mem_stub.v
// Design      : vga_mem
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a100tfgg676-2L
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "blk_mem_gen_v8_4_4,Vivado 2019.2" *)
module vga_mem(clka, wea, addra, dina, clkb, addrb, doutb)
/* synthesis syn_black_box black_box_pad_pin="clka,wea[3:0],addra[12:0],dina[31:0],clkb,addrb[12:0],doutb[31:0]" */;
  input clka;
  input [3:0]wea;
  input [12:0]addra;
  input [31:0]dina;
  input clkb;
  input [12:0]addrb;
  output [31:0]doutb;
endmodule
