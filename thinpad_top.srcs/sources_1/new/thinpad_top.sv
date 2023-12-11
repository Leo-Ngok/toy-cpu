`default_nettype none

module thinpad_top (
    input wire clk_50M,     // 50MHz 时钟输入
    input wire clk_11M0592, // 11.0592MHz 时钟输入（备用，可不用）

    input wire push_btn,  // BTN5 按钮开关，带消抖电路，按下时为 1
    input wire reset_btn, // BTN6 复位按钮，带消抖电路，按下时为 1

    input  wire [ 3:0] touch_btn,  // BTN1~BTN4，按钮开关，按下时为 1
    input  wire [31:0] dip_sw,     // 32 位拨码开关，拨到“ON”时为 1
    output wire [15:0] leds,       // 16 位 LED，输出时 1 点亮
    output wire [ 7:0] dpy0,       // 数码管低位信号，包括小数点，输出 1 点亮
    output wire [ 7:0] dpy1,       // 数码管高位信号，包括小数点，输出 1 点亮

    // CPLD 串口控制器信号
    output wire uart_rdn,        // 读串口信号，低有效
    output wire uart_wrn,        // 写串口信号，低有效
    input  wire uart_dataready,  // 串口数据准备好
    input  wire uart_tbre,       // 发送数据标志
    input  wire uart_tsre,       // 数据发送完毕标志

    // BaseRAM 信号
    inout wire [31:0] base_ram_data,  // BaseRAM 数据，低 8 位与 CPLD 串口控制器共享
    output wire [19:0] base_ram_addr,  // BaseRAM 地址
    output wire [3:0] base_ram_be_n,  // BaseRAM 字节使能，低有效。如果不使用字节使能，请保持为 0
    output wire base_ram_ce_n,  // BaseRAM 片选，低有效
    output wire base_ram_oe_n,  // BaseRAM 读使能，低有效
    output wire base_ram_we_n,  // BaseRAM 写使能，低有效

    // ExtRAM 信号
    inout wire [31:0] ext_ram_data,  // ExtRAM 数据
    output wire [19:0] ext_ram_addr,  // ExtRAM 地址
    output wire [3:0] ext_ram_be_n,  // ExtRAM 字节使能，低有效。如果不使用字节使能，请保持为 0
    output wire ext_ram_ce_n,  // ExtRAM 片选，低有效
    output wire ext_ram_oe_n,  // ExtRAM 读使能，低有效
    output wire ext_ram_we_n,  // ExtRAM 写使能，低有效

    // 直连串口信号
    output wire txd,  // 直连串口发送端
    input  wire rxd,  // 直连串口接收端

    // Flash 存储器信号，参考 JS28F640 芯片手册
    output wire [22:0] flash_a,  // Flash 地址，a0 仅在 8bit 模式有效，16bit 模式无意义
    inout wire [15:0] flash_d,  // Flash 数据
    output wire flash_rp_n,  // Flash 复位信号，低有效
    output wire flash_vpen,  // Flash 写保护信号，低电平时不能擦除、烧写
    output wire flash_ce_n,  // Flash 片选信号，低有效
    output wire flash_oe_n,  // Flash 读使能信号，低有效
    output wire flash_we_n,  // Flash 写使能信号，低有效
    output wire flash_byte_n, // Flash 8bit 模式选择，低有效。在使用 flash 的 16 位模式时请设为 1

    // USB 控制器信号，参考 SL811 芯片手册
    output wire sl811_a0,
    // inout  wire [7:0] sl811_d,     // USB 数据线与网络控制器的 dm9k_sd[7:0] 共享
    output wire sl811_wr_n,
    output wire sl811_rd_n,
    output wire sl811_cs_n,
    output wire sl811_rst_n,
    output wire sl811_dack_n,
    input  wire sl811_intrq,
    input  wire sl811_drq_n,

    // 网络控制器信号，参考 DM9000A 芯片手册
    output wire dm9k_cmd,
    inout wire [15:0] dm9k_sd,
    output wire dm9k_iow_n,
    output wire dm9k_ior_n,
    output wire dm9k_cs_n,
    output wire dm9k_pwrst_n,
    input wire dm9k_int,

    // 图像输出信号
    output wire [2:0] video_red,    // 红色像素，3 位
    output wire [2:0] video_green,  // 绿色像素，3 位
    output wire [1:0] video_blue,   // 蓝色像素，2 位
    output wire       video_hsync,  // 行同步（水平同步）信号
    output wire       video_vsync,  // 场同步（垂直同步）信号
    output wire       video_clk,    // 像素时钟输出
    output wire       video_de      // 行数据有效信号，用于区分消隐区
);

  /* =========== Demo code begin =========== */

  // PLL 分频示例
  logic locked, clk_10M, clk_20M;
`ifndef SIM
  pll_example clock_gen (
      // Clock in ports
      .clk_in1(clk_50M),  // 外部时钟输入
      // Clock out ports
      .clk_out1(clk_10M),  // 时钟输出 1，频率在 IP 配置界面中设置
      .clk_out2(clk_20M),  // 时钟输出 2，频率在 IP 配置界面中设置
      // Status and control signals
      .reset(reset_btn),  // PLL 复位输入
      .locked(locked)  // PLL 锁定指示输出，"1"表示时钟稳定，
                       // 后级电路复位信号应当由它生成（见下）
  );

  logic reset_of_clk10M;
  // 异步复位，同步释放，将 locked 信号转为后级电路的复位 reset_of_clk10M
  always_ff @(posedge clk_10M or negedge locked) begin
    if (~locked) reset_of_clk10M <= 1'b1;
    else reset_of_clk10M <= 1'b0;
  end
