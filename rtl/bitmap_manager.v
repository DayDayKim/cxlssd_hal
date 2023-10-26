`include "defines.v"

module bitmap_manager
#(
    parameter MAX_HOST_NUMBER    = `MAX_HOST_NUMBER,
    parameter MAX_PLANE_NUMBER   = `MAX_PLANE_NUMBER,
    parameter HOST_ID_BIT_WIDTH  = $clog2(MAX_HOST_NUMBER),
    parameter PLANE_ID_BIT_WIDTH = $clog2(MAX_PLANE_NUMBER),
    parameter SOURCE_FTL         = 0,
    parameter SOURCE_FMC         = 1,
    parameter NO_OF_SOURCES      = 2,
    parameter SOURCE_BIT_WIDTH   = $clog2(NO_OF_SOURCES)
)
(
    input  i_clk,
    input  i_rst_n,
    input  [HOST_ID_BIT_WIDTH-1:0]  i_host_id,
    input  [PLANE_ID_BIT_WIDTH-1:0] i_plane_id,
    input  [SOURCE_BIT_WIDTH-1:0]i_source,
    input  i_valid,
    input  i_ready,
    input  i_req,
    output o_ready,
    output o_valid,
    output [HOST_ID_BIT_WIDTH-1 : 0]  o_host_id,
    output [PLANE_ID_BIT_WIDTH-1 : 0] o_plane_id
);
// FSM States
parameter IDLE                  = 0;
parameter CHECK_VALID           = 1;
parameter SET_READY             = 2;
parameter READ_BITMAP           = 3;
parameter CHECK_SOURCE          = 4;
parameter CHECK_REQ             = 5;
parameter CLEAR_BITMAP          = 6;
parameter UPDATE_BITMAP         = 7;
parameter FIND_BITMAP           = 8;
parameter FIND_HOSTID           = 9;
parameter SET_VALID             = 10;
parameter NO_OF_STATES          = 11;

reg [NO_OF_STATES-1:0] curr_state;
reg [NO_OF_STATES-1:0] next_state;

// Transcation
wire i_xfer;
wire o_xfer;
assign i_xfer = i_valid & o_ready;
assign o_xfer = o_valid & i_ready;

reg o_valid_reg;
reg o_ready_reg;
reg o_valid_reg_next;
reg o_ready_reg_next;

assign o_valid = o_valid_reg;
assign o_ready = o_ready_reg;

// Host ID & Plane ID Register
reg [HOST_ID_BIT_WIDTH-1:0]  reg_host_id;
reg [PLANE_ID_BIT_WIDTH-1:0] reg_plane_id;
reg [HOST_ID_BIT_WIDTH-1:0]  reg_out_host_id;
reg [PLANE_ID_BIT_WIDTH-1:0] reg_out_plane_id;
reg [HOST_ID_BIT_WIDTH-1:0] reg_rr_plane_id;

assign o_host_id = reg_out_host_id;
assign o_plane_id = reg_out_plane_id;

// SRAM Interface
reg [PLANE_ID_BIT_WIDTH-1:0] reg_mem_addr;
wire [PLANE_ID_BIT_WIDTH-1:0] mem_addr;
reg reg_write_req;
reg reg_read_req;
wire write_req;
wire read_req;
assign mem_addr = reg_mem_addr;
assign write_req = reg_write_req;
assign read_req = reg_read_req;
reg [MAX_HOST_NUMBER-1:0] reg_sram_rdata;
reg [MAX_HOST_NUMBER-1:0] reg_sram_wdata;
wire [MAX_HOST_NUMBER-1:0] sram_rdata;
wire [MAX_HOST_NUMBER-1:0] sram_wdata;
assign sram_rdata = reg_sram_rdata;
assign sram_wdata = reg_sram_wdata;
wire r_trans_done;
wire w_trans_done;
wire or_rdata;

// Bitmap
reg [MAX_HOST_NUMBER-1:0] reg_bitmap;

// Bitmap Parser
reg  [MAX_HOST_NUMBER-1:0] reg_pe_bitmap;
reg  [HOST_ID_BIT_WIDTH-1:0] reg_pe_host_id;
wire [HOST_ID_BIT_WIDTH-1:0] pe_next_host_id;

// Round Robin
reg reg_rr_re_lock;
reg [HOST_ID_BIT_WIDTH-1:0] reg_rr_last_host_id_arr[MAX_PLANE_NUMBER-1:0];
reg [HOST_ID_BIT_WIDTH-1:0] reg_rr_last_host_id;
reg reg_plane_valid;
integer planeid;
always @ (*)
begin
    if (~i_rst_n)
    begin
        for (planeid=0; planeid < MAX_PLANE_NUMBER; planeid=planeid+1)
        begin
            reg_rr_last_host_id_arr[planeid] = 0;
        end
    end
end

// Ready & Valid Clock Sync
always @ (posedge i_clk or negedge i_rst_n)
begin
    if (~i_rst_n)
    begin
        o_valid_reg <= 1'b0;
        o_ready_reg <= 1'b0;
    end
    else
    begin
        o_valid_reg <= o_valid_reg_next;
        o_ready_reg <= o_ready_reg_next;
    end
end

// Data Clock Sync
//always @ (posedge i_clk or negedge i_rst_n)
//begin
//    if (~i_rst_n)
//    begin
//        reg_host_id  <= 'b0;
//        reg_plane_id <= 'b0;
//    end
//    else
//    begin
//        reg_host_id  <= reg_host_id_next;
//        reg_plane_id <= reg_plane_id_next;
//    end
//end


// Counter Interface
// Counter 필요한거 Host * Plane * Counter? 너무 큰데? Available Bitmap 만들기
// 에 512 * 512 * 65536 16Gbit.. 지랄인데.. 어떻게 비트맵을 구성할 수 있을까?
// 꼭 비트맵이필요한가? Host 정보를 이친구가 다 알필요가 있나? 이미 앞단에서
// 알고 있다면? 몇개가 밀린건지

// SRAM Interface
// Width 를 512bit(64Byte) Host ID 개수, Row를 512개

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

// Current State Behavior (Combination)
always @ (*)
begin
    case(1'b1)
        curr_state[IDLE] :
        begin
            reg_rr_re_lock = 1'b0;
            reg_read_req = 1'b0;
            reg_write_req = 1'b0;
            o_ready_reg_next = 1'b0;
            o_valid_reg_next = 1'b0;
        end
        curr_state[CHECK_VALID]:
        begin
            reg_rr_re_lock = 1'b0;
            o_ready_reg_next = 1'b1;
        end
        curr_state[SET_READY]:
        begin
            o_ready_reg_next = 1'b0;
            reg_host_id = i_host_id;
            reg_plane_id = i_plane_id;
        end
        curr_state[READ_BITMAP]:
        begin
            // SRAM Address Set & Read request
            reg_mem_addr = reg_plane_id;
            reg_read_req = 1'b1;
        end
        curr_state[CHECK_SOURCE]:
        begin
            reg_bitmap = sram_rdata;
            reg_plane_valid = or_rdata;
        end
        curr_state[UPDATE_BITMAP]:
        begin
            reg_bitmap[reg_host_id] = 1'b1;
            reg_sram_wdata = reg_bitmap;
            reg_mem_addr = reg_plane_id;
            reg_read_req = 1'b0;
            reg_write_req = 1'b1;
        end
        curr_state[CLEAR_BITMAP]:
        begin
            reg_bitmap[reg_host_id] = 1'b0;
            reg_sram_wdata = reg_bitmap;
            reg_mem_addr = reg_plane_id;
            reg_read_req = 1'b0;
            reg_write_req = 1'b1;
        end
        curr_state[CHECK_REQ]:
        begin
            reg_rr_re_lock = 1'b1;
            reg_plane_id = reg_rr_plane_id;
        end
        curr_state[FIND_BITMAP]:
        begin
            reg_read_req = 1'b0;
            reg_host_id = reg_rr_last_host_id_arr[reg_rr_plane_id];
            reg_out_plane_id = reg_rr_plane_id;
            reg_bitmap[reg_host_id] = 1'b0;
            reg_rr_plane_id = reg_rr_plane_id+1;
            reg_plane_id = reg_rr_plane_id;
        end
        curr_state[FIND_HOSTID]:
        begin
            reg_pe_bitmap = reg_bitmap;
            reg_pe_host_id = reg_host_id;
        end
        curr_state[SET_VALID]:
        begin
            reg_out_host_id = pe_next_host_id;
            o_valid_reg_next = 1'b1;
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
            if (i_valid)
            begin
                next_state[CHECK_VALID] = 1'b1;
            end
            else if (i_req)
            begin
                next_state[CHECK_REQ] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
        end
        curr_state[CHECK_VALID]:
        begin
            if (~i_xfer)
            begin
                next_state[CHECK_VALID] = 1'b1;
            end
            else
            begin
                next_state[SET_READY] = 1'b1;
            end
        end
        curr_state[SET_READY]:
        begin
            if (~i_xfer)
            begin
                next_state[READ_BITMAP] = 1'b1;
            end
            else
            begin
                next_state[SET_READY] = 1'b1;
            end
        end
        curr_state[READ_BITMAP]:
        begin
            next_state[CHECK_SOURCE] = 1'b1;
        end
        curr_state[CHECK_SOURCE]:
        begin
            if (~r_trans_done)
            begin
                next_state[CHECK_SOURCE] = 1'b1;
            end
            else if (reg_rr_re_lock)
            begin
                next_state[FIND_BITMAP] = 1'b1;
            end
            else if (i_source == SOURCE_FMC)
            begin
                next_state[CLEAR_BITMAP] = 1'b1;
            end
            else
            begin
                next_state[UPDATE_BITMAP] = 1'b1;
            end
        end
        curr_state[UPDATE_BITMAP]:
        begin
            if (~w_trans_done)
            begin
                next_state[UPDATE_BITMAP] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
        end
        curr_state[CLEAR_BITMAP]:
        begin
            if (~w_trans_done)
            begin
                next_state[CLEAR_BITMAP] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
        end
        curr_state[CHECK_REQ]:
        begin
            if (reg_rr_re_lock)
            begin
                next_state[READ_BITMAP] = 1'b1;
            end
            else
            begin
                next_state[CHECK_REQ] = 1'b1;
            end
        end
        curr_state[FIND_BITMAP]:
        begin
            if (reg_plane_valid)
            begin
                next_state[FIND_HOSTID] = 1'b1;
            end
            else
            begin
                next_state[READ_BITMAP] = 1'b1;
            end
        end
        curr_state[FIND_HOSTID]:
        begin
            next_state[SET_VALID] = 1'b1;
        end
        curr_state[SET_VALID]:
        begin
            if (~o_xfer)
            begin
                next_state[SET_VALID] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
        end
        default:
        begin
            next_state = IDLE;
        end
    endcase
end

sram_interconnect
#(
    .DATA_WIDTH(MAX_HOST_NUMBER),
    .MAX_ADDR(MAX_PLANE_NUMBER),
    .ADDR_BIT_WIDTH(PLANE_ID_BIT_WIDTH)
)
bitmap(
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_read_req(read_req),
    .i_write_req(write_req),
    .i_write_addr(mem_addr),
    .i_read_addr(mem_addr),
    .i_wdata(sram_wdata),
    .o_rdata(sram_rdata),
    .o_or_rdata(or_rdata),
    .o_w_trand_done(o_trans_done),
    .o_r_trans_done(r_trans_done)
);

bitmap_parser
#(
    .SIZE_OF_BITMAP(MAX_HOST_NUMBER),
    .INDEX_WIDTH(HOST_ID_BIT_WIDTH)
)
bitmap_parser(
    .i_bitmap(reg_pe_bitmap),
    .i_index(reg_pe_host_id),
    .o_index(pe_next_host_id)
);

endmodule

module priority_encoder_serial
#(
    parameter SIZE_OF_BITMAP = 128,
    parameter INDEX_WIDTH    = $clog2(SIZE_OF_BITMAP)
)
(
    input  [SIZE_OF_BITMAP-1:0] i_bitmap,
    output [INDEX_WIDTH-1:0] o_index
);

wire [INDEX_WIDTH-1:0] stage[SIZE_OF_BITMAP-1:0];

assign stage[0] = 0;

genvar i;
generate
    for(i=1; i < SIZE_OF_BITMAP; i=i+1)
    begin
        assign stage[i] = (|i_bitmap[i-1:0]) ? stage[i-1] : i;
    end
endgenerate

assign o_index = stage[SIZE_OF_BITMAP-1];

endmodule

module priority_encoder_parallel
#(
    parameter SIZE_OF_BITMAP = 128,
    parameter INDEX_WIDTH    = $clog2(SIZE_OF_BITMAP)
)
(
    input  [SIZE_OF_BITMAP-1:0] i_bitmap,
    output [INDEX_WIDTH-1:0] o_index
);

genvar i, j;
generate
    for(i=0; i < INDEX_WIDTH; i=i+1)
    begin : gen1
        wire            w_valid     [2**(INDEX_WIDTH-i-1)-1:0];
        wire [i+1-1:0]  w_winner    [2**(INDEX_WIDTH-i-1)-1:0];
        if (i==0)
        begin
            for(j=0;j<2**(INDEX_WIDTH-i-1);j=j+1)
            begin
                assign gen1[0].w_valid[j] = |i_bitmap[2*j+:2];
                assign gen1[0].w_winner[j] = i_bitmap[2*j]? 1'b0 : 1'b1;
            end
        end
        else
        begin
            for(j=0;j<2**(INDEX_WIDTH-i-1);j=j+1)
            begin
                assign gen1[i].w_valid[j] = gen1[i-1].w_valid[2*j] | gen1[i-1].w_valid[2*j+1];
                assign gen1[i].w_winner[j] = gen1[i-1].w_valid[2*j]? {1'b0, gen1[i-1].w_winner[2*j]} :
                                                                     {1'b1, gen1[i-1].w_winner[2*j+1]};
            end
        end
    end
endgenerate

assign o_index = gen1[INDEX_WIDTH-1].w_winner[0];
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

