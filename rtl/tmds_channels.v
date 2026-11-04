// Three-channel TMDS symbol generation for one pixel clock.
// DVI/HDMI convention: blue channel carries HSYNC/VSYNC control bits.
module tmds_channels(
 input wire pix_clk,input wire rst_n,input wire de,
 input wire hsync,input wire vsync,
 input wire [7:0] red,input wire [7:0] green,input wire [7:0] blue,
 output wire [9:0] tmds_red,output wire [9:0] tmds_green,output wire [9:0] tmds_blue);
 tmds_encoder enc_r(.pix_clk(pix_clk),.rst_n(rst_n),.din(red),.de(de),.c0(1'b0),.c1(1'b0),.tmds(tmds_red));
 tmds_encoder enc_g(.pix_clk(pix_clk),.rst_n(rst_n),.din(green),.de(de),.c0(1'b0),.c1(1'b0),.tmds(tmds_green));
 tmds_encoder enc_b(.pix_clk(pix_clk),.rst_n(rst_n),.din(blue),.de(de),.c0(hsync),.c1(vsync),.tmds(tmds_blue));
endmodule
