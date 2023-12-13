`include "defines.vh"

module bitmap_manager
#(
    parameter MAX_HOST_NUMBER           = `MAX_HOST_NUMBER,
    parameter MAX_PLANE_NUMBER          = `MAX_PLANE_NUMBER,
    parameter HOST_ID_BIT_WIDTH         = $clog2(MAX_HOST_NUMBER),
    parameter PLANE_ID_BIT_WIDTH        = $clog2(MAX_PLANE_NUMBER),
    parameter NO_OF_TAG                 = `NO_OF_TAG,
    parameter TAG_BIT_WIDTH             = $clog2(NO_OF_TAG),
    parameter SRAM_MAX_ADDR             = MAX_PLANE_NUMBER,
    parameter SRAM_ADDR_WIDTH           = $clog2(SRAM_MAX_ADDR),
    parameter SRAM_DATA_BIT_WIDTH       = MAX_HOST_NUMBER
)
(
    input  i_clk,
    input  i_rst_n,
    input  [HOST_ID_BIT_WIDTH-1:0]  i_host_id,
    input  [PLANE_ID_BIT_WIDTH-1:0] i_plane_id,
    input  i_insert_req,
    output o_valid,
    output [HOST_ID_BIT_WIDTH-1 : 0]  o_host_id,
    output [PLANE_ID_BIT_WIDTH-1 : 0] o_plane_id
);


// FSM States
parameter IDLE                  = 0;
parameter INCR_COUNTER_READ     = 1;
parameter INCR_COUNTER_WRITE    = 2;
parameter INSERT_REQ            = 3;
parameter ROUND_ROBIN_PLANE     = 4;
parameter ROUND_ROBIN_HOST      = 5;
parameter POST_ID               = 6;
parameter DECR_COUNTER          = 7;
parameter NO_OF_STATES          = 8;

reg [NO_OF_STATES-1:0] curr_state;
reg [NO_OF_STATES-1:0] next_state;

// Host ID & Plane ID Register
reg [HOST_ID_BIT_WIDTH-1:0]  r_host_id;
reg [PLANE_ID_BIT_WIDTH-1:0] r_plane_id;
reg [HOST_ID_BIT_WIDTH-1:0]  r_out_host_id;
reg [PLANE_ID_BIT_WIDTH-1:0] r_out_plane_id;
reg [PLANE_ID_BIT_WIDTH:0] r_rr_plane_count;
reg [3:0] r_idle_count;
reg r_pop_req;

// Valid
reg r_out_valid;

assign o_host_id = r_out_host_id;
assign o_plane_id = r_out_plane_id;
assign o_valid = r_out_valid;

// Bitmap
reg r_plane_valid;
reg  [MAX_HOST_NUMBER-1:0] r_pe_bitmap;
reg  [HOST_ID_BIT_WIDTH-1:0] r_pe_host_id;
wire [HOST_ID_BIT_WIDTH-1:0] w_pe_next_host_id;

// Round Robin
reg [PLANE_ID_BIT_WIDTH-1:0] r_rr_plane_id;
reg [HOST_ID_BIT_WIDTH-1:0] r_rr_last_host_id_arr[MAX_PLANE_NUMBER-1:0];
integer planeid;
always @ (*)
begin
    if (~i_rst_n)
    begin
        for (planeid=0; planeid < MAX_PLANE_NUMBER; planeid=planeid+1)
        begin
            r_rr_last_host_id_arr[planeid] = 0;
        end
    end
end


// Counter
//reg [TAG_BIT_WIDTH-1:0] counter[MAX_HOST_NUMBER-1][MAX_PLANE_NUMBER-1];
// Counter Interface
// Counter 필요한거 Host * Plane * Counter? 너무 큰데? Available Bitmap 만들기
// 에 512 * 512 * 65536 16Gbit.. 지랄인데.. 어떻게 비트맵을 구성할 수 있을까?
// 꼭 비트맵이필요한가? Host 정보를 이친구가 다 알필요가 있나? 이미 앞단에서
// 알고 있다면? 몇개가 밀린건지

// SRAM Interface
reg     r_write_req;
reg     r_read_req;
reg     [SRAM_ADDR_WIDTH-1:0] r_write_addr;
reg     [SRAM_ADDR_WIDTH-1:0] r_read_addr;
reg     [SRAM_DATA_BIT_WIDTH-1:0] r_write_data;
reg     [SRAM_DATA_BIT_WIDTH-1:0] r_read_data;
wire    [SRAM_DATA_BIT_WIDTH-1:0] w_read_data;


reg     r_write_req_count;
reg     r_read_req_count;
reg     [$clog2(MAX_HOST_NUMBER*MAX_PLANE_NUMBER)-1:0] r_write_addr_count;
reg     [$clog2(MAX_HOST_NUMBER*MAX_PLANE_NUMBER)-1:0] r_read_addr_count;
reg     [TAG_BIT_WIDTH-1:0] r_write_data_count;
reg     [TAG_BIT_WIDTH-1:0] r_read_data_count;
wire    [TAG_BIT_WIDTH-1:0] w_read_data_count;

