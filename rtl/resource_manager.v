`include "defines.vh"

module resource_manager
#(
    parameter MAX_HOST_NUMBER        = `MAX_HOST_NUMBER,
    parameter MAX_PLANE_NUMBER       = `MAX_PLANE_NUMBER,
    parameter HOST_ID_BIT_WIDTH      = $clog2(MAX_HOST_NUMBER),
    parameter PLANE_ID_BIT_WIDTH     = $clog2(MAX_PLANE_NUMBER),
    parameter NO_OF_TAG              = `NO_OF_TAG,
    parameter SRAM_DATA_BIT_WIDTH    = 128,
    parameter SRAM_ADDR_WIDTH        = $clog2(NO_OF_TAG),
    parameter META_DATA_BIT_WIDTH    = SRAM_DATA_BIT_WIDTH-$clog2(NO_OF_TAG)-HOST_ID_BIT_WIDTH-1
)
(
    input  i_clk,
    input  i_rst_n,
    input  [HOST_ID_BIT_WIDTH-1:0]  i_host_id_0,
    input  [PLANE_ID_BIT_WIDTH-1:0] i_plane_id_0,
    input  [HOST_ID_BIT_WIDTH-1:0]  i_host_id_1,
    input  [PLANE_ID_BIT_WIDTH-1:0] i_plane_id_1,
    input  i_insert_req,
    input  i_pop_req,
    input  i_bitmap_rst_req,
    input  [META_DATA_BIT_WIDTH-1 : 0] i_meta_data,
    output [META_DATA_BIT_WIDTH-1 : 0] o_meta_data,
    output o_meta_data_rdy
);

reg [META_DATA_BIT_WIDTH-1 : 0] r_meta_data;
reg r_meta_data_rdy;

assign o_meta_data = r_meta_data;
assign o_meta_data_rdy = r_meta_data_rdy;

// FSM States
parameter IDLE                          = 0;
parameter INSERT_REQ                    = 1;
parameter POP_REQ                       = 2;
parameter FIND_PLANE_INSERT_STAGE       = 3;
parameter FIND_PLANE_INSERT_STAGE2      = 4;
parameter UPDATE_RESOURCE               = 5;
parameter UPDATE_RESOURCE2              = 6;
parameter BITMAP_RESET                  = 7;
parameter UPDATE_ONLY_BIT               = 8;
parameter FIND_PLANE_POP_STAGE          = 9;
parameter FIND_PLANE_POP_STAGE2         = 10;
parameter CLEAR_RESOURCE                = 11;
parameter NO_OF_STATES                  = 12;

reg [NO_OF_STATES-1:0] curr_state;
reg [NO_OF_STATES-1:0] next_state;

// SRAM for LL
/*
* 1bit  -           53bit                    - 10bit
* Valid - Meta(Host ID, Page Number and etc  - Addr
* */
// register for each plane's address
reg     [NO_OF_TAG-1:0] r_sram_bitmap;
wire    [SRAM_ADDR_WIDTH-1:0] w_sram_bitindex;
reg     [SRAM_ADDR_WIDTH:0] r_plane_addr_arr [MAX_PLANE_NUMBER-1:0];
reg     r_write_req;
reg     r_read_req;
reg     [SRAM_ADDR_WIDTH-1:0] r_write_addr;
reg     [SRAM_ADDR_WIDTH-1:0] r_last_insert_addr;
reg     [SRAM_ADDR_WIDTH-1:0] r_need_insert_addr;
reg     [SRAM_ADDR_WIDTH-1:0] r_read_addr;
reg     [SRAM_DATA_BIT_WIDTH-1:0] r_write_data;
reg     [SRAM_DATA_BIT_WIDTH-1:0] r_read_data;
reg     [SRAM_DATA_BIT_WIDTH-1:0] r_last_read_data;
wire    [SRAM_DATA_BIT_WIDTH-1:0] w_read_data;

