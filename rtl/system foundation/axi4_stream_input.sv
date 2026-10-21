`timescale 1ns/1ps

module axi4_stream_input #(
    parameter int DATA_WIDTH = 8,
    parameter int FIFO_DEPTH = 16,
    parameter int WIDTH_WIDTH = 16,
    parameter int PTR_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH),
    parameter int COUNT_WIDTH = $clog2(FIFO_DEPTH + 1)
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  clk_enable,
    input  logic                  rx_en,

    // AXI4-Stream input from the external pixel source.
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tlast,
    input  logic                  s_axis_tuser,

    // Image dimensions from the Register Bank.
    input  logic [WIDTH_WIDTH-1:0] img_width,

    // Stream output to the Image Frontend.
    output logic                  pix_valid,
    input  logic                  pix_ready,
    output logic [DATA_WIDTH-1:0] pix_data,
    output logic                  pix_last,
    output logic                  pix_sof,

    // Error indication for the Register Bank STATUS path.
    output logic                  line_err
);

    // The input register slice holds one beat when downstream is blocked.
    logic                  slice_valid;
    logic [DATA_WIDTH-1:0] slice_data;
    logic                  slice_last;
    logic                  slice_user;
    logic                  slice_ready;

    // FIFO storage packs pixel data, end-of-line, and start-of-frame flags.
    localparam int FIFO_DATA_WIDTH = DATA_WIDTH + 2;

    logic [FIFO_DATA_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];
    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;
    logic [COUNT_WIDTH-1:0] fifo_count;

    logic fifo_full;
    logic fifo_empty;
    logic fifo_push;
    logic fifo_pop;
    logic fifo_in_ready;

    logic [FIFO_DATA_WIDTH-1:0] fifo_out_data;

    // Count accepted input pixels within the current image line.
    logic [WIDTH_WIDTH-1:0] pixel_count;

    // The FIFO can accept a beat when it has space or a beat is removed.
    assign fifo_full = (fifo_count == FIFO_DEPTH);
    assign fifo_empty = (fifo_count == 0);

    assign fifo_in_ready = !fifo_full || fifo_pop;

    // Preserve the stream beat while the FIFO cannot accept it.
    assign slice_ready = rx_en && clk_enable &&
                         (!slice_valid || fifo_in_ready);

    assign s_axis_tready = slice_ready;

    // A FIFO push occurs only when a buffered beat is accepted.
    assign fifo_push = slice_valid && fifo_in_ready && clk_enable;

    // Pop a FIFO beat only when the frontend accepts it.
    assign fifo_pop = !fifo_empty && pix_ready && clk_enable;

    // Read the current FIFO entry.
    assign fifo_out_data = fifo_mem[rd_ptr];
    
    // Suppress uninitialized memory values when the FIFO is empty.
    assign pix_data  = fifo_empty ? '0 : fifo_out_data[DATA_WIDTH-1:0];
    assign pix_last  = fifo_empty ? 1'b0 : fifo_out_data[DATA_WIDTH];
    assign pix_sof   = fifo_empty ? 1'b0 : fifo_out_data[DATA_WIDTH+1];
    assign pix_valid = !fifo_empty;

    // Capture incoming stream beats in the input register slice.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slice_valid <= 1'b0;
            slice_data  <= '0;
            slice_last  <= 1'b0;
            slice_user  <= 1'b0;
        end
        else if (clk_enable) begin
            if (slice_ready) begin
                slice_valid <= s_axis_tvalid;

                if (s_axis_tvalid) begin
                    slice_data <= s_axis_tdata;
                    slice_last <= s_axis_tlast;
                    slice_user <= s_axis_tuser;
                end
            end
        end
    end

    // Store and retrieve stream beats using a synchronous FIFO.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= '0;
            rd_ptr     <= '0;
            fifo_count <= '0;
        end
        else if (clk_enable) begin
            // Write the buffered beat into the FIFO.
            if (fifo_push) begin
                fifo_mem[wr_ptr] <= {
                    slice_user,
                    slice_last,
                    slice_data
                };

                if (wr_ptr == FIFO_DEPTH - 1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            // Advance the read pointer when the frontend accepts a beat.
            if (fifo_pop) begin
                if (rd_ptr == FIFO_DEPTH - 1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            // Update occupancy for push-only, pop-only, or simultaneous access.
            case ({fifo_push, fifo_pop})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: fifo_count <= fifo_count - 1'b1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

    // Check accepted input pixels against the configured image width.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_count <= '0;
            line_err    <= 1'b0;
        end
        else if (clk_enable) begin
            // Report an error for one cycle unless a new mismatch is detected.
            line_err <= 1'b0;

            if (s_axis_tvalid && s_axis_tready) begin
                // TUSER marks a new frame, so the first pixel starts a new line.
                if (s_axis_tuser) begin
                    if (s_axis_tlast) begin
                        if (img_width != 1)
                            line_err <= 1'b1;

                        pixel_count <= '0;
                    end
                    else begin
                        pixel_count <= 1;
                    end
                end
                else if (s_axis_tlast) begin
                    // Include the current pixel when checking the line length.
                    if ((pixel_count + 1'b1) != img_width)
                        line_err <= 1'b1;

                    pixel_count <= '0;
                end
                else begin
                    pixel_count <= pixel_count + 1'b1;
                end
            end
        end
    end

endmodule
