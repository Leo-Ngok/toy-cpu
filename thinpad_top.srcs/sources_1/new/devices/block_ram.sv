module display_controller #(
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
    input  wire                    wb_we_i,

    // No external ports!!
    // Of course feel free to add VGA ports for the sake of convenience.

    //VGA ports
    input  wire [11:0] vga_hdata,
    input  wire [ 9:0] vga_vdata,
    input  wire        vga_hsync,
    input  wire        vga_vsync,
    input  wire        vga_video_de,
    output reg  [ 7:0] pixel          // VGA 输出像素数据

);
  // TODO: Implement this module, just instantiate the 
  // BRAM IP core here and do necessary conversions.

  // One may add VGA controller here for your convenience.

  assign wb_dat_o = 32'b0;
  assign wb_ack_o = 1'b0;

  logic [  ADDR_WIDTH-1:0] write_addr;
  logic [  DATA_WIDTH-1:0] write_data;
  logic [  ADDR_WIDTH-1:0] read_addr;
  logic [  DATA_WIDTH-1:0] read_data;

  logic [DATA_WIDTH/8-1:0] vram_we;

  // conversion to read address into vram
  always_comb begin
    read_addr = vga_hdata + vga_vdata * 800;
  end

  assign write_addr = wb_adr_i;
  assign write_data = wb_dat_i;
  assign vram_we = wb_sel_i;

  cache_ram vram (
      .clka (clk_i),
      .clkb (clk_i),
      .wea  (vram_we),
      .addra(write_addr),
      .dina (write_data),

      .addrb(read_addr[ADDR_WIDTH-1:2]),
      .doutb(read_data)
  );

  always_comb begin
    case (read_addr[1:0])
      2'b00: pixel = read_data[7:0];
      2'b01: pixel = read_data[15:8];
      2'b10: pixel = read_data[23:16];
      2'b11: pixel = read_data[31:24];
    endcase
  end

endmodule