genvar i;
// FSM Control (Sequential Logic)
always@ (posedge i_clk or negedge i_rst_n)
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
always@ (*)
begin
    case(1'b1)
        curr_state[IDLE]:
        begin
            r_write_req = 1'b0;
            r_read_req = 1'b0;
            r_meta_data_rdy = 1'b0;
        end
        curr_state[INSERT_REQ]:
        begin
            r_write_addr = w_sram_bitindex;
            r_last_insert_addr = w_sram_bitindex;
            r_write_req = 1'b1;
            r_write_data = {{1'b1},i_meta_data,i_host_id_0,{(SRAM_ADDR_WIDTH){1'b1}}};
        end
        curr_state[FIND_PLANE_INSERT_STAGE]:
        begin
            r_write_req = 1'b0;
            if (r_plane_addr_arr[i_plane_id_0][SRAM_ADDR_WIDTH])
            begin
                r_need_insert_addr = r_read_addr;
                r_read_addr = r_plane_addr_arr[i_plane_id_0][SRAM_ADDR_WIDTH-1:0];
                r_read_req = 1'b1;
            end
            r_sram_bitmap[r_last_insert_addr] = 1'b1;
        end
        curr_state[FIND_PLANE_INSERT_STAGE2]:
        begin
            r_read_data = w_read_data;
            if (r_read_data[SRAM_ADDR_WIDTH-1:0] != {(SRAM_ADDR_WIDTH){1'b1}})
            begin
                if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] <= i_host_id_0)
                begin
                    r_need_insert_addr = r_read_addr;
                    r_read_addr = r_read_data[SRAM_ADDR_WIDTH-1:0];
                    r_read_req = 1'b1;
                end
                else
                begin
                    r_read_req = 1'b0;
                end
            end
            else
            begin
                r_read_req = 1'b0;
            end
        end
        curr_state[UPDATE_ONLY_BIT]:
        begin
            r_plane_addr_arr[i_plane_id_0]= {1'b1, r_last_insert_addr};
        end
        curr_state[UPDATE_RESOURCE]:
        begin
            // Update Prior
            r_write_addr = r_need_insert_addr;
            r_write_data = {r_read_data[SRAM_DATA_BIT_WIDTH-1:SRAM_ADDR_WIDTH], r_last_insert_addr};
            r_write_req = 1'b1;
        end
        curr_state[UPDATE_RESOURCE2]:
        begin
            // Update Current
            r_write_req = 1'b0;
            r_write_addr = r_last_insert_addr;
            r_write_data = {{1'b1},i_meta_data,i_host_id_0,r_read_data[SRAM_ADDR_WIDTH-1:0]};
            r_write_req = 1'b1;
        end
        curr_state[POP_REQ]:
        begin
            r_read_addr = r_plane_addr_arr[i_plane_id_1][SRAM_ADDR_WIDTH-1:0];
            r_need_insert_addr = r_read_addr;
            r_read_req = 1'd1;
        end
        curr_state[FIND_PLANE_POP_STAGE]:
        begin
            r_read_data = w_read_data;
            if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] == i_host_id_1)
            begin
                if (r_read_data[SRAM_ADDR_WIDTH-1:0] == {(SRAM_ADDR_WIDTH){1'b1}})
                begin
                    r_plane_addr_arr[i_plane_id_1] = {1'b0, {(SRAM_ADDR_WIDTH){1'b1}}};
                end
                else
                begin
                    r_plane_addr_arr[i_plane_id_1] = {1'b1, r_read_data[SRAM_ADDR_WIDTH-1:0]};
                end
                r_sram_bitmap[r_need_insert_addr] = 1'b0;
                r_meta_data = r_read_data[SRAM_ADDR_WIDTH+HOST_ID_BIT_WIDTH+:META_DATA_BIT_WIDTH];
                r_meta_data_rdy = 1'b1;
                r_read_req = 1'b0;
            end
            else
            begin
                r_last_insert_addr = r_read_addr;
                r_last_read_data = r_read_data;
                r_read_addr = r_read_data[SRAM_ADDR_WIDTH-1:0];
                r_read_req = 1'b1;
            end
        end
        curr_state[FIND_PLANE_POP_STAGE2]:
        begin
            r_read_data = w_read_data;
            if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] < i_host_id_1)
            begin
                r_last_insert_addr = r_read_addr;
                r_last_read_data = r_read_data;
                r_read_addr = r_read_data[SRAM_ADDR_WIDTH-1:0];
                r_read_req = 1'b1;
            end
            else if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] == i_host_id_1)
            begin
                r_read_req = 1'b0;
            end
        end
        curr_state[CLEAR_RESOURCE]:
        begin
            r_write_addr = r_last_insert_addr;
            r_write_data = {r_last_read_data[SRAM_DATA_BIT_WIDTH-1:SRAM_ADDR_WIDTH],r_read_data[SRAM_ADDR_WIDTH-1:0]};
            r_write_req = 1'b1;
            r_sram_bitmap[r_read_addr] = 1'b0;
            r_meta_data = r_read_data[SRAM_ADDR_WIDTH+HOST_ID_BIT_WIDTH+:META_DATA_BIT_WIDTH];
            r_meta_data_rdy = 1'b1;
        end
        curr_state[BITMAP_RESET]:
        begin
            r_sram_bitmap = 'd0;
            r_plane_addr_arr[0] = 'd0;
            r_plane_addr_arr[1] = 'd0;
            r_plane_addr_arr[2] = 'd0;
            r_plane_addr_arr[3] = 'd0;
            r_plane_addr_arr[4] = 'd0;
            r_plane_addr_arr[5] = 'd0;
            r_plane_addr_arr[6] = 'd0;
            r_plane_addr_arr[7] = 'd0;
            r_plane_addr_arr[8] = 'd0;
            r_plane_addr_arr[9] = 'd0;
            r_plane_addr_arr[10] = 'd0;
            r_plane_addr_arr[11] = 'd0;
            r_plane_addr_arr[12] = 'd0;
            r_plane_addr_arr[13] = 'd0;
            r_plane_addr_arr[14] = 'd0;
            r_plane_addr_arr[15] = 'd0;
        end
        default:
        begin
        end
    endcase
