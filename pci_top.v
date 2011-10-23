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

parameter PCI_IO_CYCLE		= 3'b001;
parameter PCI_IO_READ_CYCLE	= 4'b0010;
parameter PCI_IO_WRITE_CYCLE	= 4'b0011;
parameter PCI_MEM_CYCLE		= 3'b011;
parameter PCI_MEM_READ_CYCLE	= 4'b0110;
parameter PCI_MEM_WRITE_CYCLE	= 4'b0111;
parameter PCI_CFG_CYCLE		= 3'b101;
parameter PCI_CFG_READ_CYCLE	= 4'b1010;
parameter PCI_CFG_WRITE_CYCLE	= 4'b1011;

parameter SEQ_IDLE		= 3'b000;
parameter SEQ_IO_ACCESS		= 3'b001;
parameter SEQ_MEM_ACCESS	= 3'b010;
parameter SEQ_CFG_ACCESS	= 3'b011;
parameter SEQ_ROM_ACCESS	= 3'b100;
parameter SEQ_COMPLETE		= 3'b111;

reg [2:0] pci_current_state = PCI_IDLE, pci_next_state = PCI_IDLE;
reg [2:0] seq_current_state = SEQ_IDLE, seq_next_state = SEQ_IDLE;

//-----------------------------------
// PCI configuration parameter/registers
//-----------------------------------
parameter CFG_VendorID		= 16'h6809;
parameter CFG_DeviceID		= 16'h8000;
parameter CFG_Command		= 16'h0000;
parameter CFG_Status		= 16'h0200;
parameter CFG_BaseClass 	= 8'h05;
parameter CFG_SubClass 		= 8'h00;
parameter CFG_ProgramIF		= 8'h00;
parameter CFG_RevisionID	= 8'h00;
parameter CFG_HeaderType	= 8'h00;
parameter CFG_Int_Pin		= 8'h00;
reg CFG_Cmd_Mst = 1'b0;
reg CFG_Cmd_Mem = 1'b0;
reg CFG_Cmd_IO  = 1'b0;
reg CFG_Cmd_IntDis = 1'b0;
reg CFG_Sta_IntSta;
reg CFG_Sta_MAbt;
reg CFG_Sta_TAbt;
reg CFG_ExpROM_En = 1'b0;
reg [31:24] CFG_Base_Addr0 = 8'h0;
reg [15:5]  CFG_Base_Addr1 = 11'h0;
reg [31:20] CFG_ExpROM_Addr = 12'h0;
reg [7:0] CFG_Int_Line = 0;

reg CFG_Sta_MAbt_Clr = 1'b0;
reg CFG_Sta_TAbt_Clr = 1'b0;


