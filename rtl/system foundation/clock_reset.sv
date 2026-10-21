
`timescale 1ns/1ps

module clock_reset (
    input  logic aclk,
    input  logic aresetn,
    input  logic soft_rst,

    output logic clk,
    output logic rst_n
);
    // Internal reset request
    logic reset_req_n;
    assign reset_req_n = aresetn & ~soft_rst;
    // Clock distribution
    assign clk = aclk;
    // Two-flip-flop reset synchronizer
    logic rst_sync_ff1;
    logic rst_sync_ff2;

    always_ff @(posedge aclk or negedge reset_req_n) begin
        if (!reset_req_n) begin
            rst_sync_ff1 <= 1'b0;
            rst_sync_ff2 <= 1'b0;
        end
        else begin
            rst_sync_ff1 <= 1'b1;
            rst_sync_ff2 <= rst_sync_ff1;
        end
    end

    // Synchronized reset output
    assign rst_n = rst_sync_ff2;

endmodule
