/***********************************************************************

  File:   pci_top.v
  Rev:    3.1.161

  This is the top-level template file for Verilog designs.
  The user should place his backend application design in the
  userapp module.

  Copyright (c) 2011 macchan@sfc.wide.ad.jp, Inc.  All rights reserved.

***********************************************************************/
//`include "defines.v"

module pci_top (
	inout         RST_I,
	input         PCLK,

	inout  [31:0] AD_IO,             // PCI Ports -- do not modify names!
	inout   [3:0] CBE_IO,
	inout         PAR_IO,
	inout         FRAME_IO,
	inout         TRDY_IO,
	inout         IRDY_IO,
	inout         STOP_IO,
	inout         DEVSEL_IO,
	input         IDSEL_I,
	output        INTA_O,
	inout         PERR_IO,
	inout         SERR_IO,
	output        REQ_O,
	input         GNT_I,
	output        LED
				
);

//-----------------------------------
// PCI register
//-----------------------------------
reg [3:0] PCI_BusCommand = 4'h0;
reg [31:0] PCI_Address = 32'h0;
reg PCI_IDSel = 1'b0;

//-----------------------------------
// Port register
//-----------------------------------
reg AD_Hiz = 1'b1;
reg [31:0] AD_Port = 32'h0;
reg DEVSEL_Hiz = 1'b1;
reg DEVSEL_Port = 1'b1;
reg TRDY_Hiz = 1'b1;
reg TRDY_Port = 1'b1;
reg STOP_Hiz = 1'b1;
reg STOP_Port = 1'b1;

reg LED_Port = 1'b0;

parameter PCI_IDLE		= 3'b000;
parameter PCI_ADDR_COMPARE	= 3'b001;
parameter PCI_BUS_BUSY		= 3'b010;
parameter PCI_WAIT_IRDY		= 3'b011;
parameter PCI_WAIT_LOCAL_ACK	= 3'b100;
parameter PCI_ACC_COMPLETE	= 3'b101;
parameter PCI_DISCONNECT	= 3'b110;
parameter PCI_TURN_AROUND	= 3'b111;

parameter PCI_MEM_CYCLE		= 3'b011;
parameter PCI_MEM_READ_CYCLE	= 4'b0110;
parameter PCI_MEM_WRITE_CYCLE	= 4'b0111;

parameter SEQ_IDLE		= 2'b00;
parameter SEQ_MEM_ACCESS	= 2'b01;
parameter SEQ_COMPLETE		= 2'b11;

reg [2:0] pci_current_state = PCI_IDLE, pci_next_state = PCI_IDLE;
reg [1:0] seq_current_state = SEQ_IDLE, seq_next_state = SEQ_IDLE;

