`include "defines.vh"

module top
#
(
    parameter MAX_HOST_NUMBER        = `MAX_HOST_NUMBER,
    parameter MAX_PLANE_NUMBER       = `MAX_PLANE_NUMBER,
    parameter HOST_ID_BIT_WIDTH      = $clog2(MAX_HOST_NUMBER),
    parameter PLANE_ID_BIT_WIDTH     = $clog2(MAX_PLANE_NUMBER),
    parameter NO_OF_TAG              = `NO_OF_TAG,
    parameter INFO_DATA_BIT_WIDTH    = 128,
    parameter META_DATA_BIT_WIDTH    = INFO_DATA_BIT_WIDTH-$clog2(NO_OF_TAG)-HOST_ID_BIT_WIDTH-1
)
(
    input clk,
    input reset_n,
    input[INFO_DATA_BIT_WIDTH-1:0] input_info,
    input info_req,
    output[META_DATA_BIT_WIDTH-1:0] meta_data,
    output meta_data_valid
);

wire [HOST_ID_BIT_WIDTH-1:0] w_job_to_resource_host_id;
wire [HOST_ID_BIT_WIDTH-1:0] w_job_to_bitmap_host_id;
wire [PLANE_ID_BIT_WIDTH-1:0] w_job_to_resource_plane_id;
wire [PLANE_ID_BIT_WIDTH-1:0] w_job_to_bitmap_plane_id;
wire [META_DATA_BIT_WIDTH-1:0] w_job_to_resource_meta;
wire w_job_to_resource_valid;
wire w_job_to_bitmap_valid;

wire [HOST_ID_BIT_WIDTH-1:0] w_bitmap_to_resource_host_id;
wire [PLANE_ID_BIT_WIDTH-1:0] w_bitmap_to_resource_plane_id;
wire w_bitmap_to_resource_valid;

resource_manager u_resource_manager(
    .i_clk(clk),
    .i_rst_n(reset_n),
    .i_host_id_0(w_job_to_resource_host_id),
    .i_plane_id_0(w_job_to_resource_plane_id),
    .i_host_id_1(w_bitmap_to_resource_host_id),
    .i_plane_id_1(w_bitmap_to_resource_plane_id),
    .i_insert_req(w_job_to_resource_valid),
    .i_pop_req(w_bitmap_to_resource_valid),
    .i_bitmap_rst_req(reset_n),
    .i_meta_data(w_job_to_resource_meta),
    .o_meta_data(meta_data),
    .o_meta_data_rdy(meta_data_valid)
);

bitmap_manager u_bitmap_manager(
    .i_clk(clk),
    .i_rst_n(reset_n),
    .i_host_id(w_job_to_bitmap_host_id),
    .i_plane_id(w_job_to_bitmap_plane_id),
    .i_insert_req(w_job_to_bitmap_valid),
    .o_valid(w_bitmap_to_resource_valid),
    .o_host_id(w_bitmap_to_resource_host_id),
    .o_plane_id(w_bitmap_to_resource_plane_id)
);

job_decoder u_job_decoder(
    .i_clk(clk),
    .i_rst_n(reset_n),
    .i_input_info(input_info),
    .i_insert_req(info_req),
    .o_host_id_0(w_job_to_resource_host_id),
    .o_plane_id_0(w_job_to_resource_plane_id),
    .o_host_id_1(w_job_to_bitmap_host_id),
    .o_plane_id_1(w_job_to_bitmap_plane_id),
    .o_meta_data(w_job_to_resource_meta),
    .o_valid_0(w_job_to_resource_valid),
    .o_valid_1(w_job_to_bitmap_valid)

);

endmodule
