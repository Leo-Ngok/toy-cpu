module flash_controller #(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 32
) (
  // clk and reset
  input wire clk_i,
  input wire rst_i,

  // wishbone slave interface
  input wire wb_cyc_i,
  input wire wb_stb_i,
  output reg wb_ack_o,
  input wire [ADDR_WIDTH-1:0] wb_adr_i,
  input wire [DATA_WIDTH-1:0] wb_dat_i,
  output reg [DATA_WIDTH-1:0] wb_dat_o,
  input wire [DATA_WIDTH/8-1:0] wb_sel_i,
  input wire wb_we_i,

  // Flash 存储器信号，参考 JS28F640 芯片手册
  output wire [22:0] flash_a,  // Flash 地址，a0 仅在 8bit 模式有效，16bit 模式无意义
  inout wire [15:0] flash_d,  // Flash 数据
  output wire flash_rp_n,  // Flash 复位信号，低有效
  output wire flash_vpen,  // Flash 写保护信号，低电平时不能擦除、烧写
  output wire flash_ce_n,  // Flash 片选信号，低有效
  output wire flash_oe_n,  // Flash 读使能信号，低有效
  output wire flash_we_n,  // Flash 写使能信号，低有效
  output wire flash_byte_n // Flash 8bit 模式选择，低有效。在使用 flash 的 16 位模式时请设为 1
);

  typedef enum logic { IDLE, READ } state_t;
  state_t state;

  assign flash_a = wb_adr_i[22:0];
  assign flash_d = 16'bz;
  assign flash_rp_n = 1'b1;
  assign flash_vpen = 1'b1;
  assign flash_ce_n = 1'b0;
  assign flash_oe_n = state != READ;
  assign flash_we_n = 1'b1;
  assign flash_byte_n = 1'b1;

  // wire [31:0] data;
  // assign data = $signed(flash_d[7:0])<<8*(wb_adr_i[1:0]);
  reg [3:0] cycle_counter;
  always_ff @ (posedge clk_i) begin
    if (rst_i) begin
      state <= IDLE;
      cycle_counter <= 4'd0;
    end else begin
      case (state)
        IDLE: begin
          if (wb_cyc_i && wb_stb_i) begin
            state <= READ;
            cycle_counter <= 4'd10;
          end
        end
        READ: begin
          if(cycle_counter != 4'd0) cycle_counter <= cycle_counter - 4'd1;
          else state <= IDLE;
        end
      endcase
    end
  end
  always_comb begin
    wb_ack_o = state == READ && cycle_counter == 4'd0;
    wb_dat_o = wb_adr_i[1] ? {flash_d, 16'b0} : {16'b0, flash_d};

  end
endmodule