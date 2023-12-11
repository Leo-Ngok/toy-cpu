module instr_decoder (
    input wire [31:0] instr,

    output wire [4:0] raddr1,
    output wire [4:0] raddr2,
    output wire [4:0] waddr,
    output wire we,

    output wire mem_re,
    output wire mem_we,

    // output wire [3:0] mem_be: No, don't do this. Find write address first.
    output wire csr_acc,

    output wire clear_icache,
    output wire clear_tlb,

    output wire [31:0] immgen
);
  parameter LUI = 7'b0110111;
  parameter AUIPC = 7'b0010111;
  parameter JAL = 7'b1101111;
  parameter JALR = 7'b1100111;
  parameter BRANCH = 7'b1100011;
  parameter LOAD = 7'b0000011;
  parameter STORE = 7'b0100011; // S type
  parameter ARITHI = 7'b0010011; // I type
  parameter ARITH = 7'b0110011; // R type
  parameter SYSTEM = 7'b1110011;
  parameter FENCE_I = 7'b0001111;
  // system operations not implemented yet.
  // TODO: Implement FENCE, ECALL, CSR* ... -- DONE.

  wire [6:0] opcode;

  wire write_en;
  wire read1_en;
  wire read2_en;

  assign opcode = instr[6:0];
  wire i_type;
  wire r_type;
  wire s_type;
  wire b_type;
  wire u_type;
  wire j_type;

  assign i_type = (opcode == JALR) || (opcode == LOAD) || (opcode == ARITHI);
  assign r_type = (opcode == ARITH);
  assign s_type = (opcode == STORE);
  assign b_type = (opcode == BRANCH);
  assign u_type = (opcode == LUI) || (opcode == AUIPC);
  assign j_type = (opcode == JAL);
  // assign write_en = !(opcode == BRANCH || opcode == STORE || clear_tlb || clear_icache);
  // assign read1_en = !(
  //       opcode == LUI    || 
  //       opcode == AUIPC  || 
  //       opcode == JAL    ||
  //       clear_tlb ||
  //       clear_icache
  //   );
  // assign read2_en = (
  //       opcode == BRANCH ||
  //       opcode == STORE  ||
  //       opcode == ARITH
  //   ) && !(clear_icache || clear_tlb);


  assign mem_re = opcode == LOAD;
  assign mem_we = opcode == STORE;
  assign csr_acc = opcode == SYSTEM && instr[14:12] != 3'b0;
  // volume 2 p.138
  assign clear_tlb = opcode == SYSTEM && instr[14:7] == 8'b0 && instr[31:25] == 7'b0001001;
  // volume 1 p.131
  assign clear_icache = opcode == FENCE_I && instr[14:12] == 3'b001;
  reg [31:0] immgen_c;

  assign write_en = r_type || i_type || u_type || j_type || csr_acc ;
  assign read1_en = r_type || i_type || s_type || b_type || (csr_acc && instr[14] != 1'b1);
  assign read2_en = r_type || s_type || b_type;
  assign we = write_en;
  assign waddr = write_en ? instr[11:7] : 5'b0;
  assign raddr1 = read1_en ? instr[19:15] : 5'b0;
  assign raddr2 = read2_en ? instr[24:20] : 5'b0;
  always_comb begin
    immgen_c = 32'b0;
    case (opcode)
      // needs jump, predict no jump
      // https://riscv.org/wp-content/uploads/2017/05/riscv-spec-v2.2.pdf 
      // p. 17
      //   31    |  30:25  | 24:20 | 19:15 | 14:12  | 11:8   | 7     | 6:0    |
      // +------------------+----------+----------+--------+-------+----------+
      // | i[12] | i[10:5] |  rs2  | rs1   | funct3 | i[4:1] | i[11] | opcode |
      // +------------------+----------+----------+--------+-------+----------+
      BRANCH: immgen_c = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
      JAL:  // Refer to ISA p.16.
      // imm[20|10:1|11|19:12] | rd | opcode
      immgen_c = {
        {12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0
      };
      JALR, LOAD, ARITHI: immgen_c = {{21{instr[31]}}, instr[30:20]};
      STORE: immgen_c = {{21{instr[31]}}, instr[30:25], instr[11:7]};
      LUI, AUIPC: immgen_c = {instr[31:12], 12'b0};
    endcase
  end
  assign immgen = immgen_c;
endmodule

module instr_mux (
    input wire [4:0] raddr1,
    input wire [4:0] raddr2,

    input wire [31:0] rdata1,
    input wire [31:0] rdata2,

    input wire        alu_we,
    input wire [ 4:0] alu_waddr,
    input wire [31:0] alu_wdata,

    input wire        mem_we,
    input wire [ 4:0] mem_waddr,
    input wire [31:0] mem_wdata,

    input wire        wb_we,     // Note that data are written to regs  
    input wire [ 4:0] wb_waddr,  // after another posedge of clock,
    input wire [31:0] wb_wdata,  // rather than immediately.

    output reg [31:0] rdata1_out,
    output reg [31:0] rdata2_out
);
  always_comb begin
    if (raddr1 == 5'b0) begin
      rdata1_out = 32'b0;
    end else begin
      if (alu_we && (alu_waddr == raddr1)) begin
        rdata1_out = alu_wdata;
      end else if (mem_we && (mem_waddr == raddr1)) begin
        rdata1_out = mem_wdata;
      end else if (wb_we && (wb_waddr == raddr1)) begin
        rdata1_out = wb_wdata;
      end else begin
        rdata1_out = rdata1;
      end
    end
  end

  always_comb begin
    if (raddr2 == 5'b0) begin
      rdata2_out = 32'b0;
    end else begin
      if (alu_we && (alu_waddr == raddr2)) begin
        rdata2_out = alu_wdata;
      end else if (mem_we && (mem_waddr == raddr2)) begin
        rdata2_out = mem_wdata;
      end else if (wb_we && (wb_waddr == raddr2)) begin
        rdata2_out = wb_wdata;
      end else begin
        rdata2_out = rdata2;
      end
    end
  end
endmodule
