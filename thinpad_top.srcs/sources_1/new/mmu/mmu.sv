module mmu(
    input  wire        clock,
    input  wire        reset,

    input  wire [31:0] satp,
    input  wire [31:0] va,
    output wire [31:0] pa,

    input  wire        data_we_i,
    input  wire        data_re_i,
    input  wire [ 3:0] byte_en_i,
    input  wire [31:0] data_departure_i,
    output wire [31:0] data_arrival_o,
    output wire        data_ack_o,

    output wire        data_we_o,
    output wire        data_re_o,
    output wire [ 3:0] byte_en_o,
    output wire [31:0] data_departure_o,
    input  wire [31:0] data_arrival_i,
    input  wire        data_ack_i,

    output wire        bypass,
    input  wire        invalidate_tlb,
    input  wire        if_enable,
    input  wire [ 1:0] priv,
    input  wire        sum, // supervisor user memory access.

    output wire        page_fault,
    output wire        no_read_access,
    output wire        no_write_access,
    output wire        no_exec_access,
    output wire        addr_misaligned,
    output wire        mmu_error,

    output reg [31:0]  pte_debug // XXX
);
    typedef enum logic [3:0] { 
        WAIT, FETCH_ROOT_PAGE, FETCH_2ND_PAGE, DATA_ACCESS
    } state_t;
    
    state_t mmu_state;
    state_t next_state;

    always_ff @(posedge clock or posedge reset) begin
        if(reset) begin
            mmu_state <= WAIT;
        end else begin
            mmu_state <= next_state;
        end
    end

    wire mmu_enable;
    reg acc;

    reg tlb_we;
    reg [31:0] tlb_wva;
    reg [31:0] tlb_wpte;

    wire tlb_valid;
    wire [31:0] tlb_pte;

    reg [31:0] va_req;

    reg         page_fault_marker;
    
    reg can_read_comb;
    reg can_write_comb;
    reg can_access_comb; // R or W or X.
    reg address_misaligned_comb;

    always_comb begin
        acc = (mmu_enable) && (data_we_i || data_re_i) && !address_misaligned_comb;
        next_state = WAIT;
        case(mmu_state) 
        WAIT: begin
            if(acc
            && !tlb_valid
            ) begin
                next_state = FETCH_ROOT_PAGE;
            end else begin
                next_state = WAIT;
            end
        end
        FETCH_ROOT_PAGE: begin
            if(data_ack_i) begin
                if(page_fault_marker == 1) begin
                    next_state = WAIT;
                end else begin
                    next_state = FETCH_2ND_PAGE;
                end
            end else begin
                next_state = FETCH_ROOT_PAGE;
            end
        end
        FETCH_2ND_PAGE: begin
            if(data_ack_i) begin
                if(page_fault_marker == 1) begin
                    next_state = WAIT;
                end else begin
                    next_state = DATA_ACCESS;
                end
            end else begin
                next_state = FETCH_2ND_PAGE;
            end
        end
        DATA_ACCESS: begin
            if(data_ack_i || mmu_error) begin
                next_state = WAIT;
            end else begin
                next_state = DATA_ACCESS;
            end
        end
        endcase
        if(va_req != va) begin
            next_state = WAIT;
        end
    end

    reg        data_re_comb;
    reg        data_we_comb;
    reg [ 3:0] data_be_comb;
    reg [31:0] data_pa_comb;
    reg [31:0] data_departure_comb;

    reg        data_ack_comb;
    reg [31:0] data_arrival_comb;

    reg        bypass_comb;

    reg [31:0] second_page_pte_reg;
    reg [31:0]   data_page_pte_reg;

    always_comb begin
        data_re_comb = 0;
        data_we_comb = 0;
        data_be_comb = 4'b0;
        data_pa_comb = 32'b0;
        data_departure_comb = 32'b0;

        data_ack_comb = 0;
        data_arrival_comb = 32'b0;

        bypass_comb = 0;

        
        tlb_we = 0;
        tlb_wpte = 32'b0;
        tlb_wva = 32'b0;
        
        page_fault_marker = 0;
        
        can_read_comb = data_re_i;
        can_write_comb = data_we_i;
        can_access_comb = 0;

        address_misaligned_comb = 0;

        case(byte_en_i)
        4'b1111: address_misaligned_comb = va[1:0] != 2'b0;
        4'b0011, 4'b1100: address_misaligned_comb = va[0] != 1'b0;
        default: address_misaligned_comb = 0;
        endcase

        pte_debug = 32'b0;

        case(mmu_state)
        WAIT: begin
            if(tlb_valid) begin
                // CHECK FOR GLOBAL ACCESS.
                can_access_comb = 1;
                /*!address_misaligned_comb &&
                ((priv[0] != tlb_pte[4]) || // privilege != user bit, note that user mode is encoded as zero, supervisor is encoded as one.
                (priv[0] && sum)); */// alternatively, supervisor can also read user's page when sum is on.
                // CHECK FOR READ ACCESS.
                can_read_comb = 1;/*can_access_comb && 
                ((if_enable && tlb_pte[3]) || // This page is executable.
                (!if_enable && tlb_pte[1]));*/ // This page is readable.

                can_write_comb = 1;/*can_access_comb && 
                tlb_pte[2]; */// This page is writable.

                data_re_comb = data_re_i && can_read_comb;
                data_we_comb = data_we_i && can_write_comb;
                data_be_comb = byte_en_i;
                data_pa_comb = { tlb_pte[29:10], va[11:0] };
                data_departure_comb = data_departure_i;
                pte_debug = tlb_pte; // XXX
                if(data_ack_i) begin
                    data_ack_comb = 1;
                    data_arrival_comb = data_arrival_i;
                end
            end
        end
        FETCH_ROOT_PAGE: begin
            data_re_comb = 1;
            data_be_comb = 4'b1111;
            data_pa_comb = { satp[19:0], va[31:22], 2'b0 };
            bypass_comb = 1;
            if(data_ack_i) begin
                if(data_arrival_i[0] == 1'b0) begin // Root page pte page fault.
                    page_fault_marker = 1;
                end
            end
        end
        FETCH_2ND_PAGE: begin
            data_re_comb = 1;
            data_be_comb = 4'b1111;
            data_pa_comb = { second_page_pte_reg[29:10], va[21:12], 2'b0 };
            bypass_comb = 1;
            if(data_ack_i) begin
                if(data_arrival_i[0] == 1'b0) begin // Leaf page pte page fault.
                    page_fault_marker = 1;
                end else begin
                    tlb_we = 1;
                    tlb_wpte = data_arrival_i;
                    tlb_wva = va;
                end
            end
        end 
        DATA_ACCESS: begin
            // CHECK FOR GLOBAL ACCESS.
            can_access_comb = 1;
            /*!address_misaligned_comb &&
            ((priv[0] != data_page_pte_reg[4]) || // privilege != user bit, note that user mode is encoded as zero, supervisor is encoded as one.
            (priv[0] && sum)); */// alternatively, supervisor can also read user's page when sum is on.
            // CHECK FOR READ ACCESS.
            can_read_comb = 1;/* can_access_comb && 
            ((if_enable && data_page_pte_reg[3]) || // This page is executable.
            (!if_enable && data_page_pte_reg[1]));*/// This page is readable.

            can_write_comb = 1; /*can_access_comb && 
            data_page_pte_reg[2]; */// This page is writable.

            data_re_comb = data_re_i && can_read_comb;
            data_we_comb = data_we_i && can_write_comb;
            data_be_comb = byte_en_i;
            data_pa_comb = { data_page_pte_reg[29:10], va[11:0] };
            data_departure_comb = data_departure_i;
            pte_debug = data_page_pte_reg;
            if(data_ack_i) begin
                data_ack_comb = 1;
                data_arrival_comb = data_arrival_i;
            end
        end
        endcase
    end

    always_ff @(posedge clock or posedge reset) begin
        if(reset) begin
            data_page_pte_reg <= 32'b0;
            second_page_pte_reg <= 32'b0;
            va_req <= 32'b0;
        end else begin
            case(mmu_state)
            WAIT: begin
            if(acc
            && !tlb_valid
            ) begin
                va_req <= va;
            end
            end
            FETCH_ROOT_PAGE: begin
                if(data_ack_i) begin
                    second_page_pte_reg <= data_arrival_i;
                end 
            end
            FETCH_2ND_PAGE: begin
                if(data_ack_i) begin
                    data_page_pte_reg <= data_arrival_i;
                end
            end
            DATA_ACCESS: begin
                
            end
            endcase
        end
    end

    assign mmu_enable = satp[31];
    assign data_re_o = mmu_enable ? data_re_comb : data_re_i;
    assign data_we_o = mmu_enable ? data_we_comb : data_we_i;
    assign byte_en_o = mmu_enable ? data_be_comb : byte_en_i;
    assign pa        = mmu_enable ? data_pa_comb : va;
    assign data_departure_o = mmu_enable ? data_departure_comb : data_departure_i;

    assign data_ack_o = mmu_enable ? data_ack_comb : data_ack_i;
    assign data_arrival_o = mmu_enable ? data_arrival_comb : data_arrival_i;
    assign bypass = mmu_enable ? bypass_comb : 1'b0;

    assign page_fault = mmu_enable ? page_fault_marker : 1'b0;
    assign no_write_access = mmu_enable ? (data_we_i && !can_write_comb) : 1'b0;
    assign no_read_access =  mmu_enable ? (data_re_i && !if_enable && !can_read_comb) : 1'b0;
    assign no_exec_access = mmu_enable ? (data_re_i && if_enable && !can_read_comb) : 1'b0;
    assign addr_misaligned = (data_re_i || data_we_i) && address_misaligned_comb;
    assign mmu_error = addr_misaligned || page_fault || no_read_access || no_write_access || no_exec_access;
    tlb buffer(
        .clock(clock),
        .reset(reset),
        .invalidate(invalidate_tlb),
        .re(acc),
        .rva(va),
        .rpte(tlb_pte),
        .rvalid(tlb_valid),

        .we(tlb_we),
        .wva(tlb_wva),
        .wpte(tlb_wpte)
    );
endmodule