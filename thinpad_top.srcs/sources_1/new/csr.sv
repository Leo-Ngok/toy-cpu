module csr(
    input wire clock,
    input wire reset,

    input  wire [31:0] instr,
    input  wire [31:0] wdata,  // DATA That WRITES TO CSR (usually FROM GP register files)
    output wire [31:0] rdata, // DATA that READS FROM CSR (writes to GP register files)

    input  wire [31:0] curr_ip, // Set MEPC
    input  wire        timer_interrupt, // TIME'S UP!

    output wire       take_ip,
    output wire [31:0] new_ip,

    input wire instr_page_fault,
    input wire data_page_fault,

    input wire instr_addr_misaligned,
    input wire data_addr_misaligned,

    input wire no_read_access,
    input wire no_write_access,
    input wire no_exec_access,

    input wire [31:0] instr_fault_addr,
    input wire [31:0] data_fault_addr,

    input wire [63:0] mtime,
    output reg pause_global // XXX
);
    typedef enum logic [1:0] { 
        USER, SUPERVISOR, HYPERVISOR, MACHINE 
    } priv_mode_t;
    priv_mode_t privilege;
    /* Let's do these first.
    ????? CSR ?????????
    1. mtvec: BASE, MODE
    2. mscratch
    3. mepc
    4. mcause: Interrupt, Exception Code
    5. mstatus: MPP(12:11)
    6. mie: MTIE(7)
    7. mip: MTIP(7)
    */
    
    // MACHINE INFORMATION REGISTERS
    reg [31:0] mhartid;  // 0XF14, Hardware thread ID

    // MACHINE TRAP SETUP
    reg [31:0] mstatus;  // 0X300, Machine status register. (MONITOR)
    reg [31:0] medeleg;  // 0X302, Machine exception delegation register.
    reg [31:0] mideleg;  // 0X303, Machine interrupt delegation register.
    reg [31:0] mie;      // 0X304, Machine interrupt-enable register. (MONITOR)
    reg [31:0] mtvec;    // 0X305, Machine trap-handler base address. (MONITOR)

    // MACHINE TRAP HANDLING
    reg [31:0] mscratch; // 0X340, Scratch register for machine trap handlers. (MONITOR)
    reg [31:0] mepc;     // 0X341, Machine exception program counter. (MONITOR)
    reg [31:0] mcause;   // 0X342, Machine trap cause. (MONITOR)
    reg [31:0] mtval;    // 0X343, Machine bad address or instruction.
    reg [31:0] mip;      // 0X344, Machine interrupt pending. (MONITOR)

    // SUPERVISOR TRAP SETUP
    // reg [31:0] sstatus;  // 0X100, Supervisor status register.
    // reg [31:0] sie;      // 0X104, Supervisor interrupt-enable register.
    reg [31:0] stvec;    // 0X105, Supervisor trap handler base address.

    // SUPERVISOR TRAP HANDLING
    reg [31:0] sscratch; // 0X140, Scratch register for supervisor trap handlers.
    reg [31:0] sepc;     // 0X141, Supervisor exception program counter.
    reg [31:0] scause;   // 0X142, Supervisor trap cause.
    reg [31:0] stval;    // 0X143, Supervisor bad address or instruction.
    // reg [31:0] sip;      // 0X144, Supervisor interrupt pending.

    // SUPERVISOR PROTECTION AND TRANSLATION
    reg [31:0] satp;     // 0X180, Supervisor address translation and protection.

    parameter SYSTEM = 32'b????_????_????_????_????_????_?1110011;
    parameter CSRRW  = 32'b????_????_????_?????_001_?????_1110011;
    parameter CSRRS  = 32'b????_????_????_?????_010_?????_1110011;
    parameter CSRRC  = 32'b????_????_????_?????_011_?????_1110011;
    parameter CSRRWI = 32'b????_????_????_?????_101_?????_1110011;
    parameter CSRRSI = 32'b????_????_????_?????_110_?????_1110011;
    parameter CSRRCI = 32'b????_????_????_?????_111_?????_1110011;

    parameter ECALL  = 32'b0000_0000_0000_00000_000_00000_111_0011;
    parameter EBREAK = 32'b0000_0000_0001_00000_000_00000_111_0011;
    parameter MRET   =  32'b0011000_00010_00000_000_00000_111_0011;
    parameter SRET   =  32'b0001000_00010_00000_000_00000_111_0011;

    reg [31:0] rdata_comb;

    wire [11:0] address = instr[31:20]; // Refer to ISA ZICSR

    parameter MSTATUS_MASK = 32'b1000_0000_0111_1111_1111_1111_1110_1010;
    parameter SSTATUS_MASK = 32'b1000_0000_0000_1101_1110_0111_0110_0010;
    parameter M_INTR_MASK = 32'b1010_1010_1010;
    parameter S_INTR_MASK = 32'b0010_0010_0010;
    // READS OUT ORIGINAL CSR VALUES
    always_comb begin
        case(address) 
        12'hf14: rdata_comb = mhartid;

        12'h300: rdata_comb = mstatus & MSTATUS_MASK;
        12'h302: rdata_comb = medeleg;
        12'h303: rdata_comb = mideleg;
        12'h304: rdata_comb = mie & M_INTR_MASK;
        12'h305: rdata_comb = mtvec;

        12'h340: rdata_comb = mscratch;
        12'h341: rdata_comb = mepc;
        12'h342: rdata_comb = mcause;
        12'h343: rdata_comb = mtval;
        12'h344: rdata_comb = mip & M_INTR_MASK; 

        // sstatus shares with mstatus, however, mask it with bits that available for supervisor mode.
        12'h100: rdata_comb = mstatus & SSTATUS_MASK;
        12'h104: rdata_comb = mie & S_INTR_MASK; // sie shares the same register as mie.
        12'h105: rdata_comb = stvec;
        
        12'h140: rdata_comb = sscratch;
        12'h141: rdata_comb = sepc;
        12'h142: rdata_comb = scause;
        12'h143: rdata_comb = stval;
        12'h144: rdata_comb = mip & S_INTR_MASK; // sip shares the same register as mip.
        // no, you should always 'handle' interrupt first.
        12'h180: rdata_comb = satp;

        12'hc01: rdata_comb = mtime[31:0];
        12'hc80: rdata_comb = mtime[63:32];

        default: rdata_comb = 32'b0;
        endcase
    end

    assign rdata = rdata_comb;

    reg [31:0] wdata_internal;
    // SETS NEW CSR VALUES WHERE APPROPRIATE
    always_comb begin
        wdata_internal = (instr[14]) ? {27'b0, instr[19:15]} : wdata; 
        // case(address) 
        // // mstatus: MPP[12:11] only for monitor
        // // for bootloader, 
        // // Bootloader disables FS, clear MPIE also, so make FS[14:13], MPIE[7] writable.
        // // Refer to boot_first_hart in rbl.
        // 12'h300: wdata_comb = {
        //     mstatus[31:15], wdata_internal[14:11], 
        //     mstatus[10:8], wdata_internal[7], 
        //     mstatus[6:0]};
        // // medeleg:
        // 12'h302: wdata_comb = { 
        //     medeleg[31:16], wdata_internal[15],     // Store / AMO page fault
        //     medeleg[14],    wdata_internal[13:12], // load, instruction page fault
        //     medeleg[11:10], wdata_internal[9:0]}; // secall, uecall, store acc fault, store misalign, load acc fault, load misalign, bp, illegal instr, instr acc fault, instr misalign
        // // mideleg: STIE, SSIE, SEIE
        // 12'h303: wdata_comb = {
        //     mideleg[31:10], wdata_internal[9], // SEIE
        //     mideleg[8:6], wdata_internal[5],   // STIE
        //     mideleg[4:2], wdata_internal[1],   // SSIE
        //     mideleg[0]};
        // // mie: MTIE only for monitor
        // // Support for MSIE is provided for bootloader (though useless)
        // 12'h304: wdata_comb = wdata_internal; /*{
        //     mie[31: 8], wdata_internal[7], // MTIE
        //     mie[6:4], wdata_internal[3],   // MSIE
        //     mie[2:0]};*/
        // // mtvec
        // 12'h305: wdata_comb = wdata_internal;

        // // mscratch
        // 12'h340: wdata_comb = wdata_internal;
        // // mepc
        // 12'h341: wdata_comb = wdata_internal;
        // // mcause
        // 12'h342: wdata_comb = wdata_internal;
        // // mtval
        // 12'h343: wdata_comb = wdata_internal;
        // // mip: MTIP only for monitor
        // // add support for MSIP, since MSIE is set by bootloader.
        // 12'h344: wdata_comb = wdata_internal; /*{
        //     mip[31: 4],// wdata_internal[7], 
        //     //mip[6:4], 
        //     wdata_internal[3], 
        //     mip[2:0]};*/
        
        // // sstatus
        // // Disassemble uCore and you'll realize that
        // // only sie(1), spp(8) and sum(18) are needed
        // 12'h100: wdata_comb = {
        //     mstatus[31:19], wdata_internal[18], 
        //     mstatus[17: 9], wdata_internal[ 8],
        //     mstatus[ 7: 2], wdata_internal[ 1],
        //     mstatus[0]
        // };
        // // sie
        // // only ssie(1) and stie(5) are needed.
        // 12'h104: wdata_comb = wdata_internal; /*{
        //     mie[31:6], wdata_internal[5],
        //     mie[4:2], wdata_internal[1],
        //     mie[0]
        // };*/
        // // stvec
        // 12'h105: wdata_comb = wdata_internal;

        // // sscratch
        // 12'h140: wdata_comb = wdata_internal;
        // // sepc
        // 12'h141: wdata_comb = wdata_internal;
        // // scause
        // 12'h142: wdata_comb = wdata_internal;
        // // stval
        // 12'h143: wdata_comb = wdata_internal;
        // // sip
        // 12'h144: wdata_comb = wdata_internal; /*{
        //     mip[31:6], wdata_internal[5],
        //     mip[4:2], wdata_internal[1],
        //     mip[0]
        // };*/

        // // satp
        // 12'h180: wdata_comb = wdata_internal;
        // default: wdata_comb = 32'b0;
        // endcase
    end


    reg [31:0] mstatus_comb;

    reg [31:0] cause_comb;
    priv_mode_t next_priv;

    reg       take_ip_comb;
    reg [31:0] new_ip_comb;
    reg pause_global_comb; // XXX
    always_comb begin
        mstatus_comb = mstatus;
        
        cause_comb = 32'hffffffff;

        next_priv = privilege;
        take_ip_comb = 0;
        new_ip_comb = 32'h8000_0000;
        pause_global_comb = 0;
        casez(instr)
        MRET: begin
            take_ip_comb = 1;
            new_ip_comb = mepc;
            mstatus_comb = {
                mstatus[31:13], 2'b0, 
                mstatus[10: 8], 1'b1, 
                mstatus[ 6: 4], mstatus[7], 
                mstatus[ 2: 0]
            };
        end
        SRET: begin
            take_ip_comb = 1;
            new_ip_comb = sepc;
            mstatus_comb = {
                mstatus[31:9], 1'b0,
                mstatus[7:6], 1'b1,
                mstatus[4:2], mstatus[5],
                mstatus[0]
            };
        end
        default: begin
                    
            // (?) 0 - instr address misaligned
            // (?) 1 - instr access fault
            // ( ) 2 - illegal instr
            // (v) 3 - breakpoint
            // (?) 4 - load addr misaligned
            // (?) 5 - load access fault
            // (?) 6 - store addrss misaligned
            // (?) 7 - store access fault
            // (v) 8 - ecall from U
            // (v) 9 - ecall from S
            // (?) 11 - ecall from M
            // (?) 12 - Instr page fault
            // (v) 13 - Load page fault
            // (v) 15 - store page fault
            // ==============================================================
            // first we deal with instruction misalignment.
            if(!take_ip_comb && instr_addr_misaligned) begin
                take_ip_comb = 1;
                cause_comb = 32'd0; // instruction address misaligned.
                pause_global_comb = 1;
            end
            // ==============================================================
            // handle ecall, then handle page fault.
            if(!take_ip_comb && instr == ECALL) begin
                case(privilege)
                USER: begin 
                    cause_comb = 32'd8;
                end
                SUPERVISOR: begin
                    cause_comb = 32'd9;
                end
                HYPERVISOR: begin 
                    cause_comb = 32'd10; // Deprecated 
                end
                MACHINE: begin 
                    cause_comb = 32'd11; 
                end
                endcase
                take_ip_comb = 1;
            end
            // ecall has higher priority than ebreak.
            if(!take_ip_comb && instr == EBREAK) begin
                cause_comb = 32'd3;
                take_ip_comb = 1;
            end

            // ==============================================================
            // address misaligned.
            if(!take_ip_comb && data_addr_misaligned) begin
                take_ip_comb = 1;
                if(instr[6:0] == 7'b0000011) begin
                    cause_comb = 32'd4; // load address misaligned.
                end else if(instr[6:0] == 7'b0100011) begin
                    cause_comb = 32'd6; // Store address misaligned.
                end else begin // Illegal instruction.
                    cause_comb = 32'd2;
                end
                pause_global_comb = 1;
            end
            // ==============================================================
            // page fault
            if(!take_ip_comb && satp[31] && data_page_fault) begin
                take_ip_comb = 1;
                if(instr[6:0] == 7'b0000011) begin
                    cause_comb = 32'd13; // load page fault.
                end else if(instr[6:0] == 7'b0100011) begin
                    cause_comb = 32'd15; // Store page fault.
                end else begin // Illegal instruction.
                    cause_comb = 32'd2;
                end
            end
            // instruction page fault.
            if(!take_ip_comb && satp[31] && instr_page_fault) begin
                take_ip_comb = 1;
                cause_comb = 32'd12; // instruction page fault.
            end
            // ==============================================================
            // access violations.
            /*if(!take_ip_comb && satp[31] && no_exec_access) begin
                take_ip_comb = 1;
                cause_comb = 32'd1; // instruction access fault.
                pause_global_comb = 1;
            end
            if(!take_ip_comb && satp[31] && no_read_access && instr[6:0] == 7'b0000011) begin
                take_ip_comb = 1;
                cause_comb = 32'd5; // load access fault.
                pause_global_comb = 1;
            end*/
            if(!take_ip_comb && satp[31] && no_write_access && instr[6:0] == 7'b0100011) begin
                take_ip_comb = 1;
                cause_comb = 32'd7; // store access fault.
                pause_global_comb = 1;
            end
            // ==============================================================
            // timer interrupt, refer to p.32, p.67 of volume 2
            if(
                !take_ip_comb && 
                ((privilege == MACHINE && mstatus[3]) || privilege != MACHINE) &&
                (mie[7] && mip[7]) &&
                (mideleg[7] == 1'b0)
            ) begin
                take_ip_comb = 1;
                cause_comb = 32'h8000_0007; // machine timer interrupt.
                next_priv = MACHINE;
            end
            if(!take_ip_comb && 
             ((privilege == SUPERVISOR && mstatus[1]) || privilege == USER) &&
                    (mie[5] && mip[5]) 
            ) begin
                take_ip_comb = 1;
                cause_comb = 32'h8000_0005; // supervisor timer interrupt.
                next_priv = SUPERVISOR;
            end
            // ==============================================================

            if(take_ip_comb) begin
                if(
                    // exceptions.
                    (!cause_comb[31] && privilege != MACHINE && medeleg[cause_comb[5:0]]) ||
                    // interrupts.
                    (cause_comb[31] && next_priv == SUPERVISOR)
                ) begin
                    next_priv = SUPERVISOR;
                    new_ip_comb = { stvec[31:2], 2'b0 };
                    mstatus_comb = {
                        mstatus[31:9], privilege[0],
                        mstatus[7:6], mstatus[1],
                        mstatus[4:2], 1'b0,
                        mstatus[0]
                    };
                end else begin
                    next_priv = MACHINE;
                    new_ip_comb = { mtvec[31:2], 2'b0 };
                    mstatus_comb = {
                        mstatus[31:13], unsigned'(privilege), 
                        mstatus[10: 8], mstatus[3], 
                        mstatus[ 6: 4], 1'b0, 
                        mstatus[ 2: 0]
                    };
                end
            end
        end
        endcase
    end

    assign take_ip = take_ip_comb; 
    assign new_ip = new_ip_comb;

    always_ff @(posedge reset or posedge clock) begin
        if(reset) begin
            privilege <= MACHINE;
            mhartid <= 32'b0;       // MRO field, change for advanced implementations.

            mstatus <= 32'b0;
            medeleg <= 32'b0;
            mideleg <= 32'b0;
            mie     <= 32'b0;
            mtvec   <= 32'b0;

            mscratch<= 32'b0;
            mepc    <= 32'b0;
            mcause  <= 32'b0;
            mtval   <= 32'b0;
            mip     <= 32'b0;
            
            // sstatus <= 32'b0;
            // sie     <= 32'b0;
            stvec   <= 32'b0;
            
            sscratch<= 32'b0;
            sepc    <= 32'b0;
            scause  <= 32'b0;
            stval   <= 32'b0;
            // sip     <= 32'b0;

            satp    <= 32'b0;
            pause_global <= 0; // XXX
        end else begin
            mip[7] <= timer_interrupt;
            casez(instr)
            CSRRW, CSRRWI: begin
                case(address) 
                // 12'hf14: mhartid <= wdata_internal; No, That is a readonly field.
                12'h300: mstatus    <= (mstatus & ~MSTATUS_MASK) | (wdata_internal & MSTATUS_MASK);
                12'h302: medeleg    <= wdata_internal;
                12'h303: mideleg    <= wdata_internal;
                12'h304: mie        <= (mie & ~M_INTR_MASK) | (wdata_internal & M_INTR_MASK);
                12'h305: mtvec      <= wdata_internal;

                12'h340: mscratch   <= wdata_internal;
                12'h341: mepc       <= wdata_internal;
                12'h342: mcause     <= wdata_internal;
                12'h343: mtval      <= wdata_internal;
                12'h344: mip        <= (mip & ~M_INTR_MASK) | (wdata_internal & M_INTR_MASK);

                12'h100: mstatus    <= (mstatus & ~SSTATUS_MASK) | (wdata_internal & SSTATUS_MASK);
                12'h104: mie        <= (mie & ~S_INTR_MASK) | (wdata_internal & S_INTR_MASK); // shares with sie.
                12'h105: stvec      <= wdata_internal;

                12'h140: sscratch   <= wdata_internal;
                12'h141: sepc       <= wdata_internal;
                12'h142: scause     <= wdata_internal;
                12'h143: stval      <= wdata_internal;
                12'h144: mip        <= (mip & ~S_INTR_MASK) | (wdata_internal & S_INTR_MASK);

                12'h180: satp       <= wdata_internal;
                endcase
            end
            CSRRS, CSRRSI: begin
                case(address) 
                // 12'hf14: mhartid <= mhartid |wdata_internal; No, That is a readonly field.
                12'h300: mstatus    <= mstatus | (wdata_internal & MSTATUS_MASK);
                12'h302: medeleg    <= medeleg | wdata_internal;
                12'h303: mideleg    <= mideleg | wdata_internal;
                12'h304: mie        <= mie     | (wdata_internal & M_INTR_MASK);
                12'h305: mtvec      <= mtvec   | wdata_internal;

                12'h340: mscratch   <= mscratch| wdata_internal;
                12'h341: mepc       <= mepc    | wdata_internal;
                12'h342: mcause     <= mcause  | wdata_internal;
                12'h343: mtval      <= mtval   | wdata_internal;
                12'h344: mip        <= mip     | (wdata_internal & M_INTR_MASK);

                12'h100: mstatus    <= mstatus | (wdata_internal & SSTATUS_MASK);
                12'h104: mie        <= mie     | (wdata_internal & S_INTR_MASK);
                12'h105: stvec      <= stvec   | wdata_internal;

                12'h140: sscratch   <= sscratch| wdata_internal;
                12'h141: sepc       <= sepc    | wdata_internal;
                12'h142: scause     <= scause  | wdata_internal;
                12'h143: stval      <= stval   | wdata_internal;
                12'h144: mip        <= mip     | (wdata_internal & S_INTR_MASK);

                12'h180: satp       <= satp    | wdata_internal;
                endcase
            end
            CSRRC, CSRRCI: begin
                case(address) 
                // 12'hf14: mhartid <= mhartid & ~wdata_internal; No, That is a readonly field.
                12'h300: mstatus    <= mstatus & ~(wdata_internal & MSTATUS_MASK);
                12'h302: medeleg    <= medeleg & ~wdata_internal;
                12'h303: mideleg    <= mideleg & ~wdata_internal;
                12'h304: mie        <= mie     & ~(wdata_internal & M_INTR_MASK);
                12'h305: mtvec      <= mtvec   & ~wdata_internal;

                12'h340: mscratch   <= mscratch& ~wdata_internal;
                12'h341: mepc       <= mepc    & ~wdata_internal;
                12'h342: mcause     <= mcause  & ~wdata_internal;
                12'h343: mtval      <= mtval   & ~wdata_internal;
                12'h344: mip        <= mip     & ~(wdata_internal & M_INTR_MASK);

                12'h100: mstatus    <= mstatus & ~(wdata_internal & SSTATUS_MASK);
                12'h104: mie        <= mie     & ~(wdata_internal & S_INTR_MASK);
                12'h105: stvec      <= stvec   & ~wdata_internal;

                12'h140: sscratch   <= sscratch& ~wdata_internal;
                12'h141: sepc       <= sepc    & ~wdata_internal;
                12'h142: scause     <= scause  & ~wdata_internal;
                12'h143: stval      <= stval   & ~wdata_internal;
                12'h144: mip        <= mip     & ~(wdata_internal & S_INTR_MASK);

                12'h180: satp       <= satp    & ~wdata_internal;
                endcase
            end
            MRET: begin
                privilege <= priv_mode_t'(mstatus[12:11]);
                mstatus <= mstatus_comb;
            end
            SRET: begin
                privilege <= priv_mode_t'({1'b0, mstatus[8]});
                mstatus <= mstatus_comb;
            end
            default: begin
                if(take_ip_comb) begin
                    privilege <= next_priv;
                    if(next_priv == MACHINE) begin
                        mepc    <= curr_ip;
                        mstatus <= mstatus_comb;
                        mcause  <= cause_comb;
                        if(data_page_fault || data_addr_misaligned || no_read_access||no_write_access) begin
                            mtval <= data_fault_addr; // TODO: CHANGE IT BACK ! TO! data_fault_addr;
                        end else if(instr_page_fault || instr_addr_misaligned || no_exec_access) begin
                            mtval <= instr_fault_addr;
                        end
                    end else begin
                        sepc    <= curr_ip;
                        mstatus <= mstatus_comb;
                        scause  <= cause_comb;
                        if(data_page_fault) begin
                            stval <= data_fault_addr;
                        end else if(instr_page_fault || instr_addr_misaligned || no_exec_access) begin
                            stval <= instr_fault_addr;
                        end
                    end
                    if(pause_global_comb)
                        pause_global <= pause_global_comb;
                end
            end
            endcase
        end
    end
    
    
    // WPRI 
    // Write Preserve, Read Ignore
    // Unused fields

    // WLRL
    // Write Legal, Read Legal
    // Allocated fields, validity asserted by sw

    // WARL
    // Write any, read legal
    // Our duty to filter illegal writes.
    // When illegal write attempted, set default value.



    // mstatus fields. (DAY) ^ (-1)

    // Interrupts for lower priv. modes are always disabled,
    // higher priv modes are always enabled.

    // Should modify per-interrupt enable bits
    // in higher priv. mode before ceding to lower priv.

    // wire uie = mstatus[0]; // ---+
    // wire sie = mstatus[1]; // ---+-- Interrupt enable
    // wire mie = mstatus[3]; // ---+   

    // // trap: y -> x: xPIE <- XIE; xPP <- y;
    // // previous interupt enable
    // wire upie = mstatus[4];
    // wire spie = mstatus[5];
    // wire mpie = mstatus[7];

    // // previous privilege mode
    // // WLRL
    // wire spp = mstatus[8];      
    // wire [1:0] mpp  = mstatus[12:11];  // MONITOR
    // // when running xret:
    // // suppose y = xPP, then 
    // // xIE <- xPIE;
    // // Privilege mode set to y;
    // // xPIE <- 1;
    // // xPP <- U;

    // // useless
    // wire [1:0] fs = mstatus[14:13];
    // wire [1:0] xs = mstatus[16:15];

    // // memory privilege
    // // Modify PRiVilege
    // wire mprv = mstatus[17];

    // // permit Supervisor User Memory access 
    wire sum = mstatus[18];

    // // make executable readable.    
    // // read page marked executable only.
    // wire mxr = mstatus[19];

    // // trap virtual memory
    // wire tvm = mstatus[20];

    // // timeout wait 
    // // when set, ...
    // wire tw = mstatus[21];

    // // trap sret, permits supervisor return
    // // augmented virtualization mechanism
    // wire tsr = mstatus[22];
    // wire sd = mstatus[31];


    // // mtvec
    // wire [29:0] base = mtvec[31:2];
    // wire [1:0] mode  = mtvec[1:0];

    // // Interrupt enable and pending...
    // // For mip, 
    // // only usip, ssip, utip, stip, ueip, seip
    // // writable in m mode
    // // only usip, utip, ueip writable in s mode

    // // (s)oftware
    // // (t)imer
    // // (e)xternal

    // wire usip = mip[0];
    // wire ssip = mip[1];
    // wire msip = mip[3];

    // wire utip = mip[4];
    // wire stip = mip[5];
    // wire mtip = mip[7]; // MONITOR

    // wire ueip = mip[8];
    // wire seip = mip[9];
    // wire meip = mip[11];

    // wire usie = mie[0];
    // wire ssie = mie[1];
    // wire msie = mie[3];

    // wire utie = mie[4];
    // wire stie = mie[5];
    // wire mtie = mie[7]; // MONITOR

    // wire ueie = mie[8];
    // wire seie = mie[9];
    // wire meie = mie[11];

    // wire [30:0] ex_code = mcause[30:0];
    // wire intr = mcause[31];

    // for mtval, 
    // written with faulting eff address
    // when in hw breakpoint, 
    // if address
    // dev access load/store address
    // for illegal instr, written as faulty instr
    wire mmu_enable;
    assign mmu_enable = satp[31] && (privilege != MACHINE);
endmodule