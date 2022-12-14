`timescale 1ns / 1ps

import axi_pkg::*;

module axi4uart(
	input wire aclk,
	input wire aresetn,
	axi_if.slave s_axi,
	output wire uart_rxd_out,
	input wire uart_txd_in,
	output wire uartrcvempty );

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

//logic [31:0] writeaddress = 32'd0;
logic [7:0] din = 8'h00;
logic [3:0] we = 4'h0;

// ----------------------------------------------------------------------------
// uart transmitter
// ----------------------------------------------------------------------------

bit transmitbyte = 1'b0;
bit [7:0] datatotransmit = 8'h00;
wire uarttxbusy;

async_transmitter uart_transmit(
	.clk(aclk),
	.txd_start(transmitbyte),
	.txd_data(datatotransmit),
	.txd(uart_rxd_out),
	.txd_busy(uarttxbusy) );

wire [7:0] uartsenddout;
bit uartsendre = 1'b0;
wire uartsendfull, uartsendempty, uartsendvalid;

uartoutfifo UARTOut(
	.full(uartsendfull),
	.din(din),
	.wr_en( (|we) ),
	.clk(aclk),
	.empty(uartsendempty),
	.valid(uartsendvalid),
	.dout(uartsenddout),
	.rd_en(uartsendre),
	.rst(~aresetn) );

bit [1:0] uartwritemode = 2'b00;

always @(posedge aclk) begin
	uartsendre <= 1'b0;
	transmitbyte <= 1'b0;
	unique case(uartwritemode)
		2'b00: begin // idle
			if (~uartsendempty & (~uarttxbusy)) begin
				uartsendre <= 1'b1;
				uartwritemode <= 2'b01; // write
			end
		end
		2'b01: begin // write
			if (uartsendvalid) begin
				transmitbyte <= 1'b1;
				datatotransmit <= uartsenddout;
				uartwritemode <= 2'b10; // finalize
			end
		end
		default/*2'b10*/: begin // finalize
			// need to give uarttx one clock to
			// kick 'busy' for any adjacent
			// requests which didn't set busy yet
			uartwritemode <= 2'b00; // idle
		end
	endcase
end

// ----------------------------------------------------------------------------
// uart receiver
// ----------------------------------------------------------------------------

wire uartbyteavailable;
wire [7:0] uartbytein;

async_receiver uart_receive(
	.clk(aclk),
	.rxd(uart_txd_in),
	.rxd_data_ready(uartbyteavailable),
	.rxd_data(uartbytein),
	.rxd_idle(),
	.rxd_endofpacket() );

wire uartrcvfull, uartrcvvalid;
bit [7:0] uartrcvdin = 8'h00;
wire [7:0] uartrcvdout;
bit uartrcvre = 1'b0, uartrcvwe = 1'b0;

uartinfifo UARTIn(
	.full(uartrcvfull),
	.din(uartrcvdin),
	.wr_en(uartrcvwe),
	.clk(aclk),
	.empty(uartrcvempty),
	.dout(uartrcvdout),
	.rd_en(uartrcvre),
	.valid(uartrcvvalid),
	.rst(~aresetn) );

always @(posedge aclk) begin
	uartrcvwe <= 1'b0;
	// NOTE: Any byte that won't fit into the fifo will be dropped
	// make sure to consume them quickly on arrival!
	if (uartbyteavailable & (~uartrcvfull)) begin
		uartrcvwe <= 1'b1;
		uartrcvdin <= uartbytein;
	end
end

// IO_UARTRX     0x80000000
// IO_UARTTX     0x80000004
// IO_UARTStatus 0x80000008
// IO_UARTCtl    0x8000000C

// main state machine
always @(posedge aclk) begin
	if (~aresetn) begin
		s_axi.awready <= 1'b0;
	end else begin
		// write address
		case (waddrstate)
			2'b00: begin
				if (s_axi.awvalid) begin
					s_axi.awready <= 1'b1;
					//writeaddress <= s_axi.awaddr; // todo: select subdevice using some bits of address
					waddrstate <= 2'b01;
				end
			end
			default/*2'b01*/: begin
				s_axi.awready <= 1'b0;
				waddrstate <= 2'b00;
			end
		endcase
	end
end

always @(posedge aclk) begin
	if (~aresetn) begin
		s_axi.bresp <= 2'b00; // okay
		s_axi.bvalid <= 1'b0;
		s_axi.wready <= 1'b0;
	end else begin
		// write data
		we <= 4'h0;
		s_axi.wready <= 1'b0;
		s_axi.bvalid <= 1'b0;
		case (writestate)
			2'b00: begin
				if (s_axi.wvalid) begin
					case (s_axi.awaddr[3:0])
						4'h0: begin // rx data
							// Cannot write here, skip
							writestate <= 2'b01;
							s_axi.wready <= 1'b1;
						end
						4'h4: begin // tx data
							if (~uartsendfull) begin
								din <= s_axi.wdata[7:0];
								we <= s_axi.wstrb[3:0];
								writestate <= 2'b01;
								s_axi.wready <= 1'b1;
							end
						end
						4'h8: begin // status register
							// Cannot write here, skip
							writestate <= 2'b01;
							s_axi.wready <= 1'b1;
						end
						default/*2'hC*/: begin // control register
							// Cannot write here (yet), skip
							writestate <= 2'b01;
							s_axi.wready <= 1'b1;
						end
					endcase
				end
			end
			default/*2'b01*/: begin
				if (s_axi.bready) begin
					s_axi.bvalid <= 1'b1;
					writestate <= 2'b00;
				end
			end
		endcase
	end
end

always @(posedge aclk) begin
	if (~aresetn) begin
		s_axi.rlast <= 1'b1;
		s_axi.arready <= 1'b0;
		s_axi.rvalid <= 1'b0;
		s_axi.rresp <= 2'b00;
	end else begin
		// read address
		uartrcvre <= 1'b0;
		s_axi.rvalid <= 1'b0;
		s_axi.arready <= 1'b0;
		case (raddrstate)
			2'b00: begin
				if (s_axi.arvalid) begin
					s_axi.arready <= 1'b1;
					raddrstate <= 2'b01;
				end
			end
			2'b01: begin
				case (s_axi.araddr[3:0])
					4'h0: begin // rx data
						uartrcvre <= 1'b1;
						raddrstate <= 2'b10;
					end
					4'h4: begin // tx data
						// cannot read this, skip
						s_axi.rdata[31:0] <= 32'd0;
						s_axi.rvalid <= 1'b1;
						raddrstate <= 2'b00;
					end
					4'h8: begin // status register
						s_axi.rdata[31:0] <= {29'd0, uarttxbusy, uartrcvfull, ~uartrcvempty};
						s_axi.rvalid <= 1'b1;
						raddrstate <= 2'b00;
					end
					default/*4'hC*/: begin // control register
						// cannot read this (yet), skip
						s_axi.rdata[31:0] <= 32'd0;
						s_axi.rvalid <= 1'b1;
						raddrstate <= 2'b00;
					end
				endcase
			end
			default/*2'b10*/: begin
				// master ready to accept
				if (s_axi.rready & uartrcvvalid) begin
					s_axi.rdata[31:0] <= {uartrcvdout, uartrcvdout, uartrcvdout, uartrcvdout};
					s_axi.rvalid <= 1'b1;
					raddrstate <= 2'b00;
				end
			end
		endcase
	end
end

endmodule