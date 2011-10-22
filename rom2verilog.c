#include <stdio.h>

void main() {
	unsigned char buf[65536];
	int count, data, i, j;

	count = 0;
	while ( ( data = getchar() ) != EOF ) {
		buf[count++] = data;
	}

	for (i=0; i<4; ++i ) {
		printf("module rom%d (\n", i);
		printf("\tinput  [7:0]  dinp,\n");
		printf("\tinput         wren,\n");
		printf("\tinput  [8:0]  address,\n");
		printf("\tinput         clk,\n");
		printf("\tinput         enable,\n");
		printf("\toutput [7:0]  dout\n");
		printf(");\n\n");
		printf("\tRAMB4_S8    RAM%c_EXAMPLE (\n", 'A'+i);
		printf("\t    .DO(dout),\n");
		printf("\t    .ADDR(address),\n");
		printf("\t    .DI(dinp),\n");
		printf("\t    .EN(enable),\n");
		printf("\t    .CLK(clk),\n");
		printf("\t    .WE(wren),\n");
		printf("\t    .RST(1'b0)\n");
		printf(");\n\n");
		for (j=i; j<count; j+=4) {
			if ( ( j % 128 ) < 4 )
				printf ("//synthesis attribute INIT_%02X of RAM%c_EXAMPLE is \"", j / 128, 'A'+i);
			printf("%02X", buf[(j & 0xff80) + (127-(j % 128))]);
			if ( ( j % 128 ) >= 124 )
				printf("\"\n");

		}
		printf("\nendmodule\n\n");
	}
	
}
