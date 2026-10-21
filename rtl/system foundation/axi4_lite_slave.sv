`timescale 1ns/1ps

//=============================================================================
// Module      : axi4_lite_slave
// Description : AXI4-Lite slave interface for the NPU register bank.
//=============================================================================

module axi4_lite_slave #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
) (
    input  logic                  aclk,
    input  logic                  aresetn,

    // AXI4-Lite write address channel.
    input  logic [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic                  s_axi_awvalid,
    output logic                  s_axi_awready,

    // AXI4-Lite write data channel.
    input  logic [DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                  s_axi_wvalid,
    output logic                  s_axi_wready,

    // AXI4-Lite write response channel.
    output logic [1:0]            s_axi_bresp,
    output logic                  s_axi_bvalid,
    input  logic                  s_axi_bready,

    // AXI4-Lite read address channel.
    input  logic [ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,

    // AXI4-Lite read data channel.
    output logic [DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready,

    // Register bank write interface.
    output logic                  reg_wr_en,
    output logic [5:0]            reg_waddr,
    output logic [DATA_WIDTH-1:0] reg_wdata,
    output logic [DATA_WIDTH/8-1:0] reg_wstrb,

    // Register bank read interface.
    output logic [5:0]            reg_raddr,
    input  logic [DATA_WIDTH-1:0] reg_rdata
);

    // AXI4-Lite uses OKAY responses for this register interface.
    localparam logic [1:0] RESP_OKAY = 2'b00;

    // Write-channel state definitions.
    typedef enum logic [1:0] {
        WR_IDLE,
        WR_CAPTURE,
        WR_RESP
    } wr_state_t;

    // Read-channel state definitions.
    typedef enum logic [1:0] {
        RD_IDLE,
        RD_DATA,
        RD_RESP
    } rd_state_t;

    wr_state_t wr_state;
    rd_state_t rd_state;

    // Hold independently accepted write address and data.
    logic                  aw_captured;
    logic                  w_captured;
    logic [ADDR_WIDTH-1:0] awaddr_reg;
    logic [DATA_WIDTH-1:0] wdata_reg;
    logic [DATA_WIDTH/8-1:0] wstrb_reg;

    // Hold the read address until the read data is captured.
    logic [ADDR_WIDTH-1:0] araddr_reg;

    // Register-side write request pulse.
    logic reg_write_pending;

    // AXI write-channel handshake and register write controls.
    always_comb begin
        s_axi_awready = (wr_state == WR_IDLE) && !aw_captured && !s_axi_bvalid;

        s_axi_wready  = (wr_state == WR_IDLE) && !w_captured && !s_axi_bvalid;

        s_axi_bresp = RESP_OKAY;

        reg_wr_en = reg_write_pending;
        reg_waddr = awaddr_reg[7:2];
        reg_wdata = wdata_reg;
        reg_wstrb = wstrb_reg;
    end

    // Capture write address and data independently.
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_state         <= WR_IDLE;
            aw_captured      <= 1'b0;
            w_captured       <= 1'b0;
            awaddr_reg       <= '0;
            wdata_reg        <= '0;
            wstrb_reg        <= '0;
            s_axi_bvalid     <= 1'b0;
            reg_write_pending <= 1'b0;
        end
        else begin
            reg_write_pending <= 1'b0;

            case (wr_state)

                WR_IDLE: begin
                    // Capture AW independently of W.
                    if (s_axi_awvalid && s_axi_awready) begin
                        awaddr_reg  <= s_axi_awaddr;
                        aw_captured <= 1'b1;
                    end

                    // Capture W independently of AW.
                    if (s_axi_wvalid && s_axi_wready) begin
                        wdata_reg  <= s_axi_wdata;
                        wstrb_reg  <= s_axi_wstrb;
                        w_captured <= 1'b1;
                    end

                    // Move forward once both channels have been captured.
                    if ((aw_captured ||
                         (s_axi_awvalid && s_axi_awready)) &&
                        (w_captured ||
                         (s_axi_wvalid && s_axi_wready))) begin
                        wr_state <= WR_CAPTURE;
                    end
                end

                WR_CAPTURE: begin
                    // Issue one register write request.
                    reg_write_pending <= 1'b1;
                    s_axi_bvalid      <= 1'b1;
                    wr_state          <= WR_RESP;
                end

                WR_RESP: begin
                    // Hold the response until the host accepts it.
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        aw_captured  <= 1'b0;
                        w_captured   <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: begin
                    wr_state <= WR_IDLE;
                end

            endcase
        end
    end

    // AXI read-channel address handshake.
    always_comb begin
        s_axi_arready = (rd_state == RD_IDLE) &&
                        !s_axi_rvalid;

        reg_raddr = araddr_reg[7:2];
        s_axi_rresp = RESP_OKAY;
    end

    // Capture the read address and return the selected register value.
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rd_state    <= RD_IDLE;
            araddr_reg  <= '0;
            s_axi_rdata <= '0;
            s_axi_rvalid <= 1'b0;
        end
        else begin
            case (rd_state)

                RD_IDLE: begin
                    // Accept a new read address.
                    if (s_axi_arvalid && s_axi_arready) begin
                        araddr_reg <= s_axi_araddr;
                        rd_state   <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    // Capture the selected register-bank data.
                    s_axi_rdata  <= reg_rdata;
                    s_axi_rvalid <= 1'b1;
                    rd_state     <= RD_RESP;
                end

                RD_RESP: begin
                    // Hold read data and valid until accepted.
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        rd_state     <= RD_IDLE;
                    end
                end

                default: begin
                    rd_state <= RD_IDLE;
                end

            endcase
        end
    end

endmodule
