
`timescale 1ns/1ps

module axi4_stream_sink_bfm #(
    parameter int DATA_WIDTH = 8,
    parameter int MAX_WAIT = 10000,
    parameter int MAX_PIXELS = 65536
) (
    input logic clk,
    input logic rst_n,

    input logic                  m_axis_tvalid,
    output logic                 m_axis_tready,
    input logic [DATA_WIDTH-1:0] m_axis_tdata,
    input logic                  m_axis_tlast,
    input logic                  m_axis_tuser
);

    // Store accepted output pixels for later checking.
    logic [DATA_WIDTH-1:0] captured_data [0:MAX_PIXELS-1];

    integer received_count;
    integer error_count;

    // Initialize the sink in a not-ready state.
    initial begin
        m_axis_tready = 1'b0;
        received_count = 0;
        error_count = 0;
    end

    // Reset the sink counters and stop accepting data.
    task automatic reset_sink();
        begin
            m_axis_tready = 1'b0;
            received_count = 0;
            error_count = 0;
        end
    endtask

    // Accept one beat and capture its data.
    task automatic receive_beat(
        output logic [DATA_WIDTH-1:0] data,
        output logic last,
        output logic user
    );
        integer wait_count;
        bit accepted;
        begin
            data = '0;
            last = 1'b0;
            user = 1'b0;
            accepted = 1'b0;
            wait_count = 0;

            while (!accepted && wait_count < MAX_WAIT) begin
                @(posedge clk);

                if (!rst_n)
                    $fatal(1, "AXI Stream Sink: Reset during reception.");

                if (m_axis_tvalid && m_axis_tready) begin
                    data = m_axis_tdata;
                    last = m_axis_tlast;
                    user = m_axis_tuser;
                    accepted = 1'b1;
                end
                else begin
                    wait_count = wait_count + 1;
                end
            end

            if (!accepted)
                $fatal(1, "AXI Stream Sink: Receive timeout.");
        end
    endtask

    // Receive a frame while periodically applying backpressure and checking framing.
    task automatic receive_frame(
        input integer img_width,
        input integer img_height,
        input integer stall_period,
        input integer stall_cycles
    );
        integer cycle_count;
        integer total_pixels;
        integer expected_last;
        integer expected_user;
        integer stall_position;
        begin
            if (!rst_n)
                $fatal(1, "AXI Stream Sink: Cannot receive during reset.");

            if (img_width <= 0 || img_height <= 0)
                $fatal(1, "AXI Stream Sink: Invalid frame dimensions.");

            total_pixels = img_width * img_height;

            if (total_pixels > MAX_PIXELS)
                $fatal(1, "AXI Stream Sink: Frame exceeds capture capacity.");

            if (stall_period < 0 || stall_cycles < 0 ||
                (stall_period > 0 && stall_cycles >= stall_period))
                $fatal(1, "AXI Stream Sink: Invalid backpressure settings.");

            received_count = 0;
            error_count = 0;
            cycle_count = 0;

            // Drive READY on falling edges to avoid races with DUT sampling.
            while (received_count < total_pixels && cycle_count < MAX_WAIT) begin
                @(negedge clk);

                if (stall_period > 0) begin
                    stall_position = cycle_count % stall_period;
                    m_axis_tready = (stall_position >= stall_cycles);
                end
                else begin
                    m_axis_tready = 1'b1;
                end

                @(posedge clk);
                cycle_count = cycle_count + 1;

                // Capture only transfers accepted by both endpoints.
                if (m_axis_tvalid && m_axis_tready) begin
                    captured_data[received_count] = m_axis_tdata;

                    expected_last = ((received_count % img_width) == img_width - 1);
                    expected_user = (received_count == 0);

                    // Check TLAST against the expected end-of-line position.
                    if (m_axis_tlast !== expected_last) begin
                        $error("AXI Stream Sink: TLAST mismatch at pixel %0d.",
                               received_count);
                        error_count = error_count + 1;
                    end

                    // Check TUSER against the expected start-of-frame position.
                    if (m_axis_tuser !== expected_user) begin
                        $error("AXI Stream Sink: TUSER mismatch at pixel %0d.",
                               received_count);
                        error_count = error_count + 1;
                    end

                    $display("AXI Stream Sink: pixel=%0d data=%h last=%b user=%b",
                             received_count, m_axis_tdata,
                             m_axis_tlast, m_axis_tuser);

                    received_count = received_count + 1;
                end
            end

            // Stop accepting data after the requested frame has been received.
            @(negedge clk);
            m_axis_tready = 1'b0;

            if (received_count != total_pixels)
                $fatal(1, "AXI Stream Sink: Frame reception timeout.");

            if (error_count == 0)
                $display("AXI Stream Sink: PASS, received %0d pixels.",
                         received_count);
            else
                $error("AXI Stream Sink: FAIL, framing errors=%0d.",
                       error_count);
        end
    endtask

endmodule
