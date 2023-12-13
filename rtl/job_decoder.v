`include "defines.vh"

module job_decoder
#(
    parameter MAX_HOST_NUMBER        = `MAX_HOST_NUMBER,
    parameter MAX_PLANE_NUMBER       = `MAX_PLANE_NUMBER,
    parameter HOST_ID_BIT_WIDTH      = $clog2(MAX_HOST_NUMBER),
    parameter PLANE_ID_BIT_WIDTH     = $clog2(MAX_PLANE_NUMBER),
    parameter NO_OF_TAG              = `NO_OF_TAG,
    parameter INFO_DATA_BIT_WIDTH    = 128,
    parameter SRAM_ADDR_WIDTH        = $clog2(NO_OF_TAG),
    parameter META_DATA_BIT_WIDTH    = INFO_DATA_BIT_WIDTH-$clog2(NO_OF_TAG)-HOST_ID_BIT_WIDTH-1
)
(
    input  i_clk,
    input  i_rst_n,
    input  [INFO_DATA_BIT_WIDTH-1:0]  i_input_info,
    input  i_insert_req,
    output [HOST_ID_BIT_WIDTH-1:0]  o_host_id_0,
    output [PLANE_ID_BIT_WIDTH-1:0] o_plane_id_0,
    output [HOST_ID_BIT_WIDTH-1:0]  o_host_id_1,
    output [PLANE_ID_BIT_WIDTH-1:0] o_plane_id_1,
    output [META_DATA_BIT_WIDTH-1 : 0] o_meta_data,
    output o_valid_0,
    output o_valid_1
);

// Command Info
parameter HOST_ID_START_OFFSET = 64; // Command Specific 3 CDW12
parameter PLANE_ID_START_OFFSET = 96; // Command Specific 4 CDW13

reg [INFO_DATA_BIT_WIDTH-1:0] r_input_info;
reg r_insert_req;
reg [HOST_ID_BIT_WIDTH-1:0]  r_host_id_0;
reg [PLANE_ID_BIT_WIDTH-1:0] r_plane_id_0;
reg [HOST_ID_BIT_WIDTH-1:0]  r_host_id_1;
reg [PLANE_ID_BIT_WIDTH-1:0] r_plane_id_1;
reg [META_DATA_BIT_WIDTH-1:0] r_meta_data;
reg r_valid_0;
reg r_valid_1;

assign o_host_id_0 = r_host_id_0;
assign o_host_id_1 = r_host_id_1;
assign o_plane_id_0 = r_plane_id_0;
assign o_plane_id_1 = r_plane_id_1;
assign o_valid_0 = r_valid_0;
assign o_valid_1 = r_valid_1;
assign o_meta_data = r_meta_data;
// FSM States
parameter IDLE                          = 0;
parameter INFO_INSERT_REQ               = 1;
parameter PARSE_INFO                    = 2;
parameter POST_INFO                     = 3;
parameter NO_OF_STATES                  = 4;

reg [NO_OF_STATES-1:0] curr_state;
reg [NO_OF_STATES-1:0] next_state;

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
            r_valid_0 = 1'b0;
            r_valid_1 = 1'b0;
        end
        curr_state[INFO_INSERT_REQ]:
        begin
            r_input_info = i_input_info;
        end
        curr_state[PARSE_INFO]:
        begin
            r_host_id_0 = r_input_info[HOST_ID_START_OFFSET+:HOST_ID_BIT_WIDTH];
            r_host_id_1 = r_input_info[HOST_ID_START_OFFSET+:HOST_ID_BIT_WIDTH];
            r_plane_id_0 = r_input_info[PLANE_ID_START_OFFSET+:PLANE_ID_BIT_WIDTH];
            r_plane_id_1 = r_input_info[PLANE_ID_START_OFFSET+:PLANE_ID_BIT_WIDTH];
            r_meta_data = {r_input_info[INFO_DATA_BIT_WIDTH-2:HOST_ID_START_OFFSET+HOST_ID_BIT_WIDTH], r_input_info[HOST_ID_START_OFFSET-1:0]};
        end
        curr_state[POST_INFO]:
        begin
            r_valid_0 = 1'b1;
            r_valid_1 = 1'b1;
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
                next_state[INFO_INSERT_REQ] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
        end
        curr_state[INFO_INSERT_REQ]:
        begin
            next_state[PARSE_INFO] = 1'b1;
        end
        curr_state[PARSE_INFO]:
        begin
            next_state[POST_INFO] = 1'b1;
        end
        curr_state[POST_INFO]:
        begin
            next_state[IDLE] = 1'b1;
        end
    endcase
end

endmodule
