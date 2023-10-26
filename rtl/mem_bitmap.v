`include "defines.v"

module mem_bitmap
#(
    parameter MAX_HOST_NUMBER    = `MAX_HOST_NUMBER,
    parameter MAX_PLANE_NUMBER   = `MAX_PLANE_NUMBER,
    parameter WIDTH = MAX_HOST_NUMBER,
    parameter MAX_ADDR = MAX_PLANE_NUMBER,
    parameter ADDR_BIT_WIDTH = $clog2(MAX_ADDR)
)
(
    input i_rst_n,
    input i_cs_n,
    input i_we_n,
    input [WIDTH-1:0] i_wdata,
    input [ADDR_BIT_WIDTH-1:0] i_addr,
    output [WIDTH-1:0] o_rdata
);

reg [WIDTH-1:0] mem_data[MAX_ADDR-1:0];
reg [ADDR_BIT_WIDTH-1:0] reg_raddr;

integer row, col;

always @(*)
begin
    if (~i_rst_n)
    begin
        for (row = 0; row < MAX_ADDR; row=row+1)
        begin
            for (col = 0; col < WIDTH; col = col + 1)
            begin
                mem_data[row][col] <= 1'b0;
            end
        end
    end
    else
    begin
        if (~i_cs_n)
        begin
            if(~i_we_n)
            begin
                mem_data[i_addr] = i_wdata;
            end
            else
            begin
                reg_raddr = i_addr;
            end
        end
    end
end

assign o_rdata = mem_data[reg_raddr];

endmodule
