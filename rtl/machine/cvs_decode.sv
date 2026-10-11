// SPDX-License-Identifier: BSD-3-Clause
// CVS U15L address groups, derived from Kevtris' supplied CUPL truth equations.
// Raw pin levels: DEC5/DEC6 and PAL_DEC outputs are active low.
// Combinational pin model only; upstream bus decoding and delays are excluded.
module cvs_decode (
    input wire dec5_n,
    input wire dec6_n,
    input wire [2:0] address_hi, // A12:A10
    output wire [7:0] pal_dec_n
);
    wire bus_selected = !dec5_n || !dec6_n;
    assign pal_dec_n = bus_selected ?
        ~(8'b00000001 << (3'd7 - address_hi)) : 8'hff;
endmodule