`endif
  logic sys_clk;
  logic sys_rst;
`ifndef SIM
  assign sys_clk  = clk_10M;
  assign sys_rst  = reset_of_clk10M;
`else
  assign sys_clk = clk_50M;
  assign sys_rst = reset_btn;
`endif
  assign uart_rdn = 1'b1;
  assign uart_wrn = 1'b1;

  wire        dau_we;
  wire        dau_re;
  wire [31:0] dau_addr;
  wire [ 3:0] dau_byte_en;
  wire [31:0] dau_data_write;
  wire [31:0] dau_data_read;
  wire        dau_ack;

  wire        dau_instr_re;
  wire [31:0] dau_instr_addr;
  wire [31:0] dau_instr_data;
  wire        dau_instr_ack;

  wire        i_cache_bypass;
  wire        i_cache_invalidate;

  wire        i_cache_re;
  wire [31:0] i_cache_addr;
  wire [31:0] i_cache_data;
  wire        i_cache_ack;

  wire [31:0] i_cache_data_delayed;

  wire        d_cache_bypass;
  wire        d_cache_we;
  wire        d_cache_re;
  wire [31:0] d_cache_addr;
  wire [ 3:0] d_cache_be;
  wire [31:0] d_cache_data_departure;
  wire        d_cache_ack;
  wire [31:0] d_cache_data_arrival;

  wire [31:0] d_cache_data_delayed;

  wire        d_cache_clear;
  wire        d_cache_clear_complete;

  wire        immu_re;
  wire [31:0] immu_addr;
  wire [31:0] immu_data;
  wire        immu_ack;

  wire        dmmu_re;
  wire [31:0] dmmu_addr;
  wire [31:0] dmmu_data;
  wire        dmmu_ack;

  parameter ADDR_WIDTH = 5;
  parameter DATA_WIDTH = 32;
  wire [ADDR_WIDTH - 1 : 0] rf_raddr1;
  wire [DATA_WIDTH - 1 : 0] rf_rdata1;

  wire [ADDR_WIDTH - 1 : 0] rf_raddr2;
  wire [DATA_WIDTH - 1 : 0] rf_rdata2;

  wire rf_we;
  wire [ADDR_WIDTH - 1 : 0] rf_waddr;
  wire [DATA_WIDTH - 1 : 0] rf_wdata;

  wire [31:0] alu_opcode;
  wire [DATA_WIDTH - 1 : 0] alu_in1;
  wire [DATA_WIDTH - 1 : 0] alu_in2;
  wire [DATA_WIDTH - 1 : 0] alu_out;

  wire local_intr;

  wire step;

  logic [11:0] hdata;
  logic [9:0] vdata;
  logic [7:0] pixel;  // VGA 输出像素数据
