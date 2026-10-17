// SPDX-License-Identifier: BSD-3-Clause
// Map MiSTer-standard joystick bits to the active-low CVS input matrices.
module cvs_mister_input (
    input wire [31:0] joystick_0, joystick_1,
    output wire [7:0] in0, in1
);
    // MiSTer joystick bits are active-high (zero when idle). CVS matrix inputs
    // are active-low, so inversion makes idle one and a pressed control zero.
    // MRA button names are consecutive HPS bits from bit 4: Jump, Start 2,
    // Start 1, Coin. CVS IN0 is active-low: starts 0/1, coins 2/3,
    // cocktail/upright jump 4/5.
    assign in0={2'b11,~joystick_0[4],~joystick_1[4],
        ~joystick_0[7],~joystick_1[7],~joystick_0[5],~joystick_0[6]};
    // CVS IN1: right/left for upright then cocktail in bits 4..5 and 2..3.
    // MiSTer direction bits are Right=0 and Left=1 (Up=3, Down=2).
    assign in1={2'b11,~joystick_0[1],~joystick_0[0],
        ~joystick_1[1],~joystick_1[0],2'b11};
endmodule
