`timescale 1ns / 1ps

import axi_pkg::*;

module tophat(
	// Board clock
	input wire sys_clock,
	// UART
	output wire uart_rxd_out,
	input wire uart_txd_in,
	// LEDs
	output wire [7:0] leds);

// ----------------------------------------------------------------------------
// Clock / Reset generator
// ----------------------------------------------------------------------------

wire aclk;
wire aresetn;

clockandreset ClockAndResetGen(
	.sys_clock_i(sys_clock),
	.busclock(aclk),
	.aresetn(aresetn) );

// ----------------------------------------------------------------------------
// Bus layout
// ----------------------------------------------------------------------------

// Devices that need access to the bus
axi_if cached_axi_cpu0();
axi_if uncached_axi_cpu0();
axi_if cached_axi_cpu1();
axi_if uncached_axi_cpu1();

// Shared buses
axi_if cached_axi_m();
axi_if uncached_axi_m();

// ----------------------------------------------------------------------------
// Clock counters
// ----------------------------------------------------------------------------

logic [63:0] cpuclocktime = 'd0;

always_ff @(posedge aclk) begin
	cpuclocktime <= cpuclocktime + 1;
end

// ----------------------------------------------------------------------------
// CPUs
// ----------------------------------------------------------------------------

wire [1:0] interrupts;
rv32i #(.HARTID(0), .RESETVECTOR(32'h00000000)) rv32instanceOne (
	.aclk(aclk),
	.aresetn(aresetn),
	.interrupts(interrupts),
	.cpuclocktime(cpuclocktime),
	.cached_axi_m(cached_axi_cpu0),
	.uncached_axi_m(uncached_axi_cpu0) );

rv32i #(.HARTID(1), .RESETVECTOR(32'h00000000)) rv32instanceTwo (
	.aclk(aclk),
	.aresetn(aresetn),
	.interrupts(interrupts),
	.cpuclocktime(cpuclocktime),
	.cached_axi_m(cached_axi_cpu1),
	.uncached_axi_m(uncached_axi_cpu1) );

// ----------------------------------------------------------------------------
// AXI bus and arbiter
// ----------------------------------------------------------------------------

// Arbiter for bus access
arbiter uncachedarbiterinst(
	.aclk(aclk),
	.aresetn(aresetn),
	.axi_s({uncached_axi_cpu1, uncached_axi_cpu0}),
	.axi_m(uncached_axi_m) );

arbiter cachedarbiterinst(
	.aclk(aclk),
	.aresetn(aresetn),
	.axi_s({cached_axi_cpu1, cached_axi_cpu0}),
	.axi_m(cached_axi_m) );

// Device chains and address decoders
uncacheddevicechain uncacheddevicechaininst(
	.aclk(aclk),
	.aresetn(aresetn),
    .axi_s(uncached_axi_m),
    .uart_txd_in(uart_txd_in),
    .uart_rxd_out(uart_rxd_out),
    .leds(leds),
    .interrupts(interrupts));

cacheddevicechain cacheddevicechaininst(
	.aclk(aclk),
	.aresetn(aresetn),
    .axi_s(cached_axi_m) );

endmodule