`ifdef SIM
cache icache(
`else  // VGA

  cache_alt icache (
`endif
      .clock(sys_clk),
      .reset(sys_rst),

      .bypass(i_cache_bypass),
      .flush(1'b0),
      .invalidate(i_cache_invalidate),
      .clear_complete(),

      .cu_we(1'b0),
      .cu_re(i_cache_re),
      .cu_addr(i_cache_addr),
      .cu_be(4'b1111),
      .cu_data_i(32'b0),
      .cu_ack(i_cache_ack),
      .cu_data_o(i_cache_data),

      .cu_data_o_delayed(i_cache_data_delayed),

      .dau_we(),
      .dau_re(dau_instr_re),
      .dau_addr(dau_instr_addr),
      .dau_be(),
      .dau_data_o(),
      .dau_ack(dau_instr_ack),
      .dau_data_i(dau_instr_data)
  );
`ifdef SIM
cache dcache (
`else
cache_alt dcache (
`endif
      .clock(sys_clk),
      .reset(sys_rst),

      .bypass(d_cache_bypass),  /* Hardwire to 1 if you want to explicitly disable D-cache. */
      .flush(d_cache_clear),
      .invalidate(1'b0),
      .clear_complete(d_cache_clear_complete),

      // TO CU.
      .cu_we(d_cache_we),
      .cu_re(d_cache_re),
      .cu_addr(d_cache_addr),
      .cu_be(d_cache_be),
      .cu_data_i(d_cache_data_departure),
      .cu_ack(d_cache_ack),
      .cu_data_o(d_cache_data_arrival),

      .cu_data_o_delayed(d_cache_data_delayed),

      // TO DAU
      .dau_we(dau_we),
      .dau_re(dau_re),
      .dau_addr(dau_addr),
      .dau_be(dau_byte_en),
      .dau_data_o(dau_data_write),
      .dau_ack(dau_ack),
      .dau_data_i(dau_data_read)
  );
  dau_new dau_new_inst (
      .sys_clk(sys_clk),
      .sys_rst(sys_rst),

      // TODO
      .master0_we_i (dau_we),
      .master0_re_i (dau_re),
      .master0_adr_i(dau_addr),
      .master0_sel_i(dau_byte_en),
      .master0_dat_i(dau_data_write),
      .master0_ack_o(dau_ack),
      .master0_dat_o(dau_data_read),
      
      .master1_we_i ('0),
      .master1_re_i (dmmu_re),
      .master1_adr_i(dmmu_addr),
      .master1_sel_i(4'hF),
      .master1_dat_i(32'b0),
      .master1_ack_o(dmmu_ack),
      .master1_dat_o(dmmu_data),

      .master2_we_i ('0),
      .master2_re_i (immu_re),
      .master2_adr_i(immu_addr),
      .master2_sel_i(4'hF),
      .master2_dat_i(32'b0),
      .master2_ack_o(immu_ack),
      .master2_dat_o(immu_data),


      .master3_we_i ('0),
      .master3_re_i (dau_instr_re),
      .master3_adr_i(dau_instr_addr),
      .master3_sel_i(4'b1111),
      .master3_dat_i(32'b0),
      .master3_ack_o(dau_instr_ack),
      .master3_dat_o(dau_instr_data),


      .base_ram_data(base_ram_data),
      .base_ram_addr(base_ram_addr),
      .base_ram_be_n(base_ram_be_n),
      .base_ram_ce_n(base_ram_ce_n),
      .base_ram_oe_n(base_ram_oe_n),
      .base_ram_we_n(base_ram_we_n),

      .ext_ram_data(ext_ram_data),
      .ext_ram_addr(ext_ram_addr),
      .ext_ram_be_n(ext_ram_be_n),
      .ext_ram_ce_n(ext_ram_ce_n),
      .ext_ram_oe_n(ext_ram_oe_n),
      .ext_ram_we_n(ext_ram_we_n),

      .rxd(rxd),
      .txd(txd),

      .flash_a(flash_a),  // Flash 地址，a0 仅在 8bit 模式有效，16bit 模式无意义
      .flash_d(flash_d),  // Flash 数据
      .flash_rp_n(flash_rp_n),  // Flash 复位信号，低有效
      .flash_vpen(flash_vpen),  // Flash 写保护信号，低电平时不能擦除、烧写
      .flash_ce_n(flash_ce_n),  // Flash 片选信号，低有效
      .flash_oe_n(flash_oe_n),  // Flash 读使能信号，低有效
      .flash_we_n(flash_we_n),  // Flash 写使能信号，低有效
      .flash_byte_n(flash_byte_n), // Flash 8bit 模式选择，低有效。在使用 flash 的 16 位模式时请设为 1

      .vga_hdata(hdata),
      .vga_vdata(vdata),
      .vga_hsync(video_hsync),
      .vga_vsync(video_vsync),
      .vga_video_de(video_de),
      .pixel(pixel),
      .clk_50M(clk_50M),

      .local_intr(local_intr)
  );
  register_file registers (
      .clock(sys_clk),
      .reset(sys_rst),

      .read_addr1(rf_raddr1),
      .read_data1(rf_rdata1),

      .read_addr2(rf_raddr2),
      .read_data2(rf_rdata2),

      .we        (rf_we),
      .write_addr(rf_waddr),
      .write_data(rf_wdata)
  );
  defparam registers.WIDTH = 32;

  riscv_alu ralu (
      .opcode(alu_opcode),
      .in_1  (alu_in1),
      .in_2  (alu_in2),
      .out   (alu_out)
  );

  // debouncer deb( 
  //   .CLOCK(sys_clk), 
  //   .RESET(sys_rst), 
  //   .PUSH_I(push_btn), 
  //   .PULSE_OUT(step)
  // );
  wire [31:0] debug_ip;
  cu_pipeline control_unit (
      .clk(sys_clk),
      .rst(sys_rst),
      .fast_clock(clk_50M),

      .immu_re_o  (immu_re),
      .immu_addr_o(immu_addr),
      .immu_data_i(immu_data),
      .immu_ack_i (immu_ack),

      .icache_re_o(i_cache_re),
      .icache_addr_o(i_cache_addr),
      .icache_ack_i(i_cache_ack),
      .icache_data_i(i_cache_data),
      .icache_bypass_o(i_cache_bypass),
      .icache_cache_invalidate(i_cache_invalidate),
      .icache_data_delayed_i(i_cache_data_delayed),
      .dmmu_re_o(dmmu_re),
      .dmmu_addr_o(dmmu_addr),
      .dmmu_data_i(dmmu_data),
      .dmmu_ack_i(dmmu_ack),

      .dcache_we_o   (d_cache_we),
      .dcache_re_o   (d_cache_re),
      .dcache_addr_o (d_cache_addr),
      .dcache_byte_en(d_cache_be),
      .dcache_data_i (d_cache_data_arrival),
      .dcache_data_o (d_cache_data_departure),
      .dcache_ack_i  (d_cache_ack),

      .dcache_bypass_o(d_cache_bypass),
      .dau_cache_clear(d_cache_clear),
      .dau_cache_clear_complete(d_cache_clear_complete),
      .dcache_data_delayed_i(d_cache_data_delayed),

      .rf_raddr1(rf_raddr1),
      .rf_rdata1(rf_rdata1),

      .rf_raddr2(rf_raddr2),
      .rf_rdata2(rf_rdata2),

      .rf_waddr(rf_waddr),
      .rf_wdata(rf_wdata),
      .rf_we   (rf_we   ),

      .alu_opcode(alu_opcode),
      .alu_in1   (alu_in1   ),
      .alu_in2   (alu_in2   ),
      .alu_out   (alu_out   ),

      .step(step),
      .dip_sw(dip_sw),
      .touch_btn(touch_btn),
      .dpy0(dpy0),
      .dpy1(dpy1),
      .leds(leds),
      //.curr_ip_out(debug_ip),

      .local_intr(local_intr),
      .mtime(dau_new_inst.clint.mtime)
  );



  // =========== VGA begin =========== 
  // 图像输出演示，分辨率 800x600@75Hz，像素时钟为 50MHz

  //   assign video_red   = hdata < 266 ? 3'b111 : 0;  // 红色竖条
  //   assign video_green = hdata < 532 && hdata >= 266 ? 3'b111 : 0;  // 绿色竖条
  //   assign video_blue  = hdata >= 532 ? 2'b11 : 0;  // 蓝色竖条
  assign video_red   = pixel[7:5];
  assign video_green = pixel[4:2];
  assign video_blue  = pixel[1:0];
  assign video_clk   = clk_50M;
  vga #(12, 800, 856, 976, 1040, 600, 637, 643, 666, 1, 1) vga800x600at75 (
      .clk        (clk_50M),
      .rst        (sys_rst),
      .hdata      (hdata),        // 横坐标
      .vdata      (vdata),        // 纵坐标
      .hsync      (video_hsync),
      .vsync      (video_vsync),
      .data_enable(video_de)
  );
  /* =========== Demo code end =========== */

endmodule
