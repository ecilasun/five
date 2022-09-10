`timescale 1ns / 1ps

module clockandreset(
	input wire sys_clock_i,
	output wire busclock,
	output wire wallclock,
	output wire uartbaseclock,
	output logic aresetn);

wire centralclocklocked, deviceclklocked;

centralclock centralclockinst(
	.clk_in1(sys_clock_i),
	.busclock(busclock),
	.locked(centralclocklocked) );

deviceclock deviceclockinst(
	.clk_in1(sys_clock_i),
	.wallclock(wallclock),
	.uartbaseclock(uartbaseclock),
	.locked(deviceclklocked) );

// Hold reset until clocks are locked
wire internalreset = ~(centralclocklocked & deviceclklocked);

// delayed reset post-clock-lock
logic [3:0] resetcountdown = 4'hf;
logic selfresetn = 1'b0;
always @(posedge wallclock) begin // using slowest clock
	if (internalreset) begin
		resetcountdown <= 4'hf;
		selfresetn <= 1'b0;
		aresetn <= 1'b0;
	end else begin
		if (/*busready &&*/ (resetcountdown == 4'h0))
			selfresetn <= 1'b1;
		else
			resetcountdown <= resetcountdown - 4'h1;
		aresetn <= selfresetn;
	end
end

endmodule
