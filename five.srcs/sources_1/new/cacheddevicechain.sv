`timescale 1ns / 1ps

import axi_pkg::*;

module cacheddevicechain(
	input wire aclk,
	input wire aresetn,
    axi_if.slave axi_s );

// ------------------------------------------------------------------------------------
// Address decoder
// ------------------------------------------------------------------------------------

logic validwaddr_bmem = 1'b0, validraddr_bmem = 1'b0;

//    BMEM: 0x00000000 - 0x0000FFFF
//  unused: 0x00010000 - 0x7FFFFFFF

always_comb begin
    if (axi_s.awaddr[31] == 1'b0) begin
        validwaddr_bmem	= (axi_s.awaddr[30:0]>=31'h00000000) && (axi_s.awaddr[30:0]<31'h00010000);
    end else begin
        validwaddr_bmem	= 1'b0;
    end
end

always_comb begin
    if (axi_s.araddr[31] == 1'b0) begin
        validraddr_bmem	= (axi_s.araddr[30:0]>=31'h00000000) && (axi_s.araddr[30:0]<31'h00010000);
    end else begin
        validraddr_bmem	= 1'b0;
    end
end

// ------------------------------------------------------------------------------------
// Devices
// ------------------------------------------------------------------------------------

axi_if bmemif();
wire rsta_busy;
wire rstb_busy;
axiblockmem bootmem (
  .rsta_busy(rsta_busy),
  .rstb_busy(rstb_busy),
  .s_aclk(aclk),
  .s_aresetn(aresetn),
  .s_axi_awid(4'h0),
  .s_axi_awaddr(bmemif.awaddr),
  .s_axi_awlen(bmemif.awlen),
  .s_axi_awsize(bmemif.awsize),
  .s_axi_awburst(bmemif.awburst),
  .s_axi_awvalid(bmemif.awvalid),
  .s_axi_awready(bmemif.awready),
  .s_axi_wdata(bmemif.wdata),
  .s_axi_wstrb(bmemif.wstrb),
  .s_axi_wlast(bmemif.wlast),
  .s_axi_wvalid(bmemif.wvalid),
  .s_axi_wready(bmemif.wready),
  .s_axi_bid(),
  .s_axi_bresp(bmemif.bresp),
  .s_axi_bvalid(bmemif.bvalid),
  .s_axi_bready(bmemif.bready),
  .s_axi_arid(4'h0),
  .s_axi_araddr(bmemif.araddr),
  .s_axi_arlen(bmemif.arlen),
  .s_axi_arsize(bmemif.arsize),
  .s_axi_arburst(bmemif.arburst),
  .s_axi_arvalid(bmemif.arvalid),
  .s_axi_arready(bmemif.arready),
  .s_axi_rid(),
  .s_axi_rdata(bmemif.rdata),
  .s_axi_rresp(bmemif.rresp),
  .s_axi_rlast(bmemif.rlast),
  .s_axi_rvalid(bmemif.rvalid),
  .s_axi_rready(bmemif.rready) );

// ------------------------------------------------------------------------------------
// Write router
// ------------------------------------------------------------------------------------

wire [31:0] waddr = {3'b000, axi_s.awaddr[28:0]};

always_comb begin
	bmemif.awaddr = validwaddr_bmem ? waddr : 32'd0;
	bmemif.awvalid = validwaddr_bmem ? axi_s.awvalid : 1'b0;
	bmemif.awlen = validwaddr_bmem ? axi_s.awlen : 0;
	bmemif.awsize = validwaddr_bmem ? axi_s.awsize : 0;
	bmemif.awburst = validwaddr_bmem ? axi_s.awburst : 0;
	bmemif.wdata = validwaddr_bmem ? axi_s.wdata : 0;
	bmemif.wstrb = validwaddr_bmem ? axi_s.wstrb : 'd0;
	bmemif.wvalid = validwaddr_bmem ? axi_s.wvalid : 1'b0;
	bmemif.bready = validwaddr_bmem ? axi_s.bready : 1'b0;
	bmemif.wlast = validwaddr_bmem ? axi_s.wlast : 1'b0;

	if (validwaddr_bmem) begin
		axi_s.awready = bmemif.awready;
		axi_s.bresp = bmemif.bresp;
		axi_s.bvalid = bmemif.bvalid;
		axi_s.wready = bmemif.wready;
	end else begin
		axi_s.awready = 0;
		axi_s.bresp = 0;
		axi_s.bvalid = 0;
		axi_s.wready = 0;
	end
end

// ------------------------------------------------------------------------------------
// Read router
// ------------------------------------------------------------------------------------

wire [31:0] raddr = {3'b000, axi_s.araddr[28:0]};

always_comb begin

	bmemif.araddr = validraddr_bmem ? raddr : 32'd0;
	bmemif.arlen = validraddr_bmem ? axi_s.arlen : 0;
	bmemif.arsize = validraddr_bmem ? axi_s.arsize : 0;
	bmemif.arburst = validraddr_bmem ? axi_s.arburst : 0;
	bmemif.arvalid = validraddr_bmem ? axi_s.arvalid : 1'b0;
	bmemif.rready = validraddr_bmem ? axi_s.rready : 1'b0;

	if (validraddr_bmem) begin
		axi_s.arready = bmemif.arready;
		axi_s.rdata = bmemif.rdata;
		axi_s.rresp = bmemif.rresp;
		axi_s.rvalid = bmemif.rvalid;
		axi_s.rlast = bmemif.rlast;
	end else begin
		axi_s.arready = 0;
		axi_s.rdata = 0;
		axi_s.rresp = 0;
		axi_s.rvalid = 0;
		axi_s.rlast = 0;
	end
end

endmodule
