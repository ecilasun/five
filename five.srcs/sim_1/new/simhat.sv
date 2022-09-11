`timescale 1ns / 1ps

module simhat(
    );

logic sys_clock = 1'b0;

wire uart_rxd_out;
wire uart_rxd_in = 1'b1;

tophat tophatinst(
	.sys_clock(sys_clock),
	.uart_rxd_out(),
	.uart_txd_in() );

initial begin
    sys_clock = 1'bz;
    #10;
    sys_clock = 1'b0;
end

always begin
    sys_clock = ~sys_clock;
    #5;
end

endmodule
