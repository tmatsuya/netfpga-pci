/***********************************************************************

  File:   pci_top.v
  Rev:    3.1.161

  This is the top-level template file for Verilog designs.
  The user should place his backend application design in the
  userapp module.

  Copyright (c) 2011 macchan@sfc.wide.ad.jp, Inc.  All rights reserved.

***********************************************************************/
//`define ENABLE_EXPROM

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
reg AD_Hiz               = 1'b1;
reg [31:0] AD_Port       = 32'h0;
reg DEVSEL_Hiz           = 1'b1;
reg DEVSEL_Port          = 1'b1;
reg TRDY_Hiz             = 1'b1;
reg TRDY_Port            = 1'b1;
reg STOP_Hiz             = 1'b1;
reg STOP_Port            = 1'b1;

reg REQ_Port             = 1'b1;
reg PCIMSTAD_Hiz         = 1'b1;
wire [31:0] PCIMSTAD_Port;
reg CBE_Hiz              = 1'b1;
wire [3:0] CBE_Port;
reg FRAME_Hiz            = 1'b1;
reg FRAME_Port           = 1'b1;
reg IRDY_Hiz             = 1'b1;
reg IRDY_Port            = 1'b1;
reg PAR_Hiz              = 1'b1;
reg PAR_Port             = 1'b0;

//-----------------------------------
// Initiator register
//-----------------------------------
reg MST_Start            = 1'b0;
reg MST_Busy             = 1'b0;
reg MST_ReadWrite        = 1'b0;
reg MST_Abort            = 1'b0;
reg TGT_Abort            = 1'b0;
reg MST_IntStat          = 1'b0;
reg MST_IntClr           = 1'b0;
reg MST_IntMask          = 1'b0;
reg [3:0] DEVSEL_Count   = 4'd0;
reg Retry                = 1'b0;

reg [31:2] MST_Address   = 30'h0;
reg [31:0] MST_WriteData = 32'h0;
reg [31:0] MST_ReadData  = 32'h0;

reg LED_Port             = 1'b0;

parameter PCI_IO_CYCLE		= 3'b001;
parameter PCI_IO_READ_CYCLE	= 4'b0010;
parameter PCI_IO_WRITE_CYCLE	= 4'b0011;
parameter PCI_MEM_CYCLE		= 3'b011;
parameter PCI_MEM_READ_CYCLE	= 4'b0110;
parameter PCI_MEM_WRITE_CYCLE	= 4'b0111;
parameter PCI_CFG_CYCLE		= 3'b101;
parameter PCI_CFG_READ_CYCLE	= 4'b1010;
parameter PCI_CFG_WRITE_CYCLE	= 4'b1011;

parameter TGT_IDLE		= 3'h0;
parameter TGT_ADDR_COMPARE	= 3'h1;
parameter TGT_BUS_BUSY		= 3'h2;
parameter TGT_WAIT_IRDY		= 3'h3;
parameter TGT_WAIT_LOCAL_ACK	= 3'h4;
parameter TGT_ACC_COMPLETE	= 3'h5;
parameter TGT_DISCONNECT	= 3'h6;
parameter TGT_TURN_AROUND	= 3'h7;

parameter INI_IDLE		= 3'h0;
//parameter INI_BUS_PARK	= 3'h1;
parameter INI_WAIT_GNT		= 3'h1;
parameter INI_ADDR2DATA		= 3'h2;
parameter INI_WAIT_DEVSEL	= 3'h3;
parameter INI_WAIT_COMPLETE	= 3'h4;
parameter INI_ABORT		= 3'h5;
parameter INI_TURN_AROUND	= 3'h6;

parameter SEQ_IDLE		= 3'b000;
parameter SEQ_IO_ACCESS		= 3'b001;
parameter SEQ_MEM_ACCESS	= 3'b010;
parameter SEQ_CFG_ACCESS	= 3'b011;
parameter SEQ_ROM_ACCESS	= 3'b100;
parameter SEQ_COMPLETE		= 3'b111;

reg [2:0] target_next_state = TGT_IDLE;
reg [2:0] initiator_next_state = INI_IDLE;
reg [2:0] seq_next_state = SEQ_IDLE;

//-----------------------------------
// PCI configuration parameter/registers
//-----------------------------------
parameter CFG_VendorID		= 16'h3776;
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
assign Hit_ExpROM = (PCI_BusCommand[3:1] == PCI_MEM_CYCLE) & (PCI_Address[31:20] == CFG_ExpROM_Addr) & CFG_Cmd_Mem & CFG_ExpROM_En;
assign Hit_Device = Hit_IO | Hit_Memory | Hit_Config | Hit_ExpROM;

