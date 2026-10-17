// SPDX-License-Identifier: BSD-3-Clause
// Three PVI object instances, preserving CVS window/chip-index ordering.
module cvs_s2636_bank #(
    parameter integer Y_OFFSET = 0,
    parameter integer X_OFFSET = -26
) (
    input wire clk, reset,
    input wire [2:0] chip_select,
    input wire cpu_rd, cpu_wr,
    input wire [7:0] cpu_addr, cpu_din,
    output reg [7:0] cpu_dout,
    input wire vrst, line_start, ce_pixel,
    input wire [7:0] pixel_x,
    input wire [2:0] intack,
    output wire [2:0] irq,
    output wire [11:0] pixels, object_masks
);
    wire [23:0] read_bytes;
    genvar i;
    generate
    for (i=0;i<3;i=i+1) begin : pvi
        cvs_s2636_objects #(.Y_OFFSET(Y_OFFSET),.X_OFFSET(X_OFFSET)) chip(.clk(clk),.reset(reset),
            .cpu_rd(cpu_rd && chip_select[i]),.cpu_wr(cpu_wr && chip_select[i]),
            .cpu_addr(cpu_addr),.cpu_din(cpu_din),.cpu_dout(read_bytes[i*8 +: 8]),
            .vrst(vrst),.line_start(line_start),.ce_pixel(ce_pixel),.pixel_x(pixel_x),
            .intack(intack[i]),.irq(irq[i]),.object_mask(object_masks[i*4 +: 4]),
            .pixel_colour(pixels[i*4 +: 3]),.pixel_present(pixels[i*4+3]));
    end
    endgenerate
    always @* begin
        case (chip_select)
            3'b001: cpu_dout=read_bytes[7:0];
            3'b010: cpu_dout=read_bytes[15:8];
            3'b100: cpu_dout=read_bytes[23:16];
            default: cpu_dout=8'hff;
        endcase
    end
endmodule
