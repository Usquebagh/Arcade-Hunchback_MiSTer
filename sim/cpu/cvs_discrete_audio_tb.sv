// Independent numerical checks for the schematic-derived discrete audio model.
module cvs_discrete_audio_tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1;
    reg sample_ce = 1;
    reg [7:0] dac8 = 8'h00;
    reg [3:0] dac4 = 4'h0;
    reg [3:0] discrete = 4'h0;
    wire signed [15:0] pcm, triangle;
    wire n555, icl_square, byte_mix;
    wire [11:0] icl_hz;
    wire [15:0] env22, env10;
    cvs_discrete_audio dut(.clk(clk),.reset(reset),.sample_ce(sample_ce),.dac8(dac8),.dac4(dac4),
        .discrete(discrete),.pcm(pcm),.ne555_square(n555),.icl8038_square(icl_square),
        .icl8038_triangle(triangle),.icl8038_frequency_hz(icl_hz),.byte_dac_to_mix(byte_mix),
        .envelope_22_q16(env22),.envelope_10_q16(env10));

    integer i, transitions, rises, highs, low_hash, high_hash, off_hash, low_sample, switched_sample, lat2_swing;
    reg previous;
    integer fail_count = 0;
    task check(input bit pass, input [255:0] label_text, input integer expected, input integer observed);
        if (!pass) begin
            $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"expected\":%0d,\"observed\":%0d}",label_text,expected,observed);
            $fatal(1);
        end
    endtask
    task restart;
        begin
            @(negedge clk); reset=1; discrete=0; dac8=0; dac4=0;
            repeat(2) @(negedge clk);
            reset=0;
        end
    endtask
    task one_second_555;
        begin
            transitions=0; rises=0; highs=0; previous=n555;
            for(i=0;i<48000;i=i+1) begin
                @(posedge clk); #1;
                if(n555) highs=highs+1;
                if(n555!=previous) begin
                    transitions=transitions+1;
                    if(n555) rises=rises+1;
                end
                previous=n555;
            end
        end
    endtask
    initial begin
        restart();
        one_second_555();
        check(rises>=303 && rises<=305,"ne555_frequency_hz",304,rises);
        check(transitions>=606 && transitions<=610,"ne555_transitions_per_second",608,transitions);
        check(highs>=25600 && highs<=25800,"ne555_duty_high_samples",25674,highs);

        restart();
        transitions=0; previous=icl_square;
        for(i=0;i<48000;i=i+1) begin
            @(posedge clk); #1;
            if(icl_square!=previous) transitions=transitions+1;
            previous=icl_square;
        end
        check(icl_hz==56,"icl8038_nominal_frequency_hz",56,icl_hz);
        check(transitions>=111 && transitions<=113,"icl8038_nominal_cycles_per_second",112,transitions);
        discrete[0]=1; dac8=8'hff; #1;
        check(icl_hz==2096,"icl8038_fm_full_code_hz",2096,icl_hz);
        check(byte_mix==0,"lat4_routes_byte_dac_to_fm",0,byte_mix);
        discrete[0]=0; #1;
        check(byte_mix==1,"lat4_routes_byte_dac_to_mix",1,byte_mix);
        restart(); dac8=8'hff;
        repeat(2) @(posedge clk); #1; low_sample=pcm;
        discrete[0]=1;
        repeat(2) @(posedge clk); #1; switched_sample=pcm;
        check((low_sample-switched_sample)>10000,"lat4_switch_changes_actual_mix_route",10000,low_sample-switched_sample);

        // The four-bit resistor ladder preserves the schematic ratios and is
        // normalized so code 15 is near positive full-scale. Check both the
        // ordering and the measured SP_LAT2-only swing (code 0 to code 4).
        restart(); dac8=8'h80;
        repeat(2) @(posedge clk); #1; low_sample=pcm;
        restart(); dac8=8'h80; dac4=4'b0001; repeat(2) @(posedge clk); #1; switched_sample=pcm;
        check(switched_sample-low_sample>16000 && switched_sample-low_sample<18000,"dac4_12k_input_adds_to_mix",17057,switched_sample-low_sample);
        restart(); dac8=8'h80; dac4=4'b0010; repeat(2) @(posedge clk); #1; switched_sample=pcm;
        check(switched_sample-low_sample>9000 && switched_sample-low_sample<9700,"dac4_22k_weight_order",9303,switched_sample-low_sample);
        restart(); dac8=8'h80; dac4=4'b0100; repeat(2) @(posedge clk); #1; switched_sample=pcm;
        check(switched_sample-low_sample>4000 && switched_sample-low_sample<4700,"dac4_47k_weight_order",4355,switched_sample-low_sample);
        restart(); dac8=8'h80; dac4=4'b1000; repeat(2) @(posedge clk); #1; switched_sample=pcm;
        check(switched_sample-low_sample>1900 && switched_sample-low_sample<2200,"dac4_100k_weight_order",2046,switched_sample-low_sample);
        check(switched_sample-low_sample < 17057,"dac4_resistor_weight_order",17057,switched_sample-low_sample);
        restart(); dac8=8'h80; dac4=4'b0000; repeat(2) @(posedge clk); #1; low_sample=pcm;
        restart(); dac8=8'h80; dac4=4'b0100; repeat(2) @(posedge clk); #1; switched_sample=pcm;
        lat2_swing=switched_sample-low_sample;
        check(lat2_swing>4000 && lat2_swing<4700,"sp_lat2_toggle_audible_mix_swing",4355,lat2_swing);
        // The authenticated game trace leaves the byte DAC at code 0 while
        // toggling SP_LAT2. Verify the final discrete-module output still
        // changes by the ladder contribution instead of remaining railed.
        restart(); dac8=8'h00; dac4=4'b0000; repeat(2) @(posedge clk); #1; low_sample=pcm;
        restart(); dac8=8'h00; dac4=4'b0100; repeat(2) @(posedge clk); #1; switched_sample=pcm;
        check(low_sample < -28000,"observed_byte_dac_zero_baseline_below_-28k",-32768,low_sample);
        check(switched_sample>-32768 && switched_sample-low_sample>4000 && switched_sample-low_sample<4700,
            "observed_byte_dac_zero_sp_lat2_mix",4355,switched_sample-low_sample);

        // The envelope registers follow only their corresponding physical latch.
        restart(); discrete[2]=1;
        repeat(300000) @(posedge clk);
        #1; check(env22>16'd60000,"lat6_22s_rc_charge",65535,env22);
        discrete[2]=0;
        repeat(105600) @(posedge clk);
        #1; check(env22>=16'd22000 && env22<=16'd27000,"lat6_22s_exponential_decay",24100,env22);
        restart(); discrete[3]=1;
        repeat(120000) @(posedge clk);
        #1; check(env10>16'd58000,"lat7_10s_rc_charge",65535,env10);
        discrete[3]=0;
        repeat(48000) @(posedge clk);
        #1; check(env10>=16'd20000 && env10<=16'd26000,"lat7_10s_exponential_decay",24100,env10);

        // Check that each envelope's physical latch gates its signal into MIX2.
        restart(); dac8=8'h80; discrete[2]=1;
        repeat(300000) @(posedge clk);
        high_hash=0;
        for(i=0;i<512;i=i+1) begin @(posedge clk); #1; high_hash=high_hash+pcm; end
        discrete[2]=0;
        off_hash=0;
        for(i=0;i<512;i=i+1) begin @(posedge clk); #1; off_hash=off_hash+pcm; end
        check(high_hash!=off_hash,"lat6_gates_555_envelope_into_mix",high_hash,off_hash);
        restart(); dac8=8'h80; discrete[3]=1;
        repeat(120000) @(posedge clk);
        high_hash=0;
        for(i=0;i<512;i=i+1) begin @(posedge clk); #1; high_hash=high_hash+pcm; end
        discrete[3]=0;
        off_hash=0;
        for(i=0;i<512;i=i+1) begin @(posedge clk); #1; off_hash=off_hash+pcm; end
        check(high_hash!=off_hash,"lat7_gates_noise_envelope_into_mix",high_hash,off_hash);

        // A full-latch comparison catches wrong-bit routing of the square path.
        restart(); discrete=0; dac8=8'h00;
        low_hash=0;
        for(i=0;i<512;i=i+1) begin @(posedge clk); #1; low_hash=low_hash+pcm; end
        restart(); discrete=4'b0010; dac8=8'h00;
        high_hash=0;
        for(i=0;i<512;i=i+1) begin @(posedge clk); #1; high_hash=high_hash+pcm; end
        check(low_hash!=high_hash,"lat5_gates_icl_square_into_mix",low_hash,high_hash);
        $display("BDSM {\"status\":\"PASS\",\"ne555_hz\":%0d,\"ne555_duty_samples\":%0d,\"icl_base_hz\":56,\"icl_full_code_hz\":2096,\"sp_lat2_swing\":%0d,\"lat5_mix_delta\":%0d}",rises,highs,lat2_swing,high_hash-low_hash);
        $finish;
    end
endmodule
