// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// PACE coefficient memory.
//
// Memory-mapped store for the piecewise-polynomial approximation coefficients
// consumed by the PACE extension inside fpnew. It plays the same role as the
// Snitch reference implementation (`axi_pace_mem.sv`): software writes the
// coefficient words through the regular data path, and the whole bank is
// exposed to the FPU as a single flat bus.
//
// The bank sits on a cluster peripheral slot, so cores reach it with ordinary
// word stores. Reads are supported as well, which is only useful for debugging.

module pace_param_mem #(
  // Total width of the coefficient bus expected by fpnew (PaceParamWidth).
  parameter int unsigned PACE_PARAM_WIDTH = 2080
) (
  input logic clk_i,
  input logic rst_ni,

  // Cluster peripheral slot: `req & wen` is a read, `req & ~wen` is a write.
  XBAR_PERIPH_BUS.Slave periph_slave,

  // Flat coefficient bus towards cv32e40p_fp_wrapper.
  output logic [PACE_PARAM_WIDTH-1:0] pace_param_o
);

  localparam int unsigned NumWords = PACE_PARAM_WIDTH / 32;

  // The peripheral slot is a 1 kB window, so add[8:2] indexes up to 128 words.
  localparam int unsigned IdxBits = 7;

  logic [NumWords-1:0][31:0] param_q;

  logic [IdxBits-1:0] word_idx;
  logic               idx_valid;
  logic               do_write;
  logic               do_read;

  logic        rvalid_q;
  logic [31:0] rdata_q;
  logic [$bits(periph_slave.id)-1:0] id_q;

  assign word_idx  = periph_slave.add[IdxBits+1:2];
  assign idx_valid = (word_idx < NumWords);

  assign do_write = periph_slave.req & ~periph_slave.wen & idx_valid;
  assign do_read  = periph_slave.req &  periph_slave.wen;

  // Coefficient bank: byte-enabled word writes.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      param_q <= '0;
    end else if (do_write) begin
      for (int unsigned b = 0; b < 4; b++) begin
        if (periph_slave.be[b]) begin
          param_q[word_idx][8*b+:8] <= periph_slave.wdata[8*b+:8];
        end
      end
    end
  end

  // Response channel: single-cycle latency, never stalls the requester.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rvalid_q <= 1'b0;
      rdata_q  <= '0;
      id_q     <= '0;
    end else begin
      rvalid_q <= periph_slave.req;
      if (periph_slave.req) begin
        id_q <= periph_slave.id;
      end
      if (do_read) begin
        rdata_q <= idx_valid ? param_q[word_idx] : '0;
      end
    end
  end

  assign periph_slave.gnt     = 1'b1;
  assign periph_slave.r_valid = rvalid_q;
  assign periph_slave.r_rdata = rdata_q;
  assign periph_slave.r_opc   = 1'b0;
  assign periph_slave.r_id    = id_q;

  assign pace_param_o = param_q;

endmodule  // pace_param_mem
