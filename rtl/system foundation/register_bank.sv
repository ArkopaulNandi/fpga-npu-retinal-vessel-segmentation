`timescale 1ns/1ps

module register_bank #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  clk_enable,

    input  logic                  reg_wr_en,
    input  logic [ADDR_WIDTH-1:0] reg_waddr,
    input  logic [DATA_WIDTH-1:0] reg_wdata,

    input  logic [ADDR_WIDTH-1:0] reg_raddr,
    output logic [DATA_WIDTH-1:0] reg_rdata,

    input  logic                  status_error,
    input  logic                  status_done,
    input  logic                  status_busy,
    input  logic [DATA_WIDTH-1:0] perf_data,

    output logic                  start,
    output logic                  soft_rst,
    output logic                  irq,

    output logic [15:0]           img_width,
    output logic [15:0]           img_height,
    output logic [7:0]            num_layers,
    output logic [1:0]            prec_sel,
    output logic [2:0]            act_sel,
    output logic [7:0]            threshold
);

    localparam logic [ADDR_WIDTH-1:0] ADDR_CTRL      = 'h00;
    localparam logic [ADDR_WIDTH-1:0] ADDR_STATUS    = 'h04;
    localparam logic [ADDR_WIDTH-1:0] ADDR_IMG_CFG   = 'h08;
    localparam logic [ADDR_WIDTH-1:0] ADDR_LAYER_CFG = 'h0C;
    localparam logic [ADDR_WIDTH-1:0] ADDR_PREC_CFG  = 'h10;
    localparam logic [ADDR_WIDTH-1:0] ADDR_ACT_CFG   = 'h14;
    localparam logic [ADDR_WIDTH-1:0] ADDR_THRESH    = 'h18;
    localparam logic [ADDR_WIDTH-1:0] ADDR_PERF      = 'h20;

    logic [DATA_WIDTH-1:0] ctrl_reg;
    logic [DATA_WIDTH-1:0] img_cfg_reg;
    logic [DATA_WIDTH-1:0] layer_cfg_reg;
    logic [DATA_WIDTH-1:0] prec_cfg_reg;
    logic [DATA_WIDTH-1:0] act_cfg_reg;
    logic [DATA_WIDTH-1:0] thresh_reg;
    logic [DATA_WIDTH-1:0] status_reg;

    logic en_ctrl;
    logic en_img_cfg;
    logic en_layer_cfg;
    logic en_prec_cfg;
    logic en_act_cfg;
    logic en_thresh;

    always_comb begin
        en_ctrl      = 1'b0;
        en_img_cfg   = 1'b0;
        en_layer_cfg = 1'b0;
        en_prec_cfg  = 1'b0;
        en_act_cfg   = 1'b0;
        en_thresh    = 1'b0;

        if (reg_wr_en) begin
            case (reg_waddr[7:2])
                ADDR_CTRL[7:2]:      en_ctrl      = 1'b1;
                ADDR_IMG_CFG[7:2]:   en_img_cfg   = 1'b1;
                ADDR_LAYER_CFG[7:2]: en_layer_cfg = 1'b1;
                ADDR_PREC_CFG[7:2]:  en_prec_cfg  = 1'b1;
                ADDR_ACT_CFG[7:2]:   en_act_cfg   = 1'b1;
                ADDR_THRESH[7:2]:    en_thresh    = 1'b1;
                default: ;
            endcase
        end
    end
 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start   <= 1'b0;
            soft_rst <= 1'b0;
        end
        else if (clk_enable) begin
            start   <= 1'b0;
            soft_rst <= 1'b0;
    
            if (en_ctrl) begin
                start   <= reg_wdata[0];
                soft_rst <= reg_wdata[1];
            end
        end
    end

    logic irq_enable_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_enable_reg <= 1'b0;
        end
        else if (clk_enable && en_ctrl) begin
            irq_enable_reg <= reg_wdata[2];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            img_cfg_reg   <= '0;
            layer_cfg_reg <= '0;
            prec_cfg_reg  <= '0;
            act_cfg_reg   <= '0;
            thresh_reg    <= '0;
        end
        else if (clk_enable) begin
            if (en_img_cfg)
                img_cfg_reg <= reg_wdata;

            if (en_layer_cfg)
                layer_cfg_reg <= reg_wdata;

            if (en_prec_cfg)
                prec_cfg_reg <= reg_wdata;

            if (en_act_cfg)
                act_cfg_reg <= reg_wdata;

            if (en_thresh)
                thresh_reg <= reg_wdata;
        end
    end

    always_comb begin
        status_reg = '0;
        status_reg[0] = status_busy;
        status_reg[1] = status_done;
        status_reg[2] = status_error;
    end

    always_comb begin
        reg_rdata = '0;

        case (reg_raddr[7:2])
            ADDR_CTRL[7:2]: begin
                reg_rdata[0] = start;
                reg_rdata[1] = soft_rst;
                reg_rdata[2] = irq_enable_reg;
            end

            ADDR_STATUS[7:2]:    reg_rdata = status_reg;
            ADDR_IMG_CFG[7:2]:   reg_rdata = img_cfg_reg;
            ADDR_LAYER_CFG[7:2]: reg_rdata = layer_cfg_reg;
            ADDR_PREC_CFG[7:2]:  reg_rdata = prec_cfg_reg;
            ADDR_ACT_CFG[7:2]:   reg_rdata = act_cfg_reg;
            ADDR_THRESH[7:2]:    reg_rdata = thresh_reg;
            ADDR_PERF[7:2]:      reg_rdata = perf_data;

            default:             reg_rdata = '0;
        endcase
    end

    always_comb begin
        img_width  = img_cfg_reg[15:0];
        img_height = img_cfg_reg[31:16];
        num_layers = layer_cfg_reg[7:0];
        prec_sel   = prec_cfg_reg[1:0];
        act_sel    = act_cfg_reg[2:0];
        threshold  = thresh_reg[7:0];
    end

    always_comb begin
        irq = irq_enable_reg && (status_done || status_error);
    end

endmodule
