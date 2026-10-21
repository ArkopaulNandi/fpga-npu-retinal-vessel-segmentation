`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.08.2026 23:11:12
// Design Name: 
// Module Name: mac_unit
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mac_unit #(
    parameter int INPUT_WIDTH = 8,
    parameter int WEIGHT_WIDTH = 8,
    parameter int ACC_WIDTH = 32
) (
    input  logic                             valid_in,
    input  logic signed [INPUT_WIDTH-1:0]    activation_in,
    input  logic signed [WEIGHT_WIDTH-1:0]   weight_in,
    input  logic signed [ACC_WIDTH-1:0]      psum_in,

    output logic                             valid_out,
    output logic signed [ACC_WIDTH-1:0]      psum_out
);
    // ------------------------------------------------------------------------
    // Internal signals
    // ------------------------------------------------------------------------
    localparam int PRODUCT_WIDTH = INPUT_WIDTH + WEIGHT_WIDTH;
    logic signed [PRODUCT_WIDTH-1:0] product;
    logic signed [ACC_WIDTH-1:0]     product_ext;
    // ------------------------------------------------------------------------
    // Multiply
    // ------------------------------------------------------------------------
    assign product = activation_in * weight_in;
    // ------------------------------------------------------------------------
    // Sign-extension of multiplication result to accumulator width
    // ------------------------------------------------------------------------
    assign product_ext = {{(ACC_WIDTH-PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product};
    // ------------------------------------------------------------------------
    // Accumulate
    // ------------------------------------------------------------------------
    always_comb begin
        if (valid_in)
            psum_out = psum_in + product_ext;
        else
            psum_out = psum_in;
    end
    // ------------------------------------------------------------------------
    // Valid propagation
    // ------------------------------------------------------------------------
    assign valid_out = valid_in;
endmodule
