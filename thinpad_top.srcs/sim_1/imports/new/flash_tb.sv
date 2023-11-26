`timescale 1ps / 1ps

module flash_tb ();
  wire clk_50M;
  wire clk_11M0592;
  clock osc (
      .clk_11M0592(clk_11M0592),
      .clk_50M    (clk_50M)
  );
  wire [22:0] flash_a;  // Flash ��ַ��a0 ���� 8bit ģʽ��Ч��16bit ģʽ������
  wire [15:0] flash_d;  // Flash ����
  wire flash_rp_n;  // Flash ��λ�źţ�����Ч
  wire flash_vpen;  // Flash д�����źţ��͵�ƽʱ���ܲ�������д
  wire flash_ce_n;  // Flash Ƭѡ�źţ�����Ч
  wire flash_oe_n;  // Flash ��ʹ���źţ�����Ч
  wire flash_we_n;  // Flash дʹ���źţ�����Ч
  wire flash_byte_n; // Flash 8bit ģʽѡ�񣬵���Ч����ʹ�� flash �� 16 λģʽʱ����Ϊ 1

  parameter FLASH_INIT_FILE = "D:\\github\\ucore_os_lab\\labcodes_answer\\lab8\\bin\\ucore.img";

  x28fxxxp30 #(
      .FILENAME_MEM(FLASH_INIT_FILE)
  ) flash (
      .A   ({1'b0, flash_a}),
      .DQ  (flash_d),
      .W_N (flash_we_n),       // Write Enable 
      .G_N (flash_oe_n),       // Output Enable
      .E_N (flash_ce_n),       // Chip Enable
      .L_N (1'b0),             // Latch Enable
      .K   (1'b1),             // Clock
      .WP_N(flash_vpen),       // Write Protect
      .RP_N(flash_rp_n),       // Reset/Power-Down
      .VDD ('d3300),
      .VDDQ('d3300),
      .VPP ('d1800),
      .Info(1'b1)
  );
  reg reset;
  reg wb_cyc_i;
  reg wb_stb_i;
  reg [31:0] wb_adr_i;
  reg [31:0] wb_dat_i;
  reg [3:0] wb_sel_i;
  reg wb_we_i;
  wire read_ready, write_ready;
  flash_controller fc (
      .clk_i(clk_50M),
      .rst_i(reset),

      .wb_cyc_i(wb_cyc_i),
      .wb_stb_i(wb_stb_i),
      .wb_ack_o(),
      .wb_adr_i(wb_adr_i),
      .wb_dat_i(wb_dat_i),
      .wb_dat_o(),
      .wb_sel_i(wb_sel_i),
      .wb_we_i (wb_we_i),

      .flash_d(flash_d),
      .flash_a(flash_a),
      .flash_rp_n(flash_rp_n),
      .flash_vpen(flash_vpen),
      .flash_oe_n(flash_oe_n),
      .flash_ce_n(flash_ce_n),
      .flash_byte_n(flash_byte_n),
      .flash_we_n(flash_we_n),
      .read_ready(read_ready),
      .write_ready(write_ready)
  );
  initial begin
    reset = 1;
    wb_cyc_i = 0;
    wb_stb_i = 0;
    wb_adr_i = 32'd0;
    wb_dat_i = 32'd0;
    wb_sel_i = 4'b0;
    wb_we_i = 0;
    #20;
    reset = 0;
    #400000;
    wb_cyc_i = 1;
    wb_stb_i = 1;
    wb_adr_i = 32'd1024;
    wb_dat_i = 32'd1;
    wb_sel_i = 4'b0011;
    wb_we_i  = 1;

    #30000;
    wb_cyc_i = 0;
    wb_stb_i = 0;
    wb_adr_i = 32'd0;
    wb_dat_i = 32'd0;
    wb_sel_i = 4'b0;
    wb_we_i  = 0;
    // while (!write_ready) #400;
    #36520000;
    wb_cyc_i = 1;
    wb_stb_i = 1;
    wb_adr_i = 32'd1024;
    wb_dat_i = 32'h4000;
    wb_sel_i = 4'b0011;
    wb_we_i  = 1;
    #30000;
    wb_cyc_i = 0;
    wb_stb_i = 0;
    wb_adr_i = 32'd0;
    wb_dat_i = 32'd0;
    wb_sel_i = 4'b0;
    wb_we_i  = 0;
    // while (!read_ready);
    #43000000;
    wb_cyc_i = 1;
    wb_stb_i = 1;
    wb_adr_i = 32'd1024;
    wb_dat_i = 32'd1;
    wb_sel_i = 4'b0011;
    wb_we_i  = 1;
    #30000;
    wb_cyc_i = 0;
    wb_stb_i = 0;
    wb_adr_i = 32'd0;
    wb_dat_i = 32'd0;
    wb_sel_i = 4'b0;
    wb_we_i  = 0;
    // while (!write_ready);
    #800000000;
    wb_cyc_i = 1;
    wb_stb_i = 1;
    wb_adr_i = 32'd1024;
    wb_dat_i = 32'd0;
    wb_sel_i = 4'b0011;
    wb_we_i  = 1;

    #30000;
    wb_cyc_i = 0;
    wb_stb_i = 0;
    wb_adr_i = 32'd0;
    wb_dat_i = 32'd0;
    wb_sel_i = 4'b0;
    wb_we_i  = 0;
    #23520000;
    $finish();
  end
endmodule
