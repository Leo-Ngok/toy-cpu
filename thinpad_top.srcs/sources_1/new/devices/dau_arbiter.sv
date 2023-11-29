
`timescale 1 ns / 1 ps

module wb_arbiter_4 #
(
    parameter DATA_WIDTH = 32,                    // width of data bus in bits (8, 16, 32, or 64)
    parameter ADDR_WIDTH = 32,                    // width of address bus in bits
    parameter SELECT_WIDTH = (DATA_WIDTH/8),      // width of word select bus (1, 2, 4, or 8)
    parameter ARB_TYPE_ROUND_ROBIN = 0,           // select round robin arbitration
    parameter ARB_LSB_HIGH_PRIORITY = 1           // LSB priority selection
)
(
    input  wire                    clk,
    input  wire                    rst,
    
    /*
     * Wishbone master 0 input
     */
    input  wire [ADDR_WIDTH-1:0]   wbm0_adr_i,    // ADR_I() address input
    input  wire [DATA_WIDTH-1:0]   wbm0_dat_i,    // DAT_I() data in
    output wire [DATA_WIDTH-1:0]   wbm0_dat_o,    // DAT_O() data out
    input  wire                    wbm0_we_i,     // WE_I write enable input
    input  wire [SELECT_WIDTH-1:0] wbm0_sel_i,    // SEL_I() select input
    input  wire                    wbm0_stb_i,    // STB_I strobe input
    output wire                    wbm0_ack_o,    // ACK_O acknowledge output
    output wire                    wbm0_err_o,    // ERR_O error output
    output wire                    wbm0_rty_o,    // RTY_O retry output
    input  wire                    wbm0_cyc_i,    // CYC_I cycle input
    /*
     * Wishbone master 1 input
     */
    input  wire [ADDR_WIDTH-1:0]   wbm1_adr_i,    // ADR_I() address input
    input  wire [DATA_WIDTH-1:0]   wbm1_dat_i,    // DAT_I() data in
    output wire [DATA_WIDTH-1:0]   wbm1_dat_o,    // DAT_O() data out
    input  wire                    wbm1_we_i,     // WE_I write enable input
    input  wire [SELECT_WIDTH-1:0] wbm1_sel_i,    // SEL_I() select input
    input  wire                    wbm1_stb_i,    // STB_I strobe input
    output wire                    wbm1_ack_o,    // ACK_O acknowledge output
    output wire                    wbm1_err_o,    // ERR_O error output
    output wire                    wbm1_rty_o,    // RTY_O retry output
    input  wire                    wbm1_cyc_i,    // CYC_I cycle input
    /*
     * Wishbone master 2 input
     */
    input  wire [ADDR_WIDTH-1:0]   wbm2_adr_i,    // ADR_I() address input
    input  wire [DATA_WIDTH-1:0]   wbm2_dat_i,    // DAT_I() data in
    output wire [DATA_WIDTH-1:0]   wbm2_dat_o,    // DAT_O() data out
    input  wire                    wbm2_we_i,     // WE_I write enable input
    input  wire [SELECT_WIDTH-1:0] wbm2_sel_i,    // SEL_I() select input
    input  wire                    wbm2_stb_i,    // STB_I strobe input
    output wire                    wbm2_ack_o,    // ACK_O acknowledge output
    output wire                    wbm2_err_o,    // ERR_O error output
    output wire                    wbm2_rty_o,    // RTY_O retry output
    input  wire                    wbm2_cyc_i,    // CYC_I cycle input
    /*
     * Wishbone master 3 input
     */
    input  wire [ADDR_WIDTH-1:0]   wbm3_adr_i,    // ADR_I() address input
    input  wire [DATA_WIDTH-1:0]   wbm3_dat_i,    // DAT_I() data in
    output wire [DATA_WIDTH-1:0]   wbm3_dat_o,    // DAT_O() data out
    input  wire                    wbm3_we_i,     // WE_I write enable input
    input  wire [SELECT_WIDTH-1:0] wbm3_sel_i,    // SEL_I() select input
    input  wire                    wbm3_stb_i,    // STB_I strobe input
    output wire                    wbm3_ack_o,    // ACK_O acknowledge output
    output wire                    wbm3_err_o,    // ERR_O error output
    output wire                    wbm3_rty_o,    // RTY_O retry output
    input  wire                    wbm3_cyc_i,    // CYC_I cycle input
    
    /*
     * Wishbone slave output
     */
    output wire [ADDR_WIDTH-1:0]   wbs_adr_o,     // ADR_O() address output
    input  wire [DATA_WIDTH-1:0]   wbs_dat_i,     // DAT_I() data in
    output wire [DATA_WIDTH-1:0]   wbs_dat_o,     // DAT_O() data out
    output wire                    wbs_we_o,      // WE_O write enable output
    output wire [SELECT_WIDTH-1:0] wbs_sel_o,     // SEL_O() select output
    output wire                    wbs_stb_o,     // STB_O strobe output
    input  wire                    wbs_ack_i,     // ACK_I acknowledge input
    input  wire                    wbs_err_i,     // ERR_I error input
    input  wire                    wbs_rty_i,     // RTY_I retry input
    output wire                    wbs_cyc_o      // CYC_O cycle output
);


wire wbm0_sel =   wbm0_cyc_i;
wire wbm1_sel =  (!wbm0_sel) &&  wbm1_cyc_i;
wire wbm2_sel =  (!wbm1_sel) &&  wbm2_cyc_i;
wire wbm3_sel =  (!wbm2_sel) &&  wbm3_cyc_i;
// ======================================================

// master 0 =========================================
assign wbm0_dat_o = wbs_dat_i;
assign wbm0_ack_o = wbs_ack_i & wbm0_sel;
assign wbm0_err_o = wbs_err_i & wbm0_sel;
assign wbm0_rty_o = wbs_rty_i & wbm0_sel;
// master 1 =========================================
assign wbm1_dat_o = wbs_dat_i;
assign wbm1_ack_o = wbs_ack_i & wbm1_sel;
assign wbm1_err_o = wbs_err_i & wbm1_sel;
assign wbm1_rty_o = wbs_rty_i & wbm1_sel;
// master 2 =========================================
assign wbm2_dat_o = wbs_dat_i;
assign wbm2_ack_o = wbs_ack_i & wbm2_sel;
assign wbm2_err_o = wbs_err_i & wbm2_sel;
assign wbm2_rty_o = wbs_rty_i & wbm2_sel;
// master 3 =========================================
assign wbm3_dat_o = wbs_dat_i;
assign wbm3_ack_o = wbs_ack_i & wbm3_sel;
assign wbm3_err_o = wbs_err_i & wbm3_sel;
assign wbm3_rty_o = wbs_rty_i & wbm3_sel;

                       

// ======================================================
reg [ADDR_WIDTH - 1:0] wbs_adr_o_c;
reg [DATA_WIDTH - 1:0] wbs_dat_o_c;
reg        wbs_we_o_c;
reg [SELECT_WIDTH - 1:0] wbs_sel_o_c;
reg        wbs_stb_o_c;
reg        wbs_cyc_o_c;
always_comb begin
    wbs_adr_o_c = {ADDR_WIDTH{1'b0}};
    wbs_dat_o_c = {DATA_WIDTH{1'b0}};
    wbs_we_o_c = 1'b0;
    wbs_sel_o_c = {SELECT_WIDTH{1'b0}};
    wbs_stb_o_c = 1'b0;
    wbs_cyc_o_c = 1'b0;
    
      if(wbm0_sel) begin
        wbs_adr_o_c = wbm0_adr_i;
        wbs_dat_o_c = wbm0_dat_i;
        wbs_we_o_c = wbm0_we_i;
        wbs_sel_o_c = wbm0_sel_i;
        wbs_stb_o_c = wbm0_stb_i;
        wbs_cyc_o_c = wbm0_cyc_i;
    end
     else  if(wbm1_sel) begin
        wbs_adr_o_c = wbm1_adr_i;
        wbs_dat_o_c = wbm1_dat_i;
        wbs_we_o_c = wbm1_we_i;
        wbs_sel_o_c = wbm1_sel_i;
        wbs_stb_o_c = wbm1_stb_i;
        wbs_cyc_o_c = wbm1_cyc_i;
    end
     else  if(wbm2_sel) begin
        wbs_adr_o_c = wbm2_adr_i;
        wbs_dat_o_c = wbm2_dat_i;
        wbs_we_o_c = wbm2_we_i;
        wbs_sel_o_c = wbm2_sel_i;
        wbs_stb_o_c = wbm2_stb_i;
        wbs_cyc_o_c = wbm2_cyc_i;
    end
     else  if(wbm3_sel) begin
        wbs_adr_o_c = wbm3_adr_i;
        wbs_dat_o_c = wbm3_dat_i;
        wbs_we_o_c = wbm3_we_i;
        wbs_sel_o_c = wbm3_sel_i;
        wbs_stb_o_c = wbm3_stb_i;
        wbs_cyc_o_c = wbm3_cyc_i;
    end   
end                                
// slave
assign wbs_adr_o = wbs_adr_o_c;
assign wbs_dat_o = wbs_dat_o_c;
assign wbs_we_o = wbs_we_o_c;
assign wbs_sel_o = wbs_sel_o_c;
assign wbs_stb_o = wbs_stb_o_c;
assign wbs_cyc_o = wbs_cyc_o_c;
endmodule