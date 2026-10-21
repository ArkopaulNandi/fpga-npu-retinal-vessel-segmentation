`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.10.2026 07:10:08
// Design Name: 
// Module Name: activation_buffer
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

module activation_buffer #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH = 1024,
    parameter int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  clk_enable,

    input  logic                  activation_write,
    input  logic [ADDR_WIDTH-1:0] activation_wr_addr,
    input  logic [DATA_WIDTH-1:0] activation_data_in,

    input  logic                  activation_read,
    input  logic [ADDR_WIDTH-1:0] activation_rd_addr,
    output logic [DATA_WIDTH-1:0] activation_data_out,
    output logic                  activation_valid,

    input  logic                  buf_swap,
    output logic                  tile_ready,
    output logic                  active_bank
);

    // Two activation banks hold alternating tiles.
    logic [DATA_WIDTH-1:0] buffer_a [0:DEPTH-1];
    logic [DATA_WIDTH-1:0] buffer_b [0:DEPTH-1];

    // Reset selects B as the initial read bank so the first tile fills A.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            active_bank         <= 1'b1;
            tile_ready          <= 1'b0;
            activation_data_out <= '0;
            activation_valid    <= 1'b0;
        end
        else if (clk_enable) begin
            // Fill the bank that is not currently being read.
            if (activation_write && !active_bank)
                buffer_b[activation_wr_addr] <= activation_data_in;
            else if (activation_write && active_bank)
                buffer_a[activation_wr_addr] <= activation_data_in;

            // Read from the active tile bank.
            if (activation_read && tile_ready) begin
                if (active_bank)
                    activation_data_out <= buffer_b[activation_rd_addr];
                else
                    activation_data_out <= buffer_a[activation_rd_addr];

                activation_valid <= 1'b1;
            end
            else begin
                activation_valid <= 1'b0;
            end

            // The Tile Controller swaps banks at a tile boundary.
            if (buf_swap) begin
                active_bank <= ~active_bank;
                tile_ready  <= 1'b1;
            end
        end
    end

endmodule


