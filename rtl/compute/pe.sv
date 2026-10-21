`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 29.08.2026 00:00:27
// Design Name: 
// Module Name: pe
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


module pe #(
    parameter int INPUT_WIDTH  = 8,
    parameter int WEIGHT_WIDTH = 8,
    parameter int ACC_WIDTH    = 32
) (
    // Clock and reset
    input  logic clk,
    input  logic rst_n,    
    input  logic pe_reset,  // PE-local reset
    input  logic pe_enable, // Global PE enable
    // PE Control Signals
    input  logic act_en,    // Enables the activation input register.
    input  logic wload,     // Loads a new stationary weight.
    input  logic acc_en,    // Enables MAC/PSUM operation.
    input  logic acc_clr,   // Clears the local PSUM register.
    // Selects PSUM source: 1'b0 -> incoming PSUM from PE above, 1'b1 -> local PSUM 
    input  logic psum_src,
    // Activation input
    input  logic activation_valid,
    input  logic signed [INPUT_WIDTH-1:0] activation_in,
    // Weight preload input
    input  logic signed [WEIGHT_WIDTH-1:0] weight_in,
    // Partial-sum input from PE above
    input  logic psum_valid,
    input logic signed [ACC_WIDTH-1:0] psum_in,
    // Activation output to PE on the right
    output logic activation_valid_out,
    output logic signed [INPUT_WIDTH-1:0] activation_out,
    // Partial-sum output to PE below
    output logic psum_valid_out,
    output logic signed [ACC_WIDTH-1:0] psum_out,
    // Stationary weight observation/debug output
    output logic signed [WEIGHT_WIDTH-1:0] weight_out
);
    // Local PE Registers
    logic signed [INPUT_WIDTH-1:0] activation_reg;  // Activation register.
    logic activation_reg_valid;                     // Valid bit associated with activation_reg.
    logic signed [WEIGHT_WIDTH-1:0] weight_reg;     // Stationnary weight register.
    logic signed [ACC_WIDTH-1:0] psum_reg;          // Partial-sum register.
    logic psum_reg_valid;                           // Valid bit associated with psum_reg.
    // PSUM Source Selection
    logic signed [ACC_WIDTH-1:0] mac_psum_in;       // Selected PSUM value entering the MAC.
    logic mac_psum_valid;                           // Valid signal corresponding to selected PSUM source.
    
    always_comb begin
        if (psum_src) begin
            // Local feedback.
            mac_psum_in    = psum_reg;
            mac_psum_valid = psum_reg_valid;
        end
        else begin
            // Incoming PSUM from PE above.
            mac_psum_in    = psum_in;
            mac_psum_valid = psum_valid;
        end
    end
    // MAC Interface
    logic mac_valid;
    logic mac_valid_out;
    logic signed [ACC_WIDTH-1:0] mac_psum_out;
    
    assign mac_valid = pe_enable && acc_en && activation_reg_valid && mac_psum_valid; // MAC is allowed to operate only when: 1. PE is enabled, 2. Accumulation is enabled, 3. Activation is valid, 4. Selected PSUM source is valid.
    // MAC Instance
    mac_unit #(
        .INPUT_WIDTH  (INPUT_WIDTH),
        .WEIGHT_WIDTH (WEIGHT_WIDTH),
        .ACC_WIDTH    (ACC_WIDTH)
    ) u_mac (
        .valid_in      (mac_valid),
        .activation_in (activation_reg),
        .weight_in     (weight_reg),
        .psum_in       (mac_psum_in),
        .valid_out     (mac_valid_out),
        .psum_out      (mac_psum_out)
    );
    // Sequential PE State
    always_ff @(posedge clk) begin
        // Reset
        if (!rst_n || pe_reset) begin
            activation_reg       <= '0;
            activation_reg_valid <= 1'b0;
            weight_reg           <= '0;
            psum_reg             <= '0;
            psum_reg_valid       <= 1'b0;
        end else begin
            // Weight Register
            // Weight is loaded only when: 1. PE is enabled, 2. WlLoad is asserted.
            // Once loaded, the weight remains stationary.
            if (pe_enable && wload) begin
                weight_reg <= weight_in;
            end
            // Activation Register
            // Activation enters from the west and is registered before being forwarded to the PE on the right.
            if (pe_enable && act_en) begin
                activation_reg       <= activation_in;
                activation_reg_valid <= activation_valid;
            end
            // PSUM Register
            // AccClr has priority over accumulation.
            if (acc_clr) begin
                psum_reg       <= '0;
                psum_reg_valid <= 1'b0;
            end else if (pe_enable && acc_en) begin
                // Valid MAC result becomes the new PSUM.
                if (mac_valid_out) begin
                    psum_reg       <= mac_psum_out;
                    psum_reg_valid <= 1'b1;
                end else begin
                    psum_reg_valid <= 1'b0;
                end
            end
        end
    end
    // Systolic Routing
    // Activation travels horizontally: PE(i,j) -> PE(i,j+1)
    assign activation_out       = activation_reg;
    assign activation_valid_out = activation_reg_valid;
    // Partial sum travels vertically: PE(i,j) -> PE(i+1,j)
    assign psum_out       = psum_reg;
    assign psum_valid_out = psum_reg_valid;
    // Weight Observation
    assign weight_out = weight_reg;
endmodule