`timescale 1ns / 1ps

import axi_pkg::*;

`include "shared.vh"

module rv32i #(
	parameter int HARTID = 32'h00000000,
	parameter int RESETVECTOR = 32'h00000000
) (
	input wire aclk,
	input wire aresetn,
	input wire [1:0] interrupts, // External machine interrupts
	input wire [63:0] cpuclocktime, // CPU clock in cc domain
	axi_if.master cached_axi_m,
	axi_if.master uncached_axi_m );

// Handle CDC for signals from non-aclk domains
(* async_reg = "true" *) logic [63:0] cc1;
(* async_reg = "true" *) logic [63:0] cc2;

always @(posedge aclk) begin
	cc1 <= cpuclocktime;
	cc2 <= cc1; // CSR value
end

typedef enum logic [3:0] {INIT, RETIRE, FETCH, DECODE, ADDRESSCALC, EXECUTE, STOREWAIT, LOADWAIT, INTERRUPTSETUP, INTERRUPTVALUE, INTERRUPTCAUSE, WFI} cpustatetype;
cpustatetype cpustate = INIT;

wire [17:0] instrOneHotOut;
wire [3:0] aluop;
wire [2:0] bluop;
wire [2:0] func3;
wire [6:0] func7;
wire [11:0] func12;
wire [4:0] rs1, rs2, rs3, rd, csrindex;
wire [31:0] immed;
wire immsel, isrecordingform;
wire dready;

addr_t addr = RESETVECTOR;		// Memory address
logic ren = 1'b0;				// Read enable
logic [3:0] wstrb = 4'h0;		// Write strobe
wire [31:0] din;				// Input to CPU
logic [31:0] dout;				// Output from CPU

logic ecall = 1'b0;				// SYSCALL
logic ebreak = 1'b0;			// BREAKPOINT

logic ifetch = 1'b0;			// I$/D$ select
logic [2:0] dcacheop = 3'b000;	// Cache command
wire wready, rready;			// Cache r/w state

logic [31:0] PC = RESETVECTOR;
logic [31:0] nextPC = RESETVECTOR;
logic [31:0] offsetPC = 32'd0;
logic [31:0] rwaddress = 32'd0;
logic [31:0] adjacentPC = 32'd0;
logic [63:0] retired = 0;
logic illegalinstruction = 1'b0;

wire isuncached = addr[31];		// NOTE: anything at and above 0x80000000 is uncached memory
wire [7:0] cline = addr[13:6];	// Cache line, disregarding ifetch
wire [16:0] ctag = addr[30:14];	// Cache tag
wire [3:0] coffset = addr[5:2];	// Cache word offset

// Integer register file
logic rwe = 1'b0;
wire [31:0] rval1;
wire [31:0] rval2;
logic [31:0] rdin;

// CSR shadows
wire [31:0] mip;	// Interrupt pending
wire [31:0] mie;	// Interrupt enable
wire [31:0] mtvec;	// Interrupt handler vector
wire [31:0] mepc;	// Interrupt return address
wire [31:0] mtval;	// Interrupt time value
wire [31:0] mcause;	// Interrupt cause bits
wire [63:0] tcmp;	// Time compare

// CSR access
logic csrwe = 1'b0;
logic [31:0] csrdin = 0;
logic [31:0] csrprevval;
logic csrwenforce = 1'b0;
logic [4:0] csrenforceindex = 0;
wire [31:0] csrdout;

// BLU
wire branchout;

// ALU
wire [31:0] aluout;

// Timer trigger
wire trq = (cc2 >= tcmp) ? 1'b1 : 1'b0;
// Any external wire event triggers our interrupt service if corresponding enable bit is high
wire hwint = (|interrupts) && mie[11];	// MEIE - machine external interrupt enable
// Timer interrupts
wire timerint = trq && mie[7];	// MTIE - timer interrupt enable

