`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.10.2026 02:25:12
// Design Name: 
// Module Name: memory_scheduler
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

module memory_scheduler #(
    parameter int ADDR_WIDTH = 10
) (
    input  logic clk,
    input  logic rst_n,
    input  logic clk_enable,

    // Requests from the Tile Controller
    input  logic dma_start_req,
    input  logic dma_dest_sel_req,
    input  logic buf_swap_req,

    // Completion acknowledgements from Memory and Ping-Pong Buffers
    input  logic dma_done_in,
    input  logic buf_swap_done_in,

    // Computation and partial-sum control inputs
    input  logic tile_go,
    input  logic first_k_tile,
    input  logic last_k_tile_in,

    // DMA interface
    output logic dma_start,
    output logic dma_dest_sel,
    output logic dma_done_ack,

    // Ping-Pong Buffer interface
    output logic buf_swap,
    output logic buf_swap_done_ack,

    // Partial-Sum Buffer interface
    output logic acc_clr,
    output logic acc_en,
    output logic last_k_tile,

    // Scheduler status
    output logic busy,
    output logic done
);

    // Scheduler states
    typedef enum logic [1:0] {
        IDLE,
        WAIT_DMA,
        WAIT_SWAP
    } state_t;

    state_t state;

    // Hold the selected DMA destination during a transfer
    logic dma_dest_sel_reg;

    // Sequence DMA and buffer-swap transactions
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state              <= IDLE;
            dma_start          <= 1'b0;
            dma_dest_sel       <= 1'b0;
            dma_dest_sel_reg   <= 1'b0;
            dma_done_ack       <= 1'b0;
            buf_swap           <= 1'b0;
            buf_swap_done_ack  <= 1'b0;
            busy               <= 1'b0;
            done               <= 1'b0;
        end
        else if (clk_enable) begin
            // Default transaction outputs to inactive
            dma_start         <= 1'b0;
            dma_done_ack      <= 1'b0;
            buf_swap          <= 1'b0;
            buf_swap_done_ack <= 1'b0;
            done              <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;

                    // Give DMA requests priority over buffer swaps
                    if (dma_start_req) begin
                        dma_dest_sel_reg <= dma_dest_sel_req;
                        dma_dest_sel     <= dma_dest_sel_req;
                        dma_start        <= 1'b1;
                        busy             <= 1'b1;
                        state            <= WAIT_DMA;
                    end
                    else if (buf_swap_req) begin
                        buf_swap <= 1'b1;
                        busy     <= 1'b1;
                        state    <= WAIT_SWAP;
                    end
                end

                WAIT_DMA: begin
                    busy <= 1'b1;

                    // Wait for the active DMA transaction to finish
                    if (dma_done_in) begin
                        dma_done_ack <= 1'b1;
                        done         <= 1'b1;
                        busy         <= 1'b0;
                        state        <= IDLE;
                    end
                end

                WAIT_SWAP: begin
                    busy <= 1'b1;

                    // Wait until the buffer exchange is complete
                    if (buf_swap_done_in) begin
                        buf_swap_done_ack <= 1'b1;
                        done              <= 1'b1;
                        busy              <= 1'b0;
                        state             <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

    // Forward accumulation controls to the Partial-Sum Buffers
    always_comb begin
        acc_clr     = 1'b0;
        acc_en      = 1'b0;
        last_k_tile = 1'b0;

        if (clk_enable && tile_go) begin
            acc_clr     = first_k_tile;
            acc_en      = 1'b1;
            last_k_tile = last_k_tile_in;
        end
    end

endmodule


