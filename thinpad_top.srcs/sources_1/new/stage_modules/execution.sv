module mem_data_offset_adjust (
    input wire mem_we,
    input wire [31:0] write_address,
    input wire [31:0] instr,

    input  wire [31:0] in_data,
    output reg  [31:0] out_data,

    output reg [3:0] out_be
);
  reg [31:0] adjusted_data;
  always_comb begin
    case (instr[14:12])
      3'b000: begin  // SB, LB
        case (write_address[1:0])
          2'b00: begin
            adjusted_data = {24'b0, in_data[7:0]};
            out_be = 4'b0001;
          end
          2'b01: begin
            adjusted_data = {16'b0, in_data[7:0], 8'b0};
            out_be = 4'b0010;
          end
          2'b10: begin
            adjusted_data = {8'b0, in_data[7:0], 16'b0};
            out_be = 4'b0100;
          end
          2'b11: begin
            adjusted_data = {in_data[7:0], 24'b0};
            out_be = 4'b1000;
          end
        endcase
      end
      3'b001: begin  // SH, LH, we assert that [0] bit is always zero.
        if (write_address[1] == 1'b0) begin
          adjusted_data = {16'b0, in_data[15:0]};
          out_be = 4'b0011;
        end else begin
          adjusted_data = {in_data[15:0], 16'b0};
          out_be = 4'b1100;
        end
      end
      3'b010: begin  // SW, LW we assert that [1:0] bits are zeroes.
        adjusted_data = in_data;
        out_be = 4'b1111;
      end
      3'b100: begin  // LBU
        case (write_address[1:0])
          2'b00: begin
            out_be = 4'b0001;
          end
          2'b01: begin
            out_be = 4'b0010;
          end
          2'b10: begin
            out_be = 4'b0100;
          end
          2'b11: begin
            out_be = 4'b1000;
          end
        endcase
        adjusted_data = 32'b0;
      end
      3'b101: begin  // LHU, we assert that [0] bit is always zero.
        if (write_address[1] == 1'b0) begin
          out_be = 4'b0011;
        end else begin
          out_be = 4'b1100;
        end
        adjusted_data = 32'b0;
      end
      default: begin  // Invalid
        adjusted_data = 32'b0;
        out_be = 4'b0;
      end
    endcase
    if (mem_we) begin
      out_data = adjusted_data;
    end else begin
      out_data = 32'b0;
    end
  end
endmodule

module adjust_ip (
    input wire [31:0] instr,
    input wire [31:0] curr_ip,

    input wire [31:0] pred_pc,
    input wire [31:0] op1,
    input wire [31:0] op2,
    input wire [31:0] offset,
    output reg is_jump,
    output wire dyn_take_ip,
    output wire [31:0] dyn_new_ip

);

  localparam BRANCH = 32'b????_????_????_????_????_????_?110_0011;
  localparam BEQ = 32'b????_????_????_????_?000_????_?110_0011;  // BASE
  localparam BNE = 32'b????_????_????_????_?001_????_?110_0011;
  localparam BLT = 32'b????_????_????_????_?100_????_?110_0011;
  localparam BGE = 32'b????_????_????_????_?101_????_?110_0011;
  localparam BLTU = 32'b????_????_????_????_?110_????_?110_0011;
  localparam BGEU = 32'b????_????_????_????_?111_????_?110_0011;
  localparam JAL = 32'b????_????_????_????_????_????_?110_1111;
  localparam JALR = 32'b????_????_????_????_????_????_?110_0111;


  reg branch_needs_jump;
  reg need_jump_c;
  reg [31:0] new_ip_c;
  reg take_ip_c;
  always_comb begin
    branch_needs_jump = 0;
    need_jump_c = 0;
    new_ip_c = 32'd0;
    take_ip_c = 0;
    casez (instr)
      BEQ:  branch_needs_jump = op1 == op2;
      BNE:  branch_needs_jump = op1 != op2;
      BLT:  branch_needs_jump = $signed(op1) < $signed(op2);
      BGE:  branch_needs_jump = $signed(op1) >= $signed(op2);
      BLTU: branch_needs_jump = op1 < op2;
      BGEU: branch_needs_jump = op1 >= op2;
    endcase
    casez (instr)
      BRANCH: begin
        need_jump_c = branch_needs_jump;
        new_ip_c = branch_needs_jump ? curr_ip + offset : curr_ip + 32'd4;
      end
      JAL: begin
        need_jump_c = 1;
        new_ip_c = curr_ip + offset;
      end
      JALR: begin
        need_jump_c = 1;
        new_ip_c = op1 + offset;
      end
      default: begin
        need_jump_c = 0;
        new_ip_c = curr_ip + 32'd4;
      end
    endcase
    take_ip_c = pred_pc != new_ip_c;
    is_jump   = need_jump_c;
  end
  assign dyn_take_ip = take_ip_c;
  assign dyn_new_ip  = new_ip_c;
  wire error = (32'h8000_0000 > dyn_new_ip || 32'h807f_ffff < dyn_new_ip);
endmodule

module link_modif (
    input  wire [31:0] instr,
    input  wire [31:0] curr_ip,
    input  wire [31:0] alu_out,
    output reg  [31:0] wb_wdata
);
  parameter AUIPC = 32'b????_????_????_????_????_????_?001_0111;
  parameter JAL = 32'b????_????_????_????_????_????_?110_1111;
  parameter JALR = 32'b????_????_????_????_????_????_?110_0111;
  always_comb begin
    casez (instr)
      AUIPC: begin
        wb_wdata = curr_ip + {instr[31:12], 12'b0};
      end
      // Jump part is handled by predictor and ip correction. 
      // Here handles the link part, i.e. the return address. 
      JAL: begin
        wb_wdata = curr_ip + 32'd4;
      end
      JALR: begin
        wb_wdata = curr_ip + 32'd4;
      end
      default: begin
        wb_wdata = alu_out;
      end
    endcase
  end
endmodule
