// SPDX-License-Identifier: BSD-3-Clause
// Actual filter/quantizer plus independently driven exhaustive quantizer probe.
module cvs_tms5100_lattice_tb (
    input wire clk,reset,clear,sample_req,
    input wire [6:0] energy,
    input wire signed [7:0] excitation,
    input wire [99:0] coefficients,
    input wire signed [14:0] probe_raw,
    output wire signed [15:0] probe_pcm,
    output wire sample_ready,busy,sample_valid,protocol_error,
    output wire signed [14:0] raw_sample,
    output wire signed [15:0] pcm_sample
);
    cvs_tms5100_lattice filter(.clk(clk),.reset(reset),.clear(clear),.sample_req(sample_req),
        .energy(energy),.excitation(excitation),.coefficients(coefficients),
        .sample_ready(sample_ready),.busy(busy),.sample_valid(sample_valid),
        .protocol_error(protocol_error),.raw_sample(raw_sample),.pcm_sample(pcm_sample));
    cvs_tms5100_pcm probe(.raw_sample(probe_raw),.pcm_sample(probe_pcm));
endmodule
