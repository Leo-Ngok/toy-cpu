#!/usr/bin/env python
"""
Generates a unified device access unit with instruction and data devices to control unit.
"""

from __future__ import print_function

import argparse
import math
from jinja2 import Template
from typing import Optional
def main():
    parser = argparse.ArgumentParser(description=__doc__.strip())
    parser.add_argument('-m', '--masters', type=int, default=2, help="number of master devices.")
    parser.add_argument('-d', '--devices',  type=int, default=3, help="number of external devices.")
    parser.add_argument('-n', '--name',   type=str, help="module name")
    parser.add_argument('-o', '--output', type=str, help="output file name")
    
    args = parser.parse_args()

    try:
        generate(**args.__dict__)
    except IOError as ex:
        print(ex)
        exit(1)

def generate(output:str, masters = 2, devices=3,  name:Optional[str]=None):
    if name is None:
        name = "dau_{0}".format(devices)

    print("Opening file '{0}'...".format(output))


    print(f"Generating {devices} devices DAU with {masters} masters. {name}...")

    select_width = int(math.ceil(math.log(devices, 2)))

    t = Template(u"""
/*
{{name}} {{name}}_inst(
    .sys_clk(),
    .sys_rst(),
    {% for k in masters %}

    .master{{k}}_we_i(),
    .master{{k}}_re_i(),
    .master{{k}}_adr_i(),
    .master{{k}}_sel_i(),
    .master{{k}}_dat_i(),
    .master{{k}}_ack_o(),
    .master{{k}}_dat_o(),
    {%- endfor %}
);
*/
`timescale 1 ns / 1 ps

module {{name}} (
    input wire sys_clk,
    input wire sys_rst,

    {% for k in masters %}
    
    input  wire        master{{k}}_we_i,
    input  wire        master{{k}}_re_i,
    input  wire [31:0] master{{k}}_adr_i,
    input  wire [ 3:0] master{{k}}_sel_i,
    input  wire [31:0] master{{k}}_dat_i,
    output wire        master{{k}}_ack_o,
    output wire [31:0] master{{k}}_dat_o,

    {%- endfor %}

    // Interface to External device
    /* Add desired interfaces here, such as UART, SRAM, Flash, ... */
);
   // This module could be illustrated as the diagram below.

   // +-------------+    +--------+        +---------------+   +------------------+
   // | instruction | ---| i-mux  |+-+-----| Ext arbiter 1 |---| Ext controller 1 |
   // +-------------+    +--------+  |  +--|               |   |    (slave)       |
   //                                |  |  +---------------+   +------------------+
   //                                |  |  +---------------+   +------------------+
   //                                +-----| Ext arbiter 2 |---| Ext controller 2 |
   //                                |  +--|               |   |     (slave)      |
   //                                |  |  +---------------+   +------------------+
   //                                |  |  +---------------+   +------------------+
   // +-------------+    +--------+  +-----| Ext arbiter 3 |---| Ext controller 3 |
   // | data        | ---| d-mux  |--|--+--|               |   |     (slave)      |
   // +-------------+    +--------+  |  |  +---------------+   +------------------+
   //                                |  |        ...                ...

    wire [{{m-1}}:0]       wbm_cyc_o;
    wire [{{m-1}}:0]       wbm_stb_o;
    wire [{{m-1}}:0]       wbm_ack_i;
    wire [{{m-1}}:0][31:0] wbm_adr_o;
    wire [{{m-1}}:0][31:0] wbm_dat_o;
    wire [{{m-1}}:0][31:0] wbm_dat_i;
    wire [{{m-1}}:0][ 3:0] wbm_sel_o;
    wire [{{m-1}}:0]       wbm_we_o;

    // dau_master -- For Data part
    {% for k in masters %}
    dau_master_comb #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) master_{{k}} (
        .clk_i(sys_clk),
        .rst_i(sys_rst),

        // Interface to control unit
        .we     (master{{k}}_we_i),
        .re     (master{{k}}_re_i),
        .addr   (master{{k}}_adr_i),
        .byte_en(master{{k}}_sel_i),
        .data_i (master{{k}}_dat_i),
        .data_o (master{{k}}_dat_o),
        .ack_o  (master{{k}}_ack_o),
        
        // wishbone master
        .wb_cyc_o(wbm_cyc_o[{{k}}]),
        .wb_stb_o(wbm_stb_o[{{k}}]),
        .wb_ack_i(wbm_ack_i[{{k}}]),
        .wb_adr_o(wbm_adr_o[{{k}}]),
        .wb_dat_o(wbm_dat_o[{{k}}]),
        .wb_dat_i(wbm_dat_i[{{k}}]),
        .wb_sel_o(wbm_sel_o[{{k}}]),
        .wb_we_o (wbm_we_o[{{k}}])
    );

    {%- endfor %}
    /* =========== Master end =========== */
    parameter [31:0] slave_base[{{n-1}}:0] = { {% for k in devices %}
    32'h0{% if not loop.last %},{% else %} {% endif %}
    {%- endfor %}           
    };
    
    parameter [31:0] slave_mask[{{n-1}}:0] = { {% for k in devices %}
    32'hFFFF_FFFF{% if not loop.last %},{% else %} {% endif %}
    {%- endfor %}           
    };
    /* =========== MUX for Instruction begin =========== */
                 
    wire [{{m-1}}:0][{{n-1}}:0]       mux_arb_cyc_o;
    wire [{{m-1}}:0][{{n-1}}:0]       mux_arb_stb_o;
    wire [{{m-1}}:0][{{n-1}}:0]       mux_arb_ack_i;
    wire [{{m-1}}:0][{{n-1}}:0][31:0] mux_arb_adr_o;
    wire [{{m-1}}:0][{{n-1}}:0][31:0] mux_arb_dat_o;
    wire [{{m-1}}:0][{{n-1}}:0][31:0] mux_arb_dat_i;
    wire [{{m-1}}:0][{{n-1}}:0][ 3:0] mux_arb_sel_o;
    wire [{{m-1}}:0][{{n-1}}:0]       mux_arb_we_o;
    genvar ii;
    generate
    for(ii = 0; ii < {{m}}; ii++) begin : bus_mux
        device_access_mux mux(
            .clk(sys_clk),
            .rst(sys_rst),
                 
            .wbm_adr_i(wbm_adr_o[ii]),
            .wbm_dat_i(wbm_dat_o[ii]),
            .wbm_dat_o(wbm_dat_i[ii]),
            .wbm_we_i (wbm_we_o[ii]),
            .wbm_sel_i(wbm_sel_o[ii]),
            .wbm_stb_i(wbm_stb_o[ii]),
            .wbm_ack_o(wbm_ack_i[ii]),
            .wbm_err_o(),
            .wbm_rty_o(),
            .wbm_cyc_i(wbm_cyc_o[ii]),
            
            {% for p in devices %}
            // Slave interface {{p}}
            .wbs{{p}}_addr    (slave_base[{{p}}]),
            .wbs{{p}}_addr_msk(slave_mask[{{p}}]),

            .wbs{{p}}_adr_o(mux_arb_adr_o[ii][{{p}}]),
            .wbs{{p}}_dat_i(mux_arb_dat_i[ii][{{p}}]),
            .wbs{{p}}_dat_o(mux_arb_dat_o[ii][{{p}}]),
            .wbs{{p}}_we_o (mux_arb_we_o[ii][{{p}}]),
            .wbs{{p}}_sel_o(mux_arb_sel_o[ii][{{p}}]),
            .wbs{{p}}_stb_o(mux_arb_stb_o[ii][{{p}}]),
            .wbs{{p}}_ack_i(mux_arb_ack_i[ii][{{p}}]),
            .wbs{{p}}_err_i('0),
            .wbs{{p}}_rty_i('0),
            .wbs{{p}}_cyc_o(mux_arb_cyc_o[ii][{{p}}]) {% if not loop.last %},{% else %} {% endif %}

            {%- endfor %}
        );
    end
    endgenerate
    /* =========== Slaves begin =========== */
    // 1. The arbiters
    wire [{{n-1}}:0]       wbs_cyc_o;
    wire [{{n-1}}:0]       wbs_stb_o;
    wire [{{n-1}}:0]       wbs_ack_i;
    wire [{{n-1}}:0][31:0] wbs_adr_o;
    wire [{{n-1}}:0][31:0] wbs_dat_o;
    wire [{{n-1}}:0][31:0] wbs_dat_i;
    wire [{{n-1}}:0][ 3:0] wbs_sel_o;
    wire [{{n-1}}:0]       wbs_we_o;
    genvar jj;
    generate
    for(jj = 0; jj < {{n}}; ++jj) begin : gen_arbiter
    wb_arbiter_{{m}} arbiter_{{p}}(
        .clk(sys_clk),
        .rst(sys_rst),
    {% for k in masters %}
        /*
        * Wishbone master {{k}} input
        */
        .wbm{{k}}_adr_i(mux_arb_adr_o[{{k}}][jj]),
        .wbm{{k}}_dat_i(mux_arb_dat_o[{{k}}][jj]),
        .wbm{{k}}_dat_o(mux_arb_dat_i[{{k}}][jj]),
        .wbm{{k}}_we_i (mux_arb_we_o[{{k}}][jj]),
        .wbm{{k}}_sel_i(mux_arb_sel_o[{{k}}][jj]),
        .wbm{{k}}_stb_i(mux_arb_stb_o[{{k}}][jj]),
        .wbm{{k}}_ack_o(mux_arb_ack_i[{{k}}][jj]),
        .wbm{{k}}_err_o(),
        .wbm{{k}}_rty_o(),
        .wbm{{k}}_cyc_i(mux_arb_cyc_o[{{k}}][jj]),
                 
    {%- endfor %}
    /*
     * Wishbone slave output
     */
     .wbs_adr_o(wbs_adr_o[jj]),
     .wbs_dat_i(wbs_dat_i[jj]),
     .wbs_dat_o(wbs_dat_o[jj]),
     .wbs_we_o (wbs_we_o[jj]),
     .wbs_sel_o(wbs_sel_o[jj]),
     .wbs_stb_o(wbs_stb_o[jj]),
     .wbs_ack_i(wbs_ack_i[jj]),
     .wbs_err_i(1'b0),
     .wbs_rty_i(1'b0),
     .wbs_cyc_o(wbs_cyc_o[jj])
    );
    end
    endgenerate

    // 2. The controllers

    {% for p in devices %}
    /* TODO: Module name */ #(
        /* TODO: parameters*/
    ) /* TODO: Instance name */ (
        .clk_i(sys_clk),
        .rst_i(sys_rst),

        // Wishbone slave (to MUX)
        .wb_cyc_i(wbs_cyc_o[{{p}}]),
        .wb_stb_i(wbs_stb_o[{{p}}]),
        .wb_ack_o(wbs_ack_i[{{p}}]),
        .wb_adr_i(wbs_adr_o[{{p}}]),
        .wb_dat_i(wbs_dat_o[{{p}}]),
        .wb_dat_o(wbs_dat_i[{{p}}]),
        .wb_sel_i(wbs_sel_o[{{p}}]),
        .wb_we_i (wbs_we_o[{{p}}]),

        /* TODO: Other ports in interest. */
    );

{%- endfor %}
endmodule

""")
    arb_tmp = Template(u"""
`timescale 1 ns / 1 ps

module wb_arbiter_{{m}} #
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
    {% for k in masters %}
    /*
     * Wishbone master {{k}} input
     */
    input  wire [ADDR_WIDTH-1:0]   wbm{{k}}_adr_i,    // ADR_I() address input
    input  wire [DATA_WIDTH-1:0]   wbm{{k}}_dat_i,    // DAT_I() data in
    output wire [DATA_WIDTH-1:0]   wbm{{k}}_dat_o,    // DAT_O() data out
    input  wire                    wbm{{k}}_we_i,     // WE_I write enable input
    input  wire [SELECT_WIDTH-1:0] wbm{{k}}_sel_i,    // SEL_I() select input
    input  wire                    wbm{{k}}_stb_i,    // STB_I strobe input
    output wire                    wbm{{k}}_ack_o,    // ACK_O acknowledge output
    output wire                    wbm{{k}}_err_o,    // ERR_O error output
    output wire                    wbm{{k}}_rty_o,    // RTY_O retry output
    input  wire                    wbm{{k}}_cyc_i,    // CYC_I cycle input
                       
    {%- endfor %}
    
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

{% for k in masters %}
wire wbm{{k}}_sel = {% if k != 0 %} (!wbm{{k-1}}_sel) && {% else %} {% endif %} wbm{{k}}_cyc_i;
{%- endfor %}
// ======================================================
{% for k in masters %}
// master {{k}} =========================================
assign wbm{{k}}_dat_o = wbs_dat_i;
assign wbm{{k}}_ack_o = wbs_ack_i & wbm{{k}}_sel;
assign wbm{{k}}_err_o = wbs_err_i & wbm{{k}}_sel;
assign wbm{{k}}_rty_o = wbs_rty_i & wbm{{k}}_sel;
{%- endfor %}

                       

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
    {% for k in masters %}
    {% if k != 0 %} else {% else %} {% endif %} if(wbm{{k}}_sel) begin
        wbs_adr_o_c = wbm{{k}}_adr_i;
        wbs_dat_o_c = wbm{{k}}_dat_i;
        wbs_we_o_c = wbm{{k}}_we_i;
        wbs_sel_o_c = wbm{{k}}_sel_i;
        wbs_stb_o_c = wbm{{k}}_stb_i;
        wbs_cyc_o_c = wbm{{k}}_cyc_i;
    end
    {%- endfor %}   
end                                
// slave
assign wbs_adr_o = wbs_adr_o_c;
assign wbs_dat_o = wbs_dat_o_c;
assign wbs_we_o = wbs_we_o_c;
assign wbs_sel_o = wbs_sel_o_c;
assign wbs_stb_o = wbs_stb_o_c;
assign wbs_cyc_o = wbs_cyc_o_c;
endmodule
""")
    


    with open(f"{output}_bus.sv", 'w') as output_file:
        output_file.write(t.render(
            n=devices,
            m=masters,
            w=select_width,
            name=name,
            devices=range(devices),
            masters=range(masters)
        ))
        
    
    with open(f"{output}_arbiter.sv", 'w') as output_file:
        output_file.write(arb_tmp.render(
            n=devices,
            m=masters,
            w=select_width,
            name=name,
            devices=range(devices),
            masters=range(masters)
        ))

    print("Done")

if __name__ == "__main__":
    main()

