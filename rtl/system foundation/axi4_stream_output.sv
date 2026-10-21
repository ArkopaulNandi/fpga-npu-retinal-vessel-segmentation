
`timescale 1ns/1ps

//=============================================================================
// Module      : axi4_stream_output
// Description : AXI4-Stream output interface for the retinal segmentation mask.
// Reference   : System Interface: AXI4-Stream Input and Output diagram.
//=============================================================================

module axi4_stream_output #(
    parameter int DATA_WIDTH = 8,
    parameter int FIFO_DEPTH = 16,
    parameter int DIM_WIDTH = 16,
    parameter int PTR_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH),
    parameter int COUNT_WIDTH = $clog2(FIFO_DEPTH + 1)
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   clk_enable,

    // Pixel stream from the retinal output buffer.
    input  logic                   pixel_valid,
    output logic                   pixel_ready,
    input  logic [DATA_WIDTH-1:0]  pixel_data,

    // Image dimensions from the Register Bank.
    input  logic [DIM_WIDTH-1:0]   img_width,
    input  logic [DIM_WIDTH-1:0]   img_height,

    // AXI4-Stream output to the external sink.
    output logic                   m_axis_tvalid,
    input  logic                   m_axis_tready,
    output logic [DATA_WIDTH-1:0]  m_axis_tdata,
    output logic                   m_axis_tlast,
    output logic                   m_axis_tuser,

    // Pulses when the final pixel of a frame is accepted.
    output logic                   frame_done
);

    // FIFO stores pixel data before stream framing.
    logic [DATA_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];
    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;
    logic [COUNT_WIDTH-1:0] fifo_count;

    logic fifo_full;
    logic fifo_empty;
    logic fifo_push;
    logic fifo_pop;
    logic [DATA_WIDTH-1:0] fifo_out_data;

    // The stream framer tracks the current pixel coordinates.
    logic [DIM_WIDTH-1:0] col_count;
    logic [DIM_WIDTH-1:0] row_count;

    // The output register slice holds one framed beat.
    logic                  stage_valid;
    logic [DATA_WIDTH-1:0] stage_data;
    logic                  stage_last;
    logic                  stage_user;
    logic                  stage_frame_end;
    logic                  stage_ready;

    // Determine whether the FIFO can accept another pixel.
    assign fifo_full = (fifo_count == FIFO_DEPTH);
    assign fifo_empty = (fifo_count == 0);

    // A simultaneous FIFO pop allows a push even when the FIFO is full.
    assign fifo_out_data = fifo_mem[rd_ptr];
    assign stage_ready = clk_enable &&
                         (!stage_valid || m_axis_tready);

    // Move a FIFO pixel into the output stage when space is available.
    assign fifo_pop = !fifo_empty && stage_ready;

    // Accept an input pixel when the FIFO has space or a pop occurs.
    assign pixel_ready = clk_enable && (!fifo_full || fifo_pop);
    assign fifo_push = pixel_valid && pixel_ready;

    // Expose the registered output beat to the AXI4-Stream interface.
    assign m_axis_tvalid = stage_valid;
    assign m_axis_tdata = stage_data;
    assign m_axis_tlast = stage_last;
    assign m_axis_tuser = stage_user;

    // Write incoming retinal mask pixels into the FIFO.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= '0;
            rd_ptr     <= '0;
            fifo_count <= '0;
        end
        else if (clk_enable) begin
            // Store a pixel accepted from the retinal output buffer.
            if (fifo_push) begin
                fifo_mem[wr_ptr] <= pixel_data;

                if (wr_ptr == FIFO_DEPTH - 1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            // Advance the FIFO read pointer when a pixel enters the output stage.
            if (fifo_pop) begin
                if (rd_ptr == FIFO_DEPTH - 1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            // Update FIFO occupancy for pushes and pops.
            case ({fifo_push, fifo_pop})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: fifo_count <= fifo_count - 1'b1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

    // Frame the pixel stream and hold output data under backpressure.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_count      <= '0;
            row_count      <= '0;
            stage_valid    <= 1'b0;
            stage_data     <= '0;
            stage_last     <= 1'b0;
            stage_user     <= 1'b0;
            stage_frame_end <= 1'b0;
            frame_done     <= 1'b0;
        end
        else if (clk_enable) begin
            // Frame completion is a one-cycle pulse.
            frame_done <= 1'b0;

            // Retire the current output beat only when the sink accepts it.
            if (stage_valid && m_axis_tready && stage_frame_end)
                frame_done <= 1'b1;

            // Replace the output beat only when the stage can accept new data.
            if (stage_ready) begin
                stage_valid <= fifo_pop;

                if (fifo_pop) begin
                    stage_data <= fifo_out_data;

                    // TUSER marks the first pixel of a frame.
                    stage_user <= (col_count == 0) && (row_count == 0);

                    // TLAST marks the final pixel in each image line.
                    stage_last <= (img_width != 0) &&
                                  (col_count == img_width - 1'b1);

                    // Remember whether this beat ends the complete frame.
                    stage_frame_end <= (img_width != 0) &&
                                       (img_height != 0) &&
                                       (col_count == img_width - 1'b1) &&
                                       (row_count == img_height - 1'b1);

                    // Advance the horizontal and vertical pixel coordinates.
                    if ((img_width != 0) &&
                        (col_count == img_width - 1'b1)) begin
                        col_count <= '0;

                        if ((img_height != 0) &&
                            (row_count == img_height - 1'b1))
                            row_count <= '0;
                        else
                            row_count <= row_count + 1'b1;
                    end
                    else begin
                        col_count <= col_count + 1'b1;
                    end
                end
            end
        end
    end

endmodule
