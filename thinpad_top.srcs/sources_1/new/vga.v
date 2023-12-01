`timescale 1ns / 1ps
//
// WIDTH: bits in register hdata & vdata
// HSIZE: horizontal size of visible field 
// HFP: horizontal front of pulse
// HSP: horizontal stop of pulse
// HMAX: horizontal max size of value
// VSIZE: vertical size of visible field 
// VFP: vertical front of pulse
// VSP: vertical stop of pulse
// VMAX: vertical max size of value
// HSPP: horizontal synchro pulse polarity (0 - negative, 1 - positive)
// VSPP: vertical synchro pulse polarity (0 - negative, 1 - positive)
//
module vga #(
    parameter WIDTH = 12,
    HSIZE = 800,
    HFP = 856,
    HSP = 976,
    HMAX = 1040,
    VSIZE = 600,
    VFP = 637,
    VSP = 643,
    VMAX = 666,
    HSPP = 1,
    VSPP = 1
) (
    input wire clk,
    input wire rst,
    output wire hsync,
    output wire vsync,
    output reg [WIDTH - 1:0] hdata,
    output reg [WIDTH - 1:0] vdata,
    output wire data_enable
);

  // hdata
  always @(posedge clk /* or posedge rst */) begin
    if(rst) begin
      hdata <= 0;
    end else begin
    if (hdata == (HMAX - 1)) hdata <= 0;
    else hdata <= hdata + 1;
    end
  end

  // vdata
  always @(posedge clk /* or posedge rst */) begin
    if(rst)begin
      vdata <= 0;
    end else begin
    if (hdata == (HMAX - 1)) begin
      if (vdata == (VMAX - 1)) vdata <= 0;
      else vdata <= vdata + 1;
    end
    end
  end

  // hsync & vsync & blank
  assign hsync = ((hdata >= HFP) && (hdata < HSP)) ? HSPP : !HSPP;
  assign vsync = ((vdata >= VFP) && (vdata < VSP)) ? VSPP : !VSPP;
  assign data_enable = ((hdata < HSIZE) & (vdata < VSIZE));

endmodule
