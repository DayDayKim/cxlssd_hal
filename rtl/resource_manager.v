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

parameter IDLE              = 1;
parameter NO_OF_STATES      = 2;

reg [NO_OF_STATES-1:0] curr_state;
reg [NO_OF_STATES-1:0] next_state;

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

always@ (*)
begin
    case(1'b1)
        curr_state[IDLE]:
        begin
        end
        default:
        begin
        end
    endcase
end

always@ (*)
begin
    next_state = 'h0;
    case(1'b1)
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
        default:
        begin
        end
    endcase
end

// Max queues Host x Plane x QD x Queue Entry
sram_interconnect
#(
    .DATA_WIDTH(64), // Queue Entry 64
    .MAX_ADDR(MAX_HOST_NUMER*MAX_PLANE_NUMBER*22),
    .ADDR_BIT_WIDTH($clog2(MAX_ADDR))
)
queue(
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

sram_interconnect
#(
    .DATA_WIDTH(64), // Queue Entry 64
    .MAX_ADDR(1024), // Fixed Size
    .ADDR_BIT_WIDTH($clog2(MAX_ADDR))
)
linkedlist(
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

endmodule
