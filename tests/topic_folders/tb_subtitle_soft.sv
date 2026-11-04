`timescale 1ns/1ps
module tb_subtitle_soft;
 reg clk=0,rst_n=0,de=0,vsync=1;reg [9:0] x=0,y=0;reg [23:0] rgb_in=0;
 wire [23:0] rgb_out,legacy_out;reg [1:0] golden[0:4095];
 integer checks=0,alpha_hits[0:16],scrolls[0:8];
 always #5 clk=~clk;
 video_chinese_subtitle #(.SOFT_EDGES(1)) dut(.*);
 video_chinese_subtitle legacy(.rgb_out(legacy_out),.*);
 function automatic [7:0] blend(input integer b,f,a);
  integer v;begin v=b+(((f-b)*a+8)>>>4);blend=v[7:0];end
 endfunction
 task pixel(input integer xx,yy,s,enabled,input [23:0] bg);
  integer tx,ink,a,d;reg [23:0] fg,want,hard;
  begin
   @(negedge clk);x=xx;y=yy;de=enabled;rgb_in=bg;
   dut.scroll=s;legacy.scroll=s;
   want=bg;hard=bg;tx=xx+s-304;
   if(enabled&&xx>=16&&xx<304&&yy>=8&&yy<24&&tx>=0&&tx<224)begin
    ink=golden[(tx/16)*256+(yy-8)*16+tx%16];
    if(ink!=0)begin
     fg=(ink==2)?24'he7efec:24'h0b1420;hard=fg;
     d=((xx-16)<(303-xx))?(xx-16):(303-xx);a=(d>=32)?16:d/2;
     want={blend(bg[23:16],fg[23:16],a),blend(bg[15:8],fg[15:8],a),blend(bg[7:0],fg[7:0],a)};
     alpha_hits[a]=alpha_hits[a]+1;
    end
   end
   @(posedge clk);#1;
   if(rgb_out!==want||legacy_out!==hard)$fatal(1,"subtitle latency/blend xy=%0d,%0d scroll=%0d expected=%h got=%h legacy=%h expected=%h",xx,yy,s,want,rgb_out,legacy_out,hard);
   checks=checks+1;
  end
 endtask
 initial begin
  $readmemh("font_golden.hex",golden);
  for(integer i=0;i<=16;i=i+1)alpha_hits[i]=0;
  scrolls[0]=0;scrolls[1]=1;scrolls[2]=16;scrolls[3]=64;scrolls[4]=128;
  scrolls[5]=224;scrolls[6]=384;scrolls[7]=500;scrolls[8]=512;
  repeat(3)@(negedge clk);rst_n=1;
  for(integer s=0;s<9;s=s+1)
   for(integer yy=0;yy<32;yy=yy+1)
    for(integer xx=0;xx<640;xx=xx+1)
     pixel(xx,yy,scrolls[s],1,{xx[7:0],yy[7:0],xx[7:0]^yy[7:0]});
  for(integer xx=0;xx<640;xx=xx+1)begin
   pixel(xx,16,224,1,24'hffffff);pixel(xx,16,224,1,24'h000000);pixel(xx,16,224,0,24'h9234e1);
  end
  for(integer a=0;a<=16;a=a+1)if(alpha_hits[a]==0)$fatal(1,"untested alpha %0d",a);
  @(negedge clk);dut.scroll=512;vsync=0;@(posedge clk);#1;
  if(dut.scroll!==0)$fatal(1,"scroll wrap changed");
  @(negedge clk);rst_n=0;#1;if(rgb_out!==0)$fatal(1,"reset leaks text");
  $display("PASS soft subtitle %0d pixels, all17 alpha levels, exact1-clock latency, DE/reset/wrap and legacy mode",checks);$finish;
 end
endmodule
