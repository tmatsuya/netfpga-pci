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

pci_top pci_top0 (
	.RST_I(reset),
	.PCLK(pclk),

        .AD_IO(),            // PCI Ports -- do not modify names!
        .CBE_IO(),
        .PAR_IO(),
        .FRAME_IO(),
        .TRDY_IO(),
        .IRDY_IO(),
        .STOP_IO(),
        .DEVSEL_IO(),
        .IDSEL_I(),
        .INTA_O(),
        .PERR_IO(),
        .SERR_IO(),
        .REQ_O(),
        .GNT_I(),

        .cpci_clk(),         // CPCI
        .cpci_reset(),

        .cpci_addr(),       // CPCI-1
        .cpci_data(),
        .cpci_rd_rdy(),
        .cpci_wr_rdy(),
        .cpci_req(),

        .cpci_debug_data(),  // CPCI-2
        .cpci_dma_data(),
        .cpci_dma_wr_en(),
        .cnet_err(),

	.cpci_id(4'h1)

);

endmodule
