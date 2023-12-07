// module next_instr_ptr (
//     input wire clock,
//     input wire reset,

//     input  wire        mem_ack,
//     input  wire [31:0] curr_ip,
//     input  wire [31:0] curr_instr,
//     output reg  [31:0] next_ip_pred,
//     output reg         jump_pred      // Whether branching is chosen for prediction

// );

//   parameter BRANCH = 32'b????_????_????_????_????_????_?110_0011;
//   parameter JAL = 32'b????_????_????_????_????_????_?110_1111;
//   parameter JALR = 32'b????_????_????_????_????_????_?110_0111;
//   parameter ECALL = 32'b0000_0000_0000_00000_000_00000_111_0011;
//   parameter EBREAK = 32'b0000_0000_0001_00000_000_00000_111_0011;
//   parameter MRET = 32'b0011000_00010_00000_000_00000_111_0011;
//   parameter SRET = 32'b0001000_00010_00000_000_00000_111_0011;
//   parameter HALT = 32'b0;
//   reg [31:0] branch_ip;
//   always_comb begin
//     jump_pred = 0;
//     branch_ip = 32'b0;
//     // if(mem_ack) begin
//     casez (curr_instr)
//       HALT: begin
//         next_ip_pred = curr_ip;
//       end
//       BRANCH: begin
//         // TODO: analyze different branch commands,
//         // and add more sophisticated prediction logic.
//         // Currently, we use BTFNT
//         // i.e. Backward taken,
//         // Forward not taken.
//         // For example, beqz x0, offset is always taken.
//         // bnez x0, offset is never taken.
//         // in the instruction,
//         // imm[12|10:5]|rs2, rs1| fn3 | imm[4:1|11] | opcode
//         // lower 13 bits are provided, so sign extend the upper 19 bits.
//         // 12 -> 31
//         // 11 -> 7
//         // 10:5 -> 30:25
//         // 4:1 -> 11:8
//         // 31:13              12               11           10:5                4:1
//         branch_ip = curr_ip + { {19{curr_instr[31]}}, curr_instr[31], curr_instr[7], curr_instr[30:25], curr_instr[11:8], 1'b0};
//         if (branch_ip <= curr_ip) begin
//           next_ip_pred = branch_ip;
//           jump_pred = 1;
//         end else begin
//           next_ip_pred = curr_ip + 32'd4;
//         end
//       end
//       JAL: begin
//         // Refer to ISA p.16.
//         // imm[20|10:1|11|19:12] | rd | opcode
//         next_ip_pred = curr_ip + { 
//                 {11{curr_instr[31]}}, // sign extend
//                 curr_instr[31], curr_instr[19:12], curr_instr[20],
//                 curr_instr[30:21], 1'b0};
//       end
//       JALR, MRET, SRET, ECALL, EBREAK: begin
//         // Nope, we can do nothing, sad :(
//         next_ip_pred = curr_ip;
//       end
//       default: begin
//         next_ip_pred = curr_ip + 32'd4;
//       end
//     endcase
//   end
// endmodule

module dyn_pc_pred (
    input wire clock,
    input wire reset,

    input wire insert_entry,
    input wire needs_jump,
    input wire [31:0] source_pc,
    input wire [31:0] target_pc,

    input  wire [31:0] query_pc,
    output wire [31:0] pred_pc
);
  typedef struct packed {
    reg        valid;
    reg [28:0] tag;
    reg [1:0]  lru_priority;
    reg [1:0]  bh;            // branch history
    reg [31:0] target;        // branch target
  } way_t;

  way_t [7:0][3:0] entries;

  wire [2:0] source_index = source_pc[4:2];
  wire [28:0] source_tag = {source_pc[31:5], source_pc[1:0]};

  reg [1:0] lru_replace_idx;

  reg source_hit;
  reg [1:0] source_hit_way;
  reg [1:0] source_hit_bh;


  wire [2:0] query_index = query_pc[4:2];
  wire [28:0] query_tag = {query_pc[31:5], query_pc[1:0]};
  reg query_hit;
  reg [1:0] query_hit_way;
  reg [31:0] query_target_c;
  // Choose the line to be replaced.
  always_comb begin
    lru_replace_idx = 2'd3;
    for (int i_way = 0; i_way < 4; ++i_way) begin
      if (entries[source_index][i_way].lru_priority == 2'b0) begin
        lru_replace_idx = i_way[1:0];
        break;
      end
    end
  end
  always_comb begin
    source_hit_way = 0;
    source_hit = 1'b0;
    source_hit_bh = 2'b0;
    for (int i_way = 0; i_way < 4; ++i_way) begin
      if (entries[source_index][i_way].valid && query_tag == entries[source_index][i_way].tag) begin
        source_hit = 1'b1;
        source_hit_way = i_way;
        source_hit_bh = entries[source_index][i_way].bh;
        break;
      end
    end
  end
  always_ff @(posedge clock) begin
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
      if (insert_entry) begin
        if (source_hit) begin
          // for (int i = 0; i < 4; ++i) begin
          //   // note that for the zero entry, minus one means wrap back.
          //   if(entries[source_index][source_hit_way].lru_priority < entries[source_index][i].lru_priority)
          //     entries[source_index][i].lru_priority <= entries[source_index][i].lru_priority - 2'b1;
          // end
          entries[source_index][source_hit_way].target <= target_pc;
          if (needs_jump) begin
            if (entries[source_index][lru_replace_idx].bh == 2'b0)
              entries[source_index][lru_replace_idx].bh <= 2'b1;
            else entries[source_index][lru_replace_idx].bh <= 2'b11;
          end else begin
            if (entries[source_index][lru_replace_idx].bh == 2'b11)
              entries[source_index][lru_replace_idx].bh <= 2'b10;
            else entries[source_index][lru_replace_idx].bh <= 2'b0;
          end
        end else begin
          // for (int i = 0; i < 4; ++i) begin
          //   // note that for the zero entry, minus one means wrap back.
          //   entries[source_index][i].lru_priority <= entries[source_index][i].lru_priority - 2'b1;
          // end
          entries[source_index][lru_replace_idx].valid <= 1'b1;
          entries[source_index][lru_replace_idx].tag <= source_tag;
          entries[source_index][lru_replace_idx].bh <= {1'b0, needs_jump} + 2'b1;
          entries[source_index][lru_replace_idx].target <= target_pc;
        end
      end

      if (query_hit) begin
        for (int j = 0; j < 4; ++j) begin
          if(entries[query_index][query_hit_way].lru_priority < entries[query_index][j].lru_priority)
            entries[query_index][j].lru_priority <= entries[query_index][j].lru_priority - 2'b1;
        end
        entries[query_index][query_hit_way].lru_priority <= 2'b11;
      end
    end
  end


  always_comb begin
    query_target_c = query_pc + 32'd4;
    query_hit = 1'b0;
    query_hit_way = 2'b0;
    for (int i_way = 0; i_way < 4; ++i_way) begin
      if (entries[query_index][i_way].valid && query_tag == entries[query_index][i_way].tag) begin
        query_hit = 1'b1;
        query_hit_way = i_way;
        if (entries[query_index][i_way].bh >= 2'd2) begin
          query_target_c = entries[query_index][i_way].target;
        end
        break;
      end
    end
  end
  assign pred_pc = query_target_c;
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
