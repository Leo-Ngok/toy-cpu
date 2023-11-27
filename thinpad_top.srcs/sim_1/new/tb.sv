`timescale 1ns / 1ps
module tb;

  wire clk_50M, clk_11M0592;

  reg push_btn;  // BTN5 ????????????????��???????? 1
  reg reset_btn;  // BTN6 ??��?????????????��????????? 1

  reg [3:0] touch_btn;  // BTN1~BTN4???????????????? 1
  reg [31:0] dip_sw;  // 32 ��?????????????ON????? 1

  wire [15:0] leds;  // 16 ?? LED?????? 1 ????
  wire [7:0] dpy0;  // ??????��????????��??????? 1 ????
  wire [7:0] dpy1;  // ??????��????????��??????? 1 ????

  wire txd;  // ?????????????
  wire rxd;  // ????????????

  wire [31:0] base_ram_data;  // BaseRAM ??????? 8 ��?? CPLD ?????????????
  wire [19:0] base_ram_addr;  // BaseRAM ???
  wire [3:0] base_ram_be_n;  // BaseRAM ???????????��??????????????????????? 0
  wire base_ram_ce_n;  // BaseRAM ????????????
  wire base_ram_oe_n;  // BaseRAM ????????????
  wire base_ram_we_n;  // BaseRAM ��??????????

  wire [31:0] ext_ram_data;  // ExtRAM ????
  wire [19:0] ext_ram_addr;  // ExtRAM ???
  wire [3:0] ext_ram_be_n;  // ExtRAM ???????????��??????????????????????? 0
  wire ext_ram_ce_n;  // ExtRAM ????????????
  wire ext_ram_oe_n;  // ExtRAM ????????????
  wire ext_ram_we_n;  // ExtRAM ��??????????

  wire [22:0] flash_a;  // Flash ?????a0 ???? 8bit ????��??16bit ????????
  wire [15:0] flash_d;  // Flash ????
  wire flash_rp_n;  // Flash ??��????????��
  wire flash_vpen;  // Flash ��??????????????????????????
  wire flash_ce_n;  // Flash ??????????????
  wire flash_oe_n;  // Flash ???????????????
  wire flash_we_n;  // Flash ��?????????????
  wire flash_byte_n;  // Flash 8bit ????????��??????? flash ?? 16 ��????????? 1

  wire uart_rdn;  // ????????????????
  wire uart_wrn;  // ��??????????????
  wire uart_dataready;  // ?????????????
  wire uart_tbre;  // ????????????
  wire uart_tsre;  // ??????????????

  // Windows ??????��???????????��???? "D:\\foo\\bar.bin"
  parameter BASE_RAM_INIT_FILE = "D:\\github\\THU_PASS\\Organization\\supervisor-rv\\kernel\\kernel_final.bin"; // BaseRAM ???????????????????????��??
  // parameter BASE_RAM_INIT_FILE = "D:\\github\\ucore_os_lab\\labcodes_answer\\lab8\\bin\\rbl.img"; // BaseRAM ???????????????????????��??
  parameter EXT_RAM_INIT_FILE = "D:\\github\\ucore_os_lab\\labcodes_answer\\lab8\\bin\\ucore.img";  // ExtRAM ???????????????????????��??
  parameter FLASH_INIT_FILE = "D:\\github\\ucore_os_lab\\labcodes_answer\\lab8\\bin\\ucore.img";  // Flash ???????????????????????��??

  task write_u32;
    input [31:0] data;
    begin
      uart.pc_send_byte(data[7:0]);
      uart.pc_send_byte(data[15:8]);
      uart.pc_send_byte(data[23:16]);
      uart.pc_send_byte(data[31:24]);
    end
  endtask

  task write_asm;
    input string filename;
    input [31:0] base_addr;
    begin
      integer fd, sz;
      reg [31:0] data[0:10000000];
      fd = $fopen(filename, "rb");
      if (fd == 0) begin
        $display("Error: no file named $s\n", filename);
      end else begin
        sz = $fread(data, fd);
        $display("Read %s, size = %d", filename, sz);
        for (int i = 0; i < sz / 4; ++i) begin

          $display("Sending 0x%08x to supervisor at 0x%08x", data[i], base_addr + i * 4);
          uart.pc_send_byte(8'h41);
          write_u32(base_addr + i * 4);
          write_u32(32'd4);
          write_u32({data[i][7:0], data[i][15:8], data[i][23:16], data[i][31:24]});
        end
      end
    end
  endtask
  initial begin
    // ????????????????????????��????��
    dip_sw = 32'h0;
    touch_btn = 0;
    reset_btn = 0;
    push_btn = 0;
    #6000000;

    // uart.pc_send_byte(8'h47);  // G = 47, T = 54, A = 41
    // // 0x800010a8 <UTEST_PUTC>
    // // 0x80001080 <UTEST_4MDCT>
    // uart.pc_send_byte(8'h80);
    // uart.pc_send_byte(8'h10);
    // uart.pc_send_byte(8'h00);
    // uart.pc_send_byte(8'h80);
    //write_asm("D:\\github\\THU_PASS\\Organization\\supervisor-rv\\kernel\\read_flash.bin",
    //          32'h8010_0000);
    #300000;
    //uart.pc_send_byte(8'h47);
    //write_u32(32'h0);
    //write_u32(32'h80100000);
  end

  // ?????????????
  thinpad_top dut (
      .clk_50M(clk_50M),
      .clk_11M0592(clk_11M0592),
      .push_btn(push_btn),
      .reset_btn(reset_btn),
      .touch_btn(touch_btn),
      .dip_sw(dip_sw),
      .leds(leds),
      .dpy1(dpy1),
      .dpy0(dpy0),
      .txd(txd),
      .rxd(rxd),
      .uart_rdn(uart_rdn),
      .uart_wrn(uart_wrn),
      .uart_dataready(uart_dataready),
      .uart_tbre(uart_tbre),
      .uart_tsre(uart_tsre),
      .base_ram_data(base_ram_data),
      .base_ram_addr(base_ram_addr),
      .base_ram_ce_n(base_ram_ce_n),
      .base_ram_oe_n(base_ram_oe_n),
      .base_ram_we_n(base_ram_we_n),
      .base_ram_be_n(base_ram_be_n),
      .ext_ram_data(ext_ram_data),
      .ext_ram_addr(ext_ram_addr),
      .ext_ram_ce_n(ext_ram_ce_n),
      .ext_ram_oe_n(ext_ram_oe_n),
      .ext_ram_we_n(ext_ram_we_n),
      .ext_ram_be_n(ext_ram_be_n),
      .flash_d(flash_d),
      .flash_a(flash_a),
      .flash_rp_n(flash_rp_n),
      .flash_vpen(flash_vpen),
      .flash_oe_n(flash_oe_n),
      .flash_ce_n(flash_ce_n),
      .flash_byte_n(flash_byte_n),
      .flash_we_n(flash_we_n)
  );
  // ?????
  clock osc (
      .clk_11M0592(clk_11M0592),
      .clk_50M    (clk_50M)
  );
  // CPLD ??????????
  cpld_model cpld (
      .clk_uart(clk_11M0592),
      .uart_rdn(uart_rdn),
      .uart_wrn(uart_wrn),
      .uart_dataready(uart_dataready),
      .uart_tbre(uart_tbre),
      .uart_tsre(uart_tsre),
      .data(base_ram_data[7:0])
  );
  // ?????????????
  uart_model uart (
      .rxd(txd),
      .txd(rxd)
  );
  // BaseRAM ???????
  sram_model base1 (
      .DataIO(base_ram_data[15:0]),
      .Address(base_ram_addr[19:0]),
      .OE_n(base_ram_oe_n),
      .CE_n(base_ram_ce_n),
      .WE_n(base_ram_we_n),
      .LB_n(base_ram_be_n[0]),
      .UB_n(base_ram_be_n[1])
  );
  sram_model base2 (
      .DataIO(base_ram_data[31:16]),
      .Address(base_ram_addr[19:0]),
      .OE_n(base_ram_oe_n),
      .CE_n(base_ram_ce_n),
      .WE_n(base_ram_we_n),
      .LB_n(base_ram_be_n[2]),
      .UB_n(base_ram_be_n[3])
  );
  // ExtRAM ???????
  sram_model ext1 (
      .DataIO(ext_ram_data[15:0]),
      .Address(ext_ram_addr[19:0]),
      .OE_n(ext_ram_oe_n),
      .CE_n(ext_ram_ce_n),
      .WE_n(ext_ram_we_n),
      .LB_n(ext_ram_be_n[0]),
      .UB_n(ext_ram_be_n[1])
  );
  sram_model ext2 (
      .DataIO(ext_ram_data[31:16]),
      .Address(ext_ram_addr[19:0]),
      .OE_n(ext_ram_oe_n),
      .CE_n(ext_ram_ce_n),
      .WE_n(ext_ram_we_n),
      .LB_n(ext_ram_be_n[2]),
      .UB_n(ext_ram_be_n[3])
  );
  // Flash ???????
  x28fxxxp30 #(
      .FILENAME_MEM(FLASH_INIT_FILE)
  ) flash (
      .A   (flash_a[1+:22]),
      .DQ  (flash_d),
      .W_N (flash_we_n),      // Write Enable 
      .G_N (flash_oe_n),      // Output Enable
      .E_N (flash_ce_n),      // Chip Enable
      .L_N (1'b0),            // Latch Enable
      .K   (1'b0),            // Clock
      .WP_N(flash_vpen),      // Write Protect
      .RP_N(flash_rp_n),      // Reset/Power-Down
      .VDD ('d3300),
      .VDDQ('d3300),
      .VPP ('d1800),
      .Info(1'b1)
  );

  initial begin
    wait (flash_byte_n == 1'b0);
    $display("8-bit Flash interface is not supported in simulation!");
    $display("Please tie flash_byte_n to high");
    $stop;
  end

  // ????????? BaseRAM
  initial begin
    reg [31:0] tmp_array[0:1048575];
    integer n_File_ID, n_Init_Size;
    n_File_ID = $fopen(BASE_RAM_INIT_FILE, "rb");
    if (!n_File_ID) begin
      n_Init_Size = 0;
      $display("Failed to open BaseRAM init file");
    end else begin
      n_Init_Size = $fread(tmp_array, n_File_ID);
      n_Init_Size /= 4;
      $fclose(n_File_ID);
    end
    $display("BaseRAM Init Size(words): %d", n_Init_Size);
    for (integer i = 0; i < n_Init_Size; i++) begin
      base1.mem_array0[i] = tmp_array[i][24+:8];
      base1.mem_array1[i] = tmp_array[i][16+:8];
      base2.mem_array0[i] = tmp_array[i][8+:8];
      base2.mem_array1[i] = tmp_array[i][0+:8];
    end
  end

  // ????????? ExtRAM
  initial begin
    reg [31:0] tmp_array[0:1048575];
    integer n_File_ID, n_Init_Size;
    n_File_ID = $fopen(EXT_RAM_INIT_FILE, "rb");
    if (!n_File_ID) begin
      n_Init_Size = 0;
      $display("Failed to open ExtRAM init file");
    end else begin
      n_Init_Size = $fread(tmp_array, n_File_ID);
      n_Init_Size /= 4;
      $fclose(n_File_ID);
    end
    $display("ExtRAM Init Size(words): %d", n_Init_Size);
    for (integer i = 0; i < n_Init_Size; i++) begin
      ext1.mem_array0[i] = tmp_array[i][24+:8];
      ext1.mem_array1[i] = tmp_array[i][16+:8];
      ext2.mem_array0[i] = tmp_array[i][8+:8];
      ext2.mem_array1[i] = tmp_array[i][0+:8];
    end
  end
endmodule
