`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.10.2026 07:33:48
// Design Name: 
// Module Name: cnm_bram_banks
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

module cnm_bram_banks #(
    parameter int NUM_BANKS = 4,
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH = 1024,
    parameter int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic clk_enable,

    // Activation-bank write interface from the ping-pong/scheduler path
    input  logic [NUM_BANKS-1:0] activation_bank_we,
    input  logic [ADDR_WIDTH-1:0] activation_wr_addr,
    input  logic [NUM_BANKS*DATA_WIDTH-1:0] activation_wr_data,

    // Activation tile read interface
    input  logic activation_rd_en,
    input  logic [ADDR_WIDTH-1:0] activation_rd_addr,
    output logic [NUM_BANKS*DATA_WIDTH-1:0] activation_rows,
    output logic activation_rd_valid,

    // Weight-bank write interface from the ping-pong/scheduler path
    input  logic [NUM_BANKS-1:0] weight_bank_we,
    input  logic [ADDR_WIDTH-1:0] weight_wr_addr,
    input  logic [NUM_BANKS*DATA_WIDTH-1:0] weight_wr_data,

    // Weight tile read interface
    input  logic weight_rd_en,
    input  logic [ADDR_WIDTH-1:0] weight_rd_addr,
    output logic [NUM_BANKS*DATA_WIDTH-1:0] weight_columns,
    output logic weight_rd_valid
);

    // Each activation bank stores the data for one PE-array row.
    logic [DATA_WIDTH-1:0] activation_mem
        [0:NUM_BANKS-1][0:DEPTH-1];

    // Each weight bank stores the data for one PE-array column.
    logic [DATA_WIDTH-1:0] weight_mem
        [0:NUM_BANKS-1][0:DEPTH-1];

    // Registered read data supports synchronous BRAM inference.
    logic [DATA_WIDTH-1:0] activation_rd_reg [0:NUM_BANKS-1];
    logic [DATA_WIDTH-1:0] weight_rd_reg [0:NUM_BANKS-1];

    genvar bank;

    generate
        for (bank = 0; bank < NUM_BANKS; bank = bank + 1) begin : gen_banks

            // Activation bank: independent write enable and shared tile address.
            always_ff @(posedge clk) begin
                if (rst_n && clk_enable) begin
                    if (activation_bank_we[bank]) begin
                        activation_mem[bank][activation_wr_addr] <= activation_wr_data[bank*DATA_WIDTH +: DATA_WIDTH];
                    end
                    if (activation_rd_en) begin
                        activation_rd_reg[bank] <= activation_mem[bank][activation_rd_addr];
                    end
                end
            end

            // Weight bank: independent write enable and shared tile address.
            always_ff @(posedge clk) begin
                if (rst_n && clk_enable) begin
                    if (weight_bank_we[bank]) begin
                        weight_mem[bank][weight_wr_addr] <= weight_wr_data[bank*DATA_WIDTH +: DATA_WIDTH];
                    end
                    if (weight_rd_en) begin
                        weight_rd_reg[bank] <= weight_mem[bank][weight_rd_addr];
                    end
                end
            end

            // Pack each bank output into the row/column bus.
            assign activation_rows[bank*DATA_WIDTH +: DATA_WIDTH] = activation_rd_reg[bank];
            assign weight_columns[bank*DATA_WIDTH +: DATA_WIDTH] = weight_rd_reg[bank];

        end
    endgenerate

    // Valid signals indicate that a synchronous read was accepted.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            activation_rd_valid <= 1'b0;
            weight_rd_valid     <= 1'b0;
        end
        else if (clk_enable) begin
            activation_rd_valid <= activation_rd_en;
            weight_rd_valid     <= weight_rd_en;
        end
    end

endmodule

