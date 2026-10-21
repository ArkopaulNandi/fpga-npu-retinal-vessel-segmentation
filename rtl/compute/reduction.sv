`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 29.08.2026 01:51:35
// Design Name: 
// Module Name: reduction
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

module reduction #(
    parameter int ROWS      = 4,
    parameter int COLS      = 4,
    parameter int ACC_WIDTH = 32
) (
    input  logic clk,
    input  logic rst_n,             // Clears all running column accumulations.
    input logic accumulation_clear, // When asserted: current column PSUM is added to previous accumulation, When deasserted: current column PSUM starts a new accumulation.
    input logic accumulate_enable,
    // Partial sums from every PE.
    input logic [ROWS*COLS-1:0] pe_psum_valid,
    input logic signed [ROWS*COLS*ACC_WIDTH-1:0] pe_psum,
    // Current column reduction result.    
    output logic signed [COLS*ACC_WIDTH-1:0] reduced_psum,
    output logic [COLS-1:0] reduced_valid,
    // Registered accumulated result for each PE column.
    output logic signed [COLS*ACC_WIDTH-1:0] accumulated_result,
    output logic [COLS-1:0] accumulation_valid
);
    genvar col;

    generate
        for (col = 0; col < COLS; col = col + 1) begin : gen_column_reduction
            localparam int BOTTOM_PE_INDEX = ((ROWS - 1) * COLS) + col;
            // Extract the final PSUM of this column.
            assign reduced_psum[col*ACC_WIDTH +: ACC_WIDTH] = pe_psum[BOTTOM_PE_INDEX*ACC_WIDTH +: ACC_WIDTH];
            // Valid signal for the final PE in this column.
            assign reduced_valid[col] = pe_psum_valid[BOTTOM_PE_INDEX];
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst_n || accumulation_clear) begin
            accumulated_result <= '0;
            accumulation_valid <= '0;
        end else begin
            for (int i = 0; i < COLS; i = i + 1) begin
                if (reduced_valid[i]) begin
                    if (accumulate_enable) begin
                        accumulated_result[i*ACC_WIDTH +: ACC_WIDTH] <= accumulated_result[i*ACC_WIDTH +: ACC_WIDTH] + reduced_psum[i*ACC_WIDTH +: ACC_WIDTH];
                    end else begin
                        accumulated_result[i*ACC_WIDTH +: ACC_WIDTH] <= reduced_psum[i*ACC_WIDTH +: ACC_WIDTH];
                    end
                    accumulation_valid[i] <= 1'b1;
                end
            end
        end
    end
endmodule