`default_nettype none
module register_file(clock, reset, 
    read_addr1, read_data1,         // comb
    read_addr2, read_data2,         // comb
    we, write_addr, write_data);    // seq

    parameter WIDTH = 16;
    parameter N_REGS = 32;
    parameter LG_N_REGS = 5;

    input wire clock;
    input wire reset;

    input wire [LG_N_REGS - 1: 0] read_addr1;
    output reg [WIDTH - 1 : 0]    read_data1;

    input wire [LG_N_REGS - 1: 0] read_addr2;
    output reg [WIDTH - 1 : 0]    read_data2;

    input wire we;
    input wire [LG_N_REGS - 1: 0] write_addr;
    input wire [WIDTH - 1 : 0]    write_data;

    reg[WIDTH - 1 : 0] registers [N_REGS - 1: 0];

    always @(*) begin
        if(reset == 1'b1) begin
            read_data1 = {WIDTH{1'b0}};
        end else if(read_addr1 == 5'b0) begin
            read_data1 = {WIDTH{1'b0}}; // x0 is always zero.
        end else begin
            read_data1 = registers[read_addr1];
        end
    end

    always @(*) begin
        if(reset == 1'b1) begin
            read_data2 = {WIDTH{1'b0}};
        end else if(read_addr2 == 5'b0) begin
            read_data2 = {WIDTH{1'b0}}; // x0 is always zero.
        end else begin
            read_data2 = registers[read_addr2];
        end
    end

    always @(posedge clock) begin
        if(reset == 1'b0) begin
            if(we == 1'b1 && write_addr != 5'b0) begin
                registers[write_addr] <= write_data;
            end
        end else begin
            int i;
            for(i = 0; i < 32; ++i) begin
                registers[i] <= {WIDTH{1'b0}};
            end
        end
    end 

endmodule