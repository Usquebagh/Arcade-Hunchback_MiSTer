// Synthetic AC-coupling contract: remove DC, preserve the observed SP_LAT2
// transition as a centered audio waveform. The 22.4 Hz corner is a model
// assumption; it is not a measured board transfer function.
module cvs_audio_dc_blocker_tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1;
    reg sample_ce = 0;
    reg signed [15:0] x = 0;
    reg signed [15:0] speech = 0;
    wire signed [15:0] y;
    wire signed [15:0] audio_out;
    integer i, min_y, max_y, midpoint, peak_to_peak, mix_min, mix_max;

    cvs_audio_dc_blocker dut(.clk(clk),.reset(reset),.sample_ce(sample_ce),.x(x),.y(y));
    cvs_audio_output mix_dut(.clk(clk),.reset(reset),.sample_ce(sample_ce),
        .speech_pcm(speech),.discrete_pcm(x),.audio_pcm(audio_out));

    task tick;
        begin
            @(negedge clk); sample_ce=1;
            @(posedge clk); #1; sample_ce=0;
        end
    endtask

    task check(input bit pass, input [255:0] label_text, input integer expected, input integer observed);
        if (!pass) begin
            $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"expected\":%0d,\"observed\":%0d}",label_text,expected,observed);
            $fatal(1);
        end
    endtask

    initial begin
        repeat(2) @(negedge clk);
        reset=0;
        x=-16'sd32768;
        for(i=0;i<6000;i=i+1) tick();
        check(y>=-8 && y<=8,"dc_bias_removed",0,y);
        check(audio_out>=-8 && audio_out<=8,"idle_mix_after_coupling",0,audio_out);

        // Speech is not put through the DAC high-pass. It must retain its
        // complete signed amplitude after the discrete path settles.
        x=0; speech=16'sd12345;
        for(i=0;i<6000;i=i+1) tick();
        check(audio_out==speech,"speech_positive_passes_unattenuated",12345,audio_out);
        speech=-16'sd10000; tick();
        check(audio_out==speech,"speech_negative_passes_unattenuated",-10000,audio_out);

        min_y=32767; max_y=-32768; mix_min=32767; mix_max=-32768;
        // Trace-derived byte-DAC idle code 0 plus SP_LAT2 toggling between
        // four-bit codes 0 and 4. The AC-coupled path should now be centered
        // around zero. Also verify the effect rides on speech without clipping.
        speech=16'sd12000;
        for(i=0;i<80;i=i+1) begin
            x=16'sd0;
            repeat(14) begin
                tick();
                if(i>=30) begin
                    if(y<min_y) min_y=y;
                    if(y>max_y) max_y=y;
                    if(audio_out<mix_min) mix_min=audio_out;
                    if(audio_out>mix_max) mix_max=audio_out;
                    check(audio_out<32767 && audio_out>-32768,"speech_plus_dac_never_clips",1,audio_out);
                end
            end
            x=16'sd4355;
            repeat(14) begin
                tick();
                if(i>=30) begin
                    if(y<min_y) min_y=y;
                    if(y>max_y) max_y=y;
                    if(audio_out<mix_min) mix_min=audio_out;
                    if(audio_out>mix_max) mix_max=audio_out;
                    check(audio_out<32767 && audio_out>-32768,"speech_plus_dac_never_clips",1,audio_out);
                end
            end
        end
        peak_to_peak=max_y-min_y;
        midpoint=(max_y+min_y)/2;
        check((mix_min+mix_max)/2>=11700 && (mix_min+mix_max)/2<=12300,
            "speech_dc_preserved_with_effect",12000,(mix_min+mix_max)/2);
        check(mix_max-mix_min>=4000 && mix_max-mix_min<=4700,"sp_lat2_rides_on_speech",4355,mix_max-mix_min);
        check(peak_to_peak>=4000 && peak_to_peak<=4700,"sp_lat2_ac_swing",4355,peak_to_peak);
        check(midpoint>=-300 && midpoint<=300,"sp_lat2_centered",0,midpoint);
        $display("BDSM {\"status\":\"PASS\",\"held_dc_output\":0,\"speech_passthrough\":true,\"sp_lat2_peak_to_peak\":%0d,\"sp_lat2_midpoint\":%0d,\"speech_plus_dac\":%0d,\"assumed_corner_hz\":22}",peak_to_peak,midpoint,audio_out);
        $finish;
    end
endmodule
