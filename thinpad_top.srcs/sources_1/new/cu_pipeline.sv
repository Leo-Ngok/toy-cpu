module pipeline_state_recorder(
  input wire if1_stall,
  input wire if2_stall,
  input wire id_stall,
  input wire ex_stall,
  input wire mem_stall,
  input wire if2_bubble,
  input wire id_bubble,
  input wire ex_bubble,
  input wire mem_bubble,
  input wire wb_bubble
); endmodule

module cu_pipeline (
    input  wire        clk,
    input  wire        rst,
    input  wire        fast_clock,
    // IMMU
    output wire        immu_re_o,
    output wire [31:0] immu_addr_o,
    input  wire [31:0] immu_data_i,
    input  wire        immu_ack_i,
    // I-Cache
    output wire        icache_re_o,
    output wire [31:0] icache_addr_o,
    input  wire [31:0] icache_data_i,
    input  wire        icache_ack_i,
    output wire        icache_bypass_o,
    output wire        icache_cache_invalidate,
    input  wire [31:0] icache_data_delayed_i,
    // DMMU
    output wire        dmmu_re_o,
    output wire [31:0] dmmu_addr_o,
    input  wire [31:0] dmmu_data_i,
    input  wire        dmmu_ack_i,
    // D-Cache
    output wire        dcache_we_o,
    output wire        dcache_re_o,
    output wire [31:0] dcache_addr_o,
    output wire [ 3:0] dcache_byte_en,
    output wire [31:0] dcache_data_o,
    input  wire [31:0] dcache_data_i,
    input  wire        dcache_ack_i,
    output wire        dcache_bypass_o,

    output wire dau_cache_clear,
    input wire dau_cache_clear_complete,
    input wire [31:0] dcache_data_delayed_i,

    // Register file
    output wire [ 4:0] rf_raddr1,
    input  wire [31:0] rf_rdata1,

    output wire [ 4:0] rf_raddr2,
    input  wire [31:0] rf_rdata2,

    output wire [ 4:0] rf_waddr,
    output wire [31:0] rf_wdata,
    output wire        rf_we,

    // ALU
    output wire [31:0] alu_opcode,
    output wire [31:0] alu_in1,
    output wire [31:0] alu_in2,
    input  wire [31:0] alu_out,

    // Control signals
    input  wire        step,
    input  wire [31:0] dip_sw,
    input  wire [ 3:0] touch_btn,
    //output wire [31:0] curr_ip_out,
    output wire [ 7:0] dpy0,
    output wire [ 7:0] dpy1,
    output wire [15:0] leds,

    input wire        local_intr,
    input wire [63:0] mtime
);
  // ========================================== IF0 ==========================================
  wire [31:0] next_ip;  // input to the prefetch pc register.
  wire [31:0] if1_ip;
  // ========================================== IF1 ==========================================
  wire [31:0] satp;
  wire [31:0] if1_alt_next_ip;
  wire        if1_mmu_ack;
  wire [31:0] if1_mmu_pa;

  wire        if1_page_fault;
  wire        if1_addr_misaligned;
  wire        if1_no_exec_access;
  // ========================================== IF2 ==========================================
  wire [31:0] if2_ip;
  wire [31:0] if2_alt_next_ip;
  wire [31:0] if2_ppc;
  wire        if2_is_bubble;
  wire        if2_page_fault;
  wire        if2_addr_misaligned;
  wire        if2_no_exec_access;
  // ========================================== ID ==========================================
  // From IF stage
  wire [31:0] id_instr;
  wire [31:0] id_ip;
  wire [31:0] id_alt_next_ip;
  // Intra stage signals.
  wire [ 4:0] decoder_raddr1;
  wire [ 4:0] decoder_raddr2;

  wire [ 4:0] decoder_waddr;
  wire        decoder_we;

  wire        decoder_mre;
  wire        decoder_mwe;
  wire        decoder_csracc;
  wire        decoder_clear_icache;
  wire        decoder_clear_tlb;

  wire [31:0] id_mux_alu_op1;
  wire [31:0] id_mux_alu_op2;
  wire [31:0] decoder_imm;
  // ========================================== ALU ==========================================
  // From ID stage
  wire [31:0] alu_ip;
  wire [31:0] alu_instr;
  wire [31:0] alu_alt_ip_pred;

  wire [31:0] alu_op1;
  wire [31:0] alu_op2;
  wire [31:0] ex_imm;

  wire        alu_mwe;
  wire        alu_mre;
  wire [31:0] alu_mwdata;

  wire        alu_csracc;
  wire [31:0] alu_csrdata;

  wire        alu_clear_tlb;
  wire        alu_clear_icache;

  wire        alu_wbwe;
  wire [ 4:0] alu_wbaddr;

  // Intra stage signals (actually, {take|new} ip forwards to pre if).
  wire        alu_take_ip;
  wire [31:0] alu_new_ip;
  wire        alu_is_jump;

  wire [31:0] alu_mwdata_adjusted;
  wire [ 3:0] alu_mbe_adjusted;
  wire [31:0] alu_wbdata_adjusted;

  wire        alu_is_jump_alt;
  wire        alu_dyn_take_ip;
  wire [31:0] alu_dyn_new_ip;
  // D-MMU
  wire        alu_dmmu_ack;
  wire [31:0] alu_dmmu_pa;

  wire        alu_dmmu_page_fault;
  wire        alu_dmmu_read_violation;
  wire        alu_dmmu_write_violation;
  wire        alu_dmmu_addr_misaligned;
  wire        alu_dmmu_error;
  // ========================================== MEM ==========================================
  // From ALU stage
  wire [31:0] mem_instr;
  wire [31:0] mem_ip;

  wire        mem_mwe;
  wire        mem_mre;
  wire [ 3:0] mem_mbe;
  wire [31:0] mem_addr;
  wire [31:0] mem_data;

  wire        mem_csracc;
  wire [31:0] mem_csrdt;

  wire        mem_clear_tlb;
  wire        mem_clear_icache;

  wire        mem_wbwe;
  wire [ 4:0] mem_wbaddr;
  wire [31:0] mem_wbdata;

  wire [31:0] mem_dmmu_pa;
  wire        mem_dmmu_page_fault;
  wire        mem_dmmu_read_violation;
  wire        mem_dmmu_write_violation;
  wire        mem_dmmu_addr_misaligned;
  // Stage generated signals.
  wire [31:0] mem_rf_wdata;
  wire        mem_pause;

  wire [31:0] mem_csrwb;

  wire        mem_csr_take_ip;
  wire [31:0] mem_csr_new_ip;

  wire        mem_invalidate_tlb;
  wire        mem_invalidate_icache;

  // ========================================== WB ==========================================
  wire [31:0] wb_ip;
  wire [31:0] wb_instr;
  wire [ 4:0] wb_addr;

  wire        wb_we;
  wire        wb_mre;
  wire        wb_csracc;

  wire [31:0] wb_maddr;
  wire [31:0] wb_mdata;
  wire [31:0] wb_csrdata;
  wire [31:0] wb_aludata;
  // Stage generated signals.
  wire [31:0] wb_mrdata_adjusted;
  wire [31:0] wb_data;
  // Bubble case
  wire [31:0] if1_if2_flush_ip;
  wire [31:0] if_id_flush_ip;
  wire [31:0] id_alu_flush_ip;
  wire [31:0] alu_mem_flush_ip;
  wire [31:0] mem_wb_flush_ip;


  wire        if_id_page_fault;
  wire        if_id_addr_misaligned;
  wire        if_id_no_exec_access;

  wire        id_instr_page_fault;
  wire        id_instr_addr_misaligned;
  wire        id_instr_no_exec_access;

  wire        ex_instr_page_fault;
  wire        ex_instr_addr_misaligned;
  wire        ex_instr_no_exec_access;

  wire        mem_instr_page_fault;
  wire        mem_instr_addr_misaligned;
  wire        mem_instr_no_exec_access;
  // ========================================== IF1 ==========================================
  mmu_iter alt_instr_mm (
      .clock(clk),
      .reset(rst),

      .satp(satp),
      .va  (if1_ip),
      .pa  (immu_addr_o),

      .data_we_i(1'b0),
      .data_re_i(1'b1),
      .byte_en_i(4'b1111),
      .data_departure_i(32'b0),
      .data_arrival_o(if1_mmu_pa),
      .data_ack_o(if1_mmu_ack),

      .data_we_o(),
      .data_re_o(immu_re_o),
      .byte_en_o(),
      .data_departure_o(),
      .data_arrival_i(immu_data_i),
      .data_ack_i(immu_ack_i),

      .bypass(),
      .invalidate_tlb(mem_invalidate_tlb),
      .if_enable(1'b1),
      .priv(csr_inst.privilege),
      .sum(csr_inst.sum),

      .page_fault(if1_page_fault),
      .no_read_access(),  // never
      .no_write_access(),  // never
      .no_exec_access(if1_no_exec_access),
      .addr_misaligned(if1_addr_misaligned),
      .mmu_error(),
      .pte_debug()
  );

  dyn_pc_pred new_ip_pred (
      .clock(clk),
      .reset(rst),
      .insert_entry(alu_dyn_take_ip),
      .needs_jump(alu_is_jump_alt),
      .source_pc(alu_ip),
      .target_pc(alu_dyn_new_ip),
      .query_pc(if1_ip),
      .pred_pc(if1_alt_next_ip)
  );

  ip_mux ip_sel (
      .mem_modif(dau_cache_clear_complete),
      .csr_modif(mem_csr_take_ip),
      .alu_modif(alu_dyn_take_ip),

      .mem_ip (mem_ip),
      .csr_ip (mem_csr_new_ip),
      .alu_ip (alu_dyn_new_ip),
      .pred_ip(if1_alt_next_ip),

      .res_ip(next_ip)
  );
  // ========================================== IF2 ==========================================
  assign icache_addr_o = if2_ppc;
  assign icache_bypass_o = 0;
  assign icache_re_o = !if2_is_bubble;

  // ========================================== ID ==========================================
  assign rf_raddr1 = decoder_raddr1;
  assign rf_raddr2 = decoder_raddr2;
  instr_decoder instruction_decoder (
      .instr(id_instr),
      .raddr1(decoder_raddr1),
      .raddr2(decoder_raddr2),
      .waddr(decoder_waddr),
      .we   (decoder_we),

      .mem_re (decoder_mre),
      .mem_we (decoder_mwe),
      .csr_acc(decoder_csracc),

      .clear_icache(decoder_clear_icache),
      .clear_tlb(decoder_clear_tlb),
      .immgen(decoder_imm)
  );

  instr_mux comb_instr_mux (
      .raddr1(decoder_raddr1),
      .raddr2(decoder_raddr2),

      .rdata1(rf_rdata1),
      .rdata2(rf_rdata2),

      .alu_we(alu_wbwe),
      .alu_waddr(alu_wbaddr),
      .alu_wdata(alu_wbdata_adjusted),

      .mem_we(mem_wbwe),
      .mem_waddr(mem_wbaddr),
      .mem_wdata(mem_rf_wdata),

      .wb_we(wb_we),
      .wb_waddr(wb_addr),
      .wb_wdata(wb_data),

      .rdata1_out(id_mux_alu_op1),
      .rdata2_out(id_mux_alu_op2)
  );
  // ========================================== ALU ==========================================
  assign alu_opcode = alu_instr;
  assign alu_in1 = alu_op1;
  assign alu_in2 = alu_op2;

  adjust_ip new_pred_corr (
      .instr  (alu_instr),
      .curr_ip(alu_ip),

      .pred_pc(alu_alt_ip_pred),
      .op1(alu_op1),
      .op2(alu_op2),
      .offset(ex_imm),
      .is_jump(alu_is_jump_alt),
      .dyn_take_ip(alu_dyn_take_ip),
      .dyn_new_ip(alu_dyn_new_ip)
  );
  mem_data_offset_adjust mem_write_adjust (
      .mem_we(alu_mwe),
      .write_address(alu_op1 + ex_imm),
      .instr(alu_instr),

      .in_data (alu_op2),
      .out_data(alu_mwdata_adjusted),
      .out_be  (alu_mbe_adjusted)
  );
  link_modif handle_link (
      .instr(alu_instr),
      .curr_ip(alu_ip),
      .alu_out(alu_out),
      .wb_wdata(alu_wbdata_adjusted)
  );
  mmu_iter alt_data_mm (
      .clock(clk),
      .reset(rst),

      .satp(satp),
      .va  (alu_op1 + ex_imm),
      .pa  (dmmu_addr_o),

      .data_we_i(alu_mwe),
      .data_re_i(alu_mre),
      .byte_en_i(alu_mbe_adjusted),
      .data_departure_i(32'b0),
      .data_arrival_o(alu_dmmu_pa),
      .data_ack_o(alu_dmmu_ack),

      .data_we_o(),
      .data_re_o(dmmu_re_o),
      .byte_en_o(),
      .data_departure_o(),
      .data_arrival_i(dmmu_data_i),
      .data_ack_i(dmmu_ack_i),

      .bypass(),
      .invalidate_tlb(mem_invalidate_tlb),
      .if_enable(1'b0),
      .priv(csr_inst.privilege),
      .sum(csr_inst.sum),

      .page_fault(alu_dmmu_page_fault),
      .no_read_access(alu_dmmu_read_violation),
      .no_write_access(alu_dmmu_write_violation),
      .no_exec_access(),  // never
      .addr_misaligned(alu_dmmu_addr_misaligned),
      .mmu_error(alu_dmmu_error),
      .pte_debug()
  );
  // ========================================== MEM ==========================================
  assign dau_cache_clear = mem_clear_icache || mem_clear_tlb;
  assign mem_invalidate_icache = dau_cache_clear_complete && mem_clear_icache;
  assign mem_invalidate_tlb = dau_cache_clear_complete && mem_clear_tlb;
  assign icache_cache_invalidate = mem_invalidate_icache;

  rf_write_data_mux rf_wdata_mux (
      .rf_we  (mem_wbwe),
      .mem_re ('0),
      .csr_acc(mem_csracc),

      .alu_data(mem_wbdata),
      .mem_data('0),
      .csr_data(mem_csrwb),

      .out_data(mem_rf_wdata)
  );
  devacc_pause device_access_pause (
      .mem_instr(mem_instr),
      .dau_ack(dcache_ack_i),
      .dau_cache_clear(dau_cache_clear),
      .dau_cache_clear_complete(dau_cache_clear_complete),
      .pause_o(mem_pause)
  );
  wire csr_pause;  // XXX
  csr csr_inst (
      .clock(clk),
      .reset(rst),

      .instr(mem_instr),
      .wdata(mem_csrdt),
      .rdata(mem_csrwb),

      .curr_ip(mem_ip),
      .timer_interrupt(!dau_cache_clear && local_intr),
      .mtime(mtime),

      .take_ip(mem_csr_take_ip),
      .new_ip (mem_csr_new_ip),

      .instr_page_fault(mem_instr_page_fault),
      .data_page_fault (mem_dmmu_page_fault),

      .instr_addr_misaligned(mem_instr_addr_misaligned),
      .data_addr_misaligned (mem_dmmu_addr_misaligned),

      .no_read_access (mem_dmmu_read_violation),
      .no_write_access(mem_dmmu_write_violation),
      .no_exec_access (mem_instr_no_exec_access),

      .instr_fault_addr(mem_ip),
      .data_fault_addr (mem_addr),

      .pause_global(csr_pause)  // XXX
  );

  assign satp = {csr_inst.mmu_enable, csr_inst.satp[30:0]};
  wire [31:0] pte_debug;

  assign dcache_addr_o = mem_dmmu_pa;
  assign dcache_we_o = mem_mwe;
  assign dcache_re_o = mem_mre;
  assign dcache_byte_en = mem_mbe;
  assign dcache_data_o = mem_data;
  assign dcache_bypass_o = 1'b0;
  // ========================================== WB ==========================================
  assign rf_we    = wb_we;
  assign rf_waddr = wb_addr;
  assign rf_wdata = wb_data;
  mem_data_recv_adjust wb_read_adjust (
      .instr(wb_instr),
      .mem_addr(wb_maddr),
      .data_i(wb_mdata),
      .data_o(wb_mrdata_adjusted)
  );
  rf_write_data_mux wb_wdata_mux (
      .rf_we  (wb_we),
      .mem_re (wb_mre),
      .csr_acc(wb_csracc),

      .alu_data(wb_aludata),
      .mem_data(wb_mrdata_adjusted),
      .csr_data(wb_csrdata),

      .out_data(wb_data)
  );

  wire pre_if_stall;
  wire if1_if2_stall;
  wire if_id_stall;
  wire id_ex_stall;
  wire ex_mem_stall;
  wire mem_wb_stall;

  wire if1_if2_bubble;
  wire if_id_bubble;
  wire id_ex_bubble;
  wire ex_mem_bubble;
  wire mem_wb_bubble;

  wire debug_pause;
pipeline_state_recorder psr(
  .if1_stall(pre_if_stall),
  .if2_stall(if1_if2_stall),
  .id_stall(if_id_stall),
  .ex_stall(id_ex_stall),
  .mem_stall(ex_mem_stall),
  .if2_bubble(if1_if2_bubble),
  .id_bubble(if_id_bubble),
  .ex_bubble(id_ex_bubble),
  .mem_bubble(ex_mem_bubble),
  .wb_bubble(mem_wb_bubble)
);
  cu_orchestra cu_control (
      .if1_ip (if1_ip),
      .if1_ack(if1_mmu_ack),

      .if2_ip (if2_ip),
      .if2_ack(if2_is_bubble || icache_ack_i),

      .id_ip(id_ip),
      .id_raddr1(decoder_raddr1),
      .id_raddr2(decoder_raddr2),

      .alu_ip(alu_ip),
      .alu_instr(alu_instr),
      .alu_waddr(alu_wbaddr),
      .alu_dmmu_ack(!(alu_mre || alu_mwe) || alu_dmmu_ack),
      .alu_take_ip(alu_dyn_take_ip),
      .alu_new_ip(alu_dyn_new_ip),

      .mem_ip(mem_ip),
      .mem_instr(mem_instr),
      .mem_waddr(mem_wbaddr),
      .mem_ack(~mem_pause),
      .mem_flush_take_ip(dau_cache_clear_complete),
      .mem_flush_new_ip(mem_ip + 32'd4),
      .csr_take_ip(mem_csr_take_ip),
      .csr_new_ip(mem_csr_new_ip),

      .pause_global(  /*debug_pause*/ 1'b0),

      .pre_if_stall(pre_if_stall),

      .if1_if2_stall(if1_if2_stall),
      .if1_if2_bubble(if1_if2_bubble),
      .if1_if2_ip(if1_if2_flush_ip),

      .if_id_stall(if_id_stall),
      .if_id_bubble(if_id_bubble),
      .if_id_ip(if_id_flush_ip),

      .id_alu_stall(id_ex_stall),
      .id_alu_bubble(id_ex_bubble),
      .id_alu_ip(id_alu_flush_ip),

      .alu_mem_stall(ex_mem_stall),
      .alu_mem_bubble(ex_mem_bubble),
      .alu_mem_ip(alu_mem_flush_ip),

      .mem_wb_stall(mem_wb_stall),
      .mem_wb_bubble(mem_wb_bubble),
      .mem_wb_ip(mem_wb_flush_ip)
  );

  pre_if ppl_pre_if (
      .clock(clk),
      .reset(rst),

      .stall (pre_if_stall),
      .bubble(1'b0),
      .error (),

      .next_instr_ptr(next_ip),
      .instr_ptr(if1_ip)
  );

  if1_if2 ppl_if1_if2 (
      .clock(clk),
      .reset(rst),

      .stall (if1_if2_stall),
      .bubble(if1_if2_bubble),

      .if1_ip(if1_ip),
      .if2_ip(if2_ip),

      .if1_ppc(if1_mmu_pa),
      .if2_ppc(if2_ppc),

      .bubble_ip(if1_if2_flush_ip),

      .if1_page_fault(if1_page_fault),
      .if2_instr_page_fault(if2_page_fault),

      .if1_addr_misaligned(if1_addr_misaligned),
      .if2_instr_addr_misaligned(if2_addr_misaligned),

      .if1_no_exec_access(if1_no_exec_access),
      .if2_instr_no_exec_access(if2_no_exec_access),

      .if1_alt_next_ip(if1_alt_next_ip),
      .if2_alt_next_ip(if2_alt_next_ip),

      .is_bubble(if2_is_bubble)
  );
  if_id ppl_if_id (
      .clock(clk),
      .reset(rst),

      .stall (if_id_stall),
      .bubble(if_id_bubble),
      .error (),

      .if_ip(if2_ip),
      .id_ip(id_ip),

      .if_instr(icache_data_i),
      .id_instr(  /*id_instr*/),

      .if_instr_delayed(icache_data_delayed_i),
      .id_instr_delayed(id_instr),

      .bubble_ip(if_id_flush_ip),

      .if_page_fault(if2_page_fault),
      .id_instr_page_fault(id_instr_page_fault),

      .if_addr_misaligned(if2_addr_misaligned),
      .id_instr_addr_misaligned(id_instr_addr_misaligned),

      .if_no_exec_access(if2_no_exec_access),
      .id_instr_no_exec_access(id_instr_no_exec_access),

      .if_alt_next_ip(if2_alt_next_ip),
      .id_alt_next_ip(id_alt_next_ip),

      .if2_is_bubble(if2_is_bubble)
  );

  id_ex ppl_id_ex (
      .clock(clk),
      .reset(rst),

      .stall (id_ex_stall),
      .bubble(id_ex_bubble),
      .error (),

      // Control signals.
      .id_ip(id_ip),
      .ex_ip(alu_ip),

      .id_instr(id_instr),
      .ex_instr(alu_instr),

      // Prepare for what ALU need.
      .id_op1(id_mux_alu_op1),
      .id_op2(id_mux_alu_op2),
      .id_imm(decoder_imm),

      .ex_op1(alu_op1),
      .ex_op2(alu_op2),
      .ex_imm(ex_imm),

      .id_mre(decoder_mre),
      .ex_mre(alu_mre),

      .id_mwe(decoder_mwe),
      .ex_mwe(alu_mwe),

      .id_mdata(id_mux_alu_op2),
      .ex_mdata(alu_mwdata),

      .id_csracc(decoder_csracc),
      .ex_csracc(alu_csracc),

      .id_csrdata(id_mux_alu_op1),
      .ex_csrdata(alu_csrdata),

      .id_instr_page_fault(id_instr_page_fault),
      .ex_instr_page_fault(ex_instr_page_fault),

      .id_instr_addr_misaligned(id_instr_addr_misaligned),
      .ex_instr_addr_misaligned(ex_instr_addr_misaligned),

      .id_instr_no_exec_access(id_instr_no_exec_access),
      .ex_instr_no_exec_access(ex_instr_no_exec_access),

      .id_clear_tlb(decoder_clear_tlb),
      .ex_clear_tlb(alu_clear_tlb),

      .id_clear_icache(decoder_clear_icache),
      .ex_clear_icache(alu_clear_icache),

      // Metadata for write back stage.
      .id_we(decoder_we),
      .ex_we(alu_wbwe),

      .id_wraddr(decoder_waddr),
      .ex_wraddr(alu_wbaddr),

      .bubble_ip(id_alu_flush_ip),

      .id_alt_next_ip(id_alt_next_ip),
      .ex_alt_next_ip(alu_alt_ip_pred)
  );

  ex_mem ppl_ex_mem (
      .clock(clk),
      .reset(rst),

      .stall (ex_mem_stall),
      .bubble(ex_mem_bubble),
      .error (),

      // Part 0: Control
      .ex_instr (alu_instr),
      .mem_instr(mem_instr),

      .ex_ip (alu_ip),
      .mem_ip(mem_ip),

      // Part 1: Input for DAU
      .ex_mre (alu_mre && !alu_dmmu_error),
      .mem_mre(mem_mre),

      .ex_mwe (alu_mwe && !alu_dmmu_error),
      .mem_mwe(mem_mwe),

      .ex_mbe (alu_mbe_adjusted),
      .mem_mbe(mem_mbe),

      .ex_maddr (alu_op1 + ex_imm),
      .mem_maddr(mem_addr),

      .ex_mdata (alu_mwdata_adjusted),
      .mem_mdata(mem_data),

      .ex_mpa (32'b0),
      .mem_mpa(),

      .ex_csracc (alu_csracc),
      .mem_csracc(mem_csracc),

      .ex_csrdt (alu_op1),
      .mem_csrdt(mem_csrdt),

      .ex_instr_page_fault (ex_instr_page_fault),
      .mem_instr_page_fault(mem_instr_page_fault),

      .ex_instr_addr_misaligned (ex_instr_addr_misaligned),
      .mem_instr_addr_misaligned(mem_instr_addr_misaligned),

      .ex_instr_no_exec_access (ex_instr_no_exec_access),
      .mem_instr_no_exec_access(mem_instr_no_exec_access),

      .ex_clear_tlb (alu_clear_tlb),
      .mem_clear_tlb(mem_clear_tlb),

      .ex_clear_icache (alu_clear_icache),
      .mem_clear_icache(mem_clear_icache),

      .ex_dmmu_pa (alu_dmmu_pa),
      .mem_dmmu_pa(mem_dmmu_pa),

      .ex_dmmu_page_fault (alu_dmmu_page_fault),
      .mem_dmmu_page_fault(mem_dmmu_page_fault),

      .ex_dmmu_read_violation (alu_dmmu_read_violation),
      .mem_dmmu_read_violation(mem_dmmu_read_violation),

      .ex_dmmu_write_violation (alu_dmmu_write_violation),
      .mem_dmmu_write_violation(mem_dmmu_write_violation),

      .ex_dmmu_addr_misaligned (alu_dmmu_addr_misaligned),
      .mem_dmmu_addr_misaligned(mem_dmmu_addr_misaligned),

      // Part 2: Metadata for next stage.
      .ex_we (alu_wbwe && (!alu_mre || !alu_dmmu_error)),
      .mem_we(mem_wbwe),

      .ex_wraddr (alu_wbaddr),
      .mem_wraddr(mem_wbaddr),

      .ex_wdata (alu_wbdata_adjusted),
      .mem_wdata(mem_wbdata),

      .bubble_ip(alu_mem_flush_ip)
  );
  mem_wb ppl_mem_wb (
      .clock(clk),
      .reset(rst),

      .stall (mem_wb_stall),
      .bubble(mem_wb_bubble),
      .error (),

      .bubble_ip(mem_wb_flush_ip),
      .mem_ip(mem_ip),
      .wb_ip(wb_ip),

      .mem_instr(mem_instr),
      .wb_instr (wb_instr),

      .mem_we(mem_wbwe),
      .wb_we (wb_we),

      .mem_mre(mem_mre),
      .wb_mre (wb_mre),

      .mem_csracc(mem_csracc),
      .wb_csracc (wb_csracc),

      .mem_wraddr(mem_wbaddr),
      .wb_wraddr (wb_addr),

      .mem_maddr(mem_addr),
      .wb_maddr (wb_maddr),

      .mem_wmdata(dcache_data_i),
      .wb_wmdata(  /*wb_mdata*/),
      .mem_wmdata_delayed(dcache_data_delayed_i),
      .wb_wmdata_delayed(wb_mdata),
      .mem_wcsrdata(mem_csrwb),
      .wb_wcsrdata(wb_csrdata),

      .mem_waludata(mem_wbdata),
      .wb_waludata (wb_aludata)
  );
  // ila analyzer (
  //     .clk(fast_clock),
  //     .probe0(if1_ip),
  //     .probe5(if2_ip),
  //     .probe1(id_ip),
  //     .probe2(alu_ip),
  //     .probe3(mem_ip),
  //     .probe4(wb_ip),
  //     .probe6(id_instr),
  //     .probe7(alu_instr),
  //     .probe8(mem_instr),
  //     .probe9(wb_instr),
  //     .probe10(alt_data_mm.va),
  //     .probe11(alt_data_mm.pa),
  //     .probe12(alt_data_mm.mmu_state),
  //     .probe13(alt_data_mm.va_req),
  //     .probe14(alt_data_mm.tlb_we),
  //     .probe15(alt_data_mm.tlb_wpte),
  //     .probe16(alt_data_mm.tlb_wva),
  //     .probe17(alt_data_mm.page_fault),
  //     .probe18(alt_data_mm.page_fault_marker),
  //     .probe19(alt_instr_mm.va),
  //     .probe20(alt_instr_mm.pa),
  //     .probe21(alt_instr_mm.mmu_state),
  //     .probe22(alt_instr_mm.va_req),
  //     .probe23(alt_instr_mm.tlb_we),
  //     .probe24(alt_instr_mm.tlb_wpte),
  //     .probe25(alt_instr_mm.tlb_wva),
  //     .probe26(alt_instr_mm.page_fault),
  //     .probe27(alt_instr_mm.page_fault_marker),
  //     .probe28(csr_inst.instr),
  //     .probe29(csr_inst.privilege),
  //     .probe30(csr_inst.mstatus),
  //     .probe31(csr_inst.mie),
  //     .probe32(csr_inst.mepc),
  //     .probe33(csr_inst.mtval),
  //     .probe34(csr_inst.mip),
  //     .probe35(csr_inst.mtime),
  //     .probe36(csr_inst.timer_interrupt),
  //     .probe37(csr_inst.cause_comb)
  // );
endmodule

module cu_orchestra (
    input wire [31:0] if1_ip,
    input wire        if1_ack,
    // ------------------------------
    input wire [31:0] if2_ip,
    input wire        if2_ack,
    // ------------------------------
    input wire [31:0] id_ip,
    // load-use
    input wire [ 4:0] id_raddr1,
    input wire [ 4:0] id_raddr2,
    // ------------------------------
    input wire [31:0] alu_ip,
    // load-use
    input wire [31:0] alu_instr,
    input wire [ 4:0] alu_waddr,
    // load dmmu
    input wire        alu_dmmu_ack,
    // branch misprediction
    input wire        alu_take_ip,
    input wire [31:0] alu_new_ip,
    // ------------------------------
    input wire [31:0] mem_ip,
    // load-use
    input wire [31:0] mem_instr,
    input wire [ 4:0] mem_waddr,
    // load memory
    input wire        mem_ack,
    // sfence.vma / fence.i
    input wire        mem_flush_take_ip,
    input wire [31:0] mem_flush_new_ip,
    // swap privilege
    input wire        csr_take_ip,
    input wire [31:0] csr_new_ip,

    input  wire pause_global,  // XXX
    // ===============================================================
    output reg  pre_if_stall,

    output reg if1_if2_stall,
    output reg if1_if2_bubble,
    output reg [31:0] if1_if2_ip,

    output reg if_id_stall,
    output reg if_id_bubble,
    output reg [31:0] if_id_ip,

    output reg id_alu_stall,
    output reg id_alu_bubble,
    output reg [31:0] id_alu_ip,

    output reg alu_mem_stall,
    output reg alu_mem_bubble,
    output reg [31:0] alu_mem_ip,

    output reg mem_wb_stall,
    output reg mem_wb_bubble,
    output reg [31:0] mem_wb_ip
);
  parameter LOAD = 32'b????_????_????_????_????_????_?000_0011;
  parameter NOP = 32'b0000_0000_0000_0000_0000_0000_0001_0011;
  // This module mainly focus on handling pipeline hazards.

  // There are 3 causes of such hazards.
  // 1. Multicycle device access.
  // +--> Read is 2 cycles, Write SRAM is 3 cycles.
  // 2. Load use hazards.
  // 3. Branch misprediction / JAL, JALR

  reg if1_wait_req;
  reg if2_wait_req;
  reg id_wait_req;
  reg alu_wait_req;
  reg mem_wait_req;
  reg wb_wait_req;
  reg mem_take_ip;
  always_comb begin
    if1_if2_stall = 0;
    if1_if2_bubble = 0;
    if1_if2_ip = if1_ip;

    if_id_stall = 0;
    if_id_bubble = 0;
    if_id_ip = if2_ip;

    id_alu_stall = 0;
    id_alu_bubble = 0;
    id_alu_ip = id_ip;

    alu_mem_stall = 0;
    alu_mem_bubble = 0;
    alu_mem_ip = alu_ip;

    mem_wb_stall = 0;
    mem_wb_bubble = 0;
    mem_wb_ip = mem_ip;

    wb_wait_req = 0;

    // Case 1.
    if1_wait_req = ~if1_ack;
    if2_wait_req = ~if2_ack;
    alu_wait_req = ~alu_dmmu_ack;  // prepare for putting DMMU here.
    mem_wait_req = ~mem_ack;

    // Case 2.
    id_wait_req = (alu_instr[6:0] == 7'b000_0011 &&  // LOAD instr in ALU
    (alu_waddr == id_raddr1 || alu_waddr == id_raddr2)
        ) || (
            mem_instr[6:0] == 7'b000_0011 /*&& !mem_ack */ &&
            (mem_waddr == id_raddr1 || mem_waddr == id_raddr2)
        ) || ( // CSR Related writes
    alu_instr[6:0] == 7'b1110011 && alu_instr[14:12] > 0 &&
            (alu_waddr == id_raddr1 || alu_waddr == id_raddr2)
        );

    // Case 3. Determined by alu_take_ip
    mem_take_ip = mem_flush_take_ip || csr_take_ip;

    // =============================== Output pause/cancel/pc ================================
    // Derive pipeline status backwards.
    mem_wb_stall = pause_global;
    mem_wb_bubble = !mem_wb_stall && mem_wait_req;


    if (mem_wait_req) begin
      mem_wb_ip = mem_ip;
    end

    alu_mem_stall  = (!csr_take_ip) && (mem_wb_stall || mem_wait_req);
    alu_mem_bubble = csr_take_ip || ((!alu_mem_stall) && (mem_take_ip || alu_wait_req));

    if (csr_take_ip) begin
      alu_mem_ip = csr_new_ip;
    end else if (mem_flush_take_ip) begin
      alu_mem_ip = mem_flush_new_ip;
    end else if ((!alu_mem_stall) && alu_wait_req) begin
      alu_mem_ip = alu_ip;  // Trivial case, ignore afterwards.
    end

    id_alu_stall  = (!mem_take_ip) && (alu_mem_stall || alu_wait_req);
    id_alu_bubble = mem_take_ip || (!id_alu_stall && (alu_take_ip || id_wait_req));

    if (csr_take_ip) begin
      id_alu_ip = csr_new_ip;
    end else if (mem_flush_take_ip) begin
      id_alu_ip = mem_flush_new_ip;
    end else if (alu_take_ip) begin
      id_alu_ip = alu_new_ip;
    end

    if_id_stall = (! (mem_take_ip || alu_take_ip)) && (id_wait_req || (id_alu_stall /*&& alu_instr != NOP*/) );
    if_id_bubble = (mem_take_ip || alu_take_ip) || (!if_id_stall && if2_wait_req);

    if (csr_take_ip) begin
      if_id_ip = csr_new_ip;
    end else if (mem_flush_take_ip) begin
      if_id_ip = mem_flush_new_ip;
    end else if (alu_take_ip) begin
      if_id_ip = alu_new_ip;
    end

    if1_if2_stall  = (!(mem_take_ip || alu_take_ip)) && (if2_wait_req || if_id_stall);
    if1_if2_bubble = (mem_take_ip || alu_take_ip) || (!if1_if2_stall && if1_wait_req);

    if (csr_take_ip) begin
      if1_if2_ip = csr_new_ip;
    end else if (mem_flush_take_ip) begin
      if1_if2_ip = mem_flush_new_ip;
    end else if (alu_take_ip) begin
      if1_if2_ip = alu_new_ip;
    end

    pre_if_stall = (!(mem_take_ip || alu_take_ip)) && (if1_wait_req || if1_if2_stall);
  end

endmodule
