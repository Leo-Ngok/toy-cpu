
module tlb(
    input wire clock,
    input wire reset,
    
    input wire invalidate,
    
    input wire re,
    input  wire [31:0] rva,
    output wire [31:0] rpte,
    output wire rvalid,

    input wire we,
    input  wire [31:0] wva,
    input  wire [31:0] wpte
);
    parameter XLEN = 32;
    parameter PGSIZE = 4096;
    parameter SET_COUNT = 8;
    parameter N_WAYS = 4;

    parameter PGBITS = $clog2(PGSIZE);
    parameter SET_WIDTH = $clog2(SET_COUNT);
    parameter N_WAY_BW = $clog2(N_WAYS);

    parameter TAG_WIDTH = XLEN - PGBITS - SET_WIDTH;
   typedef struct packed {
    reg valid;
    reg [TAG_WIDTH - 1 : 0] tag;
    reg [N_WAY_BW  - 1 : 0] lru_priority;
    reg [31:0] pte;
   } way_t;

  typedef struct packed {
    way_t [N_WAYS - 1 : 0] way_arr;
  } set_t;
  set_t [SET_COUNT - 1 : 0] tlb_regs;
    wire [SET_WIDTH - 1 : 0] rtlbi = rva[PGBITS             +: SET_WIDTH];
    wire [TAG_WIDTH - 1 : 0] rtlbt = rva[PGBITS + SET_WIDTH +: TAG_WIDTH];

    reg tlb_hit;
    reg [31:0] pte_comb;
    reg [N_WAY_BW - 1: 0] hit_way;
    always_comb begin
        tlb_hit = 0;
        hit_way = {N_WAY_BW{1'b0}};
        pte_comb = 32'b0;
        if(re) begin
            for(int i_way = 0; i_way < N_WAYS; ++ i_way) begin
                if(tlb_regs[rtlbi].way_arr[i_way].valid &&
                tlb_regs[rtlbi].way_arr[i_way].tag == rtlbt) begin
                    tlb_hit = 1'b1;
                    pte_comb = tlb_regs[rtlbi].way_arr[i_way].pte;
                    hit_way = i_way;
                    break;
                end
            end 
        end
    end
    
    reg [N_WAY_BW - 1 : 0] lru_replace_idx;
    always_comb begin
        lru_replace_idx = { N_WAY_BW { 1'b0 }};
        for(int i_way = 0; i_way < N_WAYS; ++i_way) begin
            if(tlb_regs[rtlbi].way_arr[i_way].lru_priority == {N_WAY_BW{1'b0}}) begin
                lru_replace_idx = i_way;
                break;
            end
        end
    end

    wire [SET_WIDTH - 1 : 0] wtlbi = wva[PGBITS             +: SET_WIDTH];
    wire [TAG_WIDTH - 1 : 0] wtlbt = wva[PGBITS + SET_WIDTH +: TAG_WIDTH];

    always_ff @(posedge clock or posedge reset) begin
        if(reset) begin
            for(int i_set = 0; i_set < SET_COUNT; ++i_set) begin
                for(int i_way = 0; i_way < N_WAYS; ++ i_way) begin
                    tlb_regs[i_set].way_arr[i_way].valid <= 1'b0;
                    tlb_regs[i_set].way_arr[i_way].tag <= { TAG_WIDTH {1'b0}};
                    tlb_regs[i_set].way_arr[i_way].pte <= 32'b0;
                    tlb_regs[i_set].way_arr[i_way].lru_priority <= {N_WAY_BW{1'b0}};
                end
            end
        end else begin
            if(tlb_hit) begin
                for(int i_way = 0; i_way < N_WAYS; ++i_way) begin
                    if(hit_way == i_way) continue;
                    if(tlb_regs[rtlbi].way_arr[hit_way].lru_priority <
                    tlb_regs[rtlbi].way_arr[i_way].lru_priority) begin
                        tlb_regs[rtlbi].way_arr[i_way].lru_priority <=
                        tlb_regs[rtlbi].way_arr[i_way].lru_priority - 1;
                    end
                end
                tlb_regs[rtlbi].way_arr[hit_way].lru_priority <= {N_WAY_BW{1'b1}}; 
            end
            if(invalidate) begin
                for(int i_set = 0; i_set < SET_COUNT; ++i_set) begin
                for(int i_way = 0; i_way < N_WAYS; ++ i_way) begin
                    tlb_regs[i_set].way_arr[i_way].valid <= 1'b0;
                end
            end
            end else if(we) begin
                tlb_regs[wtlbi].way_arr[lru_replace_idx].valid <= 1'b1;
                tlb_regs[wtlbi].way_arr[lru_replace_idx].tag <= wtlbt;
                tlb_regs[wtlbi].way_arr[lru_replace_idx].pte <= wpte;
            end
        end
    end

    assign rvalid = tlb_hit;
    assign rpte = tlb_regs[rtlbi].way_arr[hit_way].tag == rtlbt ? tlb_regs[rtlbi].way_arr[hit_way].pte : pte_comb;
endmodule