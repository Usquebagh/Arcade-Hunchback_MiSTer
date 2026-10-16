// Actual MiSTer-input mapper connected to the real main/video machine hierarchy.
// Used by the private-ROM input regression; no internal port bits are forced.
module cvs_hps_coin_machine (
    input wire clk, reset, reset_na, video_reset, scan_run, ready,
    input wire dl_wr,
    input wire [15:0] dl_addr,
    input wire [7:0] dl_data,
    input wire [31:0] joystick_0, joystick_1,
    input wire [7:0] in2, in3, dsw1, dsw2,
    output wire [7:0] in0, in1,
    output wire pixel_valid, pixel_ce_all, display_enable,
    output wire [7:0] out_x, out_y, red, green, blue,
    output wire [2:0] raw_pixel, pvi_irq,
    output wire [3:0] palette_index,
    output wire bullet_present, background_collision, hsync_n, vsync_n,
    output wire [7:0] collision_events, collision, video_fx, audio_command,
    output wire audio_trigger, intack,
    output wire req, wr, memory_space, extended, data_port, flag,
    output wire [14:0] address,
    output wire [7:0] write_data, read_data,
    output wire [1:0] phase,
    output wire [7:0] h_count,
    output wire [8:0] v_count
);
    cvs_mister_input controls(.joystick_0(joystick_0),.joystick_1(joystick_1),.in0(in0),.in1(in1));
    cvs_machine machine (
        .clk(clk),.reset(reset),.reset_na(reset_na),.video_reset(video_reset),
        .scan_run(scan_run),.ready(ready),.dl_wr(dl_wr),.dl_addr(dl_addr),.dl_data(dl_data),
        .in0(in0),.in1(in1),.in2(in2),.in3(in3),.dsw1(dsw1),.dsw2(dsw2),
        .pixel_valid(pixel_valid),.pixel_ce_all(pixel_ce_all),.display_enable(display_enable),
        .out_x(out_x),.out_y(out_y),.red(red),.green(green),.blue(blue),
        .raw_pixel(raw_pixel),.pvi_irq(pvi_irq),.palette_index(palette_index),
        .bullet_present(bullet_present),.background_collision(background_collision),
        .hsync_n(hsync_n),.vsync_n(vsync_n),.collision_events(collision_events),
        .collision(collision),.video_fx(video_fx),.audio_command(audio_command),
        .audio_trigger(audio_trigger),.intack(intack),.req(req),.wr(wr),
        .memory_space(memory_space),.extended(extended),.data_port(data_port),
        .flag(flag),.address(address),.write_data(write_data),.read_data(read_data),
        .phase(phase),.h_count(h_count),.v_count(v_count)
    );
endmodule
