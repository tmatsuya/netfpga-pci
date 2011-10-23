`include "setup.v"

`ifdef ENABLE_EXPROM
module rom(
	input  [31:0] dinp,
	input         wren,
	input  [8:0]  address,
	input         clk,
	input         enable,
	output [31:0] dout
);

rom3 rom3_inst (
	.dinp(dinp[7:0]),
	.wren(wren),
	.address(address),
	.clk(clk),
	.enable(enable),
	.dout(dout[7:0])
);

rom2 rom2_inst (
	.dinp(dinp[15:8]),
	.wren(wren),
	.address(address),
	.clk(clk),
	.enable(enable),
	.dout(dout[15:8])
);
rom1 rom1_inst (
	.dinp(dinp[23:16]),
	.wren(wren),
	.address(address),
	.clk(clk),
	.enable(enable),
	.dout(dout[23:16])
);
rom0 rom0_inst (
	.dinp(dinp[31:24]),
	.wren(wren),
	.address(address),
	.clk(clk),
	.enable(enable),
	.dout(dout[31:24])
);
endmodule
`endif

//-----------------------------------
// これ以降は rom2verilog.c を使って自動生成したものをコピーする
//-----------------------------------

`include "initdata.v"
