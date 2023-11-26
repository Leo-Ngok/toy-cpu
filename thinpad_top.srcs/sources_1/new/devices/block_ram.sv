module block_ram_controller #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) (
    // clk and reset
    input wire clk_i,
    input wire rst_i,

    // wishbone slave interface
    input  wire                    wb_cyc_i,
    input  wire                    wb_stb_i,
    output wire                    wb_ack_o,
    input  wire [  ADDR_WIDTH-1:0] wb_adr_i,
    input  wire [  DATA_WIDTH-1:0] wb_dat_i,
    output wire [  DATA_WIDTH-1:0] wb_dat_o,
    input  wire [DATA_WIDTH/8-1:0] wb_sel_i,
    input  wire                    wb_we_i

    // No external ports!!
    // Of course feel free to add VGA ports for the sake of convenience.
);
  // TODO: Implement this module, just instantiate the 
  // BRAM IP core here and do necessary conversions.

  // One may add VGA controller here for your convenience.

  assign wb_dat_o = 32'b0;
  assign wb_ack_o = 1'b0;
endmodule
