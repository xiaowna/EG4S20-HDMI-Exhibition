// 640x480 video at 25 MHz: 800x525 total, negative HSYNC/VSYNC.
// Eight 80-pixel bars: white, yellow, cyan, green, magenta, red, blue, black.
module dmz_colorbar_video(
 input wire pix_clk,rst_n,
 output wire de,hsync,vsync,
 output reg [23:0] rgb);
 reg [9:0] x,y;
 assign de=rst_n && x<10'd640 && y<10'd480;
 assign hsync=!(x>=10'd656 && x<10'd752);
 assign vsync=!(y>=10'd490 && y<10'd492);
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin x<=0;y<=10'd480;end
  else if(x==10'd799)begin
   x<=0;
   if(y==10'd524)y<=0;else y<=y+1'b1;
  end else x<=x+1'b1;
 end
 always @* begin
  rgb=24'h000000;
  if(de)begin
   if(x<10'd80)rgb=24'hffffff;
   else if(x<10'd160)rgb=24'hffff00;
   else if(x<10'd240)rgb=24'h00ffff;
   else if(x<10'd320)rgb=24'h00ff00;
   else if(x<10'd400)rgb=24'hff00ff;
   else if(x<10'd480)rgb=24'hff0000;
   else if(x<10'd560)rgb=24'h0000ff;
  end
 end
endmodule
