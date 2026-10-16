// Interface-only shell stubs for static elaboration; never used in behavior tests.
module hps_io # (parameter CONF_STR="") (
    input wire clk_sys,
    inout wire [45:0] HPS_BUS,
    output wire [45:0] EXT_BUS,
    output wire [21:0] gamma_bus,
    output wire forced_scandoubler,
    output wire [1:0] buttons,
    output wire [127:0] status,
    input wire status_menumask,
    output wire ioctl_download,
    output wire ioctl_wr,
    output wire [26:0] ioctl_addr,
    output wire [7:0] ioctl_dout,
    output wire [15:0] ioctl_index,
    input wire ioctl_wait,
    output wire [31:0] joystick_0,
    output wire [31:0] joystick_1,
    input wire video_rotated,
    input wire new_vmode
);
    assign EXT_BUS='0;assign gamma_bus='0;assign forced_scandoubler=0;
    assign buttons=0;assign status=0;assign ioctl_download=0;assign ioctl_wr=0;
    assign ioctl_addr=0;assign ioctl_dout=0;assign ioctl_index=0;
    assign joystick_0=0;assign joystick_1=0;
endmodule

module pll(input wire refclk,rst,output wire outclk_0,locked);
    assign outclk_0=refclk;assign locked=1'b1;
endmodule
