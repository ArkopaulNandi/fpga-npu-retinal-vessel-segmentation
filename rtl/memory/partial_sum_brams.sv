`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.10.2026 11:11:04
// Design Name: 
// Module Name: partial_sum_brams
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

module partial_sum_brams #(
    parameter int NUM_BANKS = 4,
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH = 1024,
    parameter int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic clk_enable,

    // Memory Scheduler control
    input  logic acc_clr,
    input  logic acc_en,
    input  logic last_k_tile,

    // Address shared by the four output-column banks
    input  logic [ADDR_WIDTH-1:0] psum_addr,

    // Incoming partial sum from each PE-array column
    input  logic [NUM_BANKS*DATA_WIDTH-1:0] psum_in,
    input  logic psum_valid,

    // Final accumulated results
    output logic [NUM_BANKS*DATA_WIDTH-1:0] final_result,
    output logic result_valid,
    output logic busy
);

    // One running partial-sum memory per PE-array column.
    logic [DATA_WIDTH-1:0] psum_mem
        [0:NUM_BANKS-1][0:DEPTH-1];

    // Hold incoming values while synchronous BRAM reads complete.
    logic [NUM_BANKS*DATA_WIDTH-1:0] input_reg;
    logic [ADDR_WIDTH-1:0] addr_reg;
    logic clr_reg;
    logic last_reg;

    logic [DATA_WIDTH-1:0] psum_read_reg [0:NUM_BANKS-1];
    logic [DATA_WIDTH-1:0] psum_sum [0:NUM_BANKS-1];

    typedef enum logic [1:0] {
        IDLE,
        READ_PSUM,
        WRITE_PSUM
    } state_t;

    state_t state;

    integer i;

    // Read old partial sums, calculate new sums, and commit the results.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state        <= IDLE;
            input_reg    <= '0;
            addr_reg     <= '0;
            clr_reg      <= 1'b0;
            last_reg     <= 1'b0;
            final_result <= '0;
            result_valid <= 1'b0;
            busy         <= 1'b0;

            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                psum_read_reg[i] <= '0;
                psum_sum[i]      <= '0;
            end
        end
        else if (clk_enable) begin
            result_valid <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;

                    // Accept a new partial-sum transaction.
                    if (psum_valid && acc_en) begin
                        input_reg <= psum_in;
                        addr_reg  <= psum_addr;
                        clr_reg   <= acc_clr;
                        last_reg  <= last_k_tile;
                        busy      <= 1'b1;

                        if (acc_clr) begin
                            // First K-tile starts a new accumulation.
                            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                                psum_sum[i] <= psum_in[i*DATA_WIDTH +: DATA_WIDTH];
                            end

                            state <= WRITE_PSUM;
                        end
                        else begin
                            state <= READ_PSUM;
                        end
                    end
                end

                READ_PSUM: begin
                    // Synchronous read from each column's BRAM.
                    for (i = 0; i < NUM_BANKS; i = i + 1) begin
                        psum_read_reg[i] <= psum_mem[i][addr_reg];
                    end

                    state <= WRITE_PSUM;
                end

                WRITE_PSUM: begin
                    for (i = 0; i < NUM_BANKS; i = i + 1) begin
                        if (!clr_reg) begin
                            // Accumulate the previous K-tile result.
                            psum_sum[i] <= psum_read_reg[i] + input_reg[i*DATA_WIDTH +: DATA_WIDTH];

                            psum_mem[i][addr_reg] <= psum_read_reg[i] + input_reg[i*DATA_WIDTH +: DATA_WIDTH];
                        end
                        else begin
                            // Store the first K-tile partial sum.
                            psum_mem[i][addr_reg] <= psum_sum[i];
                        end

                        // Release the final accumulated column result.
                        if (last_reg) begin
                            if (clr_reg)
                                final_result[i*DATA_WIDTH +: DATA_WIDTH] <= psum_sum[i];
                            else
                                final_result[i*DATA_WIDTH +: DATA_WIDTH] <= psum_read_reg[i] + input_reg[i*DATA_WIDTH +: DATA_WIDTH];
                        end
                    end

                    result_valid <= last_reg;
                    busy         <= 1'b0;
                    state        <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule

