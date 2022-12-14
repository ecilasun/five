`timescale 1ns / 1ps

module arbiter(
	input wire aclk,
	input wire aresetn,
	axi_if.slave axi_s[1:0],	// To slave in ports of master devices
	axi_if.master axi_m );		// To master in port of slave device

typedef enum logic [3:0] {INIT, ARBITRATE, GRANTED} arbiterstatetype;
arbiterstatetype arbiterstate = INIT, nextarbiterstate = INIT;

logic [1:0] req;
logic [1:0] grant;
logic reqcomplete = 0;

// A request is considered only when an incoming read or write address is valid
genvar reqgen;
generate
for (reqgen=0; reqgen<2; reqgen++) begin
	always_comb begin
		req[reqgen] = axi_s[reqgen].arvalid || axi_s[reqgen].awvalid;
	end
end
endgenerate

// A grant is complete once we get a notification for a read or write completion
always_comb begin
	reqcomplete = (axi_m.rvalid && axi_m.rlast) || axi_m.bvalid;
end

wire [1:0] grantselect = ((~req+1)&req);

always_ff @(posedge aclk) begin
	if (~aresetn) begin
		grant <= 0;
	end else begin
		// Grant access to the lowest device index requesting (lowest bit)
		case (arbiterstate)
			ARBITRATE: grant <= grantselect;
			default: grant <= grant;
		endcase
	end
end

genvar gnt;
generate
for (gnt=0; gnt<2; gnt++) begin
	always_comb begin
		axi_s[gnt].arready = grant[gnt] ? axi_m.arready : 0;
		axi_s[gnt].rdata   = grant[gnt] ? axi_m.rdata : 'dz;
		axi_s[gnt].rresp   = grant[gnt] ? axi_m.rresp : 0;
		axi_s[gnt].rvalid  = grant[gnt] ? axi_m.rvalid : 0;
		axi_s[gnt].rlast   = grant[gnt] ? axi_m.rlast : 0;
		axi_s[gnt].awready = grant[gnt] ? axi_m.awready : 0;
		axi_s[gnt].wready  = grant[gnt] ? axi_m.wready : 0;
		axi_s[gnt].bresp   = grant[gnt] ? axi_m.bresp : 0;
		axi_s[gnt].bvalid  = grant[gnt] ? axi_m.bvalid : 0;
	end
end
endgenerate

always_comb begin
	if (grant[1]) begin
		axi_m.araddr	= axi_s[1].araddr;
		axi_m.arvalid	= axi_s[1].arvalid;
		axi_m.arlen		= axi_s[1].arlen;
		axi_m.arsize	= axi_s[1].arsize;
		axi_m.arburst	= axi_s[1].arburst;
		axi_m.rready	= axi_s[1].rready;
		axi_m.awaddr	= axi_s[1].awaddr;
		axi_m.awvalid	= axi_s[1].awvalid;
		axi_m.awlen		= axi_s[1].awlen;
		axi_m.awsize	= axi_s[1].awsize;
		axi_m.awburst	= axi_s[1].awburst;
		axi_m.wdata		= axi_s[1].wdata;
		axi_m.wstrb		= axi_s[1].wstrb;
		axi_m.wvalid	= axi_s[1].wvalid;
		axi_m.wlast		= axi_s[1].wlast;
		axi_m.bready	= axi_s[1].bready;
	end else if (grant[0]) begin
		axi_m.araddr	= axi_s[0].araddr;
		axi_m.arvalid	= axi_s[0].arvalid;
		axi_m.arlen		= axi_s[0].arlen;
		axi_m.arsize	= axi_s[0].arsize;
		axi_m.arburst	= axi_s[0].arburst;
		axi_m.rready	= axi_s[0].rready;
		axi_m.awaddr	= axi_s[0].awaddr;
		axi_m.awvalid	= axi_s[0].awvalid;
		axi_m.awlen		= axi_s[0].awlen;
		axi_m.awsize	= axi_s[0].awsize;
		axi_m.awburst	= axi_s[0].awburst;
		axi_m.wdata		= axi_s[0].wdata;
		axi_m.wstrb		= axi_s[0].wstrb;
		axi_m.wvalid	= axi_s[0].wvalid;
		axi_m.wlast		= axi_s[0].wlast;
		axi_m.bready	= axi_s[0].bready;
	end else begin
		axi_m.araddr	= 0;
		axi_m.arvalid	= 0;
		axi_m.arlen		= 0;
		axi_m.arsize	= 0;
		axi_m.arburst	= 0;
		axi_m.rready	= 0;
		axi_m.awaddr	= 0;
		axi_m.awvalid	= 0;
		axi_m.awlen		= 0;
		axi_m.awsize	= 0;
		axi_m.awburst	= 0;
		axi_m.wdata		= 'dz;
		axi_m.wstrb		= 0;
		axi_m.wvalid	= 0;
		axi_m.wlast		= 0;
		axi_m.bready	= 0;
	end
end

always_ff @(posedge aclk) begin
	if (~aresetn) begin
		arbiterstate <= INIT;
	end else begin
		arbiterstate <= nextarbiterstate;
	end
end

always_comb begin
	case (arbiterstate)
		INIT: begin
			nextarbiterstate = ARBITRATE;
		end

		ARBITRATE: begin
			nextarbiterstate = (|req) ? GRANTED : ARBITRATE;
		end

		default/*GRANTED*/: begin
			nextarbiterstate = reqcomplete ? ARBITRATE : GRANTED;
		end
	endcase
end

endmodule
