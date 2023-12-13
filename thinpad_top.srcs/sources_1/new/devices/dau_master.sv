module dau_master #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input wire clk_i,
    input wire rst_i,

    // Interface to control unit
    input wire we,
    input wire re,
    input wire [31:0] addr,
    input wire [3:0] byte_en,
    input wire [31:0] data_i,
    output wire [31:0] data_o,
    output wire ack_o,

    // wishbone master
    output wire wb_cyc_o,
    output wire wb_stb_o,
    input wire wb_ack_i,
    output wire [ADDR_WIDTH-1:0] wb_adr_o,
    output wire [DATA_WIDTH-1:0] wb_dat_o,
    input wire [DATA_WIDTH-1:0] wb_dat_i,
    output wire [DATA_WIDTH/8-1:0] wb_sel_o,
    output wire wb_we_o
);
  typedef enum logic [2:0] {
    WAIT,
    PROCESS,
    ACK
  } state_t;
  state_t state;
  reg wb_cyc_r, wb_stb_r;

  reg ack_r;
  reg [31:0] data_r;
  reg [31:0] wb_adr_r;
  reg wb_we_r;
  reg [31:0] addr_req;
  reg [3:0] sel_req;
  reg we_req;
  reg re_req;
  wire request_valid = (we_req == we) && (re_req == re) && (addr_req == addr) && (sel_req == byte_en);
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state <= WAIT;
      wb_cyc_r <= 1'b0;
      wb_stb_r <= 1'b0;
      ack_r <= 1'b0;
      data_r <= 32'b0;
      wb_we_r <= 1'b0;
      addr_req <= 32'b0;
      sel_req <= 4'b0;
      we_req <= 1'b0;
      re_req <= 1'b0;
    end else begin
      case (state)
        WAIT: begin
          if (we || re) begin
            wb_cyc_r <= 1'b1;
            wb_stb_r <= 1'b1;
            state <= PROCESS;
            addr_req <= addr;
            sel_req <= byte_en;
            we_req <= we;
            re_req <= re;
          end
        end
        PROCESS: begin
          if (wb_ack_i) begin
            state <= ACK;

            wb_cyc_r <= 1'b0;
            wb_stb_r <= 1'b0;

            ack_r <= request_valid;
            data_r <= wb_dat_i;
          end
        end
        ACK: begin
          data_r <= 32'b0;
          ack_r  <= 1'b0;
          state  <= WAIT;
        end
      endcase
      wb_adr_r <= addr;
      wb_we_r  <= we && !re;
    end
  end
  assign data_o = data_r;
  assign ack_o = ack_r;

  assign wb_cyc_o = wb_cyc_r;
  assign wb_stb_o = wb_stb_r;
  assign wb_adr_o = wb_adr_r;
  assign wb_dat_o = data_i;
  assign wb_sel_o = byte_en;
  assign wb_we_o = wb_we_r;
endmodule
