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
parameter PLANE_EMPTY_CHECK             = 1;
parameter UPDATE_ONLY_BITMAP            = 2;
parameter READ_FROM_ARRAY               = 3;
parameter CHECK_HOST_ID_FOR_FIRST       = 4;
parameter READ_FROM_LIST                = 5;
parameter CHECK_HOST_ID_FROM_LIST       = 6;
parameter UPDATE_INSERT_INDEX           = 7;
parameter UPDATE_SRAM_BITMAP            = 8;
parameter POP_REQ                       = 9;
parameter READ_FOR_POP_FIRST            = 10;
parameter FIND_HOST_ID_FOR_FIRST        = 11;
parameter READ_FOR_POP                  = 12;
parameter FIND_HOST_ID_FROM_LIST        = 13;
parameter BITMAP_RESET                  = 14;
parameter NO_OF_STATES                  = 15;

reg [NO_OF_STATES-1:0] curr_state;
reg [NO_OF_STATES-1:0] next_state;

// SRAM for LL
/*
* Valid - Meta(Host ID, Page Number and etc  - Addr
* */
// register for each plane's address
parameter VALID_BIT_OFFSET              = SRAM_ADDR_WIDTH;
reg     [SRAM_ADDR_WIDTH:0] r_plane_addr_arr [MAX_PLANE_NUMBER-1:0];
reg     [NO_OF_TAG-1:0] r_sram_bitmap;
wire    [SRAM_ADDR_WIDTH-1:0] w_sram_bitindex;
reg     [SRAM_ADDR_WIDTH-1:0] r_write_addr;
reg     [SRAM_ADDR_WIDTH-1:0] r_read_addr;
reg     [SRAM_ADDR_WIDTH-1:0] r_read_addr_old;
reg     [SRAM_DATA_BIT_WIDTH-1:0] r_write_data;
reg     r_write_req;
reg     r_read_req;
reg     [SRAM_DATA_BIT_WIDTH-1:0] r_read_data;
reg     [SRAM_DATA_BIT_WIDTH-1:0] r_read_data_old;
wire    [SRAM_DATA_BIT_WIDTH-1:0] w_read_data;

reg     [SRAM_ADDR_WIDTH-1:0] r_last_insert_addr;
reg     [SRAM_ADDR_WIDTH-1:0] r_need_insert_addr;
reg     [SRAM_ADDR_WIDTH-1:0] r_sram_update_addr;

always@ (posedge i_clk or negedge i_rst_n)
begin
    if (~i_rst_n)
    begin
        r_read_data <= 'h0;
        r_read_data_old <= 'h0;
        r_read_addr_old <= 'h0;
    end
    else
    begin
        r_read_data <= w_read_data;
        r_read_data_old <= r_read_data;
        r_read_addr_old <= r_read_addr;
    end
end


