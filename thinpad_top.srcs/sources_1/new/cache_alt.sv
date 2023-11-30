module cache_alt (
    input wire clock,
    input wire reset,

    input  wire        bypass,
    input  wire        flush,
    input  wire        invalidate,
    output wire        clear_complete,
    // TO CU.
    input  wire        cu_we,
    input  wire        cu_re,
    input  wire [31:0] cu_addr,
    input  wire [ 3:0] cu_be,
    input  wire [31:0] cu_data_i,
    output wire        cu_ack,
    output wire [31:0] cu_data_o,
    output wire [31:0] cu_data_o_delayed,
    // TO DAU
    output wire        dau_we,
    output wire        dau_re,
    output wire [31:0] dau_addr,
    output wire [ 3:0] dau_be,
    output wire [31:0] dau_data_o,
    input  wire        dau_ack,
    input  wire [31:0] dau_data_i
);
  // 2 MB for each piece of SRAM, width is 16 bit,
  // so 2 ** 20 possibilities.
  parameter VALID_ADDR_WIDTH = 21;
  parameter SET_COUNT = 8;
  parameter N_WAYS = 4;
  parameter BLOCK_COUNT = 8;

  parameter SET_WIDTH = $clog2(SET_COUNT);
  parameter BLOCK_WIDTH = $clog2(BLOCK_COUNT);
  parameter TAG_WIDTH = VALID_ADDR_WIDTH - SET_WIDTH - BLOCK_WIDTH;

  parameter N_WAY_BW = $clog2(N_WAYS);

  // TODO: WARNING: Should implement cache coherence protocol. (We now have FENCE, then who's f-- care?)
  wire bypass_internal = bypass || !(32'h8000_0000 <= cu_addr && cu_addr <= 32'h807F_FFFF);

  typedef struct packed {
    reg valid;
    reg dirty;
    reg [TAG_WIDTH -1:0] tag;
    reg [N_WAY_BW -1 : 0] lru_priority;
  } way_t;

  typedef struct packed {way_t [N_WAYS - 1:0] way_arr;} set_t;

  // Note that:
  // Size = SET_COUNT * N_WAYS * (4 * BLOCK_COUNT) Bytes;
  // Size = 4 * 4 * (4 * 16) = 1024 Bytes.
  set_t [SET_COUNT - 1:0] cache_regs;



  //   wire [VALID_ADDR_WIDTH - 1:0] valid_addr = cu_addr[22:2];
  //   wire [SET_WIDTH - 1:0] set_idx = valid_addr[BLOCK_WIDTH+:SET_WIDTH];
  //   wire [TAG_WIDTH - 1:0] tag = valid_addr[BLOCK_WIDTH+SET_WIDTH+:TAG_WIDTH];
  //   wire [BLOCK_WIDTH - 1:0] block_idx = valid_addr[0+:BLOCK_WIDTH];
  reg [VALID_ADDR_WIDTH - 1:0] valid_addr;
  reg [SET_WIDTH - 1:0] set_idx;
  reg [TAG_WIDTH - 1:0] tag;
  reg [BLOCK_WIDTH - 1:0] block_idx;
  always_comb begin
    valid_addr = cu_addr[22:2];
    set_idx = valid_addr[BLOCK_WIDTH+:SET_WIDTH];
    tag = valid_addr[BLOCK_WIDTH+SET_WIDTH+:TAG_WIDTH];
    block_idx = valid_addr[0+:BLOCK_WIDTH];
  end
  reg cache_hit;
  reg [N_WAY_BW - 1:0] way_idx;

  // logic for controlling BRAM contents.
  reg [BLOCK_WIDTH - 1:0] block_idx_c;

  reg [SET_WIDTH - 1:0] work_set_c;
  reg [N_WAY_BW - 1 : 0] work_way_c;
  reg [SET_WIDTH + N_WAY_BW + BLOCK_WIDTH - 1 : 0] read_addr;
  reg [SET_WIDTH + N_WAY_BW + BLOCK_WIDTH - 1 : 0] write_addr;
  reg [3:0] cache_we;
  reg [31:0] write_data;
  wire [31:0] read_data;
  reg [TAG_WIDTH - 1:0] hit_tag;

  typedef enum reg [4:0] {
    WAIT,
    FETCHING_BLOCKS,
    RELEASE_BLOCKS,
    FLUSH_BLOCKS
  } cache_state_t;

  reg has_dirty_block;
  reg [SET_WIDTH - 1:0] dirty_set_idx;
  reg [N_WAY_BW  - 1:0] dirty_way_idx;
  always_comb begin
    has_dirty_block = 1'b0;
    dirty_set_idx   = {SET_WIDTH{1'b0}};
    dirty_way_idx   = {N_WAY_BW{1'b0}};
    for (int i_set = 0; i_set < SET_COUNT; ++i_set) begin
      for (int i_way = 0; i_way < N_WAYS; ++i_way) begin
        if (cache_regs[i_set].way_arr[i_way].dirty) begin
          has_dirty_block = 1;
          dirty_set_idx   = i_set;
          dirty_way_idx   = i_way;
          break;
        end
      end
      if (has_dirty_block) break;
    end
  end
  cache_state_t state;
  reg [N_WAY_BW - 1:0] fetch_way_idx_comb;
  reg [BLOCK_WIDTH - 1:0] fetch_block_idx;
  reg [N_WAY_BW - 1 : 0] fetch_way_idx_reg;


  reg [SET_WIDTH - 1:0] flush_set_reg;
  reg [N_WAY_BW  - 1:0] flush_way_reg;
  reg [TAG_WIDTH - 1:0] flush_way_tag;

  reg [31:0] miss_addr_reg;
  always_ff @(posedge reset or posedge clock) begin
    if (reset) begin
      int i_set;
      int i_way;
      int i_block;
      for (i_set = 0; i_set < SET_COUNT; ++i_set) begin
        for (i_way = 0; i_way < N_WAYS; ++i_way) begin
          cache_regs[i_set].way_arr[i_way].valid <= 1'b0;
          cache_regs[i_set].way_arr[i_way].dirty <= 1'b0;
          cache_regs[i_set].way_arr[i_way].tag <= {TAG_WIDTH{1'b0}};
          cache_regs[i_set].way_arr[i_way].lru_priority <= {N_WAY_BW{1'b0}};
        end
      end
      state <= WAIT;
      fetch_block_idx <= {BLOCK_WIDTH{1'b0}};
      flush_set_reg <= {SET_WIDTH{1'b0}};
      flush_way_reg <= {N_WAY_BW{1'b0}};
      flush_way_tag <= {TAG_WIDTH{1'b0}};
      miss_addr_reg <= 32'b0;
      fetch_way_idx_reg <= {N_WAY_BW{1'b0}};
    end else begin
      case (state)
        WAIT: begin
          if (flush) begin
            if (has_dirty_block) begin
              state <= FLUSH_BLOCKS;
              flush_set_reg <= dirty_set_idx;
              flush_way_reg <= dirty_way_idx;
              cache_regs[dirty_set_idx].way_arr[dirty_way_idx].dirty <= 1'b0;
              fetch_block_idx <= {BLOCK_WIDTH{1'b0}};
              flush_way_tag <= cache_regs[dirty_set_idx].way_arr[dirty_way_idx].tag;
            end
          end else if ((cu_we || cu_re) && !cache_hit) begin
            if (!bypass_internal) begin
              miss_addr_reg <= cu_addr;
              cache_regs[set_idx].way_arr[fetch_way_idx_comb].valid <= 1'b0;
              fetch_way_idx_reg <= fetch_way_idx_comb;
              fetch_block_idx <= {BLOCK_WIDTH{1'b0}};
              if (cache_regs[set_idx].way_arr[fetch_way_idx_comb].dirty) begin
                state <= RELEASE_BLOCKS;
              end else begin
                state <= FETCHING_BLOCKS;
              end
            end
          end
          if ((cu_we || cu_re) && cache_hit) begin
            if (!bypass_internal) begin
              for (int i_way = 0; i_way < N_WAYS; ++i_way) begin
                if (way_idx == i_way) continue;

                if(cache_regs[set_idx].way_arr[i_way].lru_priority > 
                                cache_regs[set_idx].way_arr[way_idx].lru_priority) begin
                  cache_regs[set_idx].way_arr[i_way].lru_priority <=
                                cache_regs[set_idx].way_arr[i_way].lru_priority - 1;
                end
              end
              cache_regs[set_idx].way_arr[way_idx].lru_priority <= {N_WAY_BW{1'b1}};
            end
          end
          // write back cache.
          if (cu_we && cache_hit && !bypass_internal) begin
            if (cu_be != 4'b0) begin
              cache_regs[set_idx].way_arr[way_idx].dirty <= 1'b1;
            end
          end
          if (invalidate) begin
            for (int i_set = 0; i_set < SET_COUNT; ++i_set) begin
              for (int i_way = 0; i_way < N_WAYS; ++i_way) begin
                cache_regs[i_set].way_arr[i_way].valid <= 1'b0;
              end
            end
          end
        end
        RELEASE_BLOCKS: begin
          if ((cu_we || cu_re)) begin
            if (dau_ack) begin
              if (fetch_block_idx == BLOCK_COUNT - 1) begin
                state <= FETCHING_BLOCKS;
                fetch_block_idx <= 0;
                cache_regs[set_idx].way_arr[fetch_way_idx_reg].dirty <= 1'b0;
              end else begin
                fetch_block_idx <= fetch_block_idx + 1;
              end
            end
          end else begin
            // in case a mispredicted branch loading, evacuate immediately.
            state <= WAIT;
            fetch_block_idx <= 0;
          end
        end
        FETCHING_BLOCKS: begin
          if (cu_addr == miss_addr_reg) begin
            if ((cu_we || cu_re)) begin
              if (dau_ack) begin
                if (fetch_block_idx == BLOCK_COUNT - 1) begin
                  state <= WAIT;
                  fetch_block_idx <= 0;
                  cache_regs[set_idx].way_arr[fetch_way_idx_reg].valid <= 1'b1;
                  cache_regs[set_idx].way_arr[fetch_way_idx_reg].tag <= tag;
                end else begin
                  fetch_block_idx <= fetch_block_idx + 1;
                end
              end
            end else begin
              // in case a mispredicted branch loading, evacuate immediately.
              state <= WAIT;
              fetch_block_idx <= 0;
            end
          end else begin
            fetch_block_idx <= 0;
            state <= WAIT;
          end
        end
        FLUSH_BLOCKS: begin
          if (dau_ack) begin
            if (fetch_block_idx == BLOCK_COUNT - 1) begin
              fetch_block_idx <= 0;
              if (has_dirty_block) begin
                flush_set_reg <= dirty_set_idx;
                flush_way_reg <= dirty_way_idx;
                cache_regs[dirty_set_idx].way_arr[dirty_way_idx].dirty <= 1'b0;
                flush_way_tag <= cache_regs[dirty_set_idx].way_arr[dirty_way_idx].tag;
              end else begin
                state <= WAIT;
              end
            end else begin
              fetch_block_idx <= fetch_block_idx + 1;
            end
          end
        end
        default: begin
          state <= WAIT;
        end
      endcase
    end
  end
  reg        dau_re_comb;
  reg        dau_we_comb;
  reg [31:0] dau_addr_comb;
  reg [31:0] dau_data_departure_comb;

  reg        clear_complete_comb;

  always_comb begin
    dau_re_comb = 1'b0;
    dau_we_comb = 1'b0;
    dau_addr_comb = 32'b0;
    dau_data_departure_comb = 32'b0;
    fetch_way_idx_comb = N_WAYS - 1;
    clear_complete_comb = 1'b0;
    begin
      int i_way;
      for (i_way = 0; i_way < N_WAYS; ++i_way) begin
        if (cache_regs[set_idx].way_arr[i_way].lru_priority == {N_WAY_BW{1'b0}}) begin
          fetch_way_idx_comb = i_way;
          break;
        end
      end
    end
    case (state)
      WAIT: begin
        dau_re_comb   = 1'b0;
        dau_addr_comb = 32'b0;
      end
      RELEASE_BLOCKS: begin
        dau_we_comb = 1'b1;
        dau_addr_comb = {
          cu_addr[31:23],
          cache_regs[set_idx].way_arr[fetch_way_idx_reg].tag,
          cu_addr[7:5],
          fetch_block_idx,
          2'b0
        };
        dau_data_departure_comb = read_data;
      end
      FETCHING_BLOCKS: begin
        dau_re_comb   = 1'b1;
        dau_addr_comb = {cu_addr[31:2+BLOCK_WIDTH], fetch_block_idx, 2'b0};
      end
      FLUSH_BLOCKS: begin
        dau_we_comb = 1'b1;
        dau_addr_comb = {9'b1000_0000_0, flush_way_tag, flush_set_reg, fetch_block_idx, 2'b0};
        dau_data_departure_comb = read_data;
        if (dau_ack && fetch_block_idx == BLOCK_COUNT - 1 && !has_dirty_block) begin
          clear_complete_comb = 1;
        end
      end
    endcase
  end

  always_comb begin
    block_idx_c = {BLOCK_WIDTH{1'b0}};
    work_set_c = {SET_WIDTH{1'b0}};
    work_way_c = {N_WAY_BW{1'b0}};
    read_addr = {(SET_WIDTH + N_WAY_BW + BLOCK_WIDTH) {1'b0}};
    write_addr = {(SET_WIDTH + N_WAY_BW + BLOCK_WIDTH) {1'b0}};
    cache_we = 4'b0;
    write_data = 32'b0;
    // ----------------------------------------------------------------------
    cache_hit = 0;
    way_idx = 0;
    hit_tag = {TAG_WIDTH{1'b0}};
    for (int i_way = 0; i_way < N_WAYS; ++i_way) begin
      if(cache_regs[set_idx].way_arr[i_way].valid && 
               cache_regs[set_idx].way_arr[i_way].tag == tag) begin
        cache_hit = 1'b1;
        way_idx   = i_way;
        break;
      end
    end
    // ----------------------------------------------------------------------

    // ----------------------------------------------------------------------
    case (state)
      WAIT: begin
        if (flush) begin
          if (has_dirty_block) begin
            // spill all cache blocks, transit to FLUSH_BLOCKS.
            work_set_c = dirty_set_idx;
            work_way_c = dirty_way_idx;
            read_addr  = {work_set_c, work_way_c, block_idx_c};
          end
        end else if ((cu_we || cu_re) && !cache_hit) begin
          // block of least recently used is now being replaced.
          if (!bypass_internal) begin
            work_set_c = set_idx;
            work_way_c = fetch_way_idx_comb;
            // in case RELEASE_BLOCKS.
            read_addr  = {work_set_c, work_way_c, block_idx_c};
          end
        end
        if (cu_we && cache_hit && !bypass_internal) begin
          // write request when cache hits.
          cache_we   = cu_be;
          write_addr = {set_idx, way_idx, block_idx};
          write_data = cu_data_i;
        end
        if (cu_re && cache_hit && !bypass_internal) begin
          hit_tag   = cache_regs[set_idx].way_arr[way_idx].tag;
          read_addr = {cu_addr[2+BLOCK_WIDTH+:SET_WIDTH], way_idx, cu_addr[2+:BLOCK_WIDTH]};
          //   read_addr = {set_idx, way_idx, block_idx};

        end
      end
      RELEASE_BLOCKS: begin
        work_set_c  = set_idx;
        work_way_c  = fetch_way_idx_reg;
        block_idx_c = fetch_block_idx;
        if (dau_ack) begin
          // read the contents in the next block offset.
          block_idx_c = fetch_block_idx + 1;
        end
        read_addr = {work_set_c, work_way_c, block_idx_c};
      end
      FLUSH_BLOCKS: begin
        work_set_c  = flush_set_reg;
        work_way_c  = flush_way_reg;
        block_idx_c = fetch_block_idx;
        if (dau_ack) begin
          block_idx_c = fetch_block_idx + 1;
          if (fetch_block_idx == BLOCK_COUNT - 1) begin
            if (has_dirty_block) begin
              work_set_c = dirty_set_idx;
              work_way_c = dirty_way_idx;
            end
          end
        end
        read_addr = {work_set_c, work_way_c, block_idx_c};
      end
      FETCHING_BLOCKS: begin
        work_set_c  = set_idx;
        work_way_c  = fetch_way_idx_reg;
        block_idx_c = fetch_block_idx;
        write_addr  = {work_set_c, work_way_c, block_idx_c};
        if (dau_ack) begin
          cache_we   = 4'b1111;
          write_data = dau_data_i;
        end
      end
    endcase
  end
  reg write_err;
  always @(posedge clock)
    if (reset) write_err <= 0;
    else write_err <= dau_we_comb && (dau_data_departure_comb != read_data);
  cache_ram memory (
      .clka (clock),
      .clkb (clock),
      .wea  (cache_we),
      .addra(write_addr),
      .dina (write_data),

      .addrb(read_addr),
      .doutb(read_data)
  );
  reg [31:0] bus_data_delayed;
  reg bypass_relay;
  always @(posedge clock)
    if (reset) begin
      bus_data_delayed <= 32'b0;
      bypass_relay <= 0;
    end else begin
      bus_data_delayed <= dau_data_i;
      bypass_relay <= bypass_internal;
    end

  assign cu_data_o_delayed = bypass_relay ? bus_data_delayed : read_data;
  assign cu_ack = bypass_internal ? dau_ack : cache_hit;
  assign cu_data_o = 32'b0;
  assign dau_we = (bypass_internal && state != FLUSH_BLOCKS) ? cu_we : dau_we_comb;
  assign dau_re = (bypass_internal && state != FLUSH_BLOCKS) ? cu_re : dau_re_comb;
  assign dau_addr = (bypass_internal && state != FLUSH_BLOCKS) ? cu_addr : dau_addr_comb;
  assign dau_be = (bypass_internal && state != FLUSH_BLOCKS) ? cu_be : 4'b1111;
  assign dau_data_o = (bypass_internal && state != FLUSH_BLOCKS) ? cu_data_i : dau_data_departure_comb;

  assign clear_complete = bypass ? flush : clear_complete_comb;
endmodule
