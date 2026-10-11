// SPDX-License-Identifier: BSD-3-Clause
// Four-object PVI subset and status; docs/s2636.md records excluded functions.
module cvs_s2636_objects (
    input wire clk, reset,
    input wire cpu_rd, cpu_wr,
    input wire [7:0] cpu_addr, cpu_din,
    output reg [7:0] cpu_dout,
    input wire vrst, line_start, ce_pixel, intack,
    input wire [7:0] pixel_x,
    output reg [3:0] object_mask,
    output reg [2:0] pixel_colour,
    output wire pixel_present,
    output reg irq
);
    reg [7:0] registers [0:255];
    wire [7:0] bus_addr = cpu_addr[7:6] == 2'b11 ? {4'hc,cpu_addr[3:0]} : cpu_addr;
    function automatic stored(input [7:0] address);
        stored = address < 8'h2e || (address >= 8'h40 && address <= 8'h6d) ||
                 (address >= 8'h80 && address <= 8'had) ||
                 (address >= 8'hc0 && address <= 8'hc3) ||
                 (address >= 8'hc6 && address <= 8'hc9);
    endfunction
    function automatic [7:0] base_address(input integer object_index);
        case (object_index)
            0: base_address=8'h00;
            1: base_address=8'h10;
            2: base_address=8'h20;
            default: base_address=8'h40;
        endcase
    endfunction
    reg [7:0] status_ca, status_cb;
    always @* begin
        if (bus_addr == 8'hca) cpu_dout = status_ca;
        else if (bus_addr == 8'hcb) cpu_dout = status_cb;
        else if (stored(bus_addr)) cpu_dout = registers[bus_addr];
        else cpu_dout = 8'hff;
    end
    reg previous_vrst, field_valid;
    reg [8:0] wait_lines [0:3];
    reg [6:0] next_row [0:3], render_row [0:3];
    reg [1:0] scale [0:3];
    reg in_object [0:3], duplicate_mode [0:3];
    reg active_line [0:3], active_duplicate [0:3];
    reg [7:0] duplicate_hc [0:3];
    reg [3:0] hits, complete_events;
    reg [2:0] mixed_colour;
    reg [5:0] collision_events;
    reg [7:0] ca_next, cb_next;
    reg irq_next;
    assign pixel_present = |object_mask;
    // Geometric sampling of the current line. Engine state is updated only on
    // line_start; each accepted pixel sees the state prepared on an earlier edge.
    always @* begin : pixels
        reg [7:0] base, hc, shape, shape_addr;
        reg [8:0] distance;
        reg [2:0] colour, column;
        reg [3:0] row_number;
        hits=4'd0;
        mixed_colour=3'd0;
        for (integer i=0;i<4;i=i+1) begin
            base=base_address(i);
            hc=active_duplicate[i] ? duplicate_hc[i] : registers[base+8'ha];
            distance={1'b0,pixel_x}-{1'b0,hc};
            row_number=4'(render_row[i] >> scale[i]);
            shape_addr=base+{4'd0,row_number};
            shape=registers[shape_addr];
            column=3'(distance >> scale[i]);
            colour=3'(registers[i<2 ? 8'hc1 : 8'hc2] >> ((i%2==0) ? 3 : 0));
            if (field_valid && !vrst && active_line[i] && pixel_x<8'd227 &&
                pixel_x>=hc && distance<(9'd8 << scale[i]) && shape[3'd7-column]) begin
                hits[i]=1'b1;
                mixed_colour=mixed_colour | colour;
            end
        end
    end
    always @* begin
        complete_events=4'd0;
        for (integer i=0;i<4;i=i+1)
            if (field_valid && !vrst && line_start && in_object[i] &&
                next_row[i]==((7'd10 << scale[i])-7'd1))
                complete_events[3-i]=1'b1;
        collision_events={hits[0]&hits[1],hits[0]&hits[2],hits[0]&hits[3],
                          hits[1]&hits[2],hits[1]&hits[3],hits[2]&hits[3]};
        ca_next=status_ca;
        cb_next=status_cb;
        irq_next=irq;
        if (cpu_rd && bus_addr==8'hca) ca_next=8'd0;
        if (cpu_rd && bus_addr==8'hcb) cb_next=8'd0;
        if (intack) irq_next=1'b0;
        if (ce_pixel && !vrst) cb_next=cb_next | {2'b00,collision_events};
        ca_next=ca_next | {4'd0,complete_events};
        if (|complete_events) irq_next=1'b1;
        if (vrst && !previous_vrst) begin
            cb_next=cb_next | 8'h40;
            irq_next=1'b1;
        end
        if (!vrst && previous_vrst) begin
            ca_next=8'd0;
            cb_next=8'd0;
            irq_next=1'b0;
        end
    end
    always @(posedge clk) begin
        if (cpu_wr && !reset && stored(bus_addr)) registers[bus_addr] <= cpu_din;
        if (reset) begin
            previous_vrst<=1'b0;
            field_valid<=1'b0;
            status_ca<=8'd0;
            status_cb<=8'd0;
            irq<=1'b0;
            object_mask<=4'd0;
            pixel_colour<=3'd0;
            for (integer i=0;i<4;i=i+1) begin
                wait_lines[i]<=9'd0;
                next_row[i]<=7'd0;
                render_row[i]<=7'd0;
                scale[i]<=2'd0;
                in_object[i]<=1'b0;
                duplicate_mode[i]<=1'b0;
                active_line[i]<=1'b0;
                active_duplicate[i]<=1'b0;
                duplicate_hc[i]<=8'd0;
            end
        end else begin
            previous_vrst<=vrst;
            status_ca<=ca_next;
            status_cb<=cb_next;
            irq<=irq_next;
            if (ce_pixel) begin
                object_mask<=hits;
                pixel_colour<=mixed_colour;
            end
            if (vrst) begin
                field_valid<=1'b0;
                for (integer i=0;i<4;i=i+1) active_line[i]<=1'b0;
            end else if (previous_vrst) begin
                field_valid<=1'b1;
                for (integer i=0;i<4;i=i+1) begin
                    wait_lines[i]<={1'b0,registers[base_address(i)+8'hc]};
                    scale[i]<=registers[8'hc0][i*2 +: 2];
                    in_object[i]<=1'b0;
                    next_row[i]<=7'd0;
                    duplicate_mode[i]<=1'b0;
                    active_line[i]<=1'b0;
                end
            end else if (line_start && field_valid) begin
                for (integer i=0;i<4;i=i+1) begin
                    active_duplicate[i]<=duplicate_mode[i];
                    duplicate_hc[i]<=registers[base_address(i)+8'hb];
                    if (in_object[i]) begin
                        active_line[i]<=1'b1;
                        render_row[i]<=next_row[i];
                        if (complete_events[3-i]) begin
                            in_object[i]<=1'b0;
                            next_row[i]<=7'd0;
                            duplicate_mode[i]<=1'b1;
                            wait_lines[i]<={1'b0,registers[base_address(i)+8'hd]}+9'd1;
                        end else next_row[i]<=next_row[i]+7'd1;
                    end else if (wait_lines[i]==9'd0) begin
                        active_line[i]<=1'b1;
                        render_row[i]<=7'd0;
                        next_row[i]<=7'd1;
                        in_object[i]<=1'b1;
                    end else begin
                        active_line[i]<=1'b0;
                        wait_lines[i]<=wait_lines[i]-9'd1;
                    end
                end
            end
        end
    end
endmodule
