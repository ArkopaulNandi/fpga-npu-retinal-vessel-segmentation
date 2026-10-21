`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 29.08.2026 00:37:24
// Design Name: 
// Module Name: pe_array_4x4
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

module pe_array_4x4 #(
    parameter int ROWS         = 4,
    parameter int COLS         = 4,
    parameter int INPUT_WIDTH  = 8,
    parameter int WEIGHT_WIDTH = 8,
    parameter int ACC_WIDTH    = 32
) (
    input  logic clk,
    input  logic rst_n,
    input  logic pe_reset,
    input  logic pe_enable,
    // PE control signals
    input logic [ROWS-1:0] act_en,
    input logic [ROWS-1:0] wload,
    input logic [ROWS-1:0] acc_en,
    input logic [ROWS-1:0] acc_clr,
    input logic [ROWS-1:0] psum_src,
    // Activation input
    input logic [ROWS-1:0] activation_valid_in,
    input logic signed [ROWS*INPUT_WIDTH-1:0] activation_in,
    // Weight input
    input logic signed [COLS*WEIGHT_WIDTH-1:0] weight_in,
    // Partial-sum input
    input logic [COLS-1:0] psum_valid_in,
    input logic signed [COLS*ACC_WIDTH-1:0] psum_in,
    // Activation output
    output logic [ROWS-1:0] activation_valid_out,
    output logic signed [ROWS*INPUT_WIDTH-1:0] activation_out,
    // Partial-sum output
    output logic [COLS-1:0] psum_valid_out,
    output logic signed [COLS*ACC_WIDTH-1:0] psum_out,
    // All PE PSUMs for reduction
    output logic [ROWS*COLS-1:0] pe_psum_valid,
    output logic signed [ROWS*COLS*ACC_WIDTH-1:0] pe_psum,
    // Stationary weights for debug/verification
    output logic signed [ROWS*COLS*WEIGHT_WIDTH-1:0] weight_out
);
    // Internal systolic buses
    logic signed [INPUT_WIDTH-1:0] activation_bus [0:ROWS-1][0:COLS-1];
    logic activation_valid_bus [0:ROWS-1][0:COLS-1];
    logic signed [ACC_WIDTH-1:0] psum_bus [0:ROWS-1][0:COLS-1];
    logic psum_valid_bus [0:ROWS-1][0:COLS-1];

    genvar row;
    genvar col;
    // 4x4 PE Array
    generate
        for (row = 0; row < ROWS; row = row + 1) begin : gen_rows
            for (col = 0; col < COLS; col = col + 1) begin : gen_cols
                localparam int PE_INDEX = row * COLS + col;
                logic signed [INPUT_WIDTH-1:0] pe_activation_in;
                logic pe_activation_valid_in;
                logic signed [ACC_WIDTH-1:0] pe_psum_in;
                logic pe_psum_valid_in;
                // Activation routing
                if (col == 0) begin : gen_left_activation
                    assign pe_activation_in = activation_in[row*INPUT_WIDTH +: INPUT_WIDTH];
                    assign pe_activation_valid_in = activation_valid_in[row];
                end else begin : gen_internal_activation
                    assign pe_activation_in = activation_bus[row][col-1];
                    assign pe_activation_valid_in = activation_valid_bus[row][col-1];
                end
                // PSUM routing
                if (row == 0) begin : gen_top_psum
                    assign pe_psum_in = psum_in[col*ACC_WIDTH +: ACC_WIDTH];
                    assign pe_psum_valid_in = psum_valid_in[col];
                end else begin : gen_internal_psum
                    assign pe_psum_in = psum_bus[row-1][col];
                    assign pe_psum_valid_in = psum_valid_bus[row-1][col];
                end
                // PE instance
                pe #(
                    .INPUT_WIDTH  (INPUT_WIDTH),
                    .WEIGHT_WIDTH (WEIGHT_WIDTH),
                    .ACC_WIDTH    (ACC_WIDTH)
                ) u_pe (
                    .clk                  (clk),
                    .rst_n                (rst_n),
                    .pe_reset             (pe_reset),
                    .pe_enable            (pe_enable),
                    // Row-broadcast control
                    .act_en               (act_en[row]),
                    .wload                (wload[row]),
                    .acc_en               (acc_en[row]),
                    .acc_clr              (acc_clr[row]),
                    .psum_src             (psum_src[row]),
                    // Activation
                    .activation_valid     (pe_activation_valid_in),
                    .activation_in        (pe_activation_in),
                    // Column-broadcast weight
                    .weight_in            (weight_in[col*WEIGHT_WIDTH +: WEIGHT_WIDTH]),
                    // PSUM
                    .psum_valid           (pe_psum_valid_in),
                    .psum_in              (pe_psum_in),
                    // Outputs
                    .activation_valid_out (activation_valid_bus[row][col]),
                    .activation_out       (activation_bus[row][col]),
                    .psum_valid_out       (psum_valid_bus[row][col]),
                    .psum_out             (psum_bus[row][col]),
                    .weight_out           (weight_out[PE_INDEX*WEIGHT_WIDTH +: WEIGHT_WIDTH])
                );
                // Expose PE PSUM to reduction block
                assign pe_psum_valid[PE_INDEX] = psum_valid_bus[row][col];
                assign pe_psum[PE_INDEX*ACC_WIDTH +: ACC_WIDTH] = psum_bus[row][col];
            end
        end
    endgenerate
    // Right-edge activation outputs
    generate
        for (row = 0; row < ROWS; row = row + 1) begin : gen_activation_outputs
            assign activation_valid_out[row] = activation_valid_bus[row][COLS-1];
            assign activation_out[row*INPUT_WIDTH +: INPUT_WIDTH] = activation_bus[row][COLS-1];
        end
    endgenerate
    // Bottom-edge PSUM outputs
    generate
        for (col = 0; col < COLS; col = col + 1) begin : gen_psum_outputs
            assign psum_valid_out[col] = psum_valid_bus[ROWS-1][col];
            assign psum_out[col*ACC_WIDTH +: ACC_WIDTH] = psum_bus[ROWS-1][col];
        end
    endgenerate
endmodule