integer i;

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
        curr_state[PLANE_EMPTY_CHECK]:
        begin
            if (r_plane_addr_arr[i_plane_id_0][VALID_BIT_OFFSET])
            begin
                r_read_addr = r_plane_addr_arr[i_plane_id_0][SRAM_ADDR_WIDTH-1:0];
                r_need_insert_addr = r_plane_addr_arr[i_plane_id_0][SRAM_ADDR_WIDTH-1:0];
                r_read_req = 1'b1;
            end
            else
            begin
                r_write_addr = w_sram_bitindex;
                r_sram_update_addr = w_sram_bitindex;
                r_write_data = {{1'b1},i_meta_data,i_host_id_0,{(SRAM_ADDR_WIDTH){1'b1}}};
                r_write_req = 1'b1;
            end
        end
        curr_state[UPDATE_ONLY_BITMAP]:
        begin
            r_write_req = 1'b0;
            r_sram_bitmap[r_sram_update_addr] = 1'b1;
            r_plane_addr_arr[i_plane_id_0]= {1'b1, r_sram_update_addr};
        end
        curr_state[READ_FROM_ARRAY]:
        begin
            r_read_req = 1'b0;
        end
        curr_state[CHECK_HOST_ID_FOR_FIRST]:
        begin
            if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] <= i_host_id_0) // until end of same host id
            begin
                if (r_read_data[SRAM_ADDR_WIDTH-1:0] != {(SRAM_ADDR_WIDTH){1'b1}}) // Not end of list
                begin
                    // Need to read more
                    r_need_insert_addr = r_read_addr_old;
                    r_last_insert_addr = r_read_data[SRAM_ADDR_WIDTH-1:0];
                    r_read_addr = r_read_data[SRAM_ADDR_WIDTH-1:0];
                    r_read_req = 1'b1;
                end
                else // End of list
                begin
                    // Update read list
                    r_last_insert_addr = {(SRAM_ADDR_WIDTH){1'b1}};
                    r_write_addr = r_read_addr;
                    r_write_data = {r_read_data[SRAM_DATA_BIT_WIDTH-1:SRAM_ADDR_WIDTH], w_sram_bitindex};
                    r_write_req = 1'b1;
                end
            end
            else
            begin
                // Update plane register & only write inserted list
                r_last_insert_addr = r_read_addr;
                r_plane_addr_arr[i_plane_id_0]= {1'b1, w_sram_bitindex};
            end
        end
        curr_state[READ_FROM_LIST]:
        begin
            r_read_req = 1'b0;
        end
        curr_state[CHECK_HOST_ID_FROM_LIST]:
        begin
            if (r_read_data[SRAM_ADDR_WIDTH-1:0] != {(SRAM_ADDR_WIDTH){1'b1}}) // Not end of list
            begin
                if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] <= i_host_id_0) // until end of same host id
                begin
                    // Need to read more
                    r_need_insert_addr = r_read_addr_old;
                    r_last_insert_addr = r_read_data[SRAM_ADDR_WIDTH-1:0];
                    r_read_addr = r_read_data[SRAM_ADDR_WIDTH-1:0];
                    r_read_req = 1'b1;
                end
                else
                begin
                    // Update read list
                    r_write_addr = r_need_insert_addr;
                    r_write_data = {r_read_data_old[SRAM_DATA_BIT_WIDTH-1:SRAM_ADDR_WIDTH], w_sram_bitindex};
                    r_write_req = 1'b1;
                end
            end
            else // End of list
            begin
                // Update read list
                if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] <= i_host_id_0)
                begin
                    r_write_addr = r_read_addr;
                    r_last_insert_addr = {(SRAM_ADDR_WIDTH){1'b1}};
                    r_write_data = {r_read_data[SRAM_DATA_BIT_WIDTH-1:SRAM_ADDR_WIDTH], w_sram_bitindex};
                    r_write_req = 1'b1;
                end
                else
                begin
                    r_write_addr = r_need_insert_addr;
                    r_write_data = {r_read_data_old[SRAM_DATA_BIT_WIDTH-1:SRAM_ADDR_WIDTH], w_sram_bitindex};
                    r_write_req = 1'b1;
                end
            end
        end
        curr_state[UPDATE_INSERT_INDEX]:
        begin
            r_write_addr = w_sram_bitindex;
            r_sram_update_addr = w_sram_bitindex;
            r_write_data = {{1'b1},i_meta_data,i_host_id_0,r_last_insert_addr};
            r_write_req = 1'b1;
        end
        curr_state[UPDATE_SRAM_BITMAP]:
        begin
            r_write_req = 1'b0;
            r_sram_bitmap[r_sram_update_addr] = 1'b1;
        end
        curr_state[POP_REQ]:
        begin
            r_read_addr = r_plane_addr_arr[i_plane_id_1][SRAM_ADDR_WIDTH-1:0];
            r_read_req = 1'b1;
        end
        curr_state[READ_FOR_POP_FIRST]:
        begin
            r_read_req = 1'b0;
        end
        curr_state[FIND_HOST_ID_FOR_FIRST]:
        begin
            if (r_read_data[SRAM_ADDR_WIDTH+:HOST_ID_BIT_WIDTH] == i_host_id_1)
            begin
                if (r_read_data[SRAM_ADDR_WIDTH-1:0] == {(SRAM_ADDR_WIDTH){1'b1}})
                begin
                    r_plane_addr_arr[i_plane_id_1] = {1'b0, {(SRAM_ADDR_WIDTH){1'b1}}};
                end
                else
                begin
                    r_plane_addr_arr[i_plane_id_1] = {1'b1, r_read_data[SRAM_ADDR_WIDTH-1:0]};
                end
                r_sram_bitmap[r_read_addr] = 1'b0;
                r_meta_data = r_read_data[SRAM_ADDR_WIDTH+HOST_ID_BIT_WIDTH+:META_DATA_BIT_WIDTH];
                r_meta_data_rdy = 1'b1;
            end
            else
            begin
                r_need_insert_addr = r_read_addr_old;
                r_read_addr = r_read_data[SRAM_ADDR_WIDTH-1:0];
                r_read_req = 1'b1;
            end
        end
        curr_state[READ_FOR_POP]:
        begin
            r_read_req = 1'b0;
        end
        curr_state[FIND_HOST_ID_FROM_LIST]:
        begin
            if (r_read_data[SRAM_ADDR_WIDTH+:HOST_ID_BIT_WIDTH] < i_host_id_1)
            begin
                r_need_insert_addr = r_read_addr_old;
                r_read_addr = r_read_data[SRAM_ADDR_WIDTH-1:0];
                r_read_req = 1'b1;
            end
            else
            begin
                r_write_addr = r_need_insert_addr;
                r_write_data = {r_read_data_old[SRAM_DATA_BIT_WIDTH-1:SRAM_ADDR_WIDTH], r_read_data[SRAM_ADDR_WIDTH-1:0]};
                r_write_req = 1'b1;
                r_sram_bitmap[r_read_addr] = 1'b0;
                r_meta_data = r_read_data[SRAM_ADDR_WIDTH+HOST_ID_BIT_WIDTH+:META_DATA_BIT_WIDTH];
                r_meta_data_rdy = 1'b1;
            end
        end
        curr_state[BITMAP_RESET]:
        begin
            r_sram_bitmap = 'd0;
            for (i = 0; i < MAX_PLANE_NUMBER + 1; i = i + 1)
            begin
                r_plane_addr_arr[i] = 'd0;
            end
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
                next_state[PLANE_EMPTY_CHECK] = 1'b1;
            end
            else if (i_bitmap_rst_req)
            begin
                next_state[BITMAP_RESET] = 1'b1;
            end
            else if (i_pop_req)
            begin
                next_state[POP_REQ] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
        end
        curr_state[PLANE_EMPTY_CHECK]:
        begin
            if (r_plane_addr_arr[i_plane_id_0][VALID_BIT_OFFSET])
            begin
                next_state[READ_FROM_ARRAY] = 1'b1;
            end
            else
            begin
                next_state[UPDATE_ONLY_BITMAP] = 1'b1;
            end
        end
        curr_state[UPDATE_ONLY_BITMAP]:
        begin
            next_state[IDLE] = 1'b1;
        end
        curr_state[READ_FROM_ARRAY]:
        begin
            next_state[CHECK_HOST_ID_FOR_FIRST] = 1'b1;
        end
        curr_state[CHECK_HOST_ID_FOR_FIRST]:
        begin
            if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] <= i_host_id_0)
            begin
                if (r_read_data[SRAM_ADDR_WIDTH-1:0] != {(SRAM_ADDR_WIDTH){1'b1}})
                begin
                    next_state[READ_FROM_LIST] = 1'b1;
                end
                else
                begin
                    next_state[UPDATE_INSERT_INDEX] = 1'b1;
                end
            end
            else
            begin
                next_state[UPDATE_INSERT_INDEX] = 1'b1;
            end
        end
        curr_state[READ_FROM_LIST]:
        begin
            next_state[CHECK_HOST_ID_FROM_LIST] = 1'b1;
        end
        curr_state[CHECK_HOST_ID_FROM_LIST]:
        begin
            if (r_read_data[SRAM_ADDR_WIDTH-1:0] != {(SRAM_ADDR_WIDTH){1'b1}})
            begin
                if (r_read_data[SRAM_ADDR_WIDTH +:HOST_ID_BIT_WIDTH] <= i_host_id_0)
                begin
                    next_state[READ_FROM_LIST] = 1'b1;
                end
                else
                begin
                    next_state[UPDATE_INSERT_INDEX] = 1'b1;
                end
            end
            else
            begin
                next_state[UPDATE_INSERT_INDEX] = 1'b1;
            end
        end
        curr_state[UPDATE_INSERT_INDEX]:
        begin
            next_state[UPDATE_SRAM_BITMAP] = 1'b1;
        end
        curr_state[UPDATE_SRAM_BITMAP]:
        begin
            next_state[IDLE] = 1'b1;
        end
        curr_state[POP_REQ]:
        begin
            next_state[READ_FOR_POP_FIRST] = 1'b1;
        end
        curr_state[READ_FOR_POP_FIRST]:
        begin
            next_state[FIND_HOST_ID_FOR_FIRST] = 1'b1;
        end
        curr_state[FIND_HOST_ID_FOR_FIRST]:
        begin
            if (r_read_data[SRAM_ADDR_WIDTH+:HOST_ID_BIT_WIDTH] == i_host_id_1)
            begin
                next_state[IDLE] = 1'b1;
            end
            else
            begin
                next_state[READ_FOR_POP] = 1'b1;
            end
        end
        curr_state[READ_FOR_POP]:
        begin
            next_state[FIND_HOST_ID_FROM_LIST] = 1'b1;
        end
        curr_state[FIND_HOST_ID_FROM_LIST]:
        begin
            if (r_read_data[SRAM_ADDR_WIDTH+:HOST_ID_BIT_WIDTH] < i_host_id_1)
            begin
                next_state[READ_FOR_POP] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
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