assign Hit_IO = (PCI_BusCommand[3:1] == PCI_IO_CYCLE) & (PCI_Address[31:5] == {16'h0,CFG_Base_Addr1[15:5]}) & CFG_Cmd_IO;
assign Hit_Memory = (PCI_BusCommand[3:1] == PCI_MEM_CYCLE) & (PCI_Address[31:24] == CFG_Base_Addr0) & CFG_Cmd_Mem;
assign Hit_Config = (PCI_BusCommand[3:1] == PCI_CFG_CYCLE) & PCI_IDSel & (PCI_Address[10:8] == 3'b000) & (PCI_Address[1:0] == 2'b00);
assign Hit_ExpROM = (PCI_BusCommand[3:1] == PCI_MEM_CYCLE) & (PCI_Address[31:20] == CFG_ExpROM_Addr[31:20]) & CFG_Cmd_Mem & CFG_ExpROM_En;
assign Hit_Device = Hit_IO | Hit_Memory | Hit_Config | Hit_ExpROM;

reg Local_Bus_Start = 1'b0;
reg Local_DTACK = 1'b0;

//-----------------------------------
// ROM
//-----------------------------------
wire [31:0] dinp, dout;
rom rom_inst (
        .dinp(dinp),
        .wren(1'b0),
        .address(PCI_Address[10:2]),
        .clk(PCLK),
        .enable(Hit_ExpROM|Hit_Memory),
        .dout(dout)
);

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
		CFG_Cmd_Mst <= 1'b0;
		CFG_Cmd_Mem <= 1'b0;
		CFG_Cmd_IO  <= 1'b0;
		CFG_Cmd_IntDis <= 1'b0;
		CFG_ExpROM_En <= 1'b0;
		CFG_Base_Addr0 <= 8'h0;
		CFG_Base_Addr1 <= 11'h0;
		CFG_ExpROM_Addr <= 12'h0;
		CFG_Int_Line <= 0;
		CFG_Sta_MAbt_Clr <= 1'b0;
		CFG_Sta_TAbt_Clr <= 1'b0;
		Local_DTACK <= 1'b0;
	end else begin
		seq_current_state <= seq_next_state;
		case (seq_current_state)
			SEQ_IDLE: begin
				if (Local_Bus_Start) begin
					if (Hit_IO)
						seq_next_state <= SEQ_IO_ACCESS;
					else if (Hit_Memory)
						seq_next_state <= SEQ_MEM_ACCESS;
					else if (Hit_Config)
						seq_next_state <= SEQ_CFG_ACCESS;
					else if (Hit_ExpROM)
						seq_next_state <= SEQ_ROM_ACCESS;
				end
			end
			SEQ_IO_ACCESS: begin
				if (~PCI_BusCommand[0]) begin
					AD_Port[31:0] <= 32'hcdab3412;
				end else begin
					LED_Port <= AD_IO[0];
				end
				Local_DTACK <= 1'b1;
				seq_next_state <= SEQ_COMPLETE;
			end
			SEQ_MEM_ACCESS: begin
				if (~PCI_BusCommand[0]) begin
//					AD_Port[31:0] <= 32'hcdab3412;
					AD_Port[31:0] <= dout[31:0];
				end else begin
					LED_Port <= AD_IO[0];
				end
				Local_DTACK <= 1'b1;
				seq_next_state <= SEQ_COMPLETE;
			end
			SEQ_CFG_ACCESS: begin
				if (~PCI_BusCommand[0]) begin
					case (PCI_Address[7:2])
						6'b000000: begin	// Vendor/Device ID
							AD_Port[31:16] <= CFG_DeviceID;
							AD_Port[15:0]  <= CFG_VendorID;
						end
						6'b000001: begin	// Command/Status Register
							AD_Port[31:30] <= CFG_Status[15:14];
							AD_Port[29]    <= CFG_Sta_MAbt;
							AD_Port[28]    <= CFG_Sta_TAbt;
							AD_Port[27:20] <= CFG_Status[11:4];
							AD_Port[19]    <= CFG_Sta_IntSta;
							AD_Port[18:16] <= CFG_Status[2:0];
							AD_Port[15:11] <= CFG_Command[15:11];
							AD_Port[10]    <= CFG_Cmd_IntDis;
							AD_Port[9:3]   <= CFG_Command[9:3];
							AD_Port[2]     <= CFG_Cmd_Mst;
							AD_Port[1]     <= CFG_Cmd_Mem;
							AD_Port[0]     <= CFG_Cmd_IO;
						end
						6'b000010: begin	// Class Code
							AD_Port[31:24] <= CFG_BaseClass;
							AD_Port[23:16] <= CFG_SubClass;
							AD_Port[15:8]  <= CFG_ProgramIF;
							AD_Port[7:0]   <= CFG_RevisionID;
						end
						6'b000011: begin	// Header Type/other
							AD_Port[31:24] <= 8'b0;
							AD_Port[23:16] <= CFG_HeaderType;
							AD_Port[15:0]  <= 16'b0;
						end
						6'b000100: begin	// Base Addr Register 0
							AD_Port[31:24] <= CFG_Base_Addr0;
							AD_Port[23:0]  <= 24'b0;
						end
						6'b000101: begin	// Base Addr Register 1
							AD_Port[31:0]  <= {16'h0, CFG_Base_Addr1, 5'b00001};
						end
						6'b001011: begin	// Sub System Vendor/Sub System ID
							AD_Port[31:16] <= CFG_DeviceID;
							AD_Port[15:0]  <= CFG_VendorID;
						end
						6'b001100: begin	// Exp ROM Base Addr
							AD_Port[31:20] <= CFG_ExpROM_Addr;
							AD_Port[19:1]  <= 19'b0;
							AD_Port[0]     <= CFG_ExpROM_En;
						end
						6'b001111: begin	// Interrupt Register
							AD_Port[31:16] <= 16'b0;
							AD_Port[15:8]  <= CFG_Int_Pin;
							AD_Port[7:0]   <= CFG_Int_Line;
						end
						default:
							AD_Port[31:0]  <= 32'h0;
					endcase
				end else begin
					case (PCI_Address[7:2])
						6'b000001: begin	// Command/Status Register
							if (~CBE_IO[3]) begin
								CFG_Sta_MAbt_Clr <= AD_IO[29];
								CFG_Sta_TAbt_Clr <= AD_IO[28];
							end
							if (~CBE_IO[1]) begin
								CFG_Cmd_IntDis <= AD_IO[10];
							end
							if (~CBE_IO[0]) begin
								CFG_Cmd_Mst <= AD_IO[2];
								CFG_Cmd_Mem <= AD_IO[1];
								CFG_Cmd_IO  <= AD_IO[0];
							end
						end
						6'b000100: begin	// Base Addr Register 0
							if(~CBE_IO[3]) begin
								CFG_Base_Addr0[31:24] <= AD_IO[31:24];
							end
						end
						6'b000101: begin	// Base Addr Register 1
							if(~CBE_IO[1]) begin
								CFG_Base_Addr1[15:8]  <= AD_IO[15:8];
							end
							if(~CBE_IO[0]) begin
								CFG_Base_Addr1[7:5]   <= AD_IO[7:5];
							end
						end
						6'b001100: begin	// Exp ROM Base Addr
							if(~CBE_IO[3])
								CFG_ExpROM_Addr[31:24] <= AD_IO[31:24];
							if(~CBE_IO[2])
								CFG_ExpROM_Addr[23:20] <= AD_IO[23:20];
							if(~CBE_IO[0])
								CFG_ExpROM_En <= AD_IO[0];
						end
						6'b001111: begin	// Interrupt Register
							if(~CBE_IO[0]) begin
								CFG_Int_Line[7:0] <= AD_IO[7:0];
							end
						end
					endcase
				end
				Local_DTACK <= 1'b1;
				seq_next_state <= SEQ_COMPLETE;
			end
			SEQ_ROM_ACCESS: begin
				if (~PCI_BusCommand[0]) begin
//					AD_Port[31:0] <= 32'hea00aa55;
					AD_Port[31:0] <= dout[31:0];
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
			default:
				seq_next_state <= SEQ_IDLE;
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
