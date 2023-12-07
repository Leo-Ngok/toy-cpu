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
  parameter HMAX = 1040;
  parameter VMAX = 666;
  parameter HSIZE = 800;
  parameter VSIZE = 600;
  parameter VGA_SCALE = 3;  // 8 times compression

  parameter [ADDR_WIDTH-1:0] SWITCH_VRAM_ADDR = 32'h3000_F000;


  logic [1:0][BRAM_ADDR_WIDTH-1:0] write_addr;
  logic [1:0][BRAM_DATA_WIDTH-1:0] write_data;
  logic [1:0][BRAM_ADDR_WIDTH-1:0] read_addr;
  logic [1:0][BRAM_DATA_WIDTH-1:0] read_data;

  logic [1:0][BRAM_DATA_WIDTH/8-1:0] vram_we;
  logic [1:0] ena;
  logic [1:0] enb;

  logic cur_vram = 0;

  // conversion to read address of vram.
  always_comb begin
    read_addr[1 - cur_vram] = (vga_hdata >> VGA_SCALE) + (vga_vdata >> VGA_SCALE) * (HSIZE >> VGA_SCALE) ;
    pixel = read_data[1 - cur_vram];
  end

  vga_mem vram0 (
      .clka (clk_i),
      .clkb (clk_i),
      .wea  (vram_we[0]),
      .addra(write_addr[0]),
      .dina (write_data[0]),
      .ena  (1),

      .addrb(read_addr[0]),
      .doutb(read_data[0]),
      .enb  (1)
  );

  vga_mem vram1 (
      .clka (clk_i),
      .clkb (clk_i),
      .wea  (vram_we[1]),
      .addra(write_addr[1]),
      .dina (write_data[1]),
      .ena  (1),

      .addrb(read_addr[1]),
      .doutb(read_data[1]),
      .enb  (1)

  );

  typedef enum reg [4:0] {
    WAIT,
    WRITE_BLOCKS,
    SWITCH_VRAM
  } state_t;

  state_t state;

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      write_addr <= 0;
      write_data <= 0;
      vram_we    <= 0;
      cur_vram   <= 0;

      wb_ack_o <= 0;
      wb_dat_o <= 0;
      state <= WAIT;
    end else begin
      case (state)
        WAIT: begin
          wb_ack_o <= 0;
          if (wb_cyc_i && wb_stb_i) begin
            if (wb_we_i) begin
              if (wb_adr_i == SWITCH_VRAM_ADDR) begin
                state <= SWITCH_VRAM;
              end else begin
                state <= WRITE_BLOCKS;
                write_addr[cur_vram] <= wb_adr_i[BRAM_ADDR_WIDTH-1:0];
                vram_we[cur_vram] <= 1;
                case (wb_sel_i)
                  4'b0001: write_data[cur_vram] <= wb_dat_i[7:0];
                  4'b0010: write_data[cur_vram] <= wb_dat_i[15:8];
                  4'b0100: write_data[cur_vram] <= wb_dat_i[23:16];
                  4'b1000: write_data[cur_vram] <= wb_dat_i[31:24];
                  default: begin
                  end
                endcase
                wb_ack_o <= 1;
              end
            end
          end
        end
        WRITE_BLOCKS: begin
          state <= WAIT;
          wb_ack_o <= 0;
        end
        SWITCH_VRAM: begin
          if (vga_vdata == VMAX - 1 && vga_hdata > HMAX - 15) begin
            wb_ack_o <= 1;
            cur_vram <= wb_dat_i[0];
            state <= WAIT;
          end else begin
            wb_ack_o <= 0;
          end
        end
      endcase
    end
  end

endmodule
