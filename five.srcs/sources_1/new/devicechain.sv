`timescale 1ns / 1ps

import axi_pkg::*;

module uncacheddevicechain(
	input wire aclk,
	input wire aresetn,
	input wire uartbaseclock,
    axi_if.slave axi_s,
    input wire uart_txd_in,
    output wire uart_rxd_out,
    output wire [7:0] leds,
    output wire [1:0] interrupts);

// ------------------------------------------------------------------------------------
// Address decoder
// ------------------------------------------------------------------------------------

logic validwaddr_uart = 1'b0, validraddr_uart = 1'b0;
logic validwaddr_leds = 1'b0, validraddr_leds = 1'b0;

// UART: 0x80000000 - 0x8000000F
//  LED: 0x80000010 - 0x8000001F

always_comb begin
    if (axi_s.awaddr[31:16] == 16'h8000) begin
        validwaddr_uart	= (axi_s.awaddr[15:0]>=16'h0000) && (axi_s.awaddr[15:0]<16'h0010);
        validwaddr_leds	= (axi_s.awaddr[15:0]>=16'h0010) && (axi_s.awaddr[15:0]<16'h0020);
    end else begin
        validwaddr_uart	= 1'b0;
        validwaddr_leds	= 1'b0;
    end
end

always_comb begin
    if (axi_s.araddr[31:16] == 16'h8000) begin
        validraddr_uart	= (axi_s.araddr[15:0]>=16'h0000) && (axi_s.araddr[15:0]<16'h0010);
        validraddr_leds	= (axi_s.araddr[15:0]>=16'h0010) && (axi_s.araddr[15:0]<16'h0020);
    end else begin
        validraddr_uart	= 1'b0;
        validraddr_leds	= 1'b0;
    end
end

// ------------------------------------------------------------------------------------
// Devices
// ------------------------------------------------------------------------------------

axi_if uartif();
wire uart_interrupt;
axi4uartlite uartctl(
  .s_axi_aclk(aclk),
  .s_axi_aresetn(aresetn),
  .interrupt(uart_interrupt),
  .s_axi_awaddr(uartif.awaddr[3:0]),
  .s_axi_awvalid(uartif.awvalid),
  .s_axi_awready(uartif.awready),
  .s_axi_wdata(uartif.wdata[31:0]),
  .s_axi_wstrb(uartif.wstrb[3:0]),
  .s_axi_wvalid(uartif.wvalid),
  .s_axi_wready(uartif.wready),
  .s_axi_bresp(uartif.bresp),
  .s_axi_bvalid(uartif.bvalid),
  .s_axi_bready(uartif.bready),
  .s_axi_araddr(uartif.araddr[3:0]),
  .s_axi_arvalid(uartif.arvalid),
  .s_axi_arready(uartif.arready),
  .s_axi_rdata(uartif.rdata[31:0]),
  .s_axi_rresp(uartif.rresp),
  .s_axi_rvalid(uartif.rvalid),
  .s_axi_rready(uartif.rready),
  .rx(uart_txd_in),
  .tx(uart_rxd_out)
);

axi_if ledif();
axi4ledctl ledctl(
	.aclk(aclk),
	.aresetn(aresetn),
	.s_axi(ledif),
	.leds(leds) );
	
// ------------------------------------------------------------------------------------
// IRQ
// ------------------------------------------------------------------------------------

assign interrupts = {1'b0, uart_interrupt};

// ------------------------------------------------------------------------------------
// Write router
// ------------------------------------------------------------------------------------

wire [31:0] waddr = {3'b000, axi_s.awaddr[28:0]};

always_comb begin
	uartif.awaddr = validwaddr_uart ? waddr : 32'd0;
	uartif.awvalid = validwaddr_uart ? axi_s.awvalid : 1'b0;
	uartif.awlen = validwaddr_uart ? axi_s.awlen : 0;
	uartif.awsize = validwaddr_uart ? axi_s.awsize : 0;
	uartif.awburst = validwaddr_uart ? axi_s.awburst : 0;
	uartif.wdata = validwaddr_uart ? axi_s.wdata : 0;
	uartif.wstrb = validwaddr_uart ? axi_s.wstrb : 'd0;
	uartif.wvalid = validwaddr_uart ? axi_s.wvalid : 1'b0;
	uartif.bready = validwaddr_uart ? axi_s.bready : 1'b0;
	uartif.wlast = validwaddr_uart ? axi_s.wlast : 1'b0;

	ledif.awaddr = validwaddr_leds ? waddr : 32'd0;
	ledif.awvalid = validwaddr_leds ? axi_s.awvalid : 1'b0;
	ledif.awlen = validwaddr_leds ? axi_s.awlen : 0;
	ledif.awsize = validwaddr_leds ? axi_s.awsize : 0;
	ledif.awburst = validwaddr_leds ? axi_s.awburst : 0;
	ledif.wdata = validwaddr_leds ? axi_s.wdata : 0;
	ledif.wstrb = validwaddr_leds ? axi_s.wstrb : 4'h0;
	ledif.wvalid = validwaddr_leds ? axi_s.wvalid : 1'b0;
	ledif.bready = validwaddr_leds ? axi_s.bready : 1'b0;
	ledif.wlast = validwaddr_leds ? axi_s.wlast : 1'b0;

    if (validwaddr_uart) begin
		axi_s.awready = uartif.awready;
		axi_s.bresp = uartif.bresp;
		axi_s.bvalid = uartif.bvalid;
		axi_s.wready = uartif.wready;
	end else if (validwaddr_leds) begin
		axi_s.awready = ledif.awready;
		axi_s.bresp = ledif.bresp;
		axi_s.bvalid = ledif.bvalid;
		axi_s.wready = ledif.wready;
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

	uartif.araddr = validraddr_uart ? raddr : 32'd0;
	uartif.arlen = validraddr_uart ? axi_s.arlen : 0;
	uartif.arsize = validraddr_uart ? axi_s.arsize : 0;
	uartif.arburst = validraddr_uart ? axi_s.arburst : 0;
	uartif.arvalid = validraddr_uart ? axi_s.arvalid : 1'b0;
	uartif.rready = validraddr_uart ? axi_s.rready : 1'b0;

	ledif.araddr = validraddr_leds ? raddr : 32'd0;
	ledif.arlen = validraddr_leds ? axi_s.arlen : 0;
	ledif.arsize = validraddr_leds ? axi_s.arsize : 0;
	ledif.arburst = validraddr_leds ? axi_s.arburst : 0;
	ledif.arvalid = validraddr_leds ? axi_s.arvalid : 1'b0;
	ledif.rready = validraddr_leds ? axi_s.rready : 1'b0;

	if (validraddr_uart) begin
		axi_s.arready = uartif.arready;
		axi_s.rdata = uartif.rdata;
		axi_s.rresp = uartif.rresp;
		axi_s.rvalid = uartif.rvalid;
		axi_s.rlast = uartif.rlast;
	end else if (validraddr_leds) begin
		axi_s.arready = ledif.arready;
		axi_s.rdata = ledif.rdata;
		axi_s.rresp = ledif.rresp;
		axi_s.rvalid = ledif.rvalid;
		axi_s.rlast = ledif.rlast;
	end else begin
		axi_s.arready = 0;
		axi_s.rdata = 0;
		axi_s.rresp = 0;
		axi_s.rvalid = 0;
		axi_s.rlast = 0;
	end
end

endmodule