end

// Next State Transition
always@ (*)
begin
    next_state = 'h0;
    case(1'b1)
        curr_state[IDLE]:
        begin
            if (i_insert_req)
            begin
                next_state[INSERT_REQ] = 1'b1;
            end
            else if (i_pop_req)
            begin
                next_state[POP_REQ] = 1'b1;
            end
            else if (i_bitmap_rst_req)
            begin
                next_state[BITMAP_RESET] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
        end
        curr_state[INSERT_REQ]:
        begin
            next_state[FIND_PLANE_INSERT_STAGE] = 1'b1;
        end
        curr_state[POP_REQ]:
        begin
            next_state[FIND_PLANE_POP_STAGE] = 1'b1;
        end
        curr_state[FIND_PLANE_INSERT_STAGE]:
        begin
            if (r_plane_addr_arr[i_plane_id_0][SRAM_ADDR_WIDTH])
            begin
                next_state[FIND_PLANE_INSERT_STAGE2] = 1'b1;
            end
            else
            begin
                next_state[UPDATE_ONLY_BIT] = 1'b1;
            end
        end
        curr_state[UPDATE_ONLY_BIT]:
        begin
            next_state[IDLE] = 1'b1;
        end
        curr_state[FIND_PLANE_INSERT_STAGE2]:
        begin
            if (r_read_data[SRAM_ADDR_WIDTH-1:0] != {(SRAM_ADDR_WIDTH){1'b1}})
            begin
                if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] <= i_host_id_0)
                begin
                    next_state[FIND_PLANE_INSERT_STAGE2] = 1'b1;
                end
                else
                begin
                    next_state[UPDATE_RESOURCE] = 1'b1;
                end
            end
            else
            begin
                next_state[UPDATE_RESOURCE] = 1'b1;
            end
        end
        curr_state[UPDATE_RESOURCE]:
        begin
            next_state[UPDATE_RESOURCE2] = 1'b1;
        end
        curr_state[UPDATE_RESOURCE2]:
        begin
            next_state[IDLE] = 1'b1;
        end
        curr_state[FIND_PLANE_POP_STAGE]:
        begin
            if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] == i_host_id_1)
            begin
                next_state[IDLE] = 1'b1;
            end
            else
            begin
                next_state[FIND_PLANE_POP_STAGE2] = 1'b1;
            end
        end
        curr_state[FIND_PLANE_POP_STAGE2]:
        begin
            if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] < i_host_id_1)
            begin
                next_state[FIND_PLANE_POP_STAGE2] = 1'b1;
            end
            else if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] == i_host_id_1)
            begin
                next_state[CLEAR_RESOURCE] = 1'b1;
            end
        end
        curr_state[CLEAR_RESOURCE]:
        begin
            next_state[IDLE] = 1'b1;
        end
        curr_state[BITMAP_RESET]:
        begin
            if (i_bitmap_rst_req)
            begin
                next_state[BITMAP_RESET] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
        end
        default:
        begin
        end
    endcase
end

sram_interconnect_128x1024 linkedlist(
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_wr_en(r_write_req),
    .i_rd_en(r_read_req),
    .i_wr_addr(r_write_addr),
    .i_rd_addr(r_read_addr),
    .i_wr_data(r_write_data),
    .o_rd_data(w_read_data)
);

priority_encoder_parallel
#(
    .SIZE_OF_BITMAP(NO_OF_TAG),
    .INDEX_WIDTH($clog2(NO_OF_TAG))
)
pe(
    .i_bitmap(~r_sram_bitmap),
    .o_index(w_sram_bitindex)
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