// FSM Control (Sequential Logic)
always @ (posedge i_clk or negedge i_rst_n)
begin
    if (~i_rst_n)
    begin
        curr_state <= {{(NO_OF_STATES-1){1'b0}},1'b1};
    end
    else
    begin
        curr_state <= next_state;
    end
end

always @ (*)
begin
    if (~i_rst_n)
    begin
        r_idle_count = 0;
        r_pop_req = 0;
    end
    case (1'b1)
        curr_state[IDLE]:
        begin
            if (next_state[IDLE] == 1'b1)
            begin
                r_idle_count = r_idle_count + 1;
            end
            else
            begin
                r_idle_count = 0;
            end
            if (r_idle_count > 10)
            begin
                r_pop_req = 1;
            end
        end
        curr_state[ROUND_ROBIN_PLANE]:
        begin
            r_pop_req = 0;
        end
    endcase
end

// Current State Behavior (Combination)
always @ (*)
begin
    case(1'b1)
        curr_state[IDLE]:
        begin
            r_read_req = 1'b0;
            r_write_req = 1'b0;
            r_read_req_count = 1'b0;
            r_write_req_count = 1'b0;
            r_out_valid = 1'b0;
        end
        curr_state[INCR_COUNTER_READ]:
        begin
            r_host_id = i_host_id;
            r_plane_id = i_plane_id;
            r_read_addr_count = i_plane_id * MAX_HOST_NUMBER + i_host_id;
            r_read_req_count = 1'b1;
        end
        curr_state[INCR_COUNTER_WRITE]:
        begin
            r_read_data_count = w_read_data_count;
            r_write_data_count = w_read_data_count + 1;
            r_read_req_count = 1'b0;
            r_write_addr_count = r_plane_id * MAX_HOST_NUMBER + i_host_id;
            r_write_req_count = 1'b1;
            r_read_addr = r_plane_id;
            r_read_req = 1'b1;
        end
        curr_state[INSERT_REQ]:
        begin
            r_write_req_count = 1'b0;
            r_read_data = w_read_data;
            r_read_data[r_host_id] = 1'b1;
            r_read_req = 1'b0;
            if (r_read_data_count == 'd0)
            begin
                r_write_data = r_read_data;
                r_write_addr = r_plane_id;
                r_write_req = 1'b1;
            end
        end
        curr_state[ROUND_ROBIN_PLANE]:
        begin
            r_rr_plane_count = 0;
            r_read_addr = r_rr_plane_id;
            r_out_plane_id = r_rr_plane_id;
            r_host_id = r_rr_last_host_id_arr[r_rr_plane_id];
            r_read_req = 1'b1;
            r_rr_plane_id = r_rr_plane_id + 1;
        end
        curr_state[ROUND_ROBIN_HOST]:
        begin
            r_read_data = w_read_data;
            r_read_req = 1'b0;
            if (|w_read_data)
            begin
                r_pe_bitmap = r_read_data;
                r_pe_host_id = r_host_id;
            end
            else
            begin
                r_rr_plane_count = r_rr_plane_count + 1;
                r_read_addr = r_rr_plane_id;
                r_out_plane_id = r_rr_plane_id;
                r_host_id = r_rr_last_host_id_arr[r_rr_plane_id];
                r_read_req = 1'b1;
                r_rr_plane_id = r_rr_plane_id + 1;
            end
        end
        curr_state[POST_ID]:
        begin
            r_out_host_id = w_pe_next_host_id;
            r_out_valid = 1'b1;
            r_read_data[w_pe_next_host_id] = 1'b0;
            r_read_addr_count = r_out_host_id * MAX_HOST_NUMBER + r_out_plane_id;
            r_read_req_count = 1'b1;
        end
        curr_state[DECR_COUNTER]:
        begin
            r_out_valid = 1'b0;
            r_write_data_count = w_read_data_count - 1;
            r_read_req_count = 1'b0;
            r_write_addr = r_out_plane_id;
            r_write_data = r_read_data;
            r_write_req = 1'b1;
            r_write_addr_count = r_plane_id * MAX_HOST_NUMBER + i_host_id;
            r_write_req_count = 1'b1;
        end
        default :
        begin
        end
    endcase
end

// Next State Transition
always @(*)
begin
    next_state = 'h0;
    case (1'b1)
        curr_state[IDLE]:
        begin
            if (i_insert_req)
            begin
                next_state[INCR_COUNTER_READ] = 1'b1;
            end
            else if (r_pop_req)
            begin
                next_state[ROUND_ROBIN_PLANE] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
        end
        curr_state[INCR_COUNTER_READ]:
        begin
            next_state[INSERT_REQ] = 1'b1;
        end
        curr_state[INCR_COUNTER_WRITE]:
        begin
            next_state[INSERT_REQ] = 1'b1;
        end
        curr_state[INSERT_REQ]:
        begin
            next_state[IDLE] = 1'b1;
        end
        curr_state[ROUND_ROBIN_PLANE]:
        begin
            next_state[ROUND_ROBIN_HOST] = 1'b1;
        end
        curr_state[ROUND_ROBIN_HOST]:
        begin
            if (|w_read_data)
            begin
                next_state[POST_ID] = 1'b1;
            end
            else if (i_insert_req)
            begin
                next_state[INCR_COUNTER_READ] = 1'b1;
            end
            else if (r_rr_plane_count > MAX_PLANE_NUMBER)
            begin
                next_state[IDLE] = 1'b1;
            end
            else
            begin
                next_state[ROUND_ROBIN_HOST] = 1'b1;
            end
        end
        curr_state[POST_ID]:
        begin
            next_state[DECR_COUNTER] = 1'b1;
        end
        curr_state[DECR_COUNTER]:
        begin
            next_state[IDLE] = 1'b1;
        end
        default:
        begin
            next_state = IDLE;
        end
    endcase
end

//reg [TAG_BIT_WIDTH-1:0] counter[MAX_HOST_NUMBER-1][MAX_PLANE_NUMBER-1];
sram_interconnect_10x1024 counter(
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_wr_en(r_write_req_count),
    .i_rd_en(r_read_req_count),
    .i_wr_addr(r_write_addr_count),
    .i_rd_addr(r_read_addr_count),
    .i_wr_data(r_write_data_count),
    .o_rd_data(w_read_data_count)
);

sram_interconnect_32x32 bitmap(
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_wr_en(r_write_req),
    .i_rd_en(r_read_req),
    .i_wr_addr(r_write_addr),
    .i_rd_addr(r_read_addr),
    .i_wr_data(r_write_data),
    .o_rd_data(w_read_data)
);

bitmap_parser
#(
    .SIZE_OF_BITMAP(MAX_HOST_NUMBER),
    .INDEX_WIDTH(HOST_ID_BIT_WIDTH)
)
bitmap_parser(
    .i_bitmap(r_pe_bitmap),
    .i_index(r_pe_host_id),
    .o_index(w_pe_next_host_id)
);

endmodule

module priority_encoder_parallel
#(
    parameter SIZE_OF_BITMAP = 1024,
    parameter INDEX_WIDTH    = $clog2(SIZE_OF_BITMAP)
)
(
    input  [SIZE_OF_BITMAP-1:0] i_bitmap,
    output [INDEX_WIDTH-1:0] o_index
);

genvar i, j;
generate
    for(i=0; i < INDEX_WIDTH; i=i+1)
    begin : generation
        wire            w_valid     [2**(INDEX_WIDTH-i-1)-1:0];
        wire [i+1-1:0]  w_winner    [2**(INDEX_WIDTH-i-1)-1:0];
        if (i==0)
        begin
            for(j=0;j<2**(INDEX_WIDTH-i-1);j=j+1)
            begin
                assign generation[0].w_valid[j] = |i_bitmap[2*j+:2];
                assign generation[0].w_winner[j] = i_bitmap[2*j]? 1'b0 : 1'b1;
            end
        end
        else
        begin
            for(j=0;j<2**(INDEX_WIDTH-i-1);j=j+1)
            begin
                assign generation[i].w_valid[j]  = generation[i-1].w_valid[2*j] | generation[i-1].w_valid[2*j+1];
                assign generation[i].w_winner[j] = generation[i-1].w_valid[2*j]? {1'b0, generation[i-1].w_winner[2*j]} :
                                                                     {1'b1, generation[i-1].w_winner[2*j+1]};
            end
        end
    end
endgenerate

assign o_index = generation[INDEX_WIDTH-1].w_winner[0];
endmodule

module bitmap_parser
#(
    parameter SIZE_OF_BITMAP = 128,
    parameter INDEX_WIDTH    = $clog2(SIZE_OF_BITMAP)
)
(
    input  [SIZE_OF_BITMAP-1:0] i_bitmap,
    input  [INDEX_WIDTH-1:0] i_index,
    output [INDEX_WIDTH-1:0] o_index
);
wire [SIZE_OF_BITMAP-1:0] bitmap_pre;
wire [SIZE_OF_BITMAP-1:0] bitmap_post;

genvar i;
generate
    for (i=0; i<SIZE_OF_BITMAP;i=i+1)
    begin
        assign bitmap_pre[i]  = (i < i_index)? 1'b1 : 1'b0;
        assign bitmap_post[i] = (i > i_index)? 1'b1 : 1'b0;
    end
endgenerate

reg [SIZE_OF_BITMAP-1:0] reg_bitmap;
wire [INDEX_WIDTH-1:0] w_index;
reg reg_host_flag;

always @(*)
begin
    if (|bitmap_pre)
    begin
        reg_bitmap = bitmap_pre;
        reg_host_flag = 1'b0;
    end
    else if(|bitmap_post)
    begin
        reg_bitmap = bitmap_post;
        reg_host_flag = 1'b0;
    end
    else
    begin
        reg_host_flag = 1'b1;
    end
end

priority_encoder_parallel
#(
    .SIZE_OF_BITMAP(SIZE_OF_BITMAP),
    .INDEX_WIDTH(INDEX_WIDTH)
)
pe(
    .i_bitmap(reg_bitmap),
    .o_index(w_index)
);

assign o_index = reg_host_flag? i_index : w_index;

endmodule