reg Local_Bus_Start = 1'b0;
reg Local_DTACK = 1'b0;

//-----------------------------------
// ROM
//-----------------------------------
wire [31:0] dinp, dout;
`ifdef ENABLE_EXPROM
rom rom_inst (
        .dinp(dinp),
        .wren(1'b0),
        .address(PCI_Address[10:2]),
        .clk(PCLK),
        .enable(Hit_ExpROM|Hit_Memory),
        .dout(dout)
);
`else
	assign dout[31:0] = 32'hcdab3412;
`endif

//-----------------------------------
// Target
//-----------------------------------
always @(posedge PCLK) begin
	if (~RST_I) begin
		target_next_state <= TGT_IDLE;
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
		case (target_next_state)
			TGT_IDLE: begin
//				if (~FRAME_IO & IRDY_IO) begin
				if (~FRAME_IO & IRDY_IO && initiator_next_state == INI_IDLE) begin
					PCI_BusCommand <= CBE_IO;
					PCI_Address <= AD_IO;
					PCI_IDSel <= IDSEL_I;
					target_next_state <= TGT_ADDR_COMPARE;
				end
			end
			TGT_ADDR_COMPARE: begin
				if (Hit_Device) begin
					DEVSEL_Port <= 1'b0;
					DEVSEL_Hiz <= 1'b0;
					TRDY_Hiz <= 1'b0;
					STOP_Hiz <= 1'b0;
					target_next_state <= TGT_WAIT_IRDY;
				end else
					target_next_state <= TGT_BUS_BUSY;
			end
			TGT_BUS_BUSY: begin
				if (FRAME_IO & IRDY_IO)
					target_next_state <= TGT_IDLE;
			end
			TGT_WAIT_IRDY: begin
				if (~IRDY_IO) begin
					if (PCI_BusCommand[0] == 1'b0)
						AD_Hiz <= 1'b0;
					Local_Bus_Start <= 1'b1;
					target_next_state <= TGT_WAIT_LOCAL_ACK;
				end
			end
			TGT_WAIT_LOCAL_ACK: begin
				Local_Bus_Start <= 1'b0;
				if (Local_DTACK) begin
					TRDY_Port <= 1'b0;
					STOP_Port <= 1'b0;
					target_next_state <= TGT_ACC_COMPLETE;
				end
			end
			TGT_ACC_COMPLETE: begin
				TRDY_Port <= 1'b1;
				AD_Hiz <= 1'b1;
				if (~FRAME_IO) begin
					target_next_state <= TGT_DISCONNECT;
				end else begin
					DEVSEL_Port <= 1'b1;
					STOP_Port <= 1'b1;
					target_next_state <= TGT_TURN_AROUND;
				end
			end
			TGT_DISCONNECT: begin
				if (FRAME_IO) begin
					DEVSEL_Port <= 1'b1;
					STOP_Port <= 1'b1;
					target_next_state <= TGT_TURN_AROUND;
				end
			end
			TGT_TURN_AROUND: begin
				DEVSEL_Hiz <= 1'b1;
				TRDY_Hiz <= 1'b1;
				STOP_Hiz <= 1'b1;
				target_next_state <= TGT_IDLE;
			end
			default: begin
				target_next_state <= TGT_TURN_AROUND;
			end
		endcase 
	end
end

//-----------------------------------
// Initiator
//-----------------------------------
assign PCIMSTAD_Port = ~FRAME_Port ? {MST_Address, 2'b00} : MST_WriteData;
assign CBE_Port      = ~FRAME_Port ? {PCI_MEM_CYCLE, MST_ReadWrite} : 4'b0000;

always @(posedge PCLK) begin
	if (~RST_I) begin
		MST_ReadData <= 32'hffffffff;
	end else begin
		if (MST_Abort) begin
			MST_ReadData <= 32'hffffffff;
		end else begin
			if (~MST_ReadWrite & ~IRDY_Port & ~TRDY_IO)
				MST_ReadData <= AD_IO;
		end
	end
end

always @(posedge PCLK) begin
	if (~RST_I) begin
		initiator_next_state <= INI_IDLE;
		// Initiator Registers
		PCIMSTAD_Hiz         <= 1'b1;
		CBE_Hiz              <= 1'b1;
		FRAME_Hiz            <= 1'b1;
		FRAME_Port           <= 1'b1;
		IRDY_Hiz             <= 1'b1;
		IRDY_Port            <= 1'b1;
		REQ_Port             <= 1'b1;
		MST_Busy             <= 1'b0;
		MST_Abort            <= 1'b0;
		TGT_Abort            <= 1'b0;
		DEVSEL_Count         <= 4'd0;
		Retry                <= 1'b0;
	end else begin
		case (initiator_next_state)
			INI_IDLE: begin
				if (CFG_Cmd_Mst) begin
//					if (MST_Start | Retry) begin
					if ((MST_Start | Retry) & target_next_state == TGT_IDLE) begin
						MST_Busy <= 1'b1;
						if (~GNT_I & FRAME_IO & IRDY_IO) begin
							PCIMSTAD_Hiz <= 1'b0;
							CBE_Hiz      <= 1'b0;
							FRAME_Port   <= 1'b0;
							FRAME_Hiz    <= 1'b0;
							initiator_next_state <= INI_ADDR2DATA;
						end else begin
							REQ_Port <= 1'b0;
							initiator_next_state <= INI_WAIT_GNT;
						end
					end else begin
						if (~GNT_I) begin
							PCIMSTAD_Hiz <= 1'b0;
							CBE_Hiz     <= 1'b0;
						end else begin
							PCIMSTAD_Hiz <= 1'b1;
							CBE_Hiz     <= 1'b1;
						end
					end
				end else begin
					if (MST_Start) begin
						MST_Busy <= 1'b1;
						initiator_next_state <= INI_TURN_AROUND;
					end
				end
			end
			INI_WAIT_GNT: begin
				if (~GNT_I & FRAME_IO & IRDY_IO) begin
					REQ_Port     <= 1'b1;
					PCIMSTAD_Hiz <= 1'b0;
					CBE_Hiz      <= 1'b0;
					FRAME_Port   <= 1'b0;
					FRAME_Hiz    <= 1'b0;
					initiator_next_state <= INI_ADDR2DATA;
				end
			end
			INI_ADDR2DATA: begin
				FRAME_Port  <= 1'b1;
				IRDY_Port   <= 1'b0;
				IRDY_Hiz    <= 1'b0;
				if (~MST_ReadWrite)
					PCIMSTAD_Hiz <= 1'b1;
				TGT_Abort <= 1'b0;
				MST_Abort <= 1'b0;
				Retry     <= 1'b0;
				initiator_next_state <= INI_WAIT_DEVSEL;
			end
			INI_WAIT_DEVSEL: begin
				if (~DEVSEL_IO) begin
					if (~TRDY_IO) begin
						FRAME_Hiz    <= 1'b1;
						IRDY_Port    <= 1'b1;
						PCIMSTAD_Hiz <= 1'b1;
						CBE_Hiz      <= 1'b1;
						MST_Busy     <= 1'b0;
						initiator_next_state <= INI_TURN_AROUND;
					end else begin
						if (~STOP_IO)
							initiator_next_state <= INI_ABORT;
						else
							initiator_next_state <= INI_WAIT_COMPLETE;
					end
				end else begin
					if (DEVSEL_Count == 4'h03) begin
						MST_Abort <= 1'b1;
						initiator_next_state <= INI_ABORT;
					end else begin
						DEVSEL_Count <= DEVSEL_Count + 1;
					end
				end
			end
			INI_WAIT_COMPLETE: begin
				if (~DEVSEL_IO) begin
					if (~TRDY_IO) begin
						FRAME_Hiz    <= 1'b1;
						IRDY_Port    <= 1'b1;
						PCIMSTAD_Hiz <= 1'b1;
						CBE_Hiz      <= 1'b1;
						MST_Busy     <= 1'b0;
						initiator_next_state <= INI_TURN_AROUND;
					end else
						if (~STOP_IO)
							initiator_next_state <= INI_ABORT;
				end else begin
					if (~STOP_IO) begin
						TGT_Abort <= 1'b1;
					end else begin
						MST_Abort <= 1'b1;
						TGT_Abort <= 1'b1;
					end
					initiator_next_state <= INI_ABORT;
				end
			end
			INI_ABORT: begin
				FRAME_Hiz    <= 1'b1;
				IRDY_Port    <= 1'b1;
				PCIMSTAD_Hiz <= 1'b1;
				CBE_Hiz      <= 1'b1;
				if (TGT_Abort | MST_Abort)
					MST_Busy <= 1'b0;
				else
					Retry <= 1'b1;
				initiator_next_state <= INI_TURN_AROUND;
			end
			INI_TURN_AROUND: begin
				IRDY_Hiz     <= 1'b1;
				DEVSEL_Count <= 4'h0;
				initiator_next_state <= INI_IDLE;
			end
			default:
				initiator_next_state <= INI_IDLE;
		endcase
	end
end

					 
//-----------------------------------
// Sequencer
//-----------------------------------
always @(posedge PCLK) begin
	if (~RST_I) begin
		seq_next_state <= SEQ_IDLE;
		AD_Port <= 32'h0;
		// Configurartion Register
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
		// Initiator Registers
		MST_Start     <= 1'b0;
		MST_Address   <= 30'h0;
		MST_WriteData <= 32'h0;
		MST_IntStat   <= 1'b0;
		MST_IntClr    <= 1'b0;
		MST_IntMask   <= 1'b0;

		Local_DTACK <= 1'b0;
	end else begin
if (initiator_next_state == INI_WAIT_DEVSEL)
MST_Start     <= 1'b0;

		case (seq_next_state)
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
					case (PCI_Address[4:2])
						3'b000:
							AD_Port[31:0] <= {MST_IntStat,MST_IntMask,14'b0,MST_Abort,TGT_Abort,12'b0,MST_ReadWrite,MST_Busy};
						3'b001:
							AD_Port[31:0] <= {MST_Address, 2'b00};
						3'b010:
							AD_Port[31:0] <= MST_ReadData;
						3'b011:
							AD_Port[31:0] <= MST_WriteData;
						default:
							AD_Port[31:0] <= 32'hcdab3412;
					endcase
				end else begin
					case (PCI_Address[4:2])
						3'b000: begin
							if (~CBE_IO[3]) begin
								MST_IntClr  <= AD_IO[31];
								MST_IntMask <= AD_IO[30];
							end
							if (~CBE_IO[0]) begin
								MST_ReadWrite <= AD_IO[1];
								MST_Start     <= AD_IO[0];
							end
						end
						3'b001: begin
							if (~CBE_IO[3])
								MST_Address[31:24] <= AD_IO[31:24];
							if (~CBE_IO[2])
								MST_Address[23:16] <= AD_IO[23:16];
							if (~CBE_IO[1])
								MST_Address[15: 8] <= AD_IO[15: 8];
							if (~CBE_IO[0])
								MST_Address[ 7: 2] <= AD_IO[ 7: 2];
						end
						3'b011: begin
							if (~CBE_IO[3])
								MST_WriteData[31:24] <= AD_IO[31:24];
							if (~CBE_IO[2])
								MST_WriteData[23:16] <= AD_IO[23:16];
							if (~CBE_IO[1])
								MST_WriteData[15: 8] <= AD_IO[15: 8];
							if (~CBE_IO[0])
								MST_WriteData[ 7: 0] <= AD_IO[ 7: 0];
						end
						default:
							LED_Port <= AD_IO[0];
					endcase
				end
				Local_DTACK <= 1'b1;
				seq_next_state <= SEQ_COMPLETE;
			end
			SEQ_MEM_ACCESS: begin
				if (~PCI_BusCommand[0]) begin
					AD_Port[31:0] <= dout[31:0];
				end else
					LED_Port <= AD_IO[0];
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
						6'b000011: 		// Header Type/other
							AD_Port[31:0]  <= {8'b0, CFG_HeaderType, 16'b0};
						6'b000100: 		// Base Addr Register 0
							AD_Port[31:0]  <= {CFG_Base_Addr0, 24'b0};
						6'b000101: 		// Base Addr Register 1
							AD_Port[31:0]  <= {16'h0, CFG_Base_Addr1, 5'b00001};
						6'b001011:		// Sub System Vendor/Sub System ID
							AD_Port[31:0]  <= {CFG_DeviceID, CFG_VendorID};
`ifdef ENABLE_EXPROM
						6'b001100: 		// Exp ROM Base Addr
							AD_Port[31:0]  <= {CFG_ExpROM_Addr, 19'b0, CFG_ExpROM_En};
`endif
						6'b001111:		// Interrupt Register
							AD_Port[31:0]  <= {16'b0, CFG_Int_Pin, CFG_Int_Line};
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
`ifdef ENABLE_EXPROM
						6'b001100: begin	// Exp ROM Base Addr
							if(~CBE_IO[3])
								CFG_ExpROM_Addr[31:24] <= AD_IO[31:24];
							if(~CBE_IO[2])
								CFG_ExpROM_Addr[23:20] <= AD_IO[23:20];
							if(~CBE_IO[0])
								CFG_ExpROM_En <= AD_IO[0];
						end
`endif
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

//-----------------------------------
// Parity Generator
//-----------------------------------
assign TGT_temp_PAR_DB  = ^AD_Port;
assign TGT_temp_PAR_CBE = ^CBE_IO;
assign TGT_PAR = TGT_temp_PAR_DB ^ TGT_temp_PAR_CBE;
assign INI_temp_PAR_DB  = ^PCIMSTAD_Port;
assign INI_temp_PAR_CBE = ^CBE_Port;
assign INI_PAR = INI_temp_PAR_DB ^ INI_temp_PAR_CBE;
always @(posedge PCLK) begin
	if (~RST_I) begin
		PAR_Hiz   <= 1'b1;
		PAR_Port  <= 1'b0;
	end else begin
		if (~PCIMSTAD_Hiz)
			PAR_Port <= INI_PAR;
		else
			PAR_Port <= TGT_PAR;
		if (PCIMSTAD_Hiz & AD_Hiz)
			PAR_Hiz <= 1'b1;
		else
			PAR_Hiz <= 1'b0;
	end
end

assign CBE_IO    = CBE_Hiz   ? 4'hz : CBE_Port;
assign AD_IO     = (AD_Hiz & PCIMSTAD_Hiz) ? 32'hz : (AD_Hiz ? PCIMSTAD_Port : AD_Port);
assign PAR_IO    = PAR_Hiz   ? 1'hz : PAR_Port;
assign FRAME_IO  = FRAME_Hiz ? 1'hz : FRAME_Port;
assign IRDY_IO   = IRDY_Hiz  ? 1'hz : IRDY_Port;
assign TRDY_IO   = TRDY_Hiz  ? 1'hz : TRDY_Port;
assign STOP_IO   = STOP_Hiz  ? 1'hz : STOP_Port;
assign DEVSEL_IO = DEVSEL_Hiz? 1'hz : DEVSEL_Port;
assign INTA_O    = 1'hz;
assign REQ_O     = REQ_Port;
assign LED       = ~LED_Port;

//-----------------------------------
// Chipscope Pro Module
//-----------------------------------
wire [35 : 0] CONTROL;
wire [7 : 0] TRIG;
wire [63 : 0] DATA;
cs_icon INST_ICON (
	.CONTROL0(CONTROL)
);
cs_ila INST_ILA (
	.CLK(PCLK),
	.CONTROL(CONTROL),
	.TRIG0(TRIG),
	.DATA(DATA)
);
assign DATA[31:0]   = AD_IO;
assign DATA[35:32]  = CBE_IO;
assign DATA[36]     = PAR_IO;
assign DATA[37]     = FRAME_IO;
assign DATA[38]     = TRDY_IO;
assign DATA[39]     = IRDY_IO;
assign DATA[40]     = STOP_IO;
assign DATA[41]     = DEVSEL_IO;
assign DATA[42]     = IDSEL_I;
assign DATA[43]     = INTA_O;
assign DATA[44]     = TRDY_Hiz;
assign DATA[45]     = SERR_IO;
assign DATA[46]     = REQ_O;
assign DATA[47]     = GNT_I;
assign DATA[50:48]  = target_next_state;
assign DATA[53:51]  = initiator_next_state;
assign DATA[54]     = AD_Hiz;
assign DATA[55]     = PCIMSTAD_Hiz;
assign DATA[56]     = PAR_Hiz;
assign DATA[57]     = PAR_Port;
assign DATA[58]     = INI_PAR;
assign DATA[59]     = TGT_PAR;
assign DATA[63:60]  = DEVSEL_Count[3:0];
assign TRIG[ 0]     = FRAME_IO;
assign TRIG[ 1]     = MST_Start;
assign TRIG[ 2]     = 1'b0;
assign TRIG[ 3]     = 1'b0;
assign TRIG[ 4]     = 1'b0;
assign TRIG[ 5]     = 1'b0;
assign TRIG[ 6]     = 1'b0;
assign TRIG[ 7]     = 1'b0;

endmodule
