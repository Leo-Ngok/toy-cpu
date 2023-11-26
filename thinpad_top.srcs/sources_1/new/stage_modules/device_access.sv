module mem_data_recv_adjust(
    input wire [31:0] instr,
    input wire [31:0] mem_addr,
    input wire [31:0] data_i,
    output reg [31:0] data_o
);
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
    always_comb begin
        casez(instr)
        LB: begin
            case(mem_addr[1:0])
            2'b00: data_o = { {24{data_i[ 7]}}, data_i[ 7: 0] };
            2'b01: data_o = { {24{data_i[15]}}, data_i[15: 8] };
            2'b10: data_o = { {24{data_i[23]}}, data_i[23:16] };
            2'b11: data_o = { {24{data_i[31]}}, data_i[31:24] };
            endcase
        end
        LBU: begin
            case(mem_addr[1:0])
            2'b00: data_o = { {24{1'b0}}, data_i[ 7: 0] };
            2'b01: data_o = { {24{1'b0}}, data_i[15: 8] };
            2'b10: data_o = { {24{1'b0}}, data_i[23:16] };
            2'b11: data_o = { {24{1'b0}}, data_i[31:24] };
            endcase
        end
        LH: begin
            case(mem_addr[1])
            1'b0: data_o = { { 16{data_i[15]} }, data_i[15: 0] };
            1'b1: data_o = { { 16{data_i[31]} }, data_i[31:16] };
            endcase
        end
        LHU: begin
            case(mem_addr[1])
            1'b0: data_o = { { 16{1'b0} }, data_i[15: 0] };
            1'b1: data_o = { { 16{1'b0} }, data_i[31:16] };
            endcase
        end
        LW: begin
            data_o = data_i;
        end
        default: begin
            data_o = 32'b0;
        end
        endcase
    end
endmodule

module rf_write_data_mux(
    input wire rf_we,
    input wire mem_re,
    input wire csr_acc,

    input wire [31:0] alu_data,
    input wire [31:0] mem_data,
    input wire [31:0] csr_data, 

    output reg [31:0] out_data
);
    always_comb begin
        if(rf_we) begin
            if(mem_re) begin
                out_data = mem_data;
            end else if(csr_acc) begin
                out_data = csr_data;
            end else begin
                out_data = alu_data;
            end
        end else begin
            out_data = 32'b0;
        end
    end
endmodule

module devacc_pause(
    input wire [31:0] mem_instr,
    input wire dau_ack,
    input wire dau_cache_clear,
    input wire dau_cache_clear_complete,
    output reg pause_o
);

    parameter LOAD_STORE = 32'b????_????_????_????_????_????_?0?0_0011;
    parameter LOAD = 32'b????_????_????_????_????_????_?000_0011;
    parameter STORE= 32'b????_????_????_????_????_????_?010_0011;
    
    always_comb begin
        if(mem_instr[6:0] == 7'b000_0011 || mem_instr[6:0] == 7'b010_0011) begin
            pause_o = ~dau_ack;
        end else if(dau_cache_clear) begin
            pause_o = ~dau_cache_clear_complete;
        end else begin
            pause_o = 1'b0;
        end
    end
endmodule    
