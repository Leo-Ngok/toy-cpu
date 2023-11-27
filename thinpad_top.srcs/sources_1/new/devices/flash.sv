`define DEBUG_ADDR_INCR 2
`define MAX_BLOCK_OFF (510 >> (2 - `DEBUG_ADDR_INCR))
module flash_controller #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    /* Defaults are for 95ns access time part, 66MHz (15.15ns) system clock */
    /* wlwh: cycles for WE assert to WE de-assert: write time */
    parameter WRITE_CYCLES = 4,  /* wlwh = 50ns, tck = 15ns, cycles = 4*/
    /* elqv: cycles from adress  to data valid */
    parameter READ_CYCLES = 7,  /* tsop = 95ns, tck = 15ns, cycles = 5*/
    parameter PAGE_READ_CYCLES = 3,  /* 25 ns (R108) */
    parameter PROBE_CYCLES = 200
) (
    // clk and reset
    input wire clk_i,
    input wire rst_i,

    // wishbone slave interface
    input wire wb_cyc_i,
    input wire wb_stb_i,
    output wire wb_ack_o,
    input wire [ADDR_WIDTH-1:0] wb_adr_i,
    input wire [DATA_WIDTH-1:0] wb_dat_i,
    output wire [DATA_WIDTH-1:0] wb_dat_o,
    input wire [DATA_WIDTH/8-1:0] wb_sel_i,
    input wire wb_we_i,
    // Flash 存储器信号，参考 JS28F640 芯片手册
    output wire [22:0] flash_a,  // Flash 地址，a0 仅在 8bit 模式有效，16bit 模式无意义
    inout wire [15:0] flash_d,  // Flash 数据
    output wire flash_rp_n,  // Flash 复位信号，低有效
    output wire flash_vpen,  // Flash 写保护信号，低电平时不能擦除、烧写
    output wire flash_ce_n,  // Flash 片选信号，低有效
    output wire flash_oe_n,  // Flash 读使能信号，低有效
    output wire flash_we_n,  // Flash 写使能信号，低有效
    output wire flash_byte_n, // Flash 8bit 模式选择，低有效。在使用 flash 的 16 位模式时请设为 1

    output wire write_ready,
    output wire read_ready
);
  // TODO: Implement this module.
  // Terminology: 
  // Block: Memory with size of 512 bytes.
  // Array: the external non-volatile memory.

  // You may read a block during write, however you are not allowed to write a block during read.
  // Memory layout.
  // 0 - 511: a particular block read from array, read only
  // 512-1023: a particular block to be written to array, write only.
  // 1024: lower 14 bits are the block address. write only
  // Writing to this register initiates read/write operation: 
  //  when the 15th bit is set, write operation is initiated.
  //  when deasserted, read operation is initiated.
  // 1025: status register, read only.
  //   LSB(0) is read ready, (1) is write ready.

  typedef enum logic [7:0] {
    INIT,
    SET_DOUBLE_ASYNC,

    CONFIRM_DOUBLE_ASYNC_PREP,
    CONFIRM_DOUBLE_ASYNC,

    WAIT,

    READ_CMD_PREP,
    READ_CMD_ASSIGN,

    READ_FIRST,
    READ,
    READ_PAUSE,

    UNLOCK_CMD_PREP,
    UNLOCK_CMD_ASSIGN,
    UNLOCK_CONFIRM_CMD_PREP,
    UNLOCK_CONFIRM_CMD_ASSIGN,

    BUF_PROGRAM_CMD_PREP,
    BUF_PROGRAM_CMD_ASSIGN,
    SET_LEN_CMD_PREP,
    SET_LEN_CMD_ASSIGN,

    WRITE_PREP,
    WRITE,
    WRITE_CONFIRM_CMD_PREP,
    WRITE_CONFIRM_CMD_ASSIGN,

    WRITE_WAIT,

    WRITE_SUSPEND_PREP,
    WRITE_SUSPEND_ASSIGN,

    WRITE_RESUME_PREP,
    WRITE_RESUME_ASSIGN,

    READ_STAT_CMD_PREP,
    READ_STAT_CMD_ACTION,

    READ_STAT_PREP,
    READ_STAT_ACTION,

    WRITE_READY_PROBE_CMD_PREP,
    WRITE_READY_PROBE_CMD_ASSIGN,

    WRITE_READY_PROBE_PREP,
    WRITE_READY_PROBE_ACTION
  } flash_state_t;

  flash_state_t state, state_n;

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      state <= INIT;
    end else begin
      state <= state_n;
    end
  end

  reg [7:0] cycle_counter;
  reg [1:0] local_page_counter;
  reg [8:0] block_offset;
  reg suspend_flag;
  always_comb begin
    state_n = state;
    case (state)
      INIT: begin
        if (cycle_counter == 8'b0) state_n = SET_DOUBLE_ASYNC;
      end
      SET_DOUBLE_ASYNC: begin
        if (cycle_counter == 8'b0) begin
          state_n = CONFIRM_DOUBLE_ASYNC_PREP;
        end
      end
      CONFIRM_DOUBLE_ASYNC_PREP: begin
        state_n = CONFIRM_DOUBLE_ASYNC;
      end
      CONFIRM_DOUBLE_ASYNC: begin
        if (cycle_counter == 8'b0) begin
          state_n = WAIT;
        end
      end
      WAIT: begin
        if (wb_cyc_i && wb_stb_i && wb_we_i) begin
          if (wb_adr_i == 1024 && wb_sel_i == 4'd3) begin
            if (wb_dat_i[14]) begin
              state_n = UNLOCK_CMD_PREP;
            end else begin
              state_n = READ_CMD_PREP;
            end
          end
        end
      end
      // ==================== Read Array Command =====================
      READ_CMD_PREP: begin
        state_n = READ_CMD_ASSIGN;
      end
      READ_CMD_ASSIGN: begin
        if (cycle_counter == 8'b0) begin
          state_n = READ_PAUSE;
        end
      end
      // ============ Read Array data: block read ====================
      READ_PAUSE: begin
        state_n = READ_FIRST;
      end
      READ_FIRST: begin
        if (cycle_counter == 8'b0) begin
          state_n = READ;
        end
      end
      READ: begin
        if (cycle_counter == 8'b0 && local_page_counter == 2'b0) begin
          if (block_offset == `MAX_BLOCK_OFF) begin
            if (suspend_flag) begin
              state_n = WRITE_RESUME_PREP;
            end else begin
              state_n = WAIT;
            end
          end else state_n = READ_PAUSE;
        end
      end
      // ============ Buffered Program Command ====================
      // ============== Unlock the block first ====================
      UNLOCK_CMD_PREP: begin
        state_n = UNLOCK_CMD_ASSIGN;
      end
      UNLOCK_CMD_ASSIGN: begin
        if (cycle_counter == 8'b0) begin
          state_n = UNLOCK_CONFIRM_CMD_PREP;
        end
      end
      UNLOCK_CONFIRM_CMD_PREP: state_n = UNLOCK_CONFIRM_CMD_ASSIGN;
      UNLOCK_CONFIRM_CMD_ASSIGN: begin
        if (cycle_counter == 8'b0) begin
          state_n = BUF_PROGRAM_CMD_PREP;
        end
      end
      // ============== Buffered Program Command ====================
      BUF_PROGRAM_CMD_PREP: begin
        state_n = BUF_PROGRAM_CMD_ASSIGN;
      end
      BUF_PROGRAM_CMD_ASSIGN: begin
        if (cycle_counter == 8'b0) begin
          state_n = SET_LEN_CMD_PREP;
        end
      end
      SET_LEN_CMD_PREP: begin
        state_n = SET_LEN_CMD_ASSIGN;
      end
      SET_LEN_CMD_ASSIGN: begin
        if (cycle_counter == 8'b0) begin
          state_n = WRITE_PREP;
        end
      end
      // ============== Write to buffer. ====================
      WRITE_PREP: state_n = WRITE;
      WRITE: begin
        if (cycle_counter == 8'b0) begin
          if (block_offset == `MAX_BLOCK_OFF) state_n = WRITE_CONFIRM_CMD_PREP;
          else state_n = WRITE_PREP;
        end
      end
      WRITE_CONFIRM_CMD_PREP: begin
        state_n = WRITE_CONFIRM_CMD_ASSIGN;
      end
      WRITE_CONFIRM_CMD_ASSIGN: begin
        if (cycle_counter == 8'b0) begin

          state_n = WRITE_WAIT;
        end
      end
      WRITE_WAIT: begin
        if (wb_adr_i == 1024 && wb_sel_i == 4'd3) begin
          if (!wb_dat_i[14]) begin
            state_n = WRITE_SUSPEND_PREP;
          end
        end else if (cycle_counter == 8'b0) begin
          state_n = WRITE_READY_PROBE_CMD_PREP;
        end
      end
      WRITE_SUSPEND_PREP: state_n = WRITE_SUSPEND_ASSIGN;
      WRITE_SUSPEND_ASSIGN: begin
        if (cycle_counter == 8'b0) begin
          state_n = READ_STAT_CMD_PREP;
        end
      end
      READ_STAT_CMD_PREP: begin
        state_n = READ_STAT_CMD_ACTION;
      end
      READ_STAT_CMD_ACTION: begin
        if (cycle_counter == 8'b0) begin
          state_n = READ_STAT_PREP;
        end
      end
      READ_STAT_PREP: begin
        state_n = READ_STAT_ACTION;
      end
      READ_STAT_ACTION: begin
        if (cycle_counter == 8'b0) begin
          if (flash_d[7] == 1'b0) begin
            state_n = READ_STAT_CMD_PREP;
          end else begin
            state_n = READ_CMD_PREP;
          end
        end
      end
      WRITE_RESUME_PREP: begin
        state_n = WRITE_RESUME_ASSIGN;
      end
      WRITE_RESUME_ASSIGN: begin
        if (cycle_counter == 8'b0) begin
          state_n = WRITE_WAIT;
        end
      end
      WRITE_READY_PROBE_CMD_PREP: begin
        state_n = WRITE_READY_PROBE_CMD_ASSIGN;
      end
      WRITE_READY_PROBE_CMD_ASSIGN: begin
        if (cycle_counter == 8'b0) begin
          state_n = WRITE_READY_PROBE_PREP;
        end
      end
      WRITE_READY_PROBE_PREP: begin
        state_n = WRITE_READY_PROBE_ACTION;
      end
      WRITE_READY_PROBE_ACTION: begin
        if (cycle_counter == 8'b0) begin
          if (flash_d[7] == 1'b0) begin
            state_n = WRITE_WAIT;
          end else begin
            state_n = WAIT;
          end
        end
      end
    endcase
  end
  // TODO: Replace registers with BRAM.
  // An example of loading and writing with regards to read_buf is given.
  // Now let's create another flash_buffer, for replacement of write_block_values.
  reg [15:0] block_id;  // [13:0] valid  [14] set when write, not set when read. 
  reg [127:0][31:0] read_block_values;
  reg [127:0][31:0] write_block_values;

  reg [6:0] read_buf_in_addr;
  reg [31:0] read_buf_in_data;
  reg [3:0] read_buf_we;

  reg [6:0] read_buf_out_addr;
  wire [31:0] read_buf_out_data;

  flash_buffer read_buf (
      .clka (clk_i),
      .clkb (clk_i),
      // write ports, used when data fetched from non-volatile array.
      .addra(read_buf_in_addr),
      .dina (read_buf_in_data),
      .wea  (read_buf_we),
      // read ports, used for wishbone requests.
      .addrb(read_buf_out_addr),
      .doutb(read_buf_out_data)
  );

  reg [6:0] write_buf_addr;
  reg [22:0] flash_addr_o_r;
  reg [15:0] flash_data_o_r;
  reg flash_we_n_o_r;
  reg flash_oe_n_o_r;

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      flash_we_n_o_r <= 1'b1;
      flash_oe_n_o_r <= 1'b1;
      flash_addr_o_r <= '0;
      flash_data_o_r <= '0;
      cycle_counter <= WRITE_CYCLES;
      block_offset <= 0;
      local_page_counter <= 3;
      suspend_flag <= 0;
      read_block_values <= '0;
    end else begin
      case (state)
        INIT: begin
          // move to set double async.
          flash_data_o_r <= 16'h0060;
          flash_addr_o_r <= {7'b0, 16'h4000};
          if (cycle_counter > 0) begin
            cycle_counter <= cycle_counter - 1;
          end else begin
            cycle_counter  <= WRITE_CYCLES;
            flash_we_n_o_r <= 0;
          end

        end
        SET_DOUBLE_ASYNC, CONFIRM_DOUBLE_ASYNC, READ_CMD_ASSIGN,
        UNLOCK_CMD_ASSIGN, UNLOCK_CONFIRM_CMD_ASSIGN,
        BUF_PROGRAM_CMD_ASSIGN, SET_LEN_CMD_ASSIGN, 
        WRITE_SUSPEND_ASSIGN, 
        READ_STAT_CMD_ACTION,
        WRITE_READY_PROBE_CMD_ASSIGN: begin
          if (cycle_counter > 0) begin
            cycle_counter <= cycle_counter - 1;
          end else begin
            flash_we_n_o_r <= 1'b1;
            flash_oe_n_o_r <= 1'b1;
          end
        end
        CONFIRM_DOUBLE_ASYNC_PREP: begin
          flash_data_o_r <= 16'h0004;
          // flash_addr_o_r <= {6'b0, 16'h2000, 1'b0}; 
          flash_we_n_o_r <= 1'b0;
          cycle_counter  <= WRITE_CYCLES;
        end
        READ_CMD_PREP: begin
          flash_we_n_o_r <= 1'b0;
          flash_addr_o_r <= {block_id[13:0], {(8 + `DEBUG_ADDR_INCR - 1) {1'b0}}};
          flash_data_o_r <= 16'h00ff;
          cycle_counter  <= WRITE_CYCLES;
          block_offset   <= 0;
        end
        READ_PAUSE: begin
          local_page_counter <= 3;
          cycle_counter <= READ_CYCLES;
          flash_oe_n_o_r <= 1'b0;
          flash_addr_o_r <= {block_id[13:0], {(8 + `DEBUG_ADDR_INCR - 1) {1'b0}}} + block_offset;
        end
        READ_FIRST: begin
          if (cycle_counter > 0) begin
            cycle_counter <= cycle_counter - 1;
          end else begin
            local_page_counter <= local_page_counter - 1;
            block_offset <= block_offset + `DEBUG_ADDR_INCR;
            cycle_counter <= PAGE_READ_CYCLES;
            flash_addr_o_r <= flash_addr_o_r + `DEBUG_ADDR_INCR;
            read_block_values[(block_offset>>`DEBUG_ADDR_INCR)][15:0] <= flash_d;
          end
        end
        READ: begin
          if (cycle_counter > 0) begin
            cycle_counter <= cycle_counter - 1;
          end else begin
            block_offset   <= block_offset + `DEBUG_ADDR_INCR;
            flash_addr_o_r <= flash_addr_o_r + `DEBUG_ADDR_INCR;
            if (block_offset[`DEBUG_ADDR_INCR-1]) begin
              read_block_values[(block_offset>>`DEBUG_ADDR_INCR)][31:16] <= flash_d;

            end else begin
              read_block_values[(block_offset>>`DEBUG_ADDR_INCR)][15:0] <= flash_d;
            end
            if (local_page_counter > 0) begin
              local_page_counter <= local_page_counter - 1;
              cycle_counter <= PAGE_READ_CYCLES;
            end else begin
              flash_oe_n_o_r <= 1'b1;
              if (block_offset == `MAX_BLOCK_OFF) block_offset <= 0;
            end
          end
        end
        UNLOCK_CMD_PREP: begin
          flash_we_n_o_r <= 1'b0;
          flash_addr_o_r <= {block_id[13:0], {(8 + `DEBUG_ADDR_INCR - 1) {1'b0}}};
          flash_data_o_r <= 16'h0060;
          cycle_counter  <= WRITE_CYCLES;
        end
        UNLOCK_CONFIRM_CMD_PREP: begin
          flash_we_n_o_r <= 1'b0;
          flash_data_o_r <= 16'h00D0;
          cycle_counter  <= WRITE_CYCLES;
        end
        BUF_PROGRAM_CMD_PREP: begin
          flash_we_n_o_r <= 1'b0;
          flash_data_o_r <= 16'h00E8;
          cycle_counter  <= WRITE_CYCLES;
        end
        SET_LEN_CMD_PREP: begin
          flash_we_n_o_r <= 1'b0;
          flash_data_o_r <= 16'h00FF;  // A whole block
          cycle_counter  <= WRITE_CYCLES;
          block_offset   <= 0;
        end
        WRITE_PREP: begin
          flash_we_n_o_r <= 1'b0;
          flash_addr_o_r <= {block_id[13:0], {(8 + `DEBUG_ADDR_INCR - 1) {1'b0}}} + block_offset;
          if (block_offset[`DEBUG_ADDR_INCR-1]) begin
            flash_data_o_r <= read_block_values[block_offset[(`DEBUG_ADDR_INCR)+:7]][31:16];
          end else begin
            flash_data_o_r <= read_block_values[block_offset[(`DEBUG_ADDR_INCR)+:7]][15:0];
          end
          cycle_counter <= WRITE_CYCLES;
        end
        WRITE: begin
          if (cycle_counter != 8'b0) begin
            cycle_counter <= cycle_counter - 1;
          end else begin
            block_offset   <= block_offset + `DEBUG_ADDR_INCR;
            flash_we_n_o_r <= 1;
          end
        end
        WRITE_CONFIRM_CMD_PREP: begin
          flash_we_n_o_r <= 1'b0;
          flash_data_o_r <= 16'h00D0;  // A whole block
          cycle_counter  <= WRITE_CYCLES;
          block_offset   <= 0;
        end
        WRITE_SUSPEND_PREP: begin
          flash_we_n_o_r <= 1'b0;
          flash_data_o_r <= 16'h00B0;  // A whole block
          cycle_counter  <= WRITE_CYCLES;
        end
        READ_STAT_CMD_PREP, WRITE_READY_PROBE_CMD_PREP: begin
          flash_we_n_o_r <= 1'b0;
          flash_data_o_r <= 16'h0070;  // A whole block
          cycle_counter  <= WRITE_CYCLES;
        end
        READ_STAT_PREP, WRITE_READY_PROBE_PREP: begin
          flash_oe_n_o_r <= 1'b0;
          cycle_counter  <= READ_CYCLES;
        end
        READ_STAT_ACTION: begin
          if (cycle_counter > 0) begin
            cycle_counter <= cycle_counter - 1;
          end else begin
            flash_we_n_o_r <= 1'b1;
            flash_oe_n_o_r <= 1'b1;
            if (flash_d[7] == 1'b1 && flash_d[2] == 1'b1) begin
              suspend_flag <= 1;
            end
          end
        end
        WRITE_RESUME_PREP: begin
          flash_we_n_o_r <= 1'b0;
          flash_data_o_r <= 16'h00D0;  // A whole block
          cycle_counter  <= WRITE_CYCLES;
          suspend_flag   <= 0;
        end
        WRITE_RESUME_ASSIGN: begin
          if (cycle_counter > 0) begin
            cycle_counter <= cycle_counter - 1;
          end else begin
            flash_we_n_o_r <= 1'b1;
            flash_oe_n_o_r <= 1'b1;
            cycle_counter  <= PROBE_CYCLES;
          end
        end
        WRITE_CONFIRM_CMD_ASSIGN: begin
          if (cycle_counter > 0) begin
            cycle_counter <= cycle_counter - 1;
          end else begin
            flash_we_n_o_r <= 1'b1;
            flash_oe_n_o_r <= 1'b1;
            cycle_counter  <= PROBE_CYCLES;
          end
        end
        WRITE_WAIT: begin
          if (cycle_counter > 0) begin
            cycle_counter <= cycle_counter - 1;
          end
        end
        WRITE_READY_PROBE_ACTION: begin
          if (cycle_counter > 0) begin
            cycle_counter <= cycle_counter - 1;
          end else begin
            flash_we_n_o_r <= 1'b1;
            flash_oe_n_o_r <= 1'b1;
            cycle_counter  <= PROBE_CYCLES;
          end
        end
      endcase
    end
  end

  reg [6:0] block_num;
  reg hibit;
  reg [15:0] flash_data_o_c;
  always_comb begin
    block_num = 0;
    hibit = 0;

    read_buf_we = 4'b0;
    read_buf_in_addr = 7'b0;
    read_buf_in_data = 32'b0;

    read_buf_out_addr = 7'b0;

    flash_data_o_c = 16'b0;
    case (state)
      READ_FIRST, READ: begin
        block_num = block_offset >> (`DEBUG_ADDR_INCR);
        hibit = block_offset[`DEBUG_ADDR_INCR-1];
        if (cycle_counter == 8'b0) begin
          read_buf_we = hibit ? 4'b1100 : 4'b0011;
          read_buf_in_addr = block_num;
          read_buf_in_data = hibit ? {flash_d, 16'b0} : {16'b0, flash_d};
        end
      end
      WRITE_PREP: begin
        read_buf_out_addr = block_offset >> (`DEBUG_ADDR_INCR);
      end
      WRITE: begin
        read_buf_out_addr = block_offset >> (`DEBUG_ADDR_INCR);
        hibit = block_offset[`DEBUG_ADDR_INCR-1];
        flash_data_o_c = hibit ? read_buf_out_data[31:16] : read_buf_out_data[15:0];
      end
    endcase
  end

  reg [31:0] wb_dat_o_c;
  reg wb_ack_o_r;
  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      wb_ack_o_r <= 0;
    end else begin
      if (wb_ack_o_r) wb_ack_o_r <= 0;
      else if (wb_cyc_i && wb_stb_i) wb_ack_o_r <= 1;
    end
  end
  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      block_id <= 0;
      write_block_values <= '0;
      wb_dat_o_c <= 32'b0;
    end else begin
      if (wb_cyc_i && wb_stb_i) begin
        if (wb_we_i) begin
          if (wb_adr_i == 1024 && wb_sel_i == 4'd3) begin
            // specify block id, and start reading/writing block.
            block_id <= wb_dat_i[15:0];
          end else if (32'd512 <= wb_adr_i && wb_adr_i < 32'd1024) begin
            // buffer write block data.
            if (wb_sel_i[0]) write_block_values[wb_adr_i[8:2]][7:0] <= wb_dat_i[7:0];
            if (wb_sel_i[1]) write_block_values[wb_adr_i[8:2]][15:8] <= wb_dat_i[15:8];
            if (wb_sel_i[2]) write_block_values[wb_adr_i[8:2]][23:16] <= wb_dat_i[23:16];
            if (wb_sel_i[3]) write_block_values[wb_adr_i[8:2]][31:24] <= wb_dat_i[31:24];
          end
        end else begin
          if (32'd0 <= wb_adr_i && wb_adr_i < 32'd512) begin
            // quest for read data.
            wb_dat_o_c[7:0]   <= (wb_sel_i[0]) ? read_block_values[wb_adr_i[8:2]][7:0] : 8'b0;
            wb_dat_o_c[15:8]  <= (wb_sel_i[0]) ? read_block_values[wb_adr_i[8:2]][15:8] : 8'b0;
            wb_dat_o_c[23:16] <= (wb_sel_i[0]) ? read_block_values[wb_adr_i[8:2]][23:16] : 8'b0;
            wb_dat_o_c[31:24] <= (wb_sel_i[0]) ? read_block_values[wb_adr_i[8:2]][31:24] : 8'b0;
          end else if (wb_adr_i == 1028) begin
            wb_dat_o_c <= {30'b0, write_ready, read_ready};
          end
        end
      end
    end
  end
  assign flash_a = flash_addr_o_r;
  assign flash_d = (flash_we_n) ? 16'bz : flash_data_o_r;
  assign flash_rp_n = 1'b1;
  assign flash_vpen = 1'b1;
  assign flash_oe_n = flash_oe_n_o_r;
  assign flash_we_n = flash_we_n_o_r;
  assign flash_ce_n = 1'b0;
  assign flash_byte_n = 1'b1;
  assign read_ready = state == WAIT || (state == WRITE_WAIT && cycle_counter > 10);
  assign write_ready = state == WAIT;

  assign wb_dat_o = wb_dat_o_c;
  assign wb_ack_o = wb_ack_o_r && (0 <= wb_adr_i && wb_adr_i <= 1025);
endmodule


// void read_a_block(unsigned short block_id, void *target_memory_address) {
//     while(!can_read());
//     read_block(block_id); // SBI.
//     while(!can_read()); // 
//     transfer_block(target_memory_location); // SBI
// }

// void write_a_block(unsigned short block_id, void *source_memory_address) {
//     while(!can_read());
//     transfer_memory(source_memory_address);
//     while(!can_write());
//     write_block(block_id); // SBI.
//     while(!can_write());
// }

// int can_read() {
//     return (*((unsigned short *)1025) & 0x01);
// }

// int can_write() {
//     return (*((unsigned short *)1025) & 0x01);
// }