assign Hit_Device = (PCI_BusCommand[3:1] == PCI_MEM_CYCLE) && (PCI_Address[31:4] == 32'h8000000);

reg Local_Bus_Start = 1'b0;
reg Local_DTACK = 1'b0;

always @(posedge PCLK) begin
	if (~RST_I) begin
		pci_current_state <= PCI_IDLE;
		pci_next_state <= PCI_IDLE;
		AD_Hiz <= 1'b1;
		DEVSEL_Hiz <= 1'b1;
		DEVSEL_Port <= 1'b1;
		TRDY_Hiz <= 1'b1;
		TRDY_Port <= 1'b1;
		STOP_Hiz <= 1'b1;
		STOP_Port <= 1'b1;
		PCI_BusCommand <= 4'h0;
		PCI_Address <= 32'h0;
		PCI_IDSel <= 1'b0;
		Local_Bus_Start <= 1'b0;
	end else begin
		pci_current_state <= pci_next_state;
		case (pci_current_state)
			PCI_IDLE: begin
				if (~FRAME_IO && IRDY_IO) begin
					PCI_BusCommand <= CBE_IO;
					PCI_Address <= AD_IO;
					PCI_IDSel <= IDSEL_I;
					pci_next_state <= PCI_ADDR_COMPARE;
				end
			end
			PCI_ADDR_COMPARE: begin
				if (Hit_Device) begin
					DEVSEL_Port <= 1'b0;
					DEVSEL_Hiz <= 1'b0;
					TRDY_Hiz <= 1'b0;
					STOP_Hiz <= 1'b0;
					pci_next_state <= PCI_WAIT_IRDY;
				end else
					pci_next_state <= PCI_BUS_BUSY;
			end
			PCI_BUS_BUSY: begin
				if (FRAME_IO & IRDY_IO)
					pci_next_state <= PCI_IDLE;
			end
			PCI_WAIT_IRDY: begin
				if (~IRDY_IO) begin
					if (PCI_BusCommand[0] == 1'b0)
						AD_Hiz <= 1'b0;
					Local_Bus_Start <= 1'b1;
					pci_next_state <= PCI_WAIT_LOCAL_ACK;
				end
			end
			PCI_WAIT_LOCAL_ACK: begin
				Local_Bus_Start <= 1'b0;
				if (Local_DTACK) begin
					TRDY_Port <= 1'b0;
					STOP_Port <= 1'b0;
					pci_next_state <= PCI_ACC_COMPLETE;
				end
			end
			PCI_ACC_COMPLETE: begin
				TRDY_Port <= 1'b1;
				AD_Hiz <= 1'b1;
				if (~FRAME_IO) begin
					pci_next_state <= PCI_DISCONNECT;
				end else begin
					DEVSEL_Port <= 1'b1;
					STOP_Port <= 1'b1;
					pci_next_state <= PCI_TURN_AROUND;
				end
			end
			PCI_DISCONNECT: begin
				if (FRAME_IO) begin
					DEVSEL_Port <= 1'b1;
					STOP_Port <= 1'b1;
					pci_next_state <= PCI_TURN_AROUND;
				end
			end
			PCI_TURN_AROUND: begin
				DEVSEL_Hiz <= 1'b1;
				TRDY_Hiz <= 1'b1;
				STOP_Hiz <= 1'b1;
				pci_next_state <= PCI_IDLE;
			end
			default: begin
				pci_next_state <= PCI_TURN_AROUND;
			end
		endcase 
	end
end
					 
always @(posedge PCLK) begin
	if (~RST_I) begin
		seq_current_state <= SEQ_IDLE;
		seq_next_state <= SEQ_IDLE;
		AD_Port <= 32'h0;
		Local_DTACK <= 1'b0;
	end else begin
		seq_current_state <= seq_next_state;
		case (seq_current_state)
			SEQ_IDLE: begin
				if (Local_Bus_Start)
					seq_next_state <= SEQ_MEM_ACCESS;
			end
			SEQ_MEM_ACCESS: begin
				if (~PCI_BusCommand[0]) begin
					AD_Port[31:0] <= 32'h1234abcd;
				end else begin
					LED_Port <= AD_IO[0];
				end
				Local_DTACK <= 1'b1;
				seq_next_state <= SEQ_COMPLETE;
			end
			SEQ_COMPLETE: begin
				Local_DTACK <= 1'b0;
				seq_next_state <= SEQ_IDLE;
			end
		endcase
	end
end

assign CBE_IO = 4'hz;
assign AD_IO = AD_Hiz ? 32'hz : AD_Port;
assign PAR_IO = 1'hz;
assign FRAME_IO = 1'hz;
assign IRDY_IO = 1'hz;
assign TRDY_IO = TRDY_Hiz ? 1'hz : TRDY_Port;
assign STOP_IO = STOP_Hiz ? 1'hz : STOP_Port;
assign DEVSEL_IO = DEVSEL_Hiz ? 1'hz : DEVSEL_Port;
assign INTA_O = 1'hz;
assign REQ_O = 1'hz;
assign LED = ~LED_Port;

endmodule
