
/*
dau_new dau_new_inst(
    .sys_clk(),
    .sys_rst(),
    

    .master0_we_i(),
    .master0_re_i(),
    .master0_adr_i(),
    .master0_sel_i(),
    .master0_dat_i(),
    .master0_ack_o(),
    .master0_dat_o(),

    .master1_we_i(),
    .master1_re_i(),
    .master1_adr_i(),
    .master1_sel_i(),
    .master1_dat_i(),
    .master1_ack_o(),
    .master1_dat_o(),

    .master2_we_i(),
    .master2_re_i(),
    .master2_adr_i(),
    .master2_sel_i(),
    .master2_dat_i(),
    .master2_ack_o(),
    .master2_dat_o(),

    .master3_we_i(),
    .master3_re_i(),
    .master3_adr_i(),
    .master3_sel_i(),
    .master3_dat_i(),
    .master3_ack_o(),
    .master3_dat_o(),
);
*/
`timescale 1 ns / 1 ps

module dau_new (
    input wire sys_clk,
    input wire sys_rst,

    input  wire        master0_we_i,
    input  wire        master0_re_i,
    input  wire [31:0] master0_adr_i,
    input  wire [ 3:0] master0_sel_i,
    input  wire [31:0] master0_dat_i,
    output wire        master0_ack_o,
    output wire [31:0] master0_dat_o,

    input  wire        master1_we_i,
    input  wire        master1_re_i,
    input  wire [31:0] master1_adr_i,
    input  wire [ 3:0] master1_sel_i,
    input  wire [31:0] master1_dat_i,
    output wire        master1_ack_o,
    output wire [31:0] master1_dat_o,

    input  wire        master2_we_i,
    input  wire        master2_re_i,
    input  wire [31:0] master2_adr_i,
    input  wire [ 3:0] master2_sel_i,
    input  wire [31:0] master2_dat_i,
    output wire        master2_ack_o,
    output wire [31:0] master2_dat_o,

    input  wire        master3_we_i,
    input  wire        master3_re_i,
    input  wire [31:0] master3_adr_i,
    input  wire [ 3:0] master3_sel_i,
    input  wire [31:0] master3_dat_i,
    output wire        master3_ack_o,
    output wire [31:0] master3_dat_o,

    // Interface to External device

    // UART
    input  wire rxd,
    output wire txd,

    // BaseRAM
    inout wire [31:0] base_ram_data,  // BaseRAM 数据，低 8 位与 CPLD 串口控制器共享
    output wire [19:0] base_ram_addr,  // BaseRAM 地址
    output wire [ 3:0] base_ram_be_n,  // BaseRAM 字节使能，低有效。如果不使用字节使能，请保持为 0
    output wire base_ram_ce_n,  // BaseRAM 片选，低有效
    output wire base_ram_oe_n,  // BaseRAM 读使能，低有效
    output wire base_ram_we_n,  // BaseRAM 写使能，低有效

    // ExtRAM
    inout wire [31:0] ext_ram_data,  // ExtRAM 数据
    output wire [19:0] ext_ram_addr,  // ExtRAM 地址
    output wire [ 3:0] ext_ram_be_n,  // ExtRAM 字节使能，低有效。如果不使用字节使能，请保持为 0
    output wire ext_ram_ce_n,  // ExtRAM 片选，低有效
    output wire ext_ram_oe_n,  // ExtRAM 读使能，低有效
    output wire ext_ram_we_n,  // ExtRAM 写使能，低有效

    // Flash 存储器信号，参考 JS28F640 芯片手册
    output wire [22:0] flash_a,  // Flash 地址，a0 仅在 8bit 模式有效，16bit 模式无意义
    inout wire [15:0] flash_d,  // Flash 数据
    output wire flash_rp_n,  // Flash 复位信号，低有效
    output wire flash_vpen,  // Flash 写保护信号，低电平时不能擦除、烧写
    output wire flash_ce_n,  // Flash 片选信号，低有效
    output wire flash_oe_n,  // Flash 读使能信号，低有效
    output wire flash_we_n,  // Flash 写使能信号，低有效
    output wire flash_byte_n, // Flash 8bit 模式选择，低有效。在使用 flash 的 16 位模式时请设为 1

    // VGA
    input  wire [11:0] vga_hdata,
    input  wire [ 9:0] vga_vdata,
    input  wire        vga_hsync,
    input  wire        vga_vsync,
    input  wire        vga_video_de,
    output reg [7:0] pixel, // VGA 输出像素数据
    input wire clk_50M,
    
    // CLINT interrupt signal
    output wire        local_intr
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

  wire [3:0]       wbm_cyc_o;
  wire [3:0]       wbm_stb_o;
  wire [3:0]       wbm_ack_i;
  wire [3:0][31:0] wbm_adr_o;
  wire [3:0][31:0] wbm_dat_o;
  wire [3:0][31:0] wbm_dat_i;
  wire [3:0][ 3:0] wbm_sel_o;
  wire [3:0]       wbm_we_o;

  // dau_master -- For Data part

  dau_master_comb #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32)
  ) master_0 (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Interface to control unit
      .we     (master0_we_i),
      .re     (master0_re_i),
      .addr   (master0_adr_i),
      .byte_en(master0_sel_i),
      .data_i (master0_dat_i),
      .data_o (master0_dat_o),
      .ack_o  (master0_ack_o),

      // wishbone master
      .wb_cyc_o(wbm_cyc_o[0]),
      .wb_stb_o(wbm_stb_o[0]),
      .wb_ack_i(wbm_ack_i[0]),
      .wb_adr_o(wbm_adr_o[0]),
      .wb_dat_o(wbm_dat_o[0]),
      .wb_dat_i(wbm_dat_i[0]),
      .wb_sel_o(wbm_sel_o[0]),
      .wb_we_o (wbm_we_o[0])
  );
  dau_master_comb #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32)
  ) master_1 (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Interface to control unit
      .we     (master1_we_i),
      .re     (master1_re_i),
      .addr   (master1_adr_i),
      .byte_en(master1_sel_i),
      .data_i (master1_dat_i),
      .data_o (master1_dat_o),
      .ack_o  (master1_ack_o),

      // wishbone master
      .wb_cyc_o(wbm_cyc_o[1]),
      .wb_stb_o(wbm_stb_o[1]),
      .wb_ack_i(wbm_ack_i[1]),
      .wb_adr_o(wbm_adr_o[1]),
      .wb_dat_o(wbm_dat_o[1]),
      .wb_dat_i(wbm_dat_i[1]),
      .wb_sel_o(wbm_sel_o[1]),
      .wb_we_o (wbm_we_o[1])
  );
  dau_master_comb #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32)
  ) master_2 (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Interface to control unit
      .we     (master2_we_i),
      .re     (master2_re_i),
      .addr   (master2_adr_i),
      .byte_en(master2_sel_i),
      .data_i (master2_dat_i),
      .data_o (master2_dat_o),
      .ack_o  (master2_ack_o),

      // wishbone master
      .wb_cyc_o(wbm_cyc_o[2]),
      .wb_stb_o(wbm_stb_o[2]),
      .wb_ack_i(wbm_ack_i[2]),
      .wb_adr_o(wbm_adr_o[2]),
      .wb_dat_o(wbm_dat_o[2]),
      .wb_dat_i(wbm_dat_i[2]),
      .wb_sel_o(wbm_sel_o[2]),
      .wb_we_o (wbm_we_o[2])
  );
  dau_master_comb #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32)
  ) master_3 (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Interface to control unit
      .we     (master3_we_i),
      .re     (master3_re_i),
      .addr   (master3_adr_i),
      .byte_en(master3_sel_i),
      .data_i (master3_dat_i),
      .data_o (master3_dat_o),
      .ack_o  (master3_ack_o),

      // wishbone master
      .wb_cyc_o(wbm_cyc_o[3]),
      .wb_stb_o(wbm_stb_o[3]),
      .wb_ack_i(wbm_ack_i[3]),
      .wb_adr_o(wbm_adr_o[3]),
      .wb_dat_o(wbm_dat_o[3]),
      .wb_dat_i(wbm_dat_i[3]),
      .wb_sel_o(wbm_sel_o[3]),
      .wb_we_o (wbm_we_o[3])
  );
  /* =========== Master end =========== */
  parameter [31:0] slave_base[0:5] = {
    32'h8000_0000, 32'h8040_0000, 32'h1000_0000, 32'h0200_0000, 32'h2000_0000, 32'h3000_0000
  };

  parameter [31:0] slave_mask[0:5] = {
    32'hFFC0_0000, 32'hFFC0_0000, 32'hFFFF_0000, 32'hFFFF_0000, 32'hFF80_0000, 32'hFFF0_0000
  };
  /* =========== MUX for Instruction begin =========== */

  wire [3:0][5:0]       mux_arb_cyc_o;
  wire [3:0][5:0]       mux_arb_stb_o;
  wire [3:0][5:0]       mux_arb_ack_i;
  wire [3:0][5:0][31:0] mux_arb_adr_o;
  wire [3:0][5:0][31:0] mux_arb_dat_o;
  wire [3:0][5:0][31:0] mux_arb_dat_i;
  wire [3:0][5:0][ 3:0] mux_arb_sel_o;
  wire [3:0][5:0]       mux_arb_we_o;
  genvar ii;
  generate
    for (ii = 0; ii < 4; ii++) begin : bus_mux
      device_access_mux mux (
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


          // Slave interface 0
          .wbs0_addr    (slave_base[0]),
          .wbs0_addr_msk(slave_mask[0]),

          .wbs0_adr_o   (mux_arb_adr_o[ii][0]),
          .wbs0_dat_i   (mux_arb_dat_i[ii][0]),
          .wbs0_dat_o   (mux_arb_dat_o[ii][0]),
          .wbs0_we_o    (mux_arb_we_o[ii][0]),
          .wbs0_sel_o   (mux_arb_sel_o[ii][0]),
          .wbs0_stb_o   (mux_arb_stb_o[ii][0]),
          .wbs0_ack_i   (mux_arb_ack_i[ii][0]),
          .wbs0_err_i   ('0),
          .wbs0_rty_i   ('0),
          .wbs0_cyc_o   (mux_arb_cyc_o[ii][0]),
          // Slave interface 1
          .wbs1_addr    (slave_base[1]),
          .wbs1_addr_msk(slave_mask[1]),

          .wbs1_adr_o   (mux_arb_adr_o[ii][1]),
          .wbs1_dat_i   (mux_arb_dat_i[ii][1]),
          .wbs1_dat_o   (mux_arb_dat_o[ii][1]),
          .wbs1_we_o    (mux_arb_we_o[ii][1]),
          .wbs1_sel_o   (mux_arb_sel_o[ii][1]),
          .wbs1_stb_o   (mux_arb_stb_o[ii][1]),
          .wbs1_ack_i   (mux_arb_ack_i[ii][1]),
          .wbs1_err_i   ('0),
          .wbs1_rty_i   ('0),
          .wbs1_cyc_o   (mux_arb_cyc_o[ii][1]),
          // Slave interface 2
          .wbs2_addr    (slave_base[2]),
          .wbs2_addr_msk(slave_mask[2]),

          .wbs2_adr_o   (mux_arb_adr_o[ii][2]),
          .wbs2_dat_i   (mux_arb_dat_i[ii][2]),
          .wbs2_dat_o   (mux_arb_dat_o[ii][2]),
          .wbs2_we_o    (mux_arb_we_o[ii][2]),
          .wbs2_sel_o   (mux_arb_sel_o[ii][2]),
          .wbs2_stb_o   (mux_arb_stb_o[ii][2]),
          .wbs2_ack_i   (mux_arb_ack_i[ii][2]),
          .wbs2_err_i   ('0),
          .wbs2_rty_i   ('0),
          .wbs2_cyc_o   (mux_arb_cyc_o[ii][2]),
          // Slave interface 3
          .wbs3_addr    (slave_base[3]),
          .wbs3_addr_msk(slave_mask[3]),

          .wbs3_adr_o   (mux_arb_adr_o[ii][3]),
          .wbs3_dat_i   (mux_arb_dat_i[ii][3]),
          .wbs3_dat_o   (mux_arb_dat_o[ii][3]),
          .wbs3_we_o    (mux_arb_we_o[ii][3]),
          .wbs3_sel_o   (mux_arb_sel_o[ii][3]),
          .wbs3_stb_o   (mux_arb_stb_o[ii][3]),
          .wbs3_ack_i   (mux_arb_ack_i[ii][3]),
          .wbs3_err_i   ('0),
          .wbs3_rty_i   ('0),
          .wbs3_cyc_o   (mux_arb_cyc_o[ii][3]),
          // Slave interface 4
          .wbs4_addr    (slave_base[4]),
          .wbs4_addr_msk(slave_mask[4]),

          .wbs4_adr_o   (mux_arb_adr_o[ii][4]),
          .wbs4_dat_i   (mux_arb_dat_i[ii][4]),
          .wbs4_dat_o   (mux_arb_dat_o[ii][4]),
          .wbs4_we_o    (mux_arb_we_o[ii][4]),
          .wbs4_sel_o   (mux_arb_sel_o[ii][4]),
          .wbs4_stb_o   (mux_arb_stb_o[ii][4]),
          .wbs4_ack_i   (mux_arb_ack_i[ii][4]),
          .wbs4_err_i   ('0),
          .wbs4_rty_i   ('0),
          .wbs4_cyc_o   (mux_arb_cyc_o[ii][4]),
          // Slave interface 5
          .wbs5_addr    (slave_base[5]),
          .wbs5_addr_msk(slave_mask[5]),

          .wbs5_adr_o(mux_arb_adr_o[ii][5]),
          .wbs5_dat_i(mux_arb_dat_i[ii][5]),
          .wbs5_dat_o(mux_arb_dat_o[ii][5]),
          .wbs5_we_o (mux_arb_we_o[ii][5]),
          .wbs5_sel_o(mux_arb_sel_o[ii][5]),
          .wbs5_stb_o(mux_arb_stb_o[ii][5]),
          .wbs5_ack_i(mux_arb_ack_i[ii][5]),
          .wbs5_err_i('0),
          .wbs5_rty_i('0),
          .wbs5_cyc_o(mux_arb_cyc_o[ii][5])
      );
    end
  endgenerate
  /* =========== Slaves begin =========== */
  // 1. The arbiters
  wire [5:0]       wbs_cyc_o;
  wire [5:0]       wbs_stb_o;
  wire [5:0]       wbs_ack_i;
  wire [5:0][31:0] wbs_adr_o;
  wire [5:0][31:0] wbs_dat_o;
  wire [5:0][31:0] wbs_dat_i;
  wire [5:0][ 3:0] wbs_sel_o;
  wire [5:0]       wbs_we_o;
  genvar jj;
  generate
    for (jj = 0; jj < 6; ++jj) begin : gen_arbiter
      wb_arbiter_4 arbiter_ (
          .clk(sys_clk),
          .rst(sys_rst),

          /*
        * Wishbone master 0 input
        */
          .wbm0_adr_i(mux_arb_adr_o[0][jj]),
          .wbm0_dat_i(mux_arb_dat_o[0][jj]),
          .wbm0_dat_o(mux_arb_dat_i[0][jj]),
          .wbm0_we_i (mux_arb_we_o[0][jj]),
          .wbm0_sel_i(mux_arb_sel_o[0][jj]),
          .wbm0_stb_i(mux_arb_stb_o[0][jj]),
          .wbm0_ack_o(mux_arb_ack_i[0][jj]),
          .wbm0_err_o(),
          .wbm0_rty_o(),
          .wbm0_cyc_i(mux_arb_cyc_o[0][jj]),
          /*
        * Wishbone master 1 input
        */
          .wbm1_adr_i(mux_arb_adr_o[1][jj]),
          .wbm1_dat_i(mux_arb_dat_o[1][jj]),
          .wbm1_dat_o(mux_arb_dat_i[1][jj]),
          .wbm1_we_i (mux_arb_we_o[1][jj]),
          .wbm1_sel_i(mux_arb_sel_o[1][jj]),
          .wbm1_stb_i(mux_arb_stb_o[1][jj]),
          .wbm1_ack_o(mux_arb_ack_i[1][jj]),
          .wbm1_err_o(),
          .wbm1_rty_o(),
          .wbm1_cyc_i(mux_arb_cyc_o[1][jj]),
          /*
        * Wishbone master 2 input
        */
          .wbm2_adr_i(mux_arb_adr_o[2][jj]),
          .wbm2_dat_i(mux_arb_dat_o[2][jj]),
          .wbm2_dat_o(mux_arb_dat_i[2][jj]),
          .wbm2_we_i (mux_arb_we_o[2][jj]),
          .wbm2_sel_i(mux_arb_sel_o[2][jj]),
          .wbm2_stb_i(mux_arb_stb_o[2][jj]),
          .wbm2_ack_o(mux_arb_ack_i[2][jj]),
          .wbm2_err_o(),
          .wbm2_rty_o(),
          .wbm2_cyc_i(mux_arb_cyc_o[2][jj]),
          /*
        * Wishbone master 3 input
        */
          .wbm3_adr_i(mux_arb_adr_o[3][jj]),
          .wbm3_dat_i(mux_arb_dat_o[3][jj]),
          .wbm3_dat_o(mux_arb_dat_i[3][jj]),
          .wbm3_we_i (mux_arb_we_o[3][jj]),
          .wbm3_sel_i(mux_arb_sel_o[3][jj]),
          .wbm3_stb_i(mux_arb_stb_o[3][jj]),
          .wbm3_ack_o(mux_arb_ack_i[3][jj]),
          .wbm3_err_o(),
          .wbm3_rty_o(),
          .wbm3_cyc_i(mux_arb_cyc_o[3][jj]),
          /*
     * Wishbone slave output
     */
          .wbs_adr_o (wbs_adr_o[jj]),
          .wbs_dat_i (wbs_dat_i[jj]),
          .wbs_dat_o (wbs_dat_o[jj]),
          .wbs_we_o  (wbs_we_o[jj]),
          .wbs_sel_o (wbs_sel_o[jj]),
          .wbs_stb_o (wbs_stb_o[jj]),
          .wbs_ack_i (wbs_ack_i[jj]),
          .wbs_err_i (1'b0),
          .wbs_rty_i (1'b0),
          .wbs_cyc_o (wbs_cyc_o[jj])
      );
    end
  endgenerate

  // 2. The controllers


  sram_controller_fast #(
      .SRAM_ADDR_WIDTH(20),
      .SRAM_DATA_WIDTH(32)
  ) sram_controller_base (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs_cyc_o[0]),
      .wb_stb_i(wbs_stb_o[0]),
      .wb_ack_o(wbs_ack_i[0]),
      .wb_adr_i(wbs_adr_o[0]),
      .wb_dat_i(wbs_dat_o[0]),
      .wb_dat_o(wbs_dat_i[0]),
      .wb_sel_i(wbs_sel_o[0]),
      .wb_we_i (wbs_we_o[0]),

      // To SRAM chip
      .sram_addr(base_ram_addr),
      .sram_data(base_ram_data),
      .sram_ce_n(base_ram_ce_n),
      .sram_oe_n(base_ram_oe_n),
      .sram_we_n(base_ram_we_n),
      .sram_be_n(base_ram_be_n)
  );
  sram_controller_fast #(
      .SRAM_ADDR_WIDTH(20),
      .SRAM_DATA_WIDTH(32)
  ) sram_controller_ext (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs_cyc_o[1]),
      .wb_stb_i(wbs_stb_o[1]),
      .wb_ack_o(wbs_ack_i[1]),
      .wb_adr_i(wbs_adr_o[1]),
      .wb_dat_i(wbs_dat_o[1]),
      .wb_dat_o(wbs_dat_i[1]),
      .wb_sel_i(wbs_sel_o[1]),
      .wb_we_i (wbs_we_o[1]),

      // To SRAM chip
      .sram_addr(ext_ram_addr),
      .sram_data(ext_ram_data),
      .sram_ce_n(ext_ram_ce_n),
      .sram_oe_n(ext_ram_oe_n),
      .sram_we_n(ext_ram_we_n),
      .sram_be_n(ext_ram_be_n)
  );
`ifdef SIM
  uart_sim_controller #(