// Retired instruction counter
always @(posedge aclk) begin
	retired <= retired + (cpustate == RETIRE ? 64'd1 : 64'd0);
end

logic [31:0] instruction = 32'd0;
instructiondecoder instructiondecoderinst(
	.aresetn(aresetn),
	.aclk(aclk),
	.enable(cpustate == DECODE),
	.instruction(instruction),
	.instrOneHotOut(instrOneHotOut),
	.isrecordingform(isrecordingform),
	.aluop(aluop),
	.bluop(bluop),
	.func3(func3),
	.func7(func7),
	.func12(func12),
	.rs1(rs1),
	.rs2(rs2),
	.rs3(rs3),
	.rd(rd),
	.csrindex(csrindex),
	.immed(immed),
	.selectimmedasrval2(immsel),
	.dready(dready) );

systemcache cacheinst(
	.aclk(aclk),
	.aresetn(aresetn),
	// Cache address, decoded
	.uncached(isuncached),
	.line(cline),
	.tag(ctag),
	.offset(coffset),
	// From CPU
	.dcacheop(dcacheop),
	.ifetch(ifetch),
	.addr(addr),
	.din(dout),
	.dout(din),
	.wstrb(wstrb),
	.ren(ren),
	.wready(wready),
	.rready(rready),
	.a4buscached(cached_axi_m),
	.a4busuncached(uncached_axi_m) );

integerregisterfile integerregisterfileinst(
	.clock(aclk),
	.rs1(rs1),
	.rs2(rs2),
	.rd(rd),
	.wren(rwe),
	.din(rdin),
	.rval1(rval1),
	.rval2(rval2) );

csrregisterfile #(.HARTID(HARTID)) csrregisterfileinst (
	.clock(aclk),
	.cpuclocktime(cc2),
	.retired(retired),
	.tcmp(tcmp),
	.mie(mie),
	.mip(mip),
	.mtvec(mtvec),
	.mepc(mepc),
	.csrindex(csrwenforce ? csrenforceindex : csrindex),
	.we(csrwe),
	.dout(csrdout),
	.din(csrdin) );

branchlogic branchlogicunit (
	.enable(cpustate == DECODE),
	.aclk(aclk),
	.branchout(branchout),
	.val1(rval1),
	.val2(rval2),
	.bluop(bluop) );

arithmeticlogic artithmeticlogicunit (
	.enable(cpustate == DECODE),
	.aclk(aclk),
	.aluout(aluout),
	.val1(rval1),
	.val2(immsel ? immed : rval2),
	.aluop(aluop) );

