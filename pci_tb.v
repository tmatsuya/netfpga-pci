`timescale 1ns/1ps

module pci_tb();

reg sys_clk;
reg pclk;
reg reset;

initial sys_clk = 1'b0;
always #5 sys_clk = ~sys_clk;

initial pclk = 1'b0;
always #10 pclk = ~pclk;

initial begin
	reset = 1'b0;
	#200 reset = 1'b1;
end

wire [31:0] ad_io;
wire [3:0] cbe_io;
wire frame_io, trdy_io, irdy_io, par_io, stop_io,devsel_io, req_o, gnt_i;

PCI_HOST_SIM PCI_HOST_SIM0 (
	.PCICLK(pclk),
	.RST_n(reset),
	.PCIAD(ad_io),
	.C_BE_n(cbe_io),
	.FRAME_n(frame_io),
	.IRDY_n(irdy_io),
	.DEVSEL_n(devsel_io),
	.TRDY_n(trdy_io),
	.STOP_n(stop_io),
	.PAR(par_io),
	.IDSEL(),
	.INTA_n(),
	.REQ_n(req_o),
	.GNT_n(gnt_i),
	.PERR_n(),
	.SERR_n()
);

pci_top pci_top0 (
	.RST_I(reset),
	.PCLK(pclk),

        .AD_IO(ad_io),            // PCI Ports -- do not modify names!
        .CBE_IO(cbe_io),
        .PAR_IO(par_io),
        .FRAME_IO(frame_io),
        .TRDY_IO(trdy_io),
        .IRDY_IO(irdy_io),
        .STOP_IO(stop_io),
        .DEVSEL_IO(devsel_io),
        .IDSEL_I(),
        .INTA_O(),
        .PERR_IO(),
        .SERR_IO(),
        .REQ_O(req_o),
        .GNT_I(gnt_i),

        .cpci_clk(sys_clk),         // CPCI
        .cpci_reset(),

        .cpci_addr(32'hf0000000),       // CPCI-1
        .cpci_data(32'h12345678),
        .cpci_rd_rdy(),
        .cpci_wr_rdy(),
        .cpci_req(1'b0),

        .cpci_debug_data(),  // CPCI-2
        .cpci_dma_data(),
        .cpci_dma_wr_en(),
        .cnet_err(),

	.cpci_id(4'h1)

);

endmodule
