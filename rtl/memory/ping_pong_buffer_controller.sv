`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.10.2026 07:25:57
// Design Name: 
// Module Name: ping_pong_buffer_controller
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

module ping_pong_buffer_controller (
    input  logic clk,
    input  logic rst_n,
    input  logic clk_enable,

    // Activation tile lifecycle events
    input  logic activation_tile_loaded,
    input  logic activation_tile_consumed,

    // Weight tile lifecycle events
    input  logic weight_tile_loaded,
    input  logic weight_tile_consumed,

    // Controls connected to the activation and weight buffers
    output logic activation_buf_swap,
    output logic weight_buf_swap,

    // Buffer ownership and DMA write permission
    output logic activation_active_bank,
    output logic weight_active_bank,
    output logic activation_load_enable,
    output logic weight_load_enable,

    // Status outputs
    output logic activation_tile_ready,
    output logic weight_tile_ready
);

    // Bit 0 represents Buffer A; bit 1 represents Buffer B.
    logic [1:0] activation_bank_ready;
    logic [1:0] weight_bank_ready;

    logic activation_swap_request;
    logic weight_swap_request;

    // Reset selects B as the initial read bank, leaving A available for loading.
    // A swap is allowed when the next bank is ready and the current bank
    // is either empty or has been consumed.
    always_comb begin
        activation_swap_request =
            activation_bank_ready[~activation_active_bank] && (!activation_bank_ready[activation_active_bank] || activation_tile_consumed);

        weight_swap_request = weight_bank_ready[~weight_active_bank] && (!weight_bank_ready[weight_active_bank] || weight_tile_consumed);
    end

    // Generate swap pulses and update bank ownership synchronously.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            activation_active_bank <= 1'b1;
            weight_active_bank     <= 1'b1;

            activation_bank_ready  <= 2'b00;
            weight_bank_ready      <= 2'b00;

            activation_buf_swap    <= 1'b0;
            weight_buf_swap        <= 1'b0;
        end
        else if (clk_enable) begin
            // Swap outputs are one-cycle pulses.
            activation_buf_swap <= activation_swap_request;
            weight_buf_swap     <= weight_swap_request;

            // Record newly completed tiles in the inactive bank.
            if (activation_tile_loaded)
                activation_bank_ready[~activation_active_bank] <= 1'b1;

            if (weight_tile_loaded)
                weight_bank_ready[~weight_active_bank] <= 1'b1;

            // Release the active bank when its tile has been consumed.
            if (activation_tile_consumed)
                activation_bank_ready[activation_active_bank] <= 1'b0;

            if (weight_tile_consumed)
                weight_bank_ready[weight_active_bank] <= 1'b0;

            // Update ownership when a swap is requested.
            if (activation_swap_request) begin
                activation_active_bank <= ~activation_active_bank;
                activation_bank_ready[activation_active_bank] <= 1'b0;
            end

            if (weight_swap_request) begin
                weight_active_bank <= ~weight_active_bank;
                weight_bank_ready[weight_active_bank] <= 1'b0;
            end
        end
        else begin
            activation_buf_swap <= 1'b0;
            weight_buf_swap     <= 1'b0;
        end
    end

    // Permit DMA writes only when the inactive bank is available.
    always_comb begin
        activation_load_enable = !activation_bank_ready[~activation_active_bank];

        weight_load_enable = !weight_bank_ready[~weight_active_bank];

        // The active tile is readable only when its bank is ready.
        activation_tile_ready = activation_bank_ready[activation_active_bank];

        weight_tile_ready = weight_bank_ready[weight_active_bank];
    end

endmodule

