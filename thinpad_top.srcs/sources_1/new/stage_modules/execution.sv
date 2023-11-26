module mem_data_offset_adjust(
    input wire mem_we,
    input wire [31:0] write_address,
    input wire [31:0] instr,

    input wire [31:0] in_data,
    output reg [31:0] out_data,

    output reg [3:0] out_be
);
    reg [31:0] adjusted_data;
    always_comb begin
        case(instr[14:12])
            3'b000: begin // SB, LB
                case(write_address[1:0])
                2'b00: begin
                    adjusted_data = {24'b0, in_data[7:0] };
                    out_be = 4'b0001;
                end
                2'b01: begin
                    adjusted_data = { 16'b0, in_data[7:0], 8'b0 };
                    out_be = 4'b0010;
                end
                2'b10: begin
                    adjusted_data = { 8'b0, in_data[7:0], 16'b0 };
                    out_be = 4'b0100;
                end 
                2'b11: begin
                    adjusted_data = { in_data[7:0], 24'b0 };
                    out_be = 4'b1000;
                end
                endcase
            end
            3'b001: begin // SH, LH, we assert that [0] bit is always zero.
                if(write_address[1] == 1'b0) begin
                    adjusted_data = { 16'b0, in_data[15:0] };
                    out_be = 4'b0011;
                end else begin
                    adjusted_data = { in_data[15:0], 16'b0 };
                    out_be = 4'b1100;
                end
            end
            3'b010: begin // SW, LW we assert that [1:0] bits are zeroes.
                adjusted_data = in_data;
                out_be = 4'b1111;
            end 
            3'b100: begin // LBU
                case(write_address[1:0])
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
            3'b101: begin // LHU, we assert that [0] bit is always zero.
                if(write_address[1] == 1'b0) begin
                    out_be = 4'b0011;
                end else begin
                    out_be = 4'b1100;
                end
                adjusted_data = 32'b0;
            end
            default: begin // Invalid
                adjusted_data = 32'b0;
                out_be = 4'b0;
            end
        endcase
        if(mem_we) begin
            out_data = adjusted_data;
        end else begin
            out_data = 32'b0;
        end
    end
endmodule

module adjust_ip(
    input wire [31:0] instr,
    input wire [31:0] cmp_res, // From ALU, refer to ALU in how it handles JALR.
    input wire has_pred_jump,
    input wire [31:0] curr_ip,
    output reg        take_ip,
    output reg [31:0] new_ip
);
    always_comb begin
        // Branch instructions.
        if(instr[6:0] == 7'b1100011) begin
            if(cmp_res[0] != has_pred_jump) begin
                take_ip = 1'b1;
                if(cmp_res[0] == 1'b1) begin // needs jump, predict no jump
                // https://riscv.org/wp-content/uploads/2017/05/riscv-spec-v2.2.pdf 
                    // p. 17
                    //   31    |  30:25  | 24:20 | 19:15 | 14:12  | 11:8   | 7     | 6:0    |
                    // +------------------+----------+----------+--------+-------+----------+
                    // | i[12] | i[10:5] |  rs2  | rs1   | funct3 | i[4:1] | i[11] | opcode |
                    // +------------------+----------+----------+--------+-------+----------+
                    new_ip = curr_ip + { {19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
                end else begin // predict jump, no jump needed
                    new_ip = curr_ip + 32'd4;
                end
            end else begin
                new_ip = 32'b0;
                take_ip = 1'b0;
            end
            // JALR instruction.
            // Note: ret = JALR, x0, 0(x1) 
            // Remember, in CSAPP, ret has to bubble out everything after it.
            // ISA p. 16
            // https://stackoverflow.com/questions/59150608/offset-address-for-jal-and-jalr-instrctions-in-risc-v
            // Handle jump only, link part is in link_modif.
        end else if(instr[6:0] == 7'b110_0111) begin
            take_ip = 1'b1;
            new_ip = (cmp_res + {{20{instr[31]}}, instr[31:20]}) & ~(32'b1);
        end else begin
            take_ip = 1'b0;
            new_ip = curr_ip + 32'd4;
        end
    end
endmodule

module link_modif(
    input wire [31:0] instr,
    input wire [31:0] curr_ip,
    input wire [31:0] alu_out,
    output reg [31:0] wb_wdata
);
    parameter AUIPC= 32'b????_????_????_????_????_????_?001_0111;
    parameter JAL  = 32'b????_????_????_????_????_????_?110_1111;
    parameter JALR = 32'b????_????_????_????_????_????_?110_0111;
    always_comb begin
        casez(instr)
        AUIPC: begin
            wb_wdata = curr_ip + { instr[31:12], 12'b0 };
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