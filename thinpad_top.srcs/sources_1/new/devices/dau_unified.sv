
`timescale 1 ns / 1 ps

module dau_unified (
    input wire sys_clk,
    input wire sys_rst,

    // Interface to Control Unit - Instruction
    input  wire        instr_re_i,
    input  wire [31:0] instr_addr_i,
    output wire [31:0] instr_data_o,
    output wire        instr_ack_o,

    // Interface to Control Unit - Data
    input  wire        we_i,
    input  wire        re_i,
    input  wire [31:0] addr_i,
    input  wire [ 3:0] byte_en,
    input  wire [31:0] data_i,
    output wire [31:0] data_o,
    output wire        ack_o,

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

    // CLINT interrupt signal
    output wire local_intr
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

  logic        instr_wbm_cyc_o;
  logic        instr_wbm_stb_o;
  logic        instr_wbm_ack_i;
  logic [31:0] instr_wbm_adr_o;
  logic [31:0] instr_wbm_dat_o;
  logic [31:0] instr_wbm_dat_i;
  logic [ 3:0] instr_wbm_sel_o;
  logic        instr_wbm_we_o;

  // dau_master -- For Data part
  dau_master_comb #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32)
  ) instruction_master (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Interface to control unit
      .we(1'b0),
      .re(instr_re_i),
      .addr(instr_addr_i),
      .byte_en(4'b1111),
      .data_i(32'b0),
      .data_o(instr_data_o),
      .ack_o(instr_ack_o),

      // wishbone master
      .wb_cyc_o(instr_wbm_cyc_o),
      .wb_stb_o(instr_wbm_stb_o),
      .wb_ack_i(instr_wbm_ack_i),
      .wb_adr_o(instr_wbm_adr_o),
      .wb_dat_o(instr_wbm_dat_o),
      .wb_dat_i(instr_wbm_dat_i),
      .wb_sel_o(instr_wbm_sel_o),
      .wb_we_o (instr_wbm_we_o)
  );


  logic        data_wbm_cyc_o;
  logic        data_wbm_stb_o;
  logic        data_wbm_ack_i;
  logic [31:0] data_wbm_adr_o;
  logic [31:0] data_wbm_dat_o;
  logic [31:0] data_wbm_dat_i;
  logic [ 3:0] data_wbm_sel_o;
  logic        data_wbm_we_o;

  // dau_master -- For Data part
  dau_master_comb #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32)
  ) data_master (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Interface to control unit
      .we(we_i),
      .re(re_i),
      .addr(addr_i),
      .byte_en(byte_en),
      .data_i(data_i),
      .data_o(data_o),
      .ack_o(ack_o),

      // wishbone master
      .wb_cyc_o(data_wbm_cyc_o),
      .wb_stb_o(data_wbm_stb_o),
      .wb_ack_i(data_wbm_ack_i),
      .wb_adr_o(data_wbm_adr_o),
      .wb_dat_o(data_wbm_dat_o),
      .wb_dat_i(data_wbm_dat_i),
      .wb_sel_o(data_wbm_sel_o),
      .wb_we_o (data_wbm_we_o)
  );

  /* =========== Master end =========== */

  /* =========== MUX for Instruction begin =========== */

  logic instr_mux_arb0_cyc_o;
  logic instr_mux_arb0_stb_o;
  logic instr_mux_arb0_ack_i;
  logic [31:0] instr_mux_arb0_adr_o;
  logic [31:0] instr_mux_arb0_dat_o;
  logic [31:0] instr_mux_arb0_dat_i;
  logic [3:0] instr_mux_arb0_sel_o;
  logic instr_mux_arb0_we_o;

  logic instr_mux_arb1_cyc_o;
  logic instr_mux_arb1_stb_o;
  logic instr_mux_arb1_ack_i;
  logic [31:0] instr_mux_arb1_adr_o;
  logic [31:0] instr_mux_arb1_dat_o;
  logic [31:0] instr_mux_arb1_dat_i;
  logic [3:0] instr_mux_arb1_sel_o;
  logic instr_mux_arb1_we_o;

  logic instr_mux_arb2_cyc_o;
  logic instr_mux_arb2_stb_o;
  logic instr_mux_arb2_ack_i;
  logic [31:0] instr_mux_arb2_adr_o;
  logic [31:0] instr_mux_arb2_dat_o;
  logic [31:0] instr_mux_arb2_dat_i;
  logic [3:0] instr_mux_arb2_sel_o;
  logic instr_mux_arb2_we_o;

  logic instr_mux_arb3_cyc_o;
  logic instr_mux_arb3_stb_o;
  logic instr_mux_arb3_ack_i;
  logic [31:0] instr_mux_arb3_adr_o;
  logic [31:0] instr_mux_arb3_dat_o;
  logic [31:0] instr_mux_arb3_dat_i;
  logic [3:0] instr_mux_arb3_sel_o;
  logic instr_mux_arb3_we_o;

  logic instr_mux_arb4_cyc_o;
  logic instr_mux_arb4_stb_o;
  logic instr_mux_arb4_ack_i;
  logic [31:0] instr_mux_arb4_adr_o;
  logic [31:0] instr_mux_arb4_dat_o;
  logic [31:0] instr_mux_arb4_dat_i;
  logic [3:0] instr_mux_arb4_sel_o;
  logic instr_mux_arb4_we_o;

  logic instr_mux_arb5_cyc_o;
  logic instr_mux_arb5_stb_o;
  logic instr_mux_arb5_ack_i;
  logic [31:0] instr_mux_arb5_adr_o;
  logic [31:0] instr_mux_arb5_dat_o;
  logic [31:0] instr_mux_arb5_dat_i;
  logic [3:0] instr_mux_arb5_sel_o;
  logic instr_mux_arb5_we_o;

  device_access_mux instr_mux (
      .clk(sys_clk),
      .rst(sys_rst),

      // Master interface
      .wbm_adr_i(instr_wbm_adr_o),
      .wbm_dat_i(instr_wbm_dat_o),
      .wbm_dat_o(instr_wbm_dat_i),
      .wbm_we_i (instr_wbm_we_o),
      .wbm_sel_i(instr_wbm_sel_o),
      .wbm_stb_i(instr_wbm_stb_o),
      .wbm_ack_o(instr_wbm_ack_i),
      .wbm_err_o(),
      .wbm_rty_o(),
      .wbm_cyc_i(instr_wbm_cyc_o),


      // Slave interface 0 (to BaseRAM controller)
      // Address range: 0x8000_0000 ~ 0x803F_FFFF
      .wbs0_addr    (32'h8000_0000),
      .wbs0_addr_msk(32'hFFC0_0000),

      .wbs0_adr_o(instr_mux_arb0_adr_o),
      .wbs0_dat_i(instr_mux_arb0_dat_i),
      .wbs0_dat_o(instr_mux_arb0_dat_o),
      .wbs0_we_o (instr_mux_arb0_we_o),
      .wbs0_sel_o(instr_mux_arb0_sel_o),
      .wbs0_stb_o(instr_mux_arb0_stb_o),
      .wbs0_ack_i(instr_mux_arb0_ack_i),
      .wbs0_err_i('0),
      .wbs0_rty_i('0),
      .wbs0_cyc_o(instr_mux_arb0_cyc_o),

      // Slave interface 1 (to ExtRAM controller)
      // Address range: 0x8040_0000 ~ 0x807F_FFFF
      .wbs1_addr    (32'h8040_0000),
      .wbs1_addr_msk(32'hFFC0_0000),

      .wbs1_adr_o(instr_mux_arb1_adr_o),
      .wbs1_dat_i(instr_mux_arb1_dat_i),
      .wbs1_dat_o(instr_mux_arb1_dat_o),
      .wbs1_we_o (instr_mux_arb1_we_o),
      .wbs1_sel_o(instr_mux_arb1_sel_o),
      .wbs1_stb_o(instr_mux_arb1_stb_o),
      .wbs1_ack_i(instr_mux_arb1_ack_i),
      .wbs1_err_i('0),
      .wbs1_rty_i('0),
      .wbs1_cyc_o(instr_mux_arb1_cyc_o),

      // Slave interface 2 (to UART controller)
      // Address range: 0x1000_0000 ~ 0x1000_FFFF
      .wbs2_addr    (32'h1000_0000),
      .wbs2_addr_msk(32'hFFFF_0000),

      .wbs2_adr_o(instr_mux_arb2_adr_o),
      .wbs2_dat_i(instr_mux_arb2_dat_i),
      .wbs2_dat_o(instr_mux_arb2_dat_o),
      .wbs2_we_o (instr_mux_arb2_we_o),
      .wbs2_sel_o(instr_mux_arb2_sel_o),
      .wbs2_stb_o(instr_mux_arb2_stb_o),
      .wbs2_ack_i(instr_mux_arb2_ack_i),
      .wbs2_err_i('0),
      .wbs2_rty_i('0),
      .wbs2_cyc_o(instr_mux_arb2_cyc_o),

      // Slave interface 3 (to CLINT controller)
      // Address range: 0x0200_0000 ~ 0x0200_BFFF
      .wbs3_addr    (32'h0200_0000),
      .wbs3_addr_msk(32'hFFFF_0000),

      .wbs3_adr_o(instr_mux_arb3_adr_o),
      .wbs3_dat_i(instr_mux_arb3_dat_i),
      .wbs3_dat_o(instr_mux_arb3_dat_o),
      .wbs3_we_o (instr_mux_arb3_we_o),
      .wbs3_sel_o(instr_mux_arb3_sel_o),
      .wbs3_stb_o(instr_mux_arb3_stb_o),
      .wbs3_ack_i(instr_mux_arb3_ack_i),
      .wbs3_err_i('0),
      .wbs3_rty_i('0),
      .wbs3_cyc_o(instr_mux_arb3_cyc_o),

      // Slave interface 4 (Flash controller)
      .wbs4_addr    (32'h2000_0000),
      .wbs4_addr_msk(32'hFFFF_F800),  // TODO: Change mask when Flash controller is supported.

      .wbs4_adr_o(instr_mux_arb4_adr_o),
      .wbs4_dat_i(instr_mux_arb4_dat_i),
      .wbs4_dat_o(instr_mux_arb4_dat_o),
      .wbs4_we_o (instr_mux_arb4_we_o),
      .wbs4_sel_o(instr_mux_arb4_sel_o),
      .wbs4_stb_o(instr_mux_arb4_stb_o),
      .wbs4_ack_i(instr_mux_arb4_ack_i),
      .wbs4_err_i('0),
      .wbs4_rty_i('0),
      .wbs4_cyc_o(instr_mux_arb4_cyc_o),

      // Slave interface 5 (Graphics memory (as BRAM))
      .wbs5_addr    (32'h3000_0000),
      .wbs5_addr_msk(32'h0005_0000),  // TODO: Change mask when Flash controller is supported.

      .wbs5_adr_o(instr_mux_arb5_adr_o),
      .wbs5_dat_i(instr_mux_arb5_dat_i),
      .wbs5_dat_o(instr_mux_arb5_dat_o),
      .wbs5_we_o (instr_mux_arb5_we_o),
      .wbs5_sel_o(instr_mux_arb5_sel_o),
      .wbs5_stb_o(instr_mux_arb5_stb_o),
      .wbs5_ack_i(instr_mux_arb5_ack_i),
      .wbs5_err_i('0),
      .wbs5_rty_i('0),
      .wbs5_cyc_o(instr_mux_arb5_cyc_o)
  );


  logic data_mux_arb0_cyc_o;
  logic data_mux_arb0_stb_o;
  logic data_mux_arb0_ack_i;
  logic [31:0] data_mux_arb0_adr_o;
  logic [31:0] data_mux_arb0_dat_o;
  logic [31:0] data_mux_arb0_dat_i;
  logic [3:0] data_mux_arb0_sel_o;
  logic data_mux_arb0_we_o;

  logic data_mux_arb1_cyc_o;
  logic data_mux_arb1_stb_o;
  logic data_mux_arb1_ack_i;
  logic [31:0] data_mux_arb1_adr_o;
  logic [31:0] data_mux_arb1_dat_o;
  logic [31:0] data_mux_arb1_dat_i;
  logic [3:0] data_mux_arb1_sel_o;
  logic data_mux_arb1_we_o;

  logic data_mux_arb2_cyc_o;
  logic data_mux_arb2_stb_o;
  logic data_mux_arb2_ack_i;
  logic [31:0] data_mux_arb2_adr_o;
  logic [31:0] data_mux_arb2_dat_o;
  logic [31:0] data_mux_arb2_dat_i;
  logic [3:0] data_mux_arb2_sel_o;
  logic data_mux_arb2_we_o;

  logic data_mux_arb3_cyc_o;
  logic data_mux_arb3_stb_o;
  logic data_mux_arb3_ack_i;
  logic [31:0] data_mux_arb3_adr_o;
  logic [31:0] data_mux_arb3_dat_o;
  logic [31:0] data_mux_arb3_dat_i;
  logic [3:0] data_mux_arb3_sel_o;
  logic data_mux_arb3_we_o;

  logic data_mux_arb4_cyc_o;
  logic data_mux_arb4_stb_o;
  logic data_mux_arb4_ack_i;
  logic [31:0] data_mux_arb4_adr_o;
  logic [31:0] data_mux_arb4_dat_o;
  logic [31:0] data_mux_arb4_dat_i;
  logic [3:0] data_mux_arb4_sel_o;
  logic data_mux_arb4_we_o;

  logic data_mux_arb5_cyc_o;
  logic data_mux_arb5_stb_o;
  logic data_mux_arb5_ack_i;
  logic [31:0] data_mux_arb5_adr_o;
  logic [31:0] data_mux_arb5_dat_o;
  logic [31:0] data_mux_arb5_dat_i;
  logic [3:0] data_mux_arb5_sel_o;
  logic data_mux_arb5_we_o;

  device_access_mux data_mux (
      .clk(sys_clk),
      .rst(sys_rst),

      // Master interface
      .wbm_adr_i(data_wbm_adr_o),
      .wbm_dat_i(data_wbm_dat_o),
      .wbm_dat_o(data_wbm_dat_i),
      .wbm_we_i (data_wbm_we_o),
      .wbm_sel_i(data_wbm_sel_o),
      .wbm_stb_i(data_wbm_stb_o),
      .wbm_ack_o(data_wbm_ack_i),
      .wbm_err_o(),
      .wbm_rty_o(),
      .wbm_cyc_i(data_wbm_cyc_o),


      // Slave interface 0 (to BaseRAM controller)
      // Address range: 0x8000_0000 ~ 0x803F_FFFF
      .wbs0_addr    (32'h8000_0000),
      .wbs0_addr_msk(32'hFFC0_0000),

      .wbs0_adr_o(data_mux_arb0_adr_o),
      .wbs0_dat_i(data_mux_arb0_dat_i),
      .wbs0_dat_o(data_mux_arb0_dat_o),
      .wbs0_we_o (data_mux_arb0_we_o),
      .wbs0_sel_o(data_mux_arb0_sel_o),
      .wbs0_stb_o(data_mux_arb0_stb_o),
      .wbs0_ack_i(data_mux_arb0_ack_i),
      .wbs0_err_i('0),
      .wbs0_rty_i('0),
      .wbs0_cyc_o(data_mux_arb0_cyc_o),

      // Slave interface 1 (to ExtRAM controller)
      // Address range: 0x8040_0000 ~ 0x807F_FFFF
      .wbs1_addr    (32'h8040_0000),
      .wbs1_addr_msk(32'hFFC0_0000),

      .wbs1_adr_o(data_mux_arb1_adr_o),
      .wbs1_dat_i(data_mux_arb1_dat_i),
      .wbs1_dat_o(data_mux_arb1_dat_o),
      .wbs1_we_o (data_mux_arb1_we_o),
      .wbs1_sel_o(data_mux_arb1_sel_o),
      .wbs1_stb_o(data_mux_arb1_stb_o),
      .wbs1_ack_i(data_mux_arb1_ack_i),
      .wbs1_err_i('0),
      .wbs1_rty_i('0),
      .wbs1_cyc_o(data_mux_arb1_cyc_o),

      // Slave interface 2 (to UART controller)
      // Address range: 0x1000_0000 ~ 0x1000_FFFF
      .wbs2_addr    (32'h1000_0000),
      .wbs2_addr_msk(32'hFFFF_0000),

      .wbs2_adr_o(data_mux_arb2_adr_o),
      .wbs2_dat_i(data_mux_arb2_dat_i),
      .wbs2_dat_o(data_mux_arb2_dat_o),
      .wbs2_we_o (data_mux_arb2_we_o),
      .wbs2_sel_o(data_mux_arb2_sel_o),
      .wbs2_stb_o(data_mux_arb2_stb_o),
      .wbs2_ack_i(data_mux_arb2_ack_i),
      .wbs2_err_i('0),
      .wbs2_rty_i('0),
      .wbs2_cyc_o(data_mux_arb2_cyc_o),

      // Slave interface 3 (to CLINT controller)
      // Address range: 0x0200_0000 ~ 0x0200_BFFF
      .wbs3_addr    (32'h0200_0000),
      .wbs3_addr_msk(32'hFFFF_0000),

      .wbs3_adr_o(data_mux_arb3_adr_o),
      .wbs3_dat_i(data_mux_arb3_dat_i),
      .wbs3_dat_o(data_mux_arb3_dat_o),
      .wbs3_we_o (data_mux_arb3_we_o),
      .wbs3_sel_o(data_mux_arb3_sel_o),
      .wbs3_stb_o(data_mux_arb3_stb_o),
      .wbs3_ack_i(data_mux_arb3_ack_i),
      .wbs3_err_i('0),
      .wbs3_rty_i('0),
      .wbs3_cyc_o(data_mux_arb3_cyc_o),

      // Slave interface 4 (Flash controller)
      .wbs4_addr    (32'h2000_0000),
      .wbs4_addr_msk(32'hFFFF_F800),  // TODO: Change mask when Flash controller is supported.

      .wbs4_adr_o(data_mux_arb4_adr_o),
      .wbs4_dat_i(data_mux_arb4_dat_i),
      .wbs4_dat_o(data_mux_arb4_dat_o),
      .wbs4_we_o (data_mux_arb4_we_o),
      .wbs4_sel_o(data_mux_arb4_sel_o),
      .wbs4_stb_o(data_mux_arb4_stb_o),
      .wbs4_ack_i(data_mux_arb4_ack_i),
      .wbs4_err_i('0),
      .wbs4_rty_i('0),
      .wbs4_cyc_o(data_mux_arb4_cyc_o),

      // Slave interface 5 (Graphics memory (as BRAM))
      .wbs5_addr    (32'h3000_0000),
      .wbs5_addr_msk(32'h0005_0000),  // TODO: Change mask when Flash controller is supported.

      .wbs5_adr_o(data_mux_arb5_adr_o),
      .wbs5_dat_i(data_mux_arb5_dat_i),
      .wbs5_dat_o(data_mux_arb5_dat_o),
      .wbs5_we_o (data_mux_arb5_we_o),
      .wbs5_sel_o(data_mux_arb5_sel_o),
      .wbs5_stb_o(data_mux_arb5_stb_o),
      .wbs5_ack_i(data_mux_arb5_ack_i),
      .wbs5_err_i('0),
      .wbs5_rty_i('0),
      .wbs5_cyc_o(data_mux_arb5_cyc_o)
  );
  /* =========== Slaves begin =========== */
  // 1. The arbiters

  logic wbs0_cyc_o;
  logic wbs0_stb_o;
  logic wbs0_ack_i;
  logic [31:0] wbs0_adr_o;
  logic [31:0] wbs0_dat_o;
  logic [31:0] wbs0_dat_i;
  logic [3:0] wbs0_sel_o;
  logic wbs0_we_o;

  wb_arbiter_2 #(
      .ARB_LSB_HIGH_PRIORITY(1)
  ) arbiter0 (
      .clk(sys_clk),
      .rst(sys_rst),
      /*
     * Wishbone master 1 input
     */
      .wbm1_adr_i(instr_mux_arb0_adr_o),
      .wbm1_dat_i(instr_mux_arb0_dat_o),
      .wbm1_dat_o(instr_mux_arb0_dat_i),
      .wbm1_we_i(instr_mux_arb0_we_o),
      .wbm1_sel_i(instr_mux_arb0_sel_o),
      .wbm1_stb_i(instr_mux_arb0_stb_o),
      .wbm1_ack_o(instr_mux_arb0_ack_i),
      .wbm1_err_o(),
      .wbm1_rty_o(),
      .wbm1_cyc_i(instr_mux_arb0_cyc_o),

      /*
     * Wishbone master 0 input
     */
      .wbm0_adr_i(data_mux_arb0_adr_o),
      .wbm0_dat_i(data_mux_arb0_dat_o),
      .wbm0_dat_o(data_mux_arb0_dat_i),
      .wbm0_we_i (data_mux_arb0_we_o),
      .wbm0_sel_i(data_mux_arb0_sel_o),
      .wbm0_stb_i(data_mux_arb0_stb_o),
      .wbm0_ack_o(data_mux_arb0_ack_i),
      .wbm0_err_o(),
      .wbm0_rty_o(),
      .wbm0_cyc_i(data_mux_arb0_cyc_o),

      /*
     * Wishbone slave output
     */
      .wbs_adr_o(wbs0_adr_o),
      .wbs_dat_i(wbs0_dat_i),
      .wbs_dat_o(wbs0_dat_o),
      .wbs_we_o (wbs0_we_o),
      .wbs_sel_o(wbs0_sel_o),
      .wbs_stb_o(wbs0_stb_o),
      .wbs_ack_i(wbs0_ack_i),
      .wbs_err_i(1'b0),
      .wbs_rty_i(1'b0),
      .wbs_cyc_o(wbs0_cyc_o)
  );

  logic wbs1_cyc_o;
  logic wbs1_stb_o;
  logic wbs1_ack_i;
  logic [31:0] wbs1_adr_o;
  logic [31:0] wbs1_dat_o;
  logic [31:0] wbs1_dat_i;
  logic [3:0] wbs1_sel_o;
  logic wbs1_we_o;

  wb_arbiter_2 #(
      .ARB_LSB_HIGH_PRIORITY(1)
  ) arbiter1 (
      .clk(sys_clk),
      .rst(sys_rst),
      /*
     * Wishbone master 1 input
     */
      .wbm1_adr_i(instr_mux_arb1_adr_o),
      .wbm1_dat_i(instr_mux_arb1_dat_o),
      .wbm1_dat_o(instr_mux_arb1_dat_i),
      .wbm1_we_i(instr_mux_arb1_we_o),
      .wbm1_sel_i(instr_mux_arb1_sel_o),
      .wbm1_stb_i(instr_mux_arb1_stb_o),
      .wbm1_ack_o(instr_mux_arb1_ack_i),
      .wbm1_err_o(),
      .wbm1_rty_o(),
      .wbm1_cyc_i(instr_mux_arb1_cyc_o),

      /*
     * Wishbone master 0 input
     */
      .wbm0_adr_i(data_mux_arb1_adr_o),
      .wbm0_dat_i(data_mux_arb1_dat_o),
      .wbm0_dat_o(data_mux_arb1_dat_i),
      .wbm0_we_i (data_mux_arb1_we_o),
      .wbm0_sel_i(data_mux_arb1_sel_o),
      .wbm0_stb_i(data_mux_arb1_stb_o),
      .wbm0_ack_o(data_mux_arb1_ack_i),
      .wbm0_err_o(),
      .wbm0_rty_o(),
      .wbm0_cyc_i(data_mux_arb1_cyc_o),

      /*
     * Wishbone slave output
     */
      .wbs_adr_o(wbs1_adr_o),
      .wbs_dat_i(wbs1_dat_i),
      .wbs_dat_o(wbs1_dat_o),
      .wbs_we_o (wbs1_we_o),
      .wbs_sel_o(wbs1_sel_o),
      .wbs_stb_o(wbs1_stb_o),
      .wbs_ack_i(wbs1_ack_i),
      .wbs_err_i(1'b0),
      .wbs_rty_i(1'b0),
      .wbs_cyc_o(wbs1_cyc_o)
  );

  logic wbs2_cyc_o;
  logic wbs2_stb_o;
  logic wbs2_ack_i;
  logic [31:0] wbs2_adr_o;
  logic [31:0] wbs2_dat_o;
  logic [31:0] wbs2_dat_i;
  logic [3:0] wbs2_sel_o;
  logic wbs2_we_o;

  wb_arbiter_2 #(
      .ARB_LSB_HIGH_PRIORITY(1)
  ) arbiter2 (
      .clk(sys_clk),
      .rst(sys_rst),
      /*
     * Wishbone master 1 input
     */
      .wbm1_adr_i(instr_mux_arb2_adr_o),
      .wbm1_dat_i(instr_mux_arb2_dat_o),
      .wbm1_dat_o(instr_mux_arb2_dat_i),
      .wbm1_we_i(instr_mux_arb2_we_o),
      .wbm1_sel_i(instr_mux_arb2_sel_o),
      .wbm1_stb_i(instr_mux_arb2_stb_o),
      .wbm1_ack_o(instr_mux_arb2_ack_i),
      .wbm1_err_o(),
      .wbm1_rty_o(),
      .wbm1_cyc_i(instr_mux_arb2_cyc_o),

      /*
     * Wishbone master 0 input
     */
      .wbm0_adr_i(data_mux_arb2_adr_o),
      .wbm0_dat_i(data_mux_arb2_dat_o),
      .wbm0_dat_o(data_mux_arb2_dat_i),
      .wbm0_we_i (data_mux_arb2_we_o),
      .wbm0_sel_i(data_mux_arb2_sel_o),
      .wbm0_stb_i(data_mux_arb2_stb_o),
      .wbm0_ack_o(data_mux_arb2_ack_i),
      .wbm0_err_o(),
      .wbm0_rty_o(),
      .wbm0_cyc_i(data_mux_arb2_cyc_o),

      /*
     * Wishbone slave output
     */
      .wbs_adr_o(wbs2_adr_o),
      .wbs_dat_i(wbs2_dat_i),
      .wbs_dat_o(wbs2_dat_o),
      .wbs_we_o (wbs2_we_o),
      .wbs_sel_o(wbs2_sel_o),
      .wbs_stb_o(wbs2_stb_o),
      .wbs_ack_i(wbs2_ack_i),
      .wbs_err_i(1'b0),
      .wbs_rty_i(1'b0),
      .wbs_cyc_o(wbs2_cyc_o)
  );

  logic wbs3_cyc_o;
  logic wbs3_stb_o;
  logic wbs3_ack_i;
  logic [31:0] wbs3_adr_o;
  logic [31:0] wbs3_dat_o;
  logic [31:0] wbs3_dat_i;
  logic [3:0] wbs3_sel_o;
  logic wbs3_we_o;

  wb_arbiter_2 #(
      .ARB_LSB_HIGH_PRIORITY(1)
  ) arbiter3 (
      .clk(sys_clk),
      .rst(sys_rst),
      /*
     * Wishbone master 1 input
     */
      .wbm1_adr_i(instr_mux_arb3_adr_o),
      .wbm1_dat_i(instr_mux_arb3_dat_o),
      .wbm1_dat_o(instr_mux_arb3_dat_i),
      .wbm1_we_i(instr_mux_arb3_we_o),
      .wbm1_sel_i(instr_mux_arb3_sel_o),
      .wbm1_stb_i(instr_mux_arb3_stb_o),
      .wbm1_ack_o(instr_mux_arb3_ack_i),
      .wbm1_err_o(),
      .wbm1_rty_o(),
      .wbm1_cyc_i(instr_mux_arb3_cyc_o),

      /*
     * Wishbone master 0 input
     */
      .wbm0_adr_i(data_mux_arb3_adr_o),
      .wbm0_dat_i(data_mux_arb3_dat_o),
      .wbm0_dat_o(data_mux_arb3_dat_i),
      .wbm0_we_i (data_mux_arb3_we_o),
      .wbm0_sel_i(data_mux_arb3_sel_o),
      .wbm0_stb_i(data_mux_arb3_stb_o),
      .wbm0_ack_o(data_mux_arb3_ack_i),
      .wbm0_err_o(),
      .wbm0_rty_o(),
      .wbm0_cyc_i(data_mux_arb3_cyc_o),

      /*
     * Wishbone slave output
     */
      .wbs_adr_o(wbs3_adr_o),
      .wbs_dat_i(wbs3_dat_i),
      .wbs_dat_o(wbs3_dat_o),
      .wbs_we_o (wbs3_we_o),
      .wbs_sel_o(wbs3_sel_o),
      .wbs_stb_o(wbs3_stb_o),
      .wbs_ack_i(wbs3_ack_i),
      .wbs_err_i(1'b0),
      .wbs_rty_i(1'b0),
      .wbs_cyc_o(wbs3_cyc_o)
  );

  logic wbs4_cyc_o;
  logic wbs4_stb_o;
  logic wbs4_ack_i;
  logic [31:0] wbs4_adr_o;
  logic [31:0] wbs4_dat_o;
  logic [31:0] wbs4_dat_i;
  logic [3:0] wbs4_sel_o;
  logic wbs4_we_o;

  wb_arbiter_2 #(
      .ARB_LSB_HIGH_PRIORITY(1)
  ) arbiter4 (
      .clk(sys_clk),
      .rst(sys_rst),
      /*
     * Wishbone master 1 input
     */
      .wbm1_adr_i(instr_mux_arb4_adr_o),
      .wbm1_dat_i(instr_mux_arb4_dat_o),
      .wbm1_dat_o(instr_mux_arb4_dat_i),
      .wbm1_we_i(instr_mux_arb4_we_o),
      .wbm1_sel_i(instr_mux_arb4_sel_o),
      .wbm1_stb_i(instr_mux_arb4_stb_o),
      .wbm1_ack_o(instr_mux_arb4_ack_i),
      .wbm1_err_o(),
      .wbm1_rty_o(),
      .wbm1_cyc_i(instr_mux_arb4_cyc_o),

      /*
     * Wishbone master 0 input
     */
      .wbm0_adr_i(data_mux_arb4_adr_o),
      .wbm0_dat_i(data_mux_arb4_dat_o),
      .wbm0_dat_o(data_mux_arb4_dat_i),
      .wbm0_we_i (data_mux_arb4_we_o),
      .wbm0_sel_i(data_mux_arb4_sel_o),
      .wbm0_stb_i(data_mux_arb4_stb_o),
      .wbm0_ack_o(data_mux_arb4_ack_i),
      .wbm0_err_o(),
      .wbm0_rty_o(),
      .wbm0_cyc_i(data_mux_arb4_cyc_o),

      /*
     * Wishbone slave output
     */
      .wbs_adr_o(wbs4_adr_o),
      .wbs_dat_i(wbs4_dat_i),
      .wbs_dat_o(wbs4_dat_o),
      .wbs_we_o (wbs4_we_o),
      .wbs_sel_o(wbs4_sel_o),
      .wbs_stb_o(wbs4_stb_o),
      .wbs_ack_i(wbs4_ack_i),
      .wbs_err_i(1'b0),
      .wbs_rty_i(1'b0),
      .wbs_cyc_o(wbs4_cyc_o)
  );

  logic wbs5_cyc_o;
  logic wbs5_stb_o;
  logic wbs5_ack_i;
  logic [31:0] wbs5_adr_o;
  logic [31:0] wbs5_dat_o;
  logic [31:0] wbs5_dat_i;
  logic [3:0] wbs5_sel_o;
  logic wbs5_we_o;

  wb_arbiter_2 #(
      .ARB_LSB_HIGH_PRIORITY(1)
  ) arbiter5 (
      .clk(sys_clk),
      .rst(sys_rst),
      /*
     * Wishbone master 1 input
     */
      .wbm1_adr_i(instr_mux_arb5_adr_o),
      .wbm1_dat_i(instr_mux_arb5_dat_o),
      .wbm1_dat_o(instr_mux_arb5_dat_i),
      .wbm1_we_i(instr_mux_arb5_we_o),
      .wbm1_sel_i(instr_mux_arb5_sel_o),
      .wbm1_stb_i(instr_mux_arb5_stb_o),
      .wbm1_ack_o(instr_mux_arb5_ack_i),
      .wbm1_err_o(),
      .wbm1_rty_o(),
      .wbm1_cyc_i(instr_mux_arb5_cyc_o),

      /*
     * Wishbone master 0 input
     */
      .wbm0_adr_i(data_mux_arb5_adr_o),
      .wbm0_dat_i(data_mux_arb5_dat_o),
      .wbm0_dat_o(data_mux_arb5_dat_i),
      .wbm0_we_i (data_mux_arb5_we_o),
      .wbm0_sel_i(data_mux_arb5_sel_o),
      .wbm0_stb_i(data_mux_arb5_stb_o),
      .wbm0_ack_o(data_mux_arb5_ack_i),
      .wbm0_err_o(),
      .wbm0_rty_o(),
      .wbm0_cyc_i(data_mux_arb5_cyc_o),

      /*
     * Wishbone slave output
     */
      .wbs_adr_o(wbs5_adr_o),
      .wbs_dat_i(wbs5_dat_i),
      .wbs_dat_o(wbs5_dat_o),
      .wbs_we_o (wbs5_we_o),
      .wbs_sel_o(wbs5_sel_o),
      .wbs_stb_o(wbs5_stb_o),
      .wbs_ack_i(wbs5_ack_i),
      .wbs_err_i(1'b0),
      .wbs_rty_i(1'b0),
      .wbs_cyc_o(wbs5_cyc_o)
  );

  // 2. The controllers


  sram_controller_fast #(
      .SRAM_ADDR_WIDTH(20),
      .SRAM_DATA_WIDTH(32)
  ) sram_controller_base (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs0_cyc_o),
      .wb_stb_i(wbs0_stb_o),
      .wb_ack_o(wbs0_ack_i),
      .wb_adr_i(wbs0_adr_o),
      .wb_dat_i(wbs0_dat_o),
      .wb_dat_o(wbs0_dat_i),
      .wb_sel_i(wbs0_sel_o),
      .wb_we_i (wbs0_we_o),

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
      .wb_cyc_i(wbs1_cyc_o),
      .wb_stb_i(wbs1_stb_o),
      .wb_ack_o(wbs1_ack_i),
      .wb_adr_i(wbs1_adr_o),
      .wb_dat_i(wbs1_dat_o),
      .wb_dat_o(wbs1_dat_i),
      .wb_sel_i(wbs1_sel_o),
      .wb_we_i (wbs1_we_o),

      // To SRAM chip
      .sram_addr(ext_ram_addr),
      .sram_data(ext_ram_data),
      .sram_ce_n(ext_ram_ce_n),
      .sram_oe_n(ext_ram_oe_n),
      .sram_we_n(ext_ram_we_n),
      .sram_be_n(ext_ram_be_n)
  );

  // 串口控制器模块
  // NOTE: 如果修改系统时钟频率，也需要修改此处的时钟频率参数
  uart_controller #(
      .CLK_FREQ(10_000_000),
      .BAUD    (115200)
  ) uart_controller (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs2_cyc_o),
      .wb_stb_i(wbs2_stb_o),
      .wb_ack_o(wbs2_ack_i),
      .wb_adr_i(wbs2_adr_o),
      .wb_dat_i(wbs2_dat_o),
      .wb_dat_o(wbs2_dat_i),
      .wb_sel_i(wbs2_sel_o),
      .wb_we_i (wbs2_we_o),

      // to UART pins
      .uart_txd_o(txd),
      .uart_rxd_i(rxd)
  );

  // Core local interruptor
  clint clint (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs3_cyc_o),
      .wb_stb_i(wbs3_stb_o),
      .wb_ack_o(wbs3_ack_i),
      .wb_adr_i(wbs3_adr_o),
      .wb_dat_i(wbs3_dat_o),
      .wb_dat_o(wbs3_dat_i),
      .wb_sel_i(wbs3_sel_o),
      .wb_we_i (wbs3_we_o),

      .intr(local_intr)
  );

  display_controller block_ram (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs4_cyc_o),
      .wb_stb_i(wbs4_stb_o),
      .wb_ack_o(wbs4_ack_i),
      .wb_adr_i(wbs4_adr_o),
      .wb_dat_i(wbs4_dat_o),
      .wb_dat_o(wbs4_dat_i),
      .wb_sel_i(wbs4_sel_o),
      .wb_we_i (wbs4_we_o)

      /* TODO: Other ports in interest. */
      // Add VGA ports where necessary.
  );

  flash_controller flash_controller (
      .clk_i(sys_clk),
      .rst_i(sys_rst),

      // Wishbone slave (to MUX)
      .wb_cyc_i(wbs5_cyc_o),
      .wb_stb_i(wbs5_stb_o),
      .wb_ack_o(wbs5_ack_i),
      .wb_adr_i(wbs5_adr_o),
      .wb_dat_i(wbs5_dat_o),
      .wb_dat_o(wbs5_dat_i),
      .wb_sel_i(wbs5_sel_o),
      .wb_we_i (wbs5_we_o),

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

endmodule
