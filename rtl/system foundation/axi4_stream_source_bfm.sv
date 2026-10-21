
`timescale 1ns/1ps

module axi4_stream_source_bfm #(
    parameter int DATA_WIDTH = 8,
    parameter int MAX_WAIT = 100
) (
    input logic clk,
    input logic rst_n,

    output logic                  s_axis_tvalid,
    input  logic                  s_axis_tready,
    output logic [DATA_WIDTH-1:0] s_axis_tdata,
    output logic                  s_axis_tlast,
    output logic                  s_axis_tuser
);

    // Initialize source signals to the idle state.
    initial begin
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = '0;
        s_axis_tlast  = 1'b0;
        s_axis_tuser  = 1'b0;
    end

    // Drive all source signals to their idle values.
    task automatic reset_source();
        begin
            s_axis_tvalid = 1'b0;
            s_axis_tdata  = '0;
            s_axis_tlast  = 1'b0;
            s_axis_tuser  = 1'b0;
        end
    endtask

    // Send one stream beat and hold it stable until the DUT accepts it.
    task automatic send_beat(
        input logic [DATA_WIDTH-1:0] data,
        input logic last,
        input logic user
    );
        integer wait_count;
        bit accepted;
        begin
            if (!rst_n)
                $fatal(1, "AXI Stream Source: Cannot send during reset.");

            // Present the beat on the falling edge.
            @(negedge clk);
            s_axis_tdata  = data;
            s_axis_tlast  = last;
            s_axis_tuser  = user;
            s_axis_tvalid = 1'b1;

            // Wait for a valid-ready handshake.
            accepted = 1'b0;
            wait_count = 0;

            while (!accepted && wait_count < MAX_WAIT) begin
                @(posedge clk);

                if (!rst_n)
                    $fatal(1, "AXI Stream Source: Reset during transfer.");

                if (s_axis_tready)
                    accepted = 1'b1;
                else
                    wait_count = wait_count + 1;
            end

            if (!accepted)
                $fatal(1, "AXI Stream Source: Transfer timeout.");

            // Remove VALID after the accepted beat.
            @(negedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tdata  = '0;
            s_axis_tlast  = 1'b0;
            s_axis_tuser  = 1'b0;
        end
    endtask

    // Send a complete frame with automatic line and frame markers.
    task automatic send_frame(
        input integer img_width,
        input integer img_height,
        input integer base_pixel
    );
        integer row;
        integer col;
        integer pixel_value;
        begin
            if (img_width <= 0 || img_height <= 0)
                $fatal(1, "AXI Stream Source: Invalid frame dimensions.");

            for (row = 0; row < img_height; row = row + 1) begin
                for (col = 0; col < img_width; col = col + 1) begin
                    pixel_value = base_pixel + row * img_width + col;

                    // TUSER marks the first pixel; TLAST marks each line's final pixel.
                    send_beat(
                        DATA_WIDTH'(pixel_value),
                        (col == img_width - 1),
                        ((row == 0) && (col == 0))
                    );
                end
            end

            $display(
                "AXI Stream Source: Frame sent, width=%0d height=%0d",
                img_width, img_height
            );
        end
    endtask

endmodule
