// SPDX-License-Identifier: BSD-3-Clause
// MAME-compatible pending vblank interrupt. All inputs share clk.
// Simultaneous new edge/ack retains the new event, an FPGA contract.
module cvs_vblank_irq (
    input wire clk, reset, vblank, intack,
    output reg irq
);
    reg previous_blank;
    always @(posedge clk) begin
        if (reset) begin
            previous_blank <= 1'b0;
            irq <= 1'b0;
        end else begin
            previous_blank <= vblank;
            if (vblank && !previous_blank) irq <= 1'b1;
            else if (intack) irq <= 1'b0;
        end
    end
endmodule
