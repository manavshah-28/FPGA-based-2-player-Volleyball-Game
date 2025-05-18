module volley_top(
input clk50,
input reset_n,
input test_mode,          // put device in VGA Test mode

// controller inputs 
input P1_L,P1_R,
input P2_L,P2_R,

output o_hsync,
output o_vsync,
output o_sync,
output o_blank,
output [7:0] o_red,
output [7:0] o_green,
output [7:0] o_blue,
output o_vga_clock
);

// connecting vga clock generator IP
VGA60 vga_clocking(
		.refclk(clk50),   
		.rst(!reset_n),      
		.outclk_0(o_vga_clock)
	);
// connecting the vga_control
vga_control vga_monitor(.*);

endmodule