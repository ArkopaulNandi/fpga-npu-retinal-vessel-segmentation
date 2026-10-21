`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.10.2026 07:20:15
// Design Name: 
// Module Name: weight_buffer
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

module weight_buffer #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH = 1024,
    parameter int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  clk_enable,

    // DMA write interface
    input  logic                  weight_write,
    input  logic [ADDR_WIDTH-1:0] weight_wr_addr,
    input  logic [DATA_WIDTH-1:0] weight_data_in,

    // CNM or scheduler read interface
    input  logic                  weight_read,
    input  logic [ADDR_WIDTH-1:0] weight_rd_addr,
    output logic [DATA_WIDTH-1:0] weight_data_out,
    output logic                  weight_valid,

    // Tile Controller ping-pong control
    input  logic                  buf_swap,
    output logic                  tile_ready,
    output logic                  active_bank
);

    // Bank A and Bank B store separate weight tiles.
    logic [DATA_WIDTH-1:0] buffer_a [0:DEPTH-1];
    logic [DATA_WIDTH-1:0] buffer_b [0:DEPTH-1];

    // Reset selects B for reading and A for loading.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            active_bank     <= 1'b1;
            tile_ready      <= 1'b0;
            weight_data_out <= '0;
            weight_valid    <= 1'b0;
        end
        else if (clk_enable) begin
            // Write only to the bank that is not currently active for reading.
            if (weight_write && active_bank)
                buffer_a[weight_wr_addr] <= weight_data_in;
            else if (weight_write && !active_bank)
                buffer_b[weight_wr_addr] <= weight_data_in;

            // Read from the active bank only after a tile is ready.
            if (weight_read && tile_ready) begin
                if (active_bank)
                    weight_data_out <= buffer_b[weight_rd_addr];
                else
                    weight_data_out <= buffer_a[weight_rd_addr];

                weight_valid <= 1'b1;
            end
            else begin
                weight_valid <= 1'b0;
            end

            // Switch the read bank after the Tile Controller authorizes a swap.
            if (buf_swap) begin
                active_bank <= ~active_bank;
                tile_ready  <= 1'b1;
            end
        end
    end

endmodule

