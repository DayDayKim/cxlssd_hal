module sram_interconnect
#(
    parameter DATA_WIDTH = 128,
    parameter MAX_ADDR = 128,
    parameter ADDR_BIT_WIDTH = $clog2(MAX_ADDR)
)
(
    input  i_clk,
    input  i_rst_n,
    input  i_read_req,
    input  i_write_req,
    input  [ADDR_BIT_WIDTH-1:0] i_write_addr,
    input  [ADDR_BIT_WIDTH-1:0] i_read_addr,
    input  [DATA_WIDTH-1:0] i_wdata,
    output [DATA_WIDTH-1:0] o_rdata,
    output o_or_rdata,
    output o_w_trand_done,
    output o_r_trans_done
);

// SRAM Interface
reg [ADDR_BIT_WIDTH-1:0] reg_mem_addr;
wire [ADDR_BIT_WIDTH-1:0] mem_addr;
reg reg_cs_n;
reg reg_we_n;
reg reg_r_trans_done;
reg reg_w_trans_done;
reg reg_r_trans_done_next;
reg reg_w_trans_done_next;
wire cs_n;
wire we_n;
assign cs_n = reg_cs_n;
assign we_n = reg_we_n;
reg [DATA_WIDTH-1:0] reg_sram_rdata;
reg [DATA_WIDTH-1:0] reg_sram_wdata;
wire [DATA_WIDTH-1:0] sram_rdata;
assign o_w_trans_done = reg_w_trans_done;
assign o_r_trans_done = reg_r_trans_done;
assign o_rdata = reg_sram_rdata;
assign o_or_rdata = |o_rdata;

// FSM States
parameter IDLE          = 0;
parameter SRAM_READ     = 1;
parameter SRAM_WRITE    = 2;
parameter NO_OF_STATES  = 3;

reg [NO_OF_STATES-1:0] curr_state;
reg [NO_OF_STATES-1:0] next_state;

// SRAM Pin Contorl (Sequntial Logic)
always @ (posedge i_clk or negedge i_rst_n)
begin
    if (~i_rst_n)
    begin
        reg_sram_rdata <= 'h0;
        reg_r_trans_done <= 1'b0;
        reg_w_trans_done <= 1'b0;
    end
    else
    begin
        reg_sram_rdata <= sram_rdata;
        reg_r_trans_done <= reg_r_trans_done_next;
        reg_w_trans_done <= reg_w_trans_done_next;
    end
end

// FSM Control (Sequential Logic)
always @ (posedge i_clk or negedge i_rst_n)
begin
    if (~i_rst_n)
    begin
        curr_state <= 'h1;
    end
    else
    begin
        curr_state <= next_state;
    end
end

// Current State Behavior (Combinational Logic)
always @ (*)
begin
    case(1'b1)
        curr_state[IDLE] :
        begin
            reg_cs_n = 1'b1;
            reg_we_n = 1'b1;
            reg_mem_addr = 'h0;
            reg_r_trans_done_next = 1'b0;
            reg_w_trans_done_next = 1'b0;
        end
        curr_state[SRAM_READ] :
        begin
            reg_cs_n = 1'b0;
            reg_we_n = 1'b1;
            reg_mem_addr = i_read_addr;
            reg_r_trans_done_next = 1'b1;
            reg_w_trans_done_next = 1'b0;
        end
        curr_state[SRAM_WRITE] :
        begin
            reg_cs_n = 1'b0;
            reg_we_n = 1'b0;
            reg_mem_addr = i_write_addr;
            reg_sram_wdata = i_wdata;
            reg_r_trans_done_next = 1'b0;
            reg_w_trans_done_next = 1'b1;
        end
        default :
        begin
            reg_cs_n = 1'b1;
            reg_we_n = 1'b1;
            reg_mem_addr = 'h0;
            reg_r_trans_done_next = 1'b0;
            reg_w_trans_done_next = 1'b0;
        end
    endcase
end

// Next State Transition (Combinational)
always @(*)
begin
    next_state = 'h0;
    case (1'b1)
        curr_state[IDLE]:
        begin
            if (i_read_req)
            begin
                next_state[SRAM_READ] = 1'b1;
            end
            else if (i_write_req)
            begin
                next_state[SRAM_WRITE] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
        end
        curr_state[SRAM_READ]:
        begin
            if (i_write_req)
            begin
                next_state[SRAM_WRITE] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
        end
        curr_state[SRAM_WRITE]:
            if (i_read_req)
            begin
                next_state[SRAM_READ] = 1'b1;
            end
            else
            begin
                next_state[IDLE] = 1'b1;
            end
    endcase
end


sram
#(
    .DATA_WIDTH(DATA_WIDTH),
    .MAX_ADDR(MAX_ADDR),
    .ADDR_BIT_WIDTH(ADDR_BIT_WIDTH)
)sram
(
    .i_rst_n(i_rst_n),
    .i_cs_n(cs_n),
    .i_we_n(we_n),
    .i_wdata(reg_sram_wdata),
    .i_addr(reg_mem_addr),
    .o_rdata(sram_rdata)
);

endmodule