`else
  uart_controller #(
`endif
      .CLK_FREQ(75_000_000),
      .BAUD    (115200)
  ) uart_controller (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs_cyc_o[2]),
      .wb_stb_i(wbs_stb_o[2]),
      .wb_ack_o(wbs_ack_i[2]),
      .wb_adr_i(wbs_adr_o[2]),
      .wb_dat_i(wbs_dat_o[2]),
      .wb_dat_o(wbs_dat_i[2]),
      .wb_sel_i(wbs_sel_o[2]),
      .wb_we_i (wbs_we_o[2]),

      // to UART pins
      .uart_txd_o(txd),
      .uart_rxd_i(rxd)
  );
  clint clint (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs_cyc_o[3]),
      .wb_stb_i(wbs_stb_o[3]),
      .wb_ack_o(wbs_ack_i[3]),
      .wb_adr_i(wbs_adr_o[3]),
      .wb_dat_i(wbs_dat_o[3]),
      .wb_dat_o(wbs_dat_i[3]),
      .wb_sel_i(wbs_sel_o[3]),
      .wb_we_i (wbs_we_o[3]),

      .intr(local_intr)
  );
  flash_controller flash_controller (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs_cyc_o[4]),
      .wb_stb_i(wbs_stb_o[4]),
      .wb_ack_o(wbs_ack_i[4]),
      .wb_adr_i(wbs_adr_o[4]),
      .wb_dat_i(wbs_dat_o[4]),
      .wb_dat_o(wbs_dat_i[4]),
      .wb_sel_i(wbs_sel_o[4]),
      .wb_we_i (wbs_we_o[4]),

      // Flash 存储器信号，参考 JS28F640 芯片手册
      .flash_a(flash_a),  // Flash 地址，a0 仅在 8bit 模式有效，16bit 模式无意义
      .flash_d(flash_d),  // Flash 数据
      .flash_rp_n(flash_rp_n),  // Flash 复位信号，低有效
      .flash_vpen(flash_vpen),  // Flash 写保护信号，低电平时不能擦除、烧写
      .flash_ce_n(flash_ce_n),  // Flash 片选信号，低有效
      .flash_oe_n(flash_oe_n),  // Flash 读使能信号，低有效
      .flash_we_n(flash_we_n),  // Flash 写使能信号，低有效
      .flash_byte_n(flash_byte_n) // Flash 8bit 模式选择，低有效。在使用 flash 的 16 位模式时请设为 1
  );
  display_controller disp (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs_cyc_o[5]),
      .wb_stb_i(wbs_stb_o[5]),
      .wb_ack_o(wbs_ack_i[5]),
      .wb_adr_i(wbs_adr_o[5]),
      .wb_dat_i(wbs_dat_o[5]),
      .wb_dat_o(wbs_dat_i[5]),
      .wb_sel_i(wbs_sel_o[5]),
      .wb_we_i (wbs_we_o[5]),

      /* TODO: Other ports in interest. */
      .vga_clk(clk_50M),
      .vga_hdata(vga_hdata),
      .vga_vdata(vga_vdata),
      .vga_hsync(vga_hsync),
      .vga_vsync(vga_vsync),
      .vga_video_de(vga_video_de),
      .pixel(pixel)
  );
endmodule
