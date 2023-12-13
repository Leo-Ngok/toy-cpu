module display_controller #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter BRAM_ADDR_WIDTH = 14,  // 7500  pixels(100*75 with 8 times compression) 
    parameter BRAM_DATA_WIDTH = 8
) (
    // clk and reset
    input wire clk_i,
    input wire rst_i,

    // wishbone slave interface
    input  wire                    wb_cyc_i,
    input  wire                    wb_stb_i,
    output reg                     wb_ack_o,
    input  wire [  ADDR_WIDTH-1:0] wb_adr_i,
    input  wire [  DATA_WIDTH-1:0] wb_dat_i,
    output reg  [  DATA_WIDTH-1:0] wb_dat_o,
    input  wire [DATA_WIDTH/8-1:0] wb_sel_i,
    input  wire                    wb_we_i,

    // No external ports!!
    // Of course feel free to add VGA ports for the sake of convenience.

    // VGA ports
    input  wire        vga_clk,
    input  wire        vga_rst,
    input  wire [11:0] vga_hdata,
    input  wire [ 9:0] vga_vdata,
    input  wire        vga_hsync,
    input  wire        vga_vsync,
    input  wire        vga_video_de,
    output reg  [ 7:0] pixel          // VGA 输出像素数据

);
//   // TODO: Implement this module, just instantiate the 
//   // BRAM IP core here and do necessary conversions.
  parameter HMAX = 1040;
  parameter VMAX = 666;
  parameter HSIZE = 800;
  parameter VSIZE = 600;

  reg cur_vram_exposed;
  reg [3:0] vram_we;
  reg [12:0] write_addr;
  reg [31:0] write_data;

  reg [14:0] read_addr;
  reg [12:0] read_addr_ram;
  wire [1:0][31:0] read_data; 
  vga_mem vram0 (
      .clka (clk_i),
      .clkb (vga_clk),
      .wea  (vram_we & {4{!cur_vram_exposed}}),
      .addra(write_addr),
      .dina (write_data),

      .addrb(read_addr_ram),
      .doutb(read_data[0])
  );

  vga_mem vram1 (
      .clka (clk_i),
      .clkb (vga_clk),
      .wea  (vram_we & {4{cur_vram_exposed}}),
      .addra(write_addr),
      .dina (write_data),

      .addrb(read_addr_ram),
      .doutb(read_data[1])
  );
  reg vga_can_switch;
  always_ff @(posedge vga_clk) begin
    if(vga_rst) begin
      vga_can_switch <= 1'b0;
    end else begin
      vga_can_switch <= vga_vdata == VMAX - 1 && vga_hdata > HMAX - 15;
    end
  end
  reg vga_local_can_switch;
  always_ff @(posedge clk_i) begin
    if(rst_i) begin
      vga_local_can_switch <= 1'b0;
    end else begin
      vga_local_can_switch <= vga_can_switch;
    end
  end
  always_comb begin
    vram_we = 4'b0;
    write_addr = 13'b0;
    write_data = 32'b0;
    wb_dat_o = 32'b0;
    wb_ack_o = 1'b0;
    if(wb_cyc_i && wb_stb_i) begin
      if(wb_we_i) begin
        if(32'h3000_0000 <= wb_adr_i && wb_adr_i < 32'h3000_0000 + 32'd30000) begin
        vram_we = wb_sel_i;
        write_addr = wb_adr_i[14:2];
        write_data = wb_dat_i;
        wb_ack_o = 1'b1;
        end 
        if(wb_adr_i == 32'h300F_0000 && vga_local_can_switch) begin
          wb_ack_o = 1'b1;
        end
      end else begin
        // read part.
        if(wb_adr_i == 32'h300F_0000) begin
          wb_dat_o = {31'b0, cur_vram_exposed};
          wb_ack_o = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if(rst_i) begin
      cur_vram_exposed <= 1'b0;
    end else begin
      if(wb_adr_i == 32'h300F_0000 && vga_local_can_switch) begin
        cur_vram_exposed <= wb_dat_i[0];
      end
    end
  end
  reg [14:0] v_norm;
  reg [14:0] h_norm;
  reg [31:0] pixels_sel;
  reg [14:0] read_addr_prev;
  always_comb begin
    v_norm = {7'b0,vga_vdata[9:2]};
    h_norm = {5'b0,vga_hdata[11:2]};
    read_addr = (v_norm << 7) + (v_norm << 6) + (v_norm << 3) + h_norm;
    read_addr_prev = (vga_hdata[1:0] == 2'd3) ? read_addr + 14'd1 : read_addr;
    pixels_sel = read_data[!cur_vram_exposed];
    case(read_addr[1:0])
    2'd0: pixel = pixels_sel[7:0];
    2'd1: pixel = pixels_sel[15:8];
    2'd2: pixel = pixels_sel[23:16];
    2'd3: pixel = pixels_sel[31:24];
    endcase
    read_addr_ram = read_addr_prev[14:2];
  end
endmodule
