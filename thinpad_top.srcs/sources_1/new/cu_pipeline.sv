//`include "../pipeline/instr_decode.sv"
module cu_pipeline (
    input wire clk,
    input wire rst,
    
    // Device access unit
    output wire        dau_instr_re_o,
    output wire [31:0] dau_instr_addr_o,
    input  wire [31:0] dau_instr_data_i,
    input  wire        dau_instr_ack_i,
    output wire        dau_instr_bypass_o, 
    output wire        dau_instr_cache_invalidate,

    output wire        dau_we_o,
    output wire        dau_re_o,
    output wire [31:0] dau_addr_o,
    output wire [ 3:0] dau_byte_en,
    output wire [31:0] dau_data_o,
    input  wire [31:0] dau_data_i,
    input  wire        dau_ack_i,
    output wire        dau_bypass_o, 

    output wire        dau_cache_clear,
    input  wire        dau_cache_clear_complete,

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
    input wire [3:0] touch_btn,
    //output wire [31:0] curr_ip_out,
    output wire [7:0] dpy0,
    output wire [7:0] dpy1,
    output wire [15:0] leds,

    input wire         local_intr,
    input wire [63:0]  mtime
);
    parameter INSTR_BASE_ADDR = 32'h8000_0000;
    // Pre - IF
    wire [31:0] pre_if_ip;
    // IF
    wire [31:0] satp;

    wire jump_pred;
    wire [31:0] next_ip_pred;
    wire [31:0] next_ip;
    wire        if_mmu_ack;
    wire [31:0] if_mmu_data_arrival;
    
    wire if_page_fault;
    wire if_addr_misaligned;
    wire if_no_exec_access;
    wire if_mmu_error;
    // ID
    // From IF stage
    wire [31:0] id_instr;
    wire [31:0] id_ip;
    wire        id_jump_pred;
    // Intra stage signals.
    wire [4:0] decoder_raddr1;
    wire [4:0] decoder_raddr2;

    wire [4:0] decoder_waddr;
    wire       decoder_we;

    wire       decoder_mre;
    wire       decoder_mwe;
    wire       decoder_csracc;
    wire       decoder_clear_icache;
    wire       decoder_clear_tlb;

    wire [31:0] id_mux_alu_op1;
    wire [31:0] id_mux_alu_op2;
    // ALU
    // From ID stage
    wire [31:0] alu_ip;
    wire        alu_jump_pred;
    wire [31:0] alu_instr;

    wire [31:0] alu_op1;
    wire [31:0] alu_op2;

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

    wire [31:0] alu_mwdata_adjusted;
    wire [ 3:0] alu_mbe_adjusted;
    wire [31:0] alu_wbdata_adjusted;
    // MEM
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

    // Stage generated signals.
    wire [31:0] mem_mmu_data_arrival;
    wire        mem_mmu_ack;
    wire [31:0] mem_mrdata_adjusted;
    wire [31:0] mem_rf_wdata;
    wire        mem_pause;

    wire [31:0] mem_csrwb;

    wire        mem_csr_take_ip;
    wire [31:0] mem_csr_new_ip;

    wire        mem_invalidate_tlb;
    wire        mem_invalidate_icache;

    wire        mem_data_page_fault;
    wire        mem_write_violation;
    wire        mem_read_violation;
    wire        mem_addr_misaligned;
    // WB
    wire        wb_we;
    wire [ 4:0] wb_addr;
    wire [31:0] wb_data;
    wire [31:0] wb_ip;
    // Bubble case
    wire [31:0] if_id_flush_ip;
    wire [31:0] id_alu_flush_ip;
    wire [31:0] alu_mem_flush_ip;
    wire [31:0] mem_wb_flush_ip;

    
    wire if_id_page_fault;
    wire if_id_addr_misaligned;
    wire if_id_no_exec_access;

    wire id_instr_page_fault;
    wire id_instr_addr_misaligned;
    wire id_instr_no_exec_access;

    wire ex_instr_page_fault;
    wire ex_instr_addr_misaligned;
    wire ex_instr_no_exec_access;

    wire mem_instr_page_fault;
    wire mem_instr_addr_misaligned;
    wire mem_instr_no_exec_access;
    // IF
    next_instr_ptr ip_predict(
        .mem_ack(),
        .curr_ip(pre_if_ip),
        .curr_instr(if_mmu_data_arrival),
        .next_ip_pred(next_ip_pred),
        .jump_pred(jump_pred)
    );

    ip_mux ip_sel(
        .mem_modif(dau_cache_clear_complete),
        .csr_modif(mem_csr_take_ip),
        .alu_modif(alu_take_ip),

        .mem_ip(mem_ip),
        .csr_ip(mem_csr_new_ip),
        .alu_ip(alu_new_ip),
        .pred_ip(next_ip_pred),

        .res_ip(next_ip)
    );
    // ID
    assign rf_raddr1 = decoder_raddr1;
    assign rf_raddr2 = decoder_raddr2;
    instr_decoder instruction_decoder(
        .instr(id_instr),
        .raddr1(decoder_raddr1),
        .raddr2(decoder_raddr2),
        .waddr(decoder_waddr),
        .we   (decoder_we),

        .mem_re(decoder_mre),
        .mem_we(decoder_mwe),
        .csr_acc(decoder_csracc),

        .clear_icache(decoder_clear_icache),
        .clear_tlb(decoder_clear_tlb)
    );

    instr_mux comb_instr_mux(
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
    // ALU
    assign alu_opcode = alu_instr;
    assign alu_in1 = alu_op1;
    assign alu_in2 = alu_op2;

    adjust_ip ip_correction(
        .instr(alu_instr),
        .cmp_res(alu_out),
        .has_pred_jump(alu_jump_pred),
        .curr_ip(alu_ip),
        .take_ip(alu_take_ip),
        .new_ip(alu_new_ip)
    );
    mem_data_offset_adjust mem_write_adjust(
        .mem_we(alu_mwe),
        .write_address(alu_out),
        .instr(alu_instr),

        .in_data(alu_op2),
        .out_data(alu_mwdata_adjusted),
        .out_be(alu_mbe_adjusted)
    );
    link_modif handle_link(
        .instr(alu_instr),
        .curr_ip(alu_ip),
        .alu_out(alu_out),
        .wb_wdata(alu_wbdata_adjusted)
    );
    // MEM
    assign dau_cache_clear = mem_clear_icache || mem_clear_tlb;
    assign mem_invalidate_icache = dau_cache_clear_complete && mem_clear_icache;
    assign mem_invalidate_tlb = dau_cache_clear_complete && mem_clear_tlb;
    assign dau_instr_cache_invalidate = mem_invalidate_icache;
    mem_data_recv_adjust mem_read_adjust(
        .instr(mem_instr),
        .mem_addr(mem_addr),
        .data_i(mem_mmu_data_arrival),
        .data_o(mem_mrdata_adjusted)
    );
    rf_write_data_mux rf_wdata_mux(
        .rf_we(mem_wbwe),
        .mem_re(mem_mre),
        .csr_acc(mem_csracc),

        .alu_data(mem_wbdata),
        .mem_data(mem_mrdata_adjusted),
        .csr_data(mem_csrwb),
        
        .out_data(mem_rf_wdata)
    );
    devacc_pause device_access_pause(
        .mem_instr(mem_instr),
        .dau_ack(mem_mmu_ack),
        .dau_cache_clear(dau_cache_clear),
        .dau_cache_clear_complete(dau_cache_clear_complete),
        .pause_o(mem_pause)
    );
    wire csr_pause; // XXX
    csr csr_inst(
        .clock(clk),
        .reset(rst),

        .instr(mem_instr),
        .wdata(mem_csrdt),
        .rdata(mem_csrwb),

        .curr_ip(mem_ip),
        .timer_interrupt(local_intr),
        .mtime(mtime),

        .take_ip(mem_csr_take_ip),
        .new_ip(mem_csr_new_ip),

        .instr_page_fault(mem_instr_page_fault),
        .data_page_fault(mem_data_page_fault),

        .instr_addr_misaligned(mem_instr_addr_misaligned),
        .data_addr_misaligned(mem_addr_misaligned),

        .no_read_access(mem_read_violation),
        .no_write_access(mem_write_violation),
        .no_exec_access(mem_instr_no_exec_access),

        .instr_fault_addr(mem_ip),
        .data_fault_addr(mem_addr),

        .pause_global(csr_pause) // XXX
    );

    assign satp = { csr_inst.mmu_enable, csr_inst.satp[30:0] };
    wire [31:0] pte_debug;
    mmu data_mm(
        .clock(clk),
        .reset(rst),

        .satp(satp),
        .va(mem_addr),
        .pa(dau_addr_o),

        .data_we_i(mem_mwe),
        .data_re_i(mem_mre),
        .byte_en_i(mem_mbe),
        .data_departure_i(mem_data),
        .data_arrival_o(mem_mmu_data_arrival),
        .data_ack_o(mem_mmu_ack),

        .data_we_o(dau_we_o),
        .data_re_o(dau_re_o),
        .byte_en_o(dau_byte_en),
        .data_departure_o(dau_data_o),
        .data_arrival_i(dau_data_i),
        .data_ack_i(dau_ack_i),

        .bypass(dau_bypass_o),
        .invalidate_tlb(mem_invalidate_tlb),
        .if_enable(1'b0),
        .priv(csr_inst.privilege),
        .sum(csr_inst.sum),

        .page_fault(mem_data_page_fault),
        .no_read_access(mem_read_violation),
        .no_write_access(mem_write_violation),
        .no_exec_access(), // never happens.
        .addr_misaligned(mem_addr_misaligned),
        .mmu_error(), // no need.

        .pte_debug(pte_debug)
    );
    mmu instr_mm(
        .clock(clk),
        .reset(rst),

        .satp(satp),
        .va(pre_if_ip),
        .pa(dau_instr_addr_o),

        .data_we_i(1'b0),
        .data_re_i(1'b1),
        .byte_en_i(4'b1111),
        .data_departure_i(32'b0),
        .data_arrival_o(if_mmu_data_arrival),
        .data_ack_o(if_mmu_ack),

        .data_we_o(),
        .data_re_o(dau_instr_re_o),
        .byte_en_o(),
        .data_departure_o(),
        .data_arrival_i(dau_instr_data_i),
        .data_ack_i(dau_instr_ack_i),

        .bypass(dau_instr_bypass_o),
        .invalidate_tlb(mem_invalidate_tlb),
        .if_enable(1'b1),
        .priv(csr_inst.privilege),
        .sum(csr_inst.sum),

        .page_fault(if_page_fault),
        .no_read_access(), // never
        .no_write_access(), // never
        .no_exec_access(if_no_exec_access), // TODO
        .addr_misaligned(if_addr_misaligned),
        .mmu_error(if_mmu_error),
        
        .pte_debug()
    );
    // WB
    assign rf_we    = wb_we;
    assign rf_waddr = wb_addr;
    assign rf_wdata = wb_data;

    wire pre_if_stall;
    wire if_id_stall;
    wire id_ex_stall;
    wire ex_mem_stall;
    wire mem_wb_stall;

    wire if_id_bubble;
    wire id_ex_bubble;
    wire ex_mem_bubble;
    wire mem_wb_bubble;

    wire debug_pause;

    cu_orchestra cu_control(
        .if_ip(pre_if_ip),
        .if_instr(if_mmu_data_arrival),
        .if_ack  (if_mmu_ack),
        .if_page_fault(if_page_fault),
        .if_addr_misaligned(if_addr_misaligned),
        .if_no_exec_access(if_no_exec_access),
        .if_mmu_error(if_mmu_error),

        .id_ip(id_ip),
        .id_instr(id_instr),
        .id_raddr1(decoder_raddr1),
        .id_raddr2(decoder_raddr2),

        .alu_ip(alu_ip),
        .alu_instr(alu_instr),
        .alu_waddr(alu_wbaddr),
        .alu_take_ip(alu_take_ip),
        .alu_new_ip(alu_new_ip),

        .mem_ip(mem_ip),
        .mem_instr(mem_instr),
        .mem_waddr(mem_wbaddr),
        .mem_ack  (~mem_pause),
        .mem_flush_take_ip( dau_cache_clear_complete),
        .mem_flush_new_ip(mem_ip + 32'd4),
        .csr_take_ip(mem_csr_take_ip),
        .csr_new_ip(mem_csr_new_ip),

        .pause_global(/*debug_pause*/1'b0),

        .pre_if_stall(pre_if_stall),

        .if_id_stall (if_id_stall ),
        .if_id_bubble(if_id_bubble),
        .if_id_ip(if_id_flush_ip),
        .if_id_page_fault(if_id_page_fault),
        .if_id_addr_misaligned(if_id_addr_misaligned),
        .if_id_no_exec_access(if_id_no_exec_access),

        .id_alu_stall (id_ex_stall ),
        .id_alu_bubble(id_ex_bubble),
        .id_alu_ip(id_alu_flush_ip),

        .alu_mem_stall (ex_mem_stall ),
        .alu_mem_bubble(ex_mem_bubble),
        .alu_mem_ip(alu_mem_flush_ip),

        .mem_wb_stall (mem_wb_stall ),
        .mem_wb_bubble(mem_wb_bubble),
        .mem_wb_ip(mem_wb_flush_ip)
    );

    pre_if ppl_pre_if(
        .clock(clk),
        .reset(rst),

        .stall(pre_if_stall),
        .bubble(1'b0),
        .error(),

        .next_instr_ptr(next_ip),
        .instr_ptr(pre_if_ip)
    );
    if_id ppl_if_id(
        .clock(clk),
        .reset(rst),

        .stall(if_id_stall),
        .bubble(if_id_bubble),
        .error(), 

        .if_ip(pre_if_ip),
        .id_ip(id_ip),

        .if_jump_pred(jump_pred),
        .id_jump_pred(id_jump_pred),

        .if_instr(if_mmu_data_arrival),
        .id_instr(id_instr),

        .bubble_ip(if_id_flush_ip),
        
        .if_page_fault(if_id_page_fault),
        .id_instr_page_fault(id_instr_page_fault),
        
        .if_addr_misaligned(if_id_addr_misaligned),
        .id_instr_addr_misaligned(id_instr_addr_misaligned),

        .if_no_exec_access(if_id_no_exec_access),
        .id_instr_no_exec_access(id_instr_no_exec_access)

    );

    id_ex ppl_id_ex(
        .clock(clk),
        .reset(rst),

        .stall(id_ex_stall),
        .bubble(id_ex_bubble),
        .error(),

        // Control signals.
        .id_ip(id_ip),
        .ex_ip(alu_ip),

        .id_jump_pred(id_jump_pred),
        .ex_jump_pred(alu_jump_pred),

        .id_instr(id_instr),
        .ex_instr(alu_instr),

        // Prepare for what ALU need.
        .id_op1(id_mux_alu_op1),
        .id_op2(id_mux_alu_op2),

        .ex_op1(alu_op1),
        .ex_op2(alu_op2),
        
        .id_mre(decoder_mre),
        .ex_mre(alu_mre),

        .id_mwe(decoder_mwe),
        .ex_mwe(alu_mwe),

        .id_mdata(id_mux_alu_op2), // Note that this bus is used only in STORE instructions.
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

        .bubble_ip(id_alu_flush_ip)
    );

    ex_mem ppl_ex_mem(
        .clock(clk),
        .reset(rst),

        .stall(ex_mem_stall),
        .bubble(ex_mem_bubble),
        .error(),

        // Part 0: Control
        .ex_instr (alu_instr),
        .mem_instr(mem_instr),
        
        .ex_ip(alu_ip),
        .mem_ip(mem_ip), 

        // Part 1: Input for DAU
        .ex_mre (alu_mre),
        .mem_mre(mem_mre),

        .ex_mwe (alu_mwe),
        .mem_mwe(mem_mwe),

        .ex_mbe (alu_mbe_adjusted),
        .mem_mbe(mem_mbe),

        .ex_maddr (alu_out), // we always calculate sum of base and offset for mem address
        .mem_maddr(mem_addr),

        .ex_mdata (alu_mwdata_adjusted),
        .mem_mdata(mem_data),

        .ex_csracc(alu_csracc),
        .mem_csracc(mem_csracc),

        .ex_csrdt (alu_op1),
        .mem_csrdt(mem_csrdt),

        .ex_instr_page_fault(ex_instr_page_fault),
        .mem_instr_page_fault(mem_instr_page_fault),

        .ex_instr_addr_misaligned(ex_instr_addr_misaligned),
        .mem_instr_addr_misaligned(mem_instr_addr_misaligned),

        .ex_instr_no_exec_access(ex_instr_no_exec_access),
        .mem_instr_no_exec_access(mem_instr_no_exec_access),

        .ex_clear_tlb(alu_clear_tlb),
        .mem_clear_tlb(mem_clear_tlb),

        .ex_clear_icache(alu_clear_icache),
        .mem_clear_icache(mem_clear_icache),

        // Part 2: Metadata for next stage.
        .ex_we (alu_wbwe),
        .mem_we(mem_wbwe),

        .ex_wraddr (alu_wbaddr),
        .mem_wraddr(mem_wbaddr),

        .ex_wdata (alu_wbdata_adjusted),
        .mem_wdata(mem_wbdata),

        .bubble_ip(alu_mem_flush_ip)
    );
    wire [31:0] wb_instr;
    mem_wb ppl_mem_wb(
        .clock(clk),
        .reset(rst),

        .stall(mem_wb_stall),
        .bubble(mem_wb_bubble),
        .error(),

        .mem_we(mem_wbwe),
        .wb_we (wb_we),

        .mem_wraddr(mem_wbaddr),
        .wb_wraddr (wb_addr),

        .mem_wdata(mem_rf_wdata),
        .wb_wdata (wb_data),

        .mem_instr(mem_instr),
        .wb_instr(wb_instr),

        .mem_ip(mem_ip),
        .wb_ip(wb_ip)
    );

    // ila analyzer(
    //     .clk(clk),
    //     .probe0(pre_if_ip),
    //     .probe1(id_instr),
    //     .probe2(alu_instr),
    //     .probe3(mem_instr),
    //     .probe4(dau_data_o),
    //     .probe5(dau_instr_addr_o)
    // );

    //assign curr_ip_out = wb_ip;

    // debug dbg(
    //     .mstatus(csr_inst.mstatus),
    //     .medeleg(csr_inst.medeleg),
    //     .mideleg(csr_inst.mideleg),
    //     .mie(csr_inst.mie),
    //     .mtvec(csr_inst.mtvec),
    //     .mscratch(csr_inst.mscratch),
    //     .mepc(csr_inst.mepc),
    //     .mcause(csr_inst.mcause),
    //     .mtval(csr_inst.mtval),
    //     .mip(csr_inst.mip),
    //     .stvec(csr_inst.stvec),
    //     .sscratch(csr_inst.sscratch),
    //     .sepc(csr_inst.sepc),
    //     .scause(csr_inst.scause),
    //     .stval(csr_inst.stval),
    //     .satp(csr_inst.satp),

    //     .if_ip(pre_if_ip),
    //     .if_instr(if_mmu_data_arrival),

    //     .id_ip(id_ip),
    //     .id_instr(id_instr),

    //     .ex_ip(alu_ip),
    //     .ex_instr(alu_instr),

    //     .mem_ip(mem_ip),
    //     .mem_instr(mem_instr),

    //     .wb_ip(wb_ip),
    //     .wb_instr(wb_instr),

    //     .id_iaf(id_instr_no_exec_access),
    //     .id_iam(id_instr_addr_misaligned),
    //     .id_ipf(id_instr_page_fault),

    //     .ex_iaf(ex_instr_no_exec_access),
    //     .ex_iam(ex_instr_addr_misaligned),
    //     .ex_ipf(ex_instr_page_fault),

    //     .mem_iaf(mem_instr_no_exec_access),
    //     .mem_iam(mem_instr_addr_misaligned),
    //     .mem_ipf(mem_instr_page_fault),

    //     .csr_exception(csr_pause),
        
    //     .mem_addr(mem_addr),
    //     .mem_pte(pte_debug), // TODO

    //     .dip_sw(dip_sw),
    //     .touch_btn(touch_btn),
    //     .leds(leds),
    //     .clock(clk),
    //     .reset(rst),
    //     .step(step),
    //     .global_pause(debug_pause)
    // );
//     SEG7_LUT seg_lo (
//       .oSEG1(dpy0),
//       .iDIG ({2'b0, csr_inst.privilege})
//   );
//   SEG7_LUT seg_hi (
//       .oSEG1(dpy1),
//       .iDIG (csr_inst.cause_comb[3:0])
//   );
endmodule

module cu_orchestra(
    input wire [31:0] if_ip,
    input wire [31:0] if_instr,
    input wire        if_ack,
    input wire        if_page_fault,
    input wire        if_addr_misaligned,
    input wire        if_no_exec_access,
    input wire        if_mmu_error,

    input wire [31:0] id_ip,
    input wire [31:0] id_instr,
    input wire [ 4:0] id_raddr1,
    input wire [ 4:0] id_raddr2,

    input wire [31:0] alu_ip,
    input wire [31:0] alu_instr,
    input wire [ 4:0] alu_waddr,
    input wire        alu_take_ip,
    input wire [31:0] alu_new_ip,

    input wire [31:0] mem_ip,
    input wire [31:0] mem_instr,
    input wire [ 4:0] mem_waddr,
    input wire        mem_ack,
    input wire        mem_flush_take_ip,
    input wire [31:0] mem_flush_new_ip,
    input wire        csr_take_ip,
    input wire [31:0] csr_new_ip,

    input wire        pause_global, // XXX
    output reg pre_if_stall,

    output reg if_id_stall,
    output reg if_id_bubble,
    output reg [31:0] if_id_ip,
    output reg if_id_page_fault,
    output reg if_id_addr_misaligned,
    output reg if_id_no_exec_access,

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
    parameter NOP  = 32'b0000_0000_0000_0000_0000_0000_0001_0011;
    // This module mainly focus on handling pipeline hazards.

    // There are 3 causes of such hazards.
    // 1. Multicycle device access.
    // +--> Read is 2 cycles, Write SRAM is 3 cycles.
    // 2. Load use hazards.
    // 3. Branch misprediction / JAL, JALR

    reg if_wait_req;
    reg id_wait_req;
    reg alu_wait_req;
    reg mem_wait_req;
    reg wb_wait_req;
    reg mem_take_ip;
    always_comb begin
        if_id_stall = 0;
        if_id_bubble = 0;
        if_id_ip = if_ip;

        id_alu_stall = 0;
        id_alu_bubble = 0;
        id_alu_ip = id_ip;

        alu_mem_stall = 0;
        alu_mem_bubble = 0;
        alu_mem_ip = alu_ip;

        mem_wb_stall = 0;
        mem_wb_bubble = 0;
        mem_wb_ip = mem_ip;

        if_wait_req = 0;
        id_wait_req = 0;
        alu_wait_req = 0;
        mem_wait_req = 0;
        wb_wait_req = 0;

        if_id_page_fault = 0;
        if_id_no_exec_access = 0;
        if_id_addr_misaligned = 0;

        // Case 1.
        if_wait_req = ~if_ack;
        mem_wait_req = ~mem_ack;

        // Case 2.
        id_wait_req = (
            alu_instr[6:0] == 7'b000_0011 && // LOAD instr in ALU
            (alu_waddr == id_raddr1 || alu_waddr == id_raddr2)
        ) || (
            mem_instr[6:0] == 7'b000_0011 && !mem_ack &&
            (mem_waddr == id_raddr1 || mem_waddr == id_raddr2)
        ) || ( // CSR Related writes
            alu_instr[6:0] == 7'b1110011 && alu_instr[14:12] > 0 &&
            (alu_waddr == id_raddr1 || alu_waddr == id_raddr2)
        );

        // Case 3. Determined by alu_take_ip
        mem_take_ip = mem_flush_take_ip || csr_take_ip;

        // Derive pipeline status backwards.
        mem_wb_stall = pause_global;
        mem_wb_bubble = !mem_wb_stall && mem_wait_req;

        if(mem_wait_req) begin
            mem_wb_ip = mem_ip;
        end

        alu_mem_stall = (!mem_take_ip) && (mem_wb_stall || mem_wait_req);
        alu_mem_bubble = mem_take_ip || ((!alu_mem_stall) && alu_wait_req);
        // XXX
        alu_mem_stall = pause_global || alu_mem_stall;
        alu_mem_bubble = alu_mem_bubble & ~pause_global;

        if(csr_take_ip) begin
            alu_mem_ip = csr_new_ip;
        end else if(mem_flush_take_ip) begin
            alu_mem_ip = mem_flush_new_ip;
        end else if((!alu_mem_stall) && alu_wait_req) begin
            alu_mem_ip = alu_ip; // Trivial case, ignore afterwards.
        end

        id_alu_stall = (! (mem_take_ip || alu_take_ip)) && (alu_wait_req || (alu_mem_stall /*&& mem_instr != NOP*/) );
        id_alu_bubble = mem_take_ip || alu_take_ip || (!id_alu_stall && id_wait_req);

        // XXX
        id_alu_stall = id_alu_stall || pause_global;
        id_alu_bubble = id_alu_bubble & ~pause_global;

        if(csr_take_ip) begin
            id_alu_ip = csr_new_ip;
        end else if(mem_flush_take_ip) begin
            id_alu_ip = mem_flush_new_ip;
        end else if(alu_take_ip) begin
            id_alu_ip = alu_new_ip;
        end 

        if_id_stall = (! (mem_take_ip || alu_take_ip)) && (id_wait_req || (id_alu_stall /*&& alu_instr != NOP*/) );
        if_id_bubble = mem_take_ip || alu_take_ip || (!if_id_stall && if_wait_req);

        // XXX
        if_id_stall = if_id_stall || pause_global;
        if_id_bubble = if_id_bubble & ~pause_global;

        if(csr_take_ip) begin
            if_id_ip = csr_new_ip;
        end else if(mem_flush_take_ip) begin
            if_id_ip = mem_flush_new_ip;
        end else if(alu_take_ip) begin
            if_id_ip = alu_new_ip;
        end 

        pre_if_stall = (! (mem_take_ip || alu_take_ip)) && if_id_stall;

        // XXX
        pre_if_stall = pre_if_stall || pause_global;
        if(if_mmu_error) begin
            if_id_page_fault = if_page_fault;
            if_id_no_exec_access = if_no_exec_access;
            if_id_addr_misaligned = if_addr_misaligned;
        end
    end

endmodule

// module debug(
//     input wire [31:0] mstatus,
//     input wire [31:0] medeleg,
//     input wire [31:0] mideleg,
//     input wire [31:0] mie,
//     input wire [31:0] mtvec,
//     input wire [31:0] mscratch,
//     input wire [31:0] mepc,
//     input wire [31:0] mcause,
//     input wire [31:0] mtval,
//     input wire [31:0] mip,
//     input wire [31:0] stvec,
//     input wire [31:0] sscratch,
//     input wire [31:0] sepc,
//     input wire [31:0] scause,
//     input wire [31:0] stval,
//     input wire [31:0] satp,

//     input wire [31:0] if_ip,
//     input wire [31:0] if_instr,
//     input wire [31:0] id_ip,
//     input wire [31:0] id_instr,
//     input wire [31:0] ex_ip,
//     input wire [31:0] ex_instr,
//     input wire [31:0] mem_ip,
//     input wire [31:0] mem_instr,
//     input wire [31:0] wb_ip,
//     input wire [31:0] wb_instr,

//     input wire id_iaf,
//     input wire id_iam,
//     input wire id_ipf,
//     input wire ex_iaf,
//     input wire ex_iam,
//     input wire ex_ipf,
//     input wire mem_iaf,
//     input wire mem_iam,
//     input wire mem_ipf,
    
//     input wire csr_exception,

//     input wire [31:0] mem_addr,
//     input wire [31:0] mem_pte,

//     input wire [31:0] dip_sw,
//     input wire [ 3:0] touch_btn,
//     output reg [15:0] leds,

//     input wire clock,
//     input wire reset,

//     input wire step,
//     output reg global_pause
// );
//     typedef enum logic [2:0] {
//         WAIT, NORMAL, PAUSE, NEXT
//     } debug_state_t;
//     debug_state_t state;
//     reg [31:0] breakpoint_addr;
//     always_ff @(posedge clock or posedge reset) begin
//         if(reset) begin
//             state <= WAIT;
//             breakpoint_addr <= 32'h8000_0000;
//         end else begin
//             case(state) 
//             WAIT: begin
//                 if(step) begin
//                     state <= NORMAL;
//                     breakpoint_addr <= dip_sw;
//                 end
//             end
//             NORMAL: begin
//                 if(mem_ip == breakpoint_addr || csr_exception) begin
//                     state <= PAUSE;
//                 end
//             end
//             PAUSE: begin
//                 if(step) begin
//                     if(touch_btn == 4'b1111) begin
//                         state <= NORMAL;
//                         breakpoint_addr <= dip_sw;
//                     end else begin
//                         state <= NEXT;
//                     end
//                 end
//             end
//             NEXT:begin
//                 state <= PAUSE;
//             end
//             endcase
//         end
//     end

//     always_comb begin
//         global_pause = 0;
//         case(state) 
//         WAIT: begin
//             global_pause = 1;
//         end
//         NORMAL: begin
//             if(mem_ip == breakpoint_addr || csr_exception) begin
//                 global_pause = 1;
//             end
//         end
//         PAUSE: begin
//             global_pause = 1;
//         end
        
//         endcase
//         case(dip_sw) 
//         16'h0300: leds = mstatus[15:0];
//         16'h1300: leds = mstatus[31:16];
//         16'h0302: leds = medeleg[15:0];
//         16'h1302: leds = medeleg[31:16];
//         16'h0303: leds = mideleg[15:0];
//         16'h0304: leds = mie[15:0];
//         16'h0305: leds = mtvec[15:0];

//         16'h1303: leds = mideleg[31:16];
//         16'h1304: leds = mie[31:16];
//         16'h1305: leds = mtvec[31:16];

//         16'h0340: leds = mscratch[15:0];
//         16'h0341: leds = mepc[15:0];
//         16'h0342: leds = mcause[15:0];
//         16'h0343: leds = mtval[15:0];
//         16'h0344: leds = mip[15:0];

//         // sstatus shares with mstatus, however, mask it with bits that available for supervisor mode.
//         16'h0105: leds = stvec[15:0];
        
//         12'h0140: leds = sscratch[15:0];
//         12'h0141: leds = sepc[15:0];
//         12'h0142: leds = scause[15:0];
//         12'h0143: leds = stval[15:0];
        
//         12'h0180: leds = satp[15:0];

//         16'h1340: leds = mscratch[31:16];
//         16'h1341: leds = mepc[31:16];
//         16'h1342: leds = mcause[31:16];
//         16'h1343: leds = mtval[31:16];
//         16'h1344: leds = mip[31:16];

//         // sstatus shares with mstatus, however, mask it with bits that available for supervisor mode.
//         16'h1105: leds = stvec[31:16];
        
//         16'h1140: leds = sscratch[31:16];
//         16'h1141: leds = sepc[31:16];
//         16'h1142: leds = scause[31:16];
//         16'h1143: leds = stval[31:16];
        
//         16'h1180: leds = satp[31:16];

//         16'h2000: leds = if_ip[15:0]; // 8192
//         16'h2001: leds = id_ip[15:0];
//         16'h2002: leds = ex_ip[15:0];
//         16'h2003: leds = mem_ip[15:0];
//         16'h2004: leds = wb_ip[15:0];

//         16'h2005: leds = if_ip[31:16]; // 8197
//         16'h2006: leds = id_ip[31:16];
//         16'h2007: leds = ex_ip[31:16];
//         16'h2008: leds = mem_ip[31:16];
//         16'h2009: leds = wb_ip[31:16];

//         16'h200a: leds = if_instr[15:0]; // 8202
//         16'h200b: leds = id_instr[15:0];
//         16'h200c: leds = ex_instr[15:0];
//         16'h200d: leds = mem_instr[15:0];
//         16'h200e: leds = wb_instr[15:0];

//         16'h200f: leds = if_instr[31:16]; // 8207
//         16'h2010: leds = id_instr[31:16];
//         16'h2011: leds = ex_instr[31:16];
//         16'h2012: leds = mem_instr[31:16];
//         16'h2013: leds = wb_instr[31:16];

//         16'h2014: leds = {13'b0, id_iaf, id_iam, id_ipf}; // 8212
//         16'h2014: leds = {13'b0, ex_iaf, ex_iam, ex_ipf};
//         16'h2014: leds = {13'b0, mem_iaf, mem_iam, mem_ipf};
//         16'h2014: leds = mem_addr[15:0];
//         16'h2014: leds = mem_addr[31:16];
//         16'h2014: leds = mem_pte[15:0];
//         16'h2014: leds = mem_pte[31:16];
//         default: leds = 16'b0;

//         endcase
//     end 
// endmodule