// SPDX-License-Identifier: BSD-3-Clause
// Pinned MAME CVS I/O compatibility; raw input polarity is preserved.
module cvs_main_io (
    input wire clk, reset,
    input wire io_rd, io_wr, extended, data_port,
    input wire [7:0] address, din,
    output reg [7:0] dout,
    input wire [7:0] in0, in1, in2, in3, dsw1, dsw2, collision,
    output reg [1:0] char_page, char_mode,
    output reg [7:0] scroll, video_fx, audio_command,
    output reg collision_clear, audio_trigger
);
    always @(posedge clk) begin
        collision_clear <= 1'b0;
        audio_trigger <= 1'b0;
        if (reset) begin
            dout <= 8'd0;
            char_page <= 2'd0;
            char_mode <= 2'd0;
            scroll <= 8'd0;
            video_fx <= 8'd0;
            audio_command <= 8'd0;
        end else begin
            if (io_rd) begin
                if (extended) begin
                    char_page <= address[7:6];
                    char_mode <= address[5:4];
                    case (address[3:0])
                        4'h0: dout <= in0;
                        4'h2: dout <= in1;
                        4'h3: dout <= in2;
                        4'h4: dout <= in3;
                        4'h6: dout <= dsw2;
                        4'h7: dout <= dsw1;
                        default: dout <= 8'd0;
                    endcase
                end else if (data_port) begin
                    dout <= 8'd0;
                    collision_clear <= 1'b1;
                end else dout <= collision;
            end
            if (io_wr) begin
                if (extended) scroll <= 8'hff - din;
                else if (data_port) video_fx <= din;
                else begin
                    audio_command <= din;
                    audio_trigger <= !audio_command[7] && din[7];
                end
            end
        end
    end
endmodule