always @(posedge aclk) begin
	if (~aresetn) begin
		cpustate <= INIT;
	end else begin

		wstrb <= 4'h0;
	 	ren <= 1'b0;
	 	rwe <= 1'b0;
	 	csrwe <= 1'b0;
	 	csrwenforce <= 1'b0;
	 	dcacheop <= 3'b000;

		case (cpustate)
			INIT: begin
				addr <= RESETVECTOR;
				PC <= RESETVECTOR;
				nextPC <= RESETVECTOR;
				cpustate <= RETIRE;
			end

			RETIRE: begin
				if ( (illegalinstruction || ecall || ebreak || hwint || timerint) && ~(|mip)) begin
				    csrwe <= 1'b1;
					csrwenforce <= 1'b1;
					// Save PC of next instruction that would have executed before IRQ
					// For EBREAK, use current PC so that debugger can stop where it wants to
					csrdin <= ebreak ? PC : nextPC;
					csrenforceindex <= `CSR_MEPC;
					// Branch to the ISR instead
					// For EBREAK, we have to do special debugger processing in the ISR
					PC <= mtvec;
					// Need to set up a few CSRs before we can actually trigger the FETCH
					cpustate <= INTERRUPTSETUP;
				end else begin
                    // Regular instruction fetch
                    PC <= nextPC;
                    addr <= nextPC;
                    ifetch <= 1'b1; // This read is to use I$, hold high until read is complete
                    ren <= 1'b1;
                    cpustate <= FETCH;
                end
			end

			INTERRUPTSETUP: begin
				// Write machine interrupt pending bits
				csrwe <= 1'b1;
				csrwenforce <= 1'b1;
				csrenforceindex <= `CSR_MIP;
				csrdin <= 32'd0;
				// NOTE: Interrupt service ordering according to privileged isa is: mei/msi/mti/sei/ssi/sti
				if (hwint) begin
					// MEI, external hardware interrupt
					csrdin <= {mip[31:12], 1'b1, mip[10:0]};
				end else if (illegalinstruction || ecall || ebreak) begin
					// MSI, exception
					csrdin <= {mip[31:4], 1'b1, mip[2:0]};
				end else if (timerint) begin
					// MTI, timer interrupt
					csrdin <= {mip[31:8], 1'b1, mip[6:0]};
				end
				cpustate <= INTERRUPTVALUE;
			end

			INTERRUPTVALUE: begin
				// Write the interrupt value bits
				csrwe <= 1'b1;
				csrwenforce <= 1'b1;
				csrenforceindex <= `CSR_MTVAL;
				csrdin <= 32'd0;
				if (hwint) begin
					// MEI, external hardware interrupt
					csrdin  <= {30'd0, interrupts};	// Device IRQ bits, all those are pending
				end else if (illegalinstruction || ecall || ebreak) begin
					// MSI, exception
					csrdin <= ebreak ? PC : 32'd0;	// Write PC for ebreak instruction TODO: write offending instruction here for illlegalinstruction
				end else if (timerint) begin
					// MTI, timer interrupt
					csrdin  <= 32'd0;				// TODO: timer interrupt doesn't need much data, maybe store the PC where interrupt occurred?
				end
				cpustate <= INTERRUPTCAUSE;
			end

			INTERRUPTCAUSE: begin
				// Write the interrupt/exception cause
				csrwe <= 1'b1;
				csrwenforce <= 1'b1;
				csrenforceindex <= `CSR_MCAUSE;
				csrdin <= 32'd0;
				if (hwint) begin
					// MEI, external hardware interrupt
					csrdin  <= 32'h8000000b; // [31]=1'b1(interrupt), 11->h/w
				end else if (illegalinstruction || ecall || ebreak) begin
					// MSI, exception
					// See: https://www.five-embeddev.com/riscv-isa-manual/latest/machine.html#sec:mcause
					// [31]=1'b0(exception)
					// 0xb->ecall
					// 0x3->ebreak
					// 0x2->illegal instruction
					csrdin  <= ecall ? 32'h0000000b : (ebreak ? 32'h00000003 : 32'h00000002);
				end else if (timerint) begin
					// MTI, timer interrupt
					csrdin  <= 32'h80000007; // [31]=1'b1(interrupt), 7->timer
				end
				// We can now resume reading the first instruction of the ISR
				// Return address is saved in MEPC, so we can go back once done
				addr <= mtvec;
				ifetch <= 1'b1;
				ren <= 1'b1;
				cpustate <= FETCH;
			end

			FETCH: begin
				instruction <= din;
				ifetch <= ~rready;
				cpustate <= rready ? DECODE : FETCH;
			end
			
			DECODE: begin
				cpustate <= dready ? ADDRESSCALC : DECODE;
			end

			ADDRESSCALC: begin
				rwaddress <= rval1 + immed;
				adjacentPC <= PC + 32'd4;
				offsetPC <= PC + immed;
				csrprevval <= csrdout;
				cpustate <= EXECUTE;
			end

			EXECUTE: begin
    			cpustate <= RETIRE;
				rwe <= isrecordingform;
				illegalinstruction <= 1'b0; // No longer an illegal instruction
				ecall <= 1'b0; // No longer in ECALL
				nextPC <= adjacentPC;

				case (1'b1)
					instrOneHotOut[`O_H_AUIPC]: begin
						rdin <= offsetPC;
					end
					instrOneHotOut[`O_H_LUI]: begin
						rdin <= immed;
					end
					instrOneHotOut[`O_H_JAL]: begin
						rdin <= adjacentPC;
						nextPC <= offsetPC;
					end
					instrOneHotOut[`O_H_JALR]: begin
						rdin <= adjacentPC;
						nextPC <= rwaddress;
					end
					instrOneHotOut[`O_H_BRANCH]: begin
						nextPC <= branchout == 1'b1 ? offsetPC : adjacentPC;
					end
					instrOneHotOut[`O_H_OP], instrOneHotOut[`O_H_OP_IMM]: begin
						cpustate <= RETIRE;
						rdin <= aluout;
					end
					instrOneHotOut[`O_H_LOAD]: begin
						addr <= rwaddress;
						ren <= 1'b1; // This read is to use D$ (i.e. ifetch == 0 here)
						cpustate <= LOADWAIT;
					end
					instrOneHotOut[`O_H_STORE]: begin
						case (func3)
							3'b000: begin // BYTE
								dout <= {rval2[7:0], rval2[7:0], rval2[7:0], rval2[7:0]};
								case (rwaddress[1:0])
									2'b11: begin wstrb <= 4'b1000; end
									2'b10: begin wstrb <= 4'b0100; end
									2'b01: begin wstrb <= 4'b0010; end
									default/*2'b00*/: begin wstrb <= 4'b0001; end
								endcase
							end
							3'b001: begin // WORD
								dout <= {rval2[15:0], rval2[15:0]};
								case (rwaddress[1])
									1'b1: begin wstrb <= 4'b1100; end
									default/*1'b0*/: begin wstrb <= 4'b0011; end
								endcase
							end
							default: begin // DWORD
								dout <= rval2;
								wstrb <= 4'b1111;
							end
						endcase
						addr <= rwaddress;
						cpustate <= STOREWAIT;
					end
					instrOneHotOut[`O_H_FENCE]: begin
						// f12            rs1   f3  rd    OPCODE
						// 0000_pred_succ_00000_000_00000_0001111 -> FENCE (32'h0ff0000f)
						//if (instruction == 32'h0ff0000f) // FENCE
						//	fence <= 1'b1;

						// f12         rs1   f3  rd    OPCODE
						//000000000000_00000_001_00000_0001111 -> FENCE.I (32'h0000100F) Flush I$
						if ({func12, func3} == {12'd0, 3'b001}) begin
							dcacheop <= 3'b101;			// I$, do not write back (invalidate tags to fore re-read), mark valid
							cpustate <= STOREWAIT;
						end	else
							dcacheop <= 3'b000;		// noop
					end
					instrOneHotOut[`O_H_SYSTEM]: begin
						// Store previous value of CSR in target register
						rdin <= csrprevval;
						rwe <= (func3 == 3'b000) ? 1'b0 : 1'b1; // No register write back for non-CSR sys ops
						csrwe <= 1'b1;
						case (func3)
							default/*3'b000*/: begin
								case (func12)
									12'b1111110_00000: begin	// CFLUSH.D.L1 (32'hFC000073) Writeback dirty D$ lines and invalidate tags
										// 1111110_00000_0000000000000_1110011
										dcacheop <= 3'b011;		// D$, write back (no tag invalidation), mark valid
										ren <= 1'b1;
										addr <= rval1;
										cpustate <= STOREWAIT;
									end
									12'b1111110_00010: begin	// CDISCARD.D.L1 (32'hFC200073) Invalidate D$
										// 1111110_00010_0000000000000_1110011
										dcacheop <= 3'b001;		// D$, do not write back (invalidate tags to fore re-read), mark valid
										ren <= 1'b1;
										addr <= rval1;
										cpustate <= STOREWAIT;
									end
									12'b0000000_00000: begin	// ECALL - sys call
										ecall <= mie[3]; 		// MSIE
										// Ignore store
										csrwe <= 1'b0;
									end
									12'b0000000_00001: begin	// EBREAK - software breakpoint (jump into debugger environment)
										ebreak <= mie[3];		// MSIE
										// Ignore store
										csrwe <= 1'b0;
									end
									12'b0001000_00101: begin	// WFI - wait for interrupt
										cpustate <= WFI;
										// Ignore store
										csrwe <= 1'b0;
									end
									default/*12'b0011000_00010*/: begin	// MRET - return from interrupt
										// Ignore whatever random CSR might be selected, and use ours
										csrwenforce <= 1'b1;
										csrenforceindex <= `CSR_MIP;
										// Return to interrupt point
										nextPC <= mepc;
										// Clear interrupt pending bit with correct priority
										if (mip[11])
											csrdin <= {mip[31:12], 1'b0, mip[10:0]};
										else if (mip[3])
											csrdin <= {mip[31:4], 1'b0, mip[2:0]};
										else if (mip[7])
											csrdin <= {mip[31:8], 1'b0, mip[6:0]};
									end
								endcase
							end
							3'b100: begin // Unknown
								csrdin <= csrprevval;
							end
							3'b001: begin
								csrdin <= rval1;
							end
							3'b101: begin
								csrdin <= immed;
							end
							3'b010: begin
								csrdin <= csrprevval | rval1;
							end
							3'b110: begin
								csrdin <= csrprevval | immed;
							end
							3'b011: begin
								csrdin <= csrprevval & (~rval1);
							end
							3'b111: begin
								csrdin <= csrprevval & (~immed);
							end
						endcase
					end
					default: begin
						// Illegal instruction triggers only
						// if machine software interrupts are enabled
						illegalinstruction <= mie[3];
					end
				endcase
			end

			STOREWAIT: begin
				// Wait for memory write (or cacheop) to complete
				cpustate <= wready ? RETIRE : STOREWAIT;
			end

			LOADWAIT: begin
				// Read complete, handle register write-back
				rwe <= rready;
				case (func3)
					3'b000: begin // BYTE with sign extension
						case (rwaddress[1:0])
							2'b11: begin rdin <= {{24{din[31]}}, din[31:24]}; end
							2'b10: begin rdin <= {{24{din[23]}}, din[23:16]}; end
							2'b01: begin rdin <= {{24{din[15]}}, din[15:8]}; end
							default/*2'b00*/: begin rdin <= {{24{din[7]}}, din[7:0]}; end
						endcase
					end
					3'b001: begin // HALF with sign extension
						case (rwaddress[1])
							1'b1: begin rdin <= {{16{din[31]}}, din[31:16]}; end
							default/*1'b0*/: begin rdin <= {{16{din[15]}}, din[15:0]}; end
						endcase
					end
					3'b100: begin // BYTE with zero extension
						case (rwaddress[1:0])
							2'b11: begin rdin <= {24'd0, din[31:24]}; end
							2'b10: begin rdin <= {24'd0, din[23:16]}; end
							2'b01: begin rdin <= {24'd0, din[15:8]}; end
							default/*2'b00*/: begin rdin <= {24'd0, din[7:0]}; end
						endcase
					end
					3'b101: begin // HALF with zero extension
						case (rwaddress[1])
							1'b1: begin rdin <= {16'd0, din[31:16]}; end
							default/*1'b0*/: begin rdin <= {16'd0, din[15:0]}; end
						endcase
					end
					default/*3'b010*/: begin // WORD
						rdin <= din[31:0];
					end
				endcase
				cpustate <= rready ? RETIRE : LOADWAIT;
			end

			default /*WFI*/: begin
				// Everything except illegalinstruction and swint wakes up this HART
				if ( hwint || timerint ) begin
					cpustate <= RETIRE;
				end else begin
					cpustate <= WFI;
				end
			end
        endcase
	end
end

endmodule
