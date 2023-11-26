module clint #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) (
    // clk and reset
    input wire clk_i,
    input wire rst_i,

    // wishbone slave interface
    input  wire                    wb_cyc_i,
    input  wire                    wb_stb_i,
    output wire                    wb_ack_o,
    input  wire [ADDR_WIDTH-1:0]   wb_adr_i,
    input  wire [DATA_WIDTH-1:0]   wb_dat_i,
    output wire [DATA_WIDTH-1:0]   wb_dat_o,
    input  wire [DATA_WIDTH/8-1:0] wb_sel_i,
    input  wire                    wb_we_i,

    // notify interrupt happens.
    output wire                     intr
);
    

    reg [63:0] mtime;
    reg [63:0] mtimecmp;

    always_ff @(posedge clk_i or posedge rst_i) begin
        if(rst_i) begin
            mtime <= 64'b0;
            mtimecmp <= 64'b0;
        end else begin
            
            if(wb_cyc_i && wb_stb_i && wb_we_i && wb_adr_i == 32'h0200_4000) begin
                mtimecmp[31:0] <= wb_dat_i;
            end
            if(wb_cyc_i && wb_stb_i && wb_we_i && wb_adr_i == 32'h0200_4004) begin
                mtimecmp[63:32] <= wb_dat_i;
            end
            if(wb_cyc_i && wb_stb_i && wb_we_i && wb_adr_i == 32'h0200_BFF8) begin
                mtime[31:0] <= wb_dat_i;
            end else if(wb_cyc_i && wb_stb_i && wb_we_i && wb_adr_i == 32'h0200_BFFC) begin
                mtime[63:32] <= wb_dat_i;
            end else begin
                mtime <= mtime + 1;
            end
        end
    end

    assign intr = mtime >= mtimecmp;
    reg [31:0] read_out;
    always_comb begin
        read_out = 32'b0;
        if(wb_cyc_i && wb_stb_i && !wb_we_i) begin
            case(wb_adr_i) 
            32'h0200_4000: read_out = mtimecmp[31:0];
            32'h0200_4004: read_out = mtimecmp[63:32];
            32'h0200_BFF8: read_out = mtime[31:0];
            32'h0200_BFFC: read_out = mtime[63:32];
            endcase
        end
    end
    assign wb_dat_o = read_out;
    assign wb_ack_o = wb_cyc_i && wb_stb_i;
endmodule