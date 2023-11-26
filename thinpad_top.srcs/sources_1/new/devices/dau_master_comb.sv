module dau_master_comb #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter BASE_START = 32'h8000_0000,
    parameter  EXT_START = 32'h8040_0000,
    parameter UART_START = 32'h1000_0000,
    
    parameter UART_STATUS_ADDR = 32'h1000_0005,
    parameter UART_DATA_ADDR   = 32'h1000_0000,
    parameter UART_STATUS_SEL = 4'b0010,
    parameter UART_DATA_SEL   = 4'b0001
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
    assign data_o = wb_dat_i;
    assign ack_o = wb_ack_i;

    assign wb_cyc_o = we || re;
    assign wb_stb_o = we || re;
    assign wb_adr_o = addr;
    assign wb_dat_o = data_i;
    assign wb_sel_o = byte_en;
    assign wb_we_o = we && (!re);
endmodule