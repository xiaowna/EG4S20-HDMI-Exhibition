// Pixel-clock consumer. raster_start occurs at least one cycle before first DE.
// On a missing/misaligned pixel, black the rest of this raster and drain the
// failed source frame through its last marker. This prevents horizontal shifts.
// Producer must send exactly one ordered frame with a reliable last marker.
// Output DE/RGB are registered one cycle; delay HSYNC/VSYNC by the same cycle.
module video_pixel_sink #(parameter FRAME_PIXELS=640*480)(
 input wire pix_clk,rst_n,raster_start,de,
 input wire pixel_valid,input wire [31:0] pixel_addr,input wire [23:0] pixel_rgb,
 input wire pixel_last,output wire pixel_ready,
 output reg out_de,output reg [23:0] out_rgb,output reg frame_underflow);
 reg active,dropping;
 localparam integer EXPECTED_BITS=(FRAME_PIXELS>1)?$clog2(FRAME_PIXELS):1;
 reg [EXPECTED_BITS-1:0] expected;
 assign pixel_ready=dropping || (active&&de&&!raster_start);
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin active<=0;dropping<=0;expected<=0;out_de<=0;out_rgb<=0;frame_underflow<=0;end
  else begin
   out_de<=de;out_rgb<=0;
   if(dropping && pixel_valid && pixel_last)dropping<=0;
   if(raster_start)begin
    expected<=0;frame_underflow<=0;
    if(!dropping && !active)active<=1;
    else begin
     active<=0;dropping<=!(dropping && pixel_valid && pixel_last);frame_underflow<=1;
    end
   end else if(active&&de)begin
    if(!pixel_valid || pixel_addr!=expected || pixel_last!=(expected==FRAME_PIXELS-1))begin
     active<=0;dropping<=!(pixel_valid&&pixel_last);frame_underflow<=1;
    end else begin
     out_rgb<=pixel_rgb;
     if(pixel_last)active<=0;else expected<=expected+1'b1;
    end
   end
  end
 end
endmodule
