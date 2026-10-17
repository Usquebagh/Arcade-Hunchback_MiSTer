// SPDX-License-Identifier: BSD-3-Clause
// MiSTer arcade MRA byte-read cheat adapter. Supports byte replacement codes.
module cvs_cheat_engine #(
    parameter integer MAX_CODES = 16,
    parameter SUPPORTS_COMPARE = 1'b1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire [128:0] code,
    input  wire        capture,
    input  wire [14:0] address,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out
);
    reg [14:0] code_address [0:MAX_CODES-1];
    reg [7:0] code_value [0:MAX_CODES-1];
    reg [7:0] code_compare [0:MAX_CODES-1];
    reg code_compare_enable [0:MAX_CODES-1];
    reg code_valid [0:MAX_CODES-1];
    integer count;
    integer i;
    reg response_valid;
    reg response_compare_enable;
    reg [7:0] response_compare;
    reg [7:0] response_value;
    reg match_valid;
    reg match_compare_enable;
    reg [7:0] match_compare;
    reg [7:0] match_value;
    wire [MAX_CODES-1:0] address_match;
    wire [MAX_CODES-1:0] selected_match;
    wire code_supported = ~|{code[127:106],code[103],code[99:97],
                            code[95:79],code[63:40],code[31:8]};
    wire compare_supported = SUPPORTS_COMPARE || !code[96];

    // Resolve duplicate addresses when codes load, preserving last-loaded-code
    // priority without an encoder on the synchronous CPU read path.
    genvar g;
    generate for (g = 0; g < MAX_CODES; g = g + 1) begin : address_decode
        assign address_match[g] = code_valid[g] && code_address[g] == address;
        assign selected_match[g] = address_match[g];
    end endgenerate

    // MRA encodes four 32-bit big-endian fields: flags, address, compare,
    // replacement. Hunchback's imported Pugsy entries are all byte writes.
    always @(posedge clk) begin
        if (reset) begin
            count <= 0;
            for (i = 0; i < MAX_CODES; i = i + 1)
                code_valid[i] <= 1'b0;
        end else if (code[128] && count < MAX_CODES && code_supported && compare_supported) begin
            if (code[102:100] == 3'b001 && code[105:104] == 2'b00) begin
                for (i = 0; i < MAX_CODES; i = i + 1)
                    if (code_valid[i] && code_address[i] == code[78:64])
                        code_valid[i] <= 1'b0;
                code_address[count] <= code[78:64];
                code_value[count] <= code[7:0];
                code_compare[count] <= code[39:32];
                code_compare_enable[count] <= code[96];
                code_valid[count] <= 1'b1;
                count <= count + 1;
            end
        end
    end

    always @* begin
        match_valid = |address_match;
        match_compare_enable = 1'b0;
        match_compare = 8'd0;
        match_value = 8'd0;
        for (integer n = 0; n < MAX_CODES; n = n + 1) begin
            match_compare_enable = match_compare_enable |
                                   (selected_match[n] && code_compare_enable[n]);
            match_compare = match_compare |
                            (code_compare[n] & {8{selected_match[n]}});
            match_value = match_value |
                          (code_value[n] & {8{selected_match[n]}});
        end
        if (SUPPORTS_COMPARE)
            data_out = (response_valid &&
                        (!response_compare_enable || response_compare == data_in)) ?
                        response_value : data_in;
        else
            data_out = response_valid ? response_value : data_in;
    end

    // Decode the read address before the RAM response joins the path. The
    // following cycle only needs a byte compare and output mux, avoiding a
    // sixteen-code priority chain behind the synchronous program RAM.
    always @(posedge clk) begin
        if (reset) begin
            response_valid <= 1'b0;
            response_compare_enable <= 1'b0;
            response_compare <= 8'd0;
            response_value <= 8'd0;
        end else if (capture) begin
            response_valid <= match_valid;
            response_compare_enable <= match_compare_enable;
            response_compare <= match_compare;
            response_value <= match_value;
        end
    end
endmodule
