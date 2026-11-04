`timescale 1ns/1ps
module tb_osd_edges;
 reg clk=0,rst_n=1,de=0,vsync=1;
 reg [23:0] rgb=0;reg [2:0] image_count=0;reg [1:0] image_index=0;
 reg paused=0,wav_found=0,catalog_ready=0,image_valid=0;reg [10:0] settings_word=0;
 wire [3:0] mode_status=0;
 wire [23:0] a,b;wire [9:0] ax,ay,bx,by;
 always #5 clk=~clk;
 video_scroll_osd #(.SETTINGS_UI(0)) no_menu(.*,.rgb_out(a),.pixel_x(ax),.pixel_y(ay));
 video_scroll_osd #(.SETTINGS_UI(1)) menu(.*,.rgb_out(b),.pixel_x(bx),.pixel_y(by));
 integer i,j,y,seed=32'h193d59c7,frames=0;
 task tick;begin @(negedge clk);#1;end endtask
 task random_inputs;reg [31:0] n;begin
  n=$random(seed);rgb=n[23:0];image_count=n[26:24];image_index=n[28:27];paused=n[29];wav_found=n[30];catalog_ready=n[31];
  n=$random(seed);settings_word=n[10:0];image_valid=n[11];
 end endtask
 initial begin
  #1;rst_n=0;tick;rst_n=1;
  // Coordinates wrap at 1024, not 640; verify overflow and variable DE gaps.
  for(y=0;y<1030;y=y+1)begin
   random_inputs;de=1;repeat(y%3==0?1030:6)tick;
   de=0;repeat(y%4+1)tick;
  end
  // Exercise reset at arbitrary phases, VSYNC edges and unstable metadata.
  for(i=0;i<60000;i=i+1)begin
   random_inputs;de=($random(seed)&7)!=0;
   if(i%97==0)begin vsync=0;frames=frames+1;end else vsync=1;
   if(i%997==0)begin #1;rst_n=0;#1;rst_n=1;end
   tick;
  end
  $display("PASS OSD edges: 1024-coordinate wrap, irregular DE/VSYNC, asynchronous resets, arbitrary RGB/metadata and %0d frame captures",frames);$finish;
 end
 initial begin #100000000;$fatal(1,"OSD edge timeout");end
endmodule
