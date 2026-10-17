`timescale 1ns/1ps
module mister_cheat_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg [128:0] code = 129'd0;
    reg capture = 0;
    reg [14:0] address = 0;
    reg [7:0] data_in = 0;
    wire [7:0] data_out;
    wire [7:0] hunchback_data_out;

    cvs_cheat_engine dut(.*);
    cvs_cheat_engine #(.SUPPORTS_COMPARE(1'b0)) hunchback_codes(
        .clk(clk),.reset(reset),.code(code),.capture(capture),.address(address),
        .data_in(data_in),.data_out(hunchback_data_out));

    task automatic install(input [31:0] flags, input [31:0] addr,
                           input [31:0] compare, input [31:0] value);
        begin
            @(negedge clk);
            code = {1'b1, flags, addr, compare, value};
            @(negedge clk);
            code = 129'd0;
        end
    endtask
    task automatic read_at(input [14:0] addr, input [7:0] value);
        begin
            @(negedge clk); address=addr; data_in=value; capture=1;
            @(negedge clk); capture=0;
            #1;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        reset = 0;
        install(32'h00000010, 32'h00001c84, 32'h00000000, 32'h00000005);
        read_at(15'h1c84,8'h02);
        if (data_out !== 8'h05) $fatal(1, "MRA byte replacement failed");
        read_at(15'h1c85,8'h02);
        #1;
        if (data_out !== 8'h02) $fatal(1, "cheat matched an unrelated address");

        install(32'h00000011, 32'h00001c85, 32'h00000003, 32'h00000009);
        read_at(15'h1c85,8'h03);
        if (data_out !== 8'h09) $fatal(1, "compare-enabled cheat failed to match");
        if (hunchback_data_out !== 8'h03)
            $fatal(1, "Hunchback profile accepted an unsupported compare code");
        data_in = 8'h04;
        #1;
        if (data_out !== 8'h04) $fatal(1, "compare-enabled cheat ignored compare");

        install(32'h00000010, 32'h00001c84, 32'h00000000, 32'h00000006);
        read_at(15'h1c84,8'h02);
        if (data_out !== 8'h06) $fatal(1, "last matching code did not take priority");

        reset = 1;
        @(negedge clk);
        reset = 0;
        data_in = 8'h02;
        read_at(15'h1c84,8'h02);
        #1;
        if (data_out !== 8'h02) $fatal(1, "reset did not clear installed codes");
        $display("PASS mister_cheat_tb");
        $finish;
    end
endmodule
