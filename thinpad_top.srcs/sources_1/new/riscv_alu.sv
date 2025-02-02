module riscv_alu(
    input wire [31:0] opcode,
    input wire [31:0] in_1,
    input wire [31:0] in_2,
    output reg [31:0] out
);
    // Miscellaneous
    parameter  LUI = 32'b????_????_????_????_????_????_?011_0111; // BASE
    parameter AUIPC= 32'b????_????_????_????_????_????_?001_0111;
    parameter JAL  = 32'b????_????_????_????_????_????_?110_1111;
    parameter JALR = 32'b????_????_????_????_????_????_?110_0111;
    // B-Type: Branch instructions.
    // +--------------+-----+-----+--------+-------------+--------+
    // | imm[12|10:5] | rs2 | rs1 | funct3 | imm[4:1|11] | opcode |
    // +--------------+-----+-----+--------+-------------+--------+
    // Note:
    // opcode: always 1100011.
    // imm: offset rel. to base.
    // funct3: type of branch instr.
    // rs1, rs2: sources of data registers to compare.
    parameter BRANCH = 32'b????_????_????_????_????_????_?110_0011;
    parameter  BEQ = 32'b????_????_????_????_?000_????_?110_0011; // BASE
    parameter  BNE = 32'b????_????_????_????_?001_????_?110_0011;
    parameter  BLT = 32'b????_????_????_????_?100_????_?110_0011;
    parameter  BGE = 32'b????_????_????_????_?101_????_?110_0011;
    parameter BLTU = 32'b????_????_????_????_?110_????_?110_0011;
    parameter BGEU = 32'b????_????_????_????_?111_????_?110_0011;


    parameter LOAD_STORE = 32'b????_????_????_????_????_????_?0?0_0011;
    // I-Type: (Part ONE) Load instructions.
    // +-----------+-----+--------+----+--------+
    // | imm[11:0] | rs1 | funct3 | rd | opcode |
    // +-----------+-----+--------+----+--------+
    // opcode: 0000011
    // rd: load destination register.
    // rs1: base address.
    // imm: offset relative to base address.
    // funct3: type of load instr. 
    parameter LOAD = 32'b????_????_????_????_????_????_?000_0011;
    parameter   LB = 32'b????_????_????_????_?000_????_?000_0011; // BASE
    parameter   LH = 32'b????_????_????_????_?001_????_?000_0011;
    parameter   LW = 32'b????_????_????_????_?010_????_?000_0011;
    parameter  LBU = 32'b????_????_????_????_?100_????_?000_0011;
    parameter  LHU = 32'b????_????_????_????_?101_????_?000_0011;
    
    // S-Type: Store instructions.
    // +-----------+-----+-----+--------+----------+--------+
    // | imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode |
    // +-----------+-----+-----+--------+----------+--------+
    // opcode: 0100011
    // rs1: base address.
    // imm: offset rel to base.
    // rs2: data to store.
    // funct3: type of store instr.
    parameter STORE= 32'b????_????_????_????_????_????_?010_0011;
    parameter   SB = 32'b????_????_????_????_?000_????_?010_0011; // BASE
    parameter   SH = 32'b????_????_????_????_?001_????_?010_0011;
    parameter   SW = 32'b????_????_????_????_?010_????_?010_0011; // BASE

    // I-Type: (Part TWO) Arith. w/ immediates.
    // +-----------+-----+--------+----+--------+
    // | imm[11:0] | rs1 | funct3 | rd | opcode |
    // +-----------+-----+--------+----+--------+
    // opcode: 0000011
    // rd: load destination register.
    // rs1: the first operand.
    // imm: the second operand as immediate.
    // funct3: type of arith. instr.
    parameter ADDI = 32'b????_????_????_????_?000_????_?001_0011; // BASE
    parameter SLTI = 32'b????_????_????_????_?010_????_?001_0011; 
    parameter SLTIU= 32'b????_????_????_????_?011_????_?001_0011; 
    parameter XORI = 32'b????_????_????_????_?100_????_?001_0011; 
    parameter  ORI = 32'b????_????_????_????_?110_????_?001_0011; 
    parameter ANDI = 32'b????_????_????_????_?111_????_?001_0011; // BASE

    parameter SLLI = 32'b0000_000?_????_????_?001_????_?001_0011; 
    parameter SRLI = 32'b0000_000?_????_????_?101_????_?001_0011; 
    parameter SRAI = 32'b0100_000?_????_????_?101_????_?001_0011; 

    // R-Type: Regular arith instructions.
    // +--------+-----+-----+--------+----+--------+
    // | funct7 | rs2 | rs1 | funct3 | rd | opcode |
    // +--------+-----+-----+--------+----+--------+
    // opcode: 0110011
    // rd:  dest reg
    // rs1: src operand 1
    // rs2: src operand 2
    // funct3: Type of instructions
    // funct7: further distinguish type if funct3 is not enough.

    parameter  ADD = 32'b0000_000?_????_????_?000_????_?011_0011; // BASE
    parameter  SUB = 32'b0100_000?_????_????_?000_????_?011_0011;

    parameter  SLL = 32'b0000_000?_????_????_?001_????_?011_0011;
    parameter  SLT = 32'b0000_000?_????_????_?010_????_?011_0011;
    parameter SLTU = 32'b0000_000?_????_????_?011_????_?011_0011;
    parameter  XOR = 32'b0000_000?_????_????_?100_????_?011_0011;
    parameter  SRL = 32'b0000_000?_????_????_?101_????_?011_0011;
    parameter  SRA = 32'b0100_000?_????_????_?101_????_?011_0011;
    parameter   OR = 32'b0000_000?_????_????_?110_????_?011_0011;
    parameter  AND = 32'b0000_000?_????_????_?111_????_?011_0011;

    parameter XPERM8 = 32'b0010100_?????_?????_100_?????_0110011;

    parameter SYSTEM = 32'b????_????_????_????_????_????_?1110011;
    parameter CSRRW  = 32'b????_????_????_?????_001_?????_1110011;
    parameter CSRRS  = 32'b????_????_????_?????_010_?????_1110011;
    parameter CSRRC  = 32'b????_????_????_?????_011_?????_1110011;
    parameter CSRRWI = 32'b????_????_????_?????_101_?????_1110011;
    parameter CSRRSI = 32'b????_????_????_?????_110_?????_1110011;
    parameter CSRRCI = 32'b????_????_????_?????_111_?????_1110011;

    parameter PACK  = 32'b0000_100?_????_????_?100_????_?011_0011;
    parameter SBSET = 32'b0010_100?_????_????_?001_????_?011_0011;
    parameter CLZ   = 32'b0110_0000_0000_????_?001_????_?001_0011;

    reg [7:0] i1, i2, i3, i4;
    always_comb begin
        i1 = 0;
        i2 = 0;
        i3 = 0;
        i4 = 0;
        out = 32'b0;
        casez (opcode)
             LUI: out = { opcode[31:12], 12'b0 };
            AUIPC: out = 32'b0; // It is not our duty to calculate pc + offset, it is link_modif's job (in execution.sv).
             JAL: out = 32'b0; // No, it is again not our duty.
             JALR: out = in_1; // Give this value to IP correction module, to update next instruction pointer. 
             BEQ: out = (in_1 == in_2) ? 32'b1 : 32'b0;
             BNE: out = (in_1 != in_2) ? 32'b1 : 32'b0;
             BLT: out = ($signed(in_1)  < $signed(in_2)) ? 32'b1 : 32'b0;
             BGE: out = ($signed(in_1) >= $signed(in_2)) ? 32'b1 : 32'b0;
             BLTU: out = (in_1  < in_2) ? 32'b1 : 32'b0;
             BGEU: out = (in_1 >= in_2) ? 32'b1 : 32'b0;
              //LB: out <= in_1 + { 19'b0, opcode[31], opcode[7], opcode[30:25], opcode[11:8], 1'b0 };
             
             
             LOAD : out = in_1 + { {20{opcode[31]}}, opcode[31:20] };
             STORE: out = in_1 + { {20{opcode[31]}}, opcode[31:25], opcode[11:7] };
            
            ADDI: out = in_1 + { {20{opcode[31]}}, opcode[31:20] };
            SLTI: out = ($signed(in_1)  < $signed({ {20{opcode[31]}}, opcode[31:20] })) ? 32'b1 : 32'b0;
            SLTIU: out = (in_1  < { {20{opcode[31]}}, opcode[31:20] }) ? 32'b1 : 32'b0;
            XORI: out = in_1 ^ { {20{opcode[31]}}, opcode[31:20] };
             ORI: out = in_1 | { {20{opcode[31]}}, opcode[31:20] };
            ANDI: out = in_1 & { {20{opcode[31]}}, opcode[31:20] };

            SLLI: out = in_1 << opcode[24:20]; 
            SRLI: out = in_1 >> opcode[24:20];
            SRAI: out = $signed(in_1) >>> opcode[24:20]; 

             ADD: out = in_1 + in_2;
             SUB: out = in_1 - in_2;
             SLL: out = in_1 << in_2[4:0];
             SLT: out = ($signed(in_1)  < $signed(in_2)) ? 32'b1 : 32'b0;
            SLTU: out = (in_1  < in_2) ? 32'b1 : 32'b0;
             XOR: out = in_1 ^ in_2;
             SRL: out = in_1 >> in_2[4:0];
             SRA: out = $signed(in_1) >>> in_2[4:0];
              OR: out = in_1 | in_2;
             AND: out = in_1 & in_2;
             XPERM8: begin
            i1 = in_2[ 7: 0];
            i2 = in_2[15: 8];
            i3 = in_2[23:16];
            i4 = in_2[31:24];
            if(i1 < 8'd4) begin
                out[7:0] = in_1[8*i1+:8];
            end else begin
                out[7:0] = 8'b0;
            end
            if(i2 < 8'd4) begin
                out[15:8] = in_1[8*i2+:8];
            end else begin
                out[15:8] = 8'b0;
            end
            if(i3 < 8'd4) begin
                out[23:16] = in_1[8*i3+:8];
            end else begin
                out[23:16] = 8'b0;
            end
            if(i4 < 8'd4) begin
                out[31:24] = in_1[8*i4+:8];
            end else begin
                out[31:24] = 8'b0;
            end
            end

              PACK: begin
                out[31:0] = ((in_1[31:0] << 16) >> 16) | (in_2[31:0] << 16);
            end
            SBSET: begin
                out[31:0] = in_1[31:0] | (32'b1 << (in_2[31:0] & 31));
            end
            CLZ: begin
                out[31:0] = 32'd32;
                for (int count = 0; count < 31; count++) begin
                    if ((in_1 << count) >> 31) begin
                        out[31:0] = count;
                        break;
                    end
                end
            end

            default: out = 32'b0;
        endcase
    end
endmodule
