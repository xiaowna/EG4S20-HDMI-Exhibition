`timescale 1ns/1ps
module tb_settings_osd;
 reg clk=0,rst_n=1,de=0,vsync=1;
 reg [23:0] rgb=24'h804020;
 reg [10:0] settings_word=0;
 wire [23:0] rgb_out;wire [9:0] pixel_x,pixel_y;
 always #5 clk=~clk;
 video_scroll_osd #(.SETTINGS_UI(1)) dut(.clk(clk),.rst_n(rst_n),.de(de),.vsync(vsync),.rgb(rgb),
  .image_count(3'd4),.image_index(2'd1),.paused(1'b0),.wav_found(1'b1),.catalog_ready(1'b1),.image_valid(1'b1),
  .settings_word(settings_word),.rgb_out(rgb_out),.pixel_x(pixel_x),.pixel_y(pixel_y));
 integer x,y,f,line,col,row,bitcol,page,bright,gain,expected_lit,expected_bar,selected,checks=0;
 reg [10:0] snapshot;
 reg [23:0] expected;
 reg [7:0] letter;
 reg [63:0] bitmap;
 integer preview;
 task tick;begin @(posedge clk);#1;@(negedge clk);#1;end endtask
 function [7:0] menu_char(input integer ln,c);
  reg [63:0] text;
  begin
   case(ln)
    0:text="SETUP   ";1:text="BRIGHT  ";2:text="CONTRAST";
    3:text="FADE    ";4:text="WAVE    ";6:text="OK      ";default:text="        ";
   endcase
   menu_char=text[63-c*8 -: 8];
  end
 endfunction
 function [63:0] glyph(input [7:0] ch);
  begin case(ch)
   "S":glyph=64'h3e40403c02027c00;"E":glyph=64'h7e40407c40407e00;
   "T":glyph=64'h7e18181818181800;"U":glyph=64'h4242424242423c00;
   "P":glyph=64'h7c42427c40404000;"B":glyph=64'h7c42427c42427c00;
   "R":glyph=64'h7c42427c48444200;"I":glyph=64'h3c18181818183c00;
   "G":glyph=64'h3c42404e42423c00;"H":glyph=64'h4242427e42424200;
   "C":glyph=64'h3c42404040423c00;"O":glyph=64'h3c42424242423c00;
   "N":glyph=64'h4262524a46424200;"A":glyph=64'h3c42427e42424200;
   "F":glyph=64'h7e40407c40404000;"D":glyph=64'h7844424242447800;
   "W":glyph=64'h42425a5a66664200;"V":glyph=64'h4242422424181800;
   "K":glyph=64'h4244487048444200;default:glyph=0;
  endcase end
 endfunction
 initial begin
  #1;rst_n=0;tick;rst_n=1;
  preview=$fopen("settings_preview.ppm","w");$fwrite(preview,"P3\n640 480\n255\n");
  for(f=0;f<12;f=f+1)begin
   page=f%4;bright=f%5;gain=(f+2)%5;
   settings_word={1'b1,page[1:0],bright[2:0],gain[2:0],f[0],f[1]};snapshot=settings_word;
   vsync=0;tick;vsync=1;tick;
   for(y=0;y<480;y=y+1)begin
    de=1;
    for(x=0;x<640;x=x+1)begin
     #1;
     if(pixel_x!==x || pixel_y!==y)$fatal(1,"OSD coordinate alignment %0d,%0d actual %0d,%0d",x,y,pixel_x,pixel_y);
     if(x>=160 && x<480 && y>=112 && y<352)begin
      line=(y-128)/32;
      if(y<128)line=-1;
      col=(x-176)/16;row=((y-128)%16)/2;bitcol=((x-176)%16)/2;
      expected_lit=0;
      if(x>=176 && x<304 && y>=128 && (y-128)%32<16)begin
       bitmap=glyph(menu_char(line,col));expected_lit=bitmap[63-row*8-bitcol];
      end
      selected=(line>=1 && line<=4 && page==line-1);
      expected_bar=0;
      if(x>=336 && x<456 && y>=128 && (y-128)%32>=4 && (y-128)%32<12)begin
       if(line==1)expected_bar=((x-336)/24==bright && (x-336)%24<16);
       else if(line==2)expected_bar=((x-336)/24==gain && (x-336)%24<16);
       else if(line==3)expected_bar=snapshot[1];
       else if(line==4)expected_bar=snapshot[0];
      end
      expected=expected_lit?24'he7efec:(expected_bar?24'hf0b877:(selected?24'h203f47:24'h162737));
      if(rgb_out!==expected)$fatal(1,"menu pixel mismatch frame=%0d xy=%0d,%0d expected=%h actual=%h",f,x,y,expected,rgb_out);
      checks=checks+1;
     end else if(!(y>=24 && y<56) && !(y>=432 && y<464) && rgb_out!==rgb)$fatal(1,"menu overwrote outside panel");
     if(f==0)$fwrite(preview,"%0d %0d %0d\n",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
     if(x==400 && y==200)settings_word=0; // must retain the frame snapshot
     tick;
    end
    de=0;tick;tick;
   end
  end
  $fclose(preview);
  // Clearing the menu takes effect only at the following VSYNC.
  settings_word=0;vsync=0;tick;vsync=1;tick;
  for(y=0;y<360;y=y+1)begin
   de=1;for(x=0;x<640;x=x+1)begin #1;
    if(y>=112 && y<352 && rgb_out!==rgb)$fatal(1,"closed settings panel persisted");
    tick;
   end de=0;tick;tick;
  end
  $display("PASS settings OSD: %0d independent panel pixels, all labels/pages/levels, frame-atomic updates, outside passthrough and close",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"settings OSD timeout");end
endmodule
