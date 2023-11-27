module next_instr_ptr (
    input wire clock,
    input wire reset,

    input  wire        mem_ack,
    input  wire [31:0] curr_ip,
    input  wire [31:0] curr_instr,
    output reg  [31:0] next_ip_pred,
    output reg         jump_pred,     // Whether branching is chosen for prediction

    input wire insert_entry,
    input wire jump,
    input wire [31:0] source_ip,
    input wire [31:0] target_ip
);

  parameter BRANCH = 32'b????_????_????_????_????_????_?110_0011;
  parameter JAL = 32'b????_????_????_????_????_????_?110_1111;
  parameter JALR = 32'b????_????_????_????_????_????_?110_0111;
  parameter ECALL = 32'b0000_0000_0000_00000_000_00000_111_0011;
  parameter EBREAK = 32'b0000_0000_0001_00000_000_00000_111_0011;
  parameter MRET = 32'b0011000_00010_00000_000_00000_111_0011;
  parameter SRET = 32'b0001000_00010_00000_000_00000_111_0011;
  parameter HALT = 32'b0;
  reg [31:0] branch_ip;
  always_comb begin
    jump_pred = 0;
    branch_ip = 32'b0;
    // if(mem_ack) begin
    casez (curr_instr)
      HALT: begin
        next_ip_pred = curr_ip;
      end
      BRANCH: begin
        // TODO: analyze different branch commands,
        // and add more sophisticated prediction logic.
        // Currently, we use BTFNT
        // i.e. Backward taken,
        // Forward not taken.
        // For example, beqz x0, offset is always taken.
        // bnez x0, offset is never taken.
        // in the instruction,
        // imm[12|10:5]|rs2, rs1| fn3 | imm[4:1|11] | opcode
        // lower 13 bits are provided, so sign extend the upper 19 bits.
        // 12 -> 31
        // 11 -> 7
        // 10:5 -> 30:25
        // 4:1 -> 11:8
        // 31:13              12               11           10:5                4:1
        branch_ip = curr_ip + { {19{curr_instr[31]}}, curr_instr[31], curr_instr[7], curr_instr[30:25], curr_instr[11:8], 1'b0};
        if (branch_ip <= curr_ip) begin
          next_ip_pred = branch_ip;
          jump_pred = 1;
        end else begin
          next_ip_pred = curr_ip + 32'd4;
        end
      end
      JAL: begin
        // Refer to ISA p.16.
        // imm[20|10:1|11|19:12] | rd | opcode
        next_ip_pred = curr_ip + { 
                {11{curr_instr[31]}}, // sign extend
                curr_instr[31], curr_instr[19:12], curr_instr[20],
                curr_instr[30:21], 1'b0};
      end
      JALR, MRET, SRET, ECALL, EBREAK: begin
        // Nope, we can do nothing, sad :(
        next_ip_pred = curr_ip;
      end
      default: begin
        next_ip_pred = curr_ip + 32'd4;
      end
    endcase
  end



  typedef struct packed {
    reg        valid;
    reg [28:0] tag;
    reg [1:0]  lru_priority;
    reg [1:0]  bh;            // branch history
    reg [31:0] target;        // branch target
  } way_t;

  way_t [7:0][3:0] entries;

  wire [2:0] entry_index = source_ip[4:2];
  wire [28:0] entry_tag = {source_ip[31:5], source_ip[1:0]};

  reg [1:0] lru_replace_idx;




  // Choose the line to be replaced.
  always_comb begin
    for (int i_way = 0; i_way < 4; ++i_way) begin
      if (entries[entry_index][i_way].lru_priority == 2'b0) begin
        lru_replace_idx = i_way;
        break;
      end
    end
  end

  always_ff @(posedge clock or posedge reset) begin
    if (reset) begin
      for (int i_set = 0; i_set < 8; ++i_set) begin
        for (int i_way = 0; i_way < 4; ++i_way) begin
          entries[i_set][i_way].valid <= 1'b0;
          entries[i_set][i_way].tag <= 'd0;
          entries[i_set][i_way].lru_priority <= 'd0;
          entries[i_set][i_way].bh <= 'd0;
          entries[i_set][i_way].target <= 'd0;
        end
      end
    end else begin

    end
  end


endmodule

module ip_mux (
    input wire mem_modif,
    input wire csr_modif,
    input wire alu_modif,

    input wire [31:0] mem_ip,
    input wire [31:0] csr_ip,
    input wire [31:0] alu_ip,
    input wire [31:0] pred_ip,

    output wire [31:0] res_ip
);
  reg [31:0] res_ip_comb;
  always_comb begin
    if (mem_modif) begin
      res_ip_comb = mem_ip + 4;
    end else if (csr_modif) begin
      res_ip_comb = csr_ip;
    end else if (alu_modif) begin
      res_ip_comb = alu_ip;
    end else begin
      res_ip_comb = pred_ip;
    end
  end
  assign res_ip = res_ip_comb;
endmodule
