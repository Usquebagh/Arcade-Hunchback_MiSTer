// SPDX-License-Identifier: BSD-3-Clause
// MAME-compatible digital boundary; physical TMS/level/ROM clocks unresolved.
module cvs_speech_bus (
    input wire clk,reset,ready,req,wr,memory_space,
    input wire [14:0] address,
    input wire [7:0] din,
    input wire [6:0] command,
    input wire ctl_status,
    output wire ack,
    output wire [7:0] dout,
    input wire program_dl_wr,
    input wire [10:0] program_dl_addr,
    input wire data_dl_wr,
    input wire [11:0] data_dl_addr,
    input wire [7:0] dl_data,
    output reg [2:0] control_latches,
    output wire [3:0] ctl,
    output reg pdc,ctl_wr,pdc_wr,
    input wire bit_req,
    output wire bit_ready,
    output reg bit_valid,bit_data,
    output reg [15:0] bit_address
);
    reg [7:0] data_rom[0:4095];
    wire accepted=req && ready;
    wire write_transfer=accepted && wr && memory_space && !reset;
    wire pointer_write=write_transfer && (address==15'h1d00 || address==15'h1d40);
    wire program_collision=program_dl_wr && program_dl_addr==address[10:0];
    wire program_read=accepted && !wr && memory_space && address<15'h0800 && !program_collision;
    wire [7:0] program_q;
    reg program_response_q;
    reg [7:0] response_data_q;
    wire [7:0] serial_byte=data_dl_wr && data_dl_addr==bit_address[14:3] ? dl_data : data_rom[bit_address[14:3]];

    cvs_sync_rom #(.ADDR_WIDTH(11),.DEPTH(2048)) program_rom (
        .clk(clk),.write_enable(program_dl_wr),.write_address(program_dl_addr),.write_data(dl_data),
        .read_enable(program_read),.read_address(address[10:0]),.read_data(program_q));
    assign dout=program_response_q ? program_q : response_data_q;
    assign ack=ready;
    assign bit_ready=!reset && !pointer_write;
    assign ctl={control_latches[1],control_latches[2],control_latches[1],1'b0};
    always @(posedge clk)begin
        if(data_dl_wr)data_rom[data_dl_addr]<=dl_data;
        if(accepted && !wr)begin
            if(!memory_space)begin program_response_q<=1'b0;response_data_q<=8'hff;end
            else if(address<15'h0800)begin
                if(program_collision)begin program_response_q<=1'b0;response_data_q<=dl_data;end
                else program_response_q<=1'b1;
            end else if(address==15'h1d80)begin program_response_q<=1'b0;response_data_q<={!ctl_status,command};end
            else begin program_response_q<=1'b0;response_data_q<=8'hff;end
        end
        ctl_wr<=1'b0;pdc_wr<=1'b0;bit_valid<=1'b0;
        if(reset)begin
            control_latches<=3'd0;pdc<=1'b0;bit_address<=16'd0;bit_data<=1'b0;
        end else begin
            if(write_transfer)begin
                if(address==15'h1d00)bit_address<={bit_address[15:11],din,3'd0};
                else if(address==15'h1d40)bit_address<={din[4:0],bit_address[10:0]};
                else if(address>=15'h1ddc && address<=15'h1dde)begin
                    control_latches[address[1:0]]<=!din[7];ctl_wr<=1'b1;
                end else if(address==15'h1ddf)begin pdc<=!din[7];pdc_wr<=1'b1;end
            end
            if(bit_req && bit_ready)begin
                bit_data<=serial_byte[bit_address[2:0]];bit_valid<=1'b1;
                bit_address<={1'b0,bit_address[14:0]}+16'd1;
            end
        end
    end
endmodule
