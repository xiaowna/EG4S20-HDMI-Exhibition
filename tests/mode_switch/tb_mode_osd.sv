`timescale 1ns/1ps
module tb_mode_osd;
 reg clk=0,rst_n=1,de=0,vsync=1;
 reg [10:0] settings_word=0;
 reg [3:0] mode_status=0;
 wire [23:0] rgb_out;wire [9:0] pixel_x,pixel_y;
 integer f,x,y,row,col,bitcol,lit,bar,selected,checks=0;
 reg [23:0] expected;
 reg [31:0] label_word;
 reg [63:0] bitmap;
 reg [3:0] snapshot;
 always #5 clk=~clk;
 video_scroll_osd #(.SETTINGS_UI(1),.MODE_CONTROL(1)) dut(.clk(clk),.rst_n(rst_n),
  .de(de),.vsync(vsync),.rgb(24'h804020),.settings_word(settings_word),.mode_status(mode_status),
  .image_count(3'd4),.image_index(2'd0),.paused(1'b0),.wav_found(1'b1),.catalog_ready(1'b1),
  .image_valid(1'b1),.rgb_out(rgb_out),.pixel_x(pixel_x),.pixel_y(pixel_y));
 task tick;begin @(posedge clk);#1;@(negedge clk);#1;end endtask
 // Independent ASCII bitmap oracle already used for the original four pages.
 function [63:0] glyph(input [7:0] ch);
  begin case(ch)
   "A":glyph=64'h3c42427e42424200;"U":glyph=64'h4242424242423c00;
   "T":glyph=64'h7e18181818181800;"O":glyph=64'h3c42424242423c00;
   "D":glyph=64'h7844424242447800;"E":glyph=64'h7e40407c40407e00;
   "M":glyph=64'h42665a4242424200;"S":glyph=64'h3e40403c02027c00;
   "H":glyph=64'h4242427e42424200;"P":glyph=64'h7c42427c40404000;
   "W":glyph=64'h42425a5a66664200;"I":glyph=64'h3c18181818183c00;
   default:glyph=0;
  endcase end
 endfunction
 initial begin
  #1;rst_n=0;tick;rst_n=1;
  for(f=0;f<4;f=f+1)begin
   case(f)0:mode_status=4'b0001;1:mode_status=4'b0100;2:mode_status=4'b0111;3:mode_status=4'b1100;endcase
   snapshot=mode_status;settings_word=11'b1_00_010_010_0_0;
   label_word=snapshot[3]?"WAIT":(snapshot[2]?"SHOP":"DEMO");
   vsync=0;tick;vsync=1;tick;
   for(y=0;y<480;y=y+1)begin
    de=1;
    for(x=0;x<640;x=x+1)begin
     #1;
     if(y>=288 && y<320 && x>=160 && x<480)begin
      row=(y-288)/2;col=(x-176)/16;bitcol=(x-176)%16/2;lit=0;
      if(y<304 && x>=176 && x<240)begin
       case(col)0:bitmap=glyph("A");1:bitmap=glyph("U");2:bitmap=glyph("T");3:bitmap=glyph("O");endcase
       lit=bitmap[63-row*8-bitcol];
      end
      selected=snapshot[1];bar=x>=336&&x<456&&y>=292&&y<300&&snapshot[0];
      expected=lit?24'he7efec:(bar?24'hf0b877:(selected?24'h203f47:24'h162737));
      if(rgb_out!==expected)$fatal(1,"AUTO page pixel frame=%0d xy=%0d,%0d expected=%h actual=%h",f,x,y,expected,rgb_out);
      checks=checks+1;
     end
     if(y>=440 && y<456 && x>=336 && x<400)begin
      bitmap=glyph(label_word[31-(x-336)/16*8 -: 8]);
      lit=bitmap[63-(y-440)/2*8-(x-336)%16/2];
      expected=lit?24'hb6e7d7:24'h402010;
      if(rgb_out!==expected)$fatal(1,"mode status pixel frame=%0d xy=%0d,%0d expected=%h actual=%h",f,x,y,expected,rgb_out);
      checks=checks+1;
     end
     if(x==400&&y==200)begin mode_status=~snapshot;settings_word=0;end
     tick;
    end
    de=0;tick;tick;
   end
  end
  $display("PASS mode_osd: %0d independent pixels; DEMO/SHOP/WAIT, AUTO on/off/highlight, frame-atomic metadata",checks);$finish;
 end
 initial begin #20000000;$fatal(1,"mode OSD timeout");end
endmodule
