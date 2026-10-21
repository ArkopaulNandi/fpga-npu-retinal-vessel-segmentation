
`timescale 1ns/1ps

module axi4_lite_master_bfm #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32,
    parameter int MAX_WAIT = 100
) (
    input logic aclk,
    input logic aresetn,

    output logic [ADDR_WIDTH-1:0] s_axi_awaddr,
    output logic s_axi_awvalid,
    input logic s_axi_awready,

    output logic [DATA_WIDTH-1:0] s_axi_wdata,
    output logic [DATA_WIDTH/8-1:0] s_axi_wstrb,
    output logic s_axi_wvalid,
    input logic s_axi_wready,

    input logic [1:0] s_axi_bresp,
    input logic s_axi_bvalid,
    output logic s_axi_bready,

    output logic [ADDR_WIDTH-1:0] s_axi_araddr,
    output logic s_axi_arvalid,
    input logic s_axi_arready,

    input logic [DATA_WIDTH-1:0] s_axi_rdata,
    input logic [1:0] s_axi_rresp,
    input logic s_axi_rvalid,
    output logic s_axi_rready
);

    // Initialize master-driven signals before transactions begin.
    initial begin
        s_axi_awaddr  = '0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = '0;
        s_axi_wstrb   = '0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_araddr  = '0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;
    end

    // Drive the master interface to its idle state during reset.
    task automatic reset_master();
        begin
            s_axi_awaddr  = '0;
            s_axi_awvalid = 1'b0;
            s_axi_wdata   = '0;
            s_axi_wstrb   = '0;
            s_axi_wvalid  = 1'b0;
            s_axi_bready  = 1'b0;
            s_axi_araddr  = '0;
            s_axi_arvalid = 1'b0;
            s_axi_rready  = 1'b0;
        end
    endtask

    // Perform an AXI4-Lite write with independently handshaken AW and W channels.
    task automatic write(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic [DATA_WIDTH/8-1:0] strb,
        output logic [1:0] resp
    );
        integer aw_wait;
        integer w_wait;
        integer b_wait;
        begin
            resp = 2'bxx;

            if (!aresetn) begin
                $error("AXI BFM WRITE: Reset is active.");
            end
            else begin
                // Present the write transaction on a falling clock edge.
                @(negedge aclk);
                s_axi_awaddr  = addr;
                s_axi_wdata   = data;
                s_axi_wstrb   = strb;
                s_axi_awvalid = 1'b1;
                s_axi_wvalid  = 1'b1;
                s_axi_bready  = 1'b1;

                // Allow address and data to handshake independently.
                fork
                    begin
                        aw_wait = 0;
                        while (s_axi_awvalid && aw_wait < MAX_WAIT) begin
                            @(posedge aclk);
                            if (s_axi_awready) begin
                                @(negedge aclk);
                                s_axi_awvalid = 1'b0;
                            end
                            else begin
                                aw_wait = aw_wait + 1;
                            end
                        end
                        if (s_axi_awvalid)
                            $fatal(1, "AXI BFM: AW handshake timeout.");
                    end

                    begin
                        w_wait = 0;
                        while (s_axi_wvalid && w_wait < MAX_WAIT) begin
                            @(posedge aclk);
                            if (s_axi_wready) begin
                                @(negedge aclk);
                                s_axi_wvalid = 1'b0;
                            end
                            else begin
                                w_wait = w_wait + 1;
                            end
                        end
                        if (s_axi_wvalid)
                            $fatal(1, "AXI BFM: W handshake timeout.");
                    end
                join

                // Wait for and accept the write response.
                b_wait = 0;
                while (!s_axi_bvalid && b_wait < MAX_WAIT) begin
                    @(posedge aclk);
                    b_wait = b_wait + 1;
                end

                if (!s_axi_bvalid)
                    $fatal(1, "AXI BFM: B response timeout.");

                resp = s_axi_bresp;
                @(negedge aclk);
                s_axi_bready = 1'b0;

                if (resp != 2'b00)
                    $error("AXI BFM WRITE: Non-OKAY response %b at address %h.", resp, addr);
                else
                    $display("AXI BFM WRITE: addr=%h data=%h strb=%b resp=%b",
                             addr, data, strb, resp);
            end
        end
    endtask

    // Perform an AXI4-Lite read and return the data and response.
    task automatic read(
        input logic [ADDR_WIDTH-1:0] addr,
        output logic [DATA_WIDTH-1:0] data,
        output logic [1:0] resp
    );
        integer ar_wait;
        integer r_wait;
        begin
            data = '0;
            resp = 2'bxx;

            if (!aresetn) begin
                $error("AXI BFM READ: Reset is active.");
            end
            else begin
                // Present the read address and prepare to accept read data.
                @(negedge aclk);
                s_axi_araddr  = addr;
                s_axi_arvalid = 1'b1;
                s_axi_rready  = 1'b1;

                // Hold ARVALID until the slave accepts the address.
                ar_wait = 0;
                while (s_axi_arvalid && ar_wait < MAX_WAIT) begin
                    @(posedge aclk);
                    if (s_axi_arready) begin
                        @(negedge aclk);
                        s_axi_arvalid = 1'b0;
                    end
                    else begin
                        ar_wait = ar_wait + 1;
                    end
                end

                if (s_axi_arvalid)
                    $fatal(1, "AXI BFM: AR handshake timeout.");

                // Wait for the read response.
                r_wait = 0;
                while (!s_axi_rvalid && r_wait < MAX_WAIT) begin
                    @(posedge aclk);
                    r_wait = r_wait + 1;
                end

                if (!s_axi_rvalid)
                    $fatal(1, "AXI BFM: R response timeout.");

                data = s_axi_rdata;
                resp = s_axi_rresp;

                @(negedge aclk);
                s_axi_rready = 1'b0;

                if (resp != 2'b00)
                    $error("AXI BFM READ: Non-OKAY response %b at address %h.", resp, addr);
                else
                    $display("AXI BFM READ: addr=%h data=%h resp=%b",
                             addr, data, resp);
            end
        end
    endtask

endmodule
