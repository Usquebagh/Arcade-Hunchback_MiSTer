// SPDX-License-Identifier: BSD-3-Clause
// Map MiSTer-standard joystick bits to the active-low CVS input matrices.
module cvs_mister_input (
    input wire [31:0] joystick_0, joystick_1,
    output wire [7:0] in0, in1
);
    // MAME CVS IN0: starts 0/1, coins 2/3, cocktail/upright jump 4/5.
    assign in0={2'b11,~joystick_0[4],~joystick_1[4],
        ~joystick_0[9],~joystick_1[9],~joystick_0[6],~joystick_0[8]};
    // CVS IN1: cocktail/upright horizontal directions in bits 2..5.
    assign in1={2'b11,~joystick_0[2],~joystick_0[3],
        ~joystick_1[2],~joystick_1[3],2'b11};
endmodule
