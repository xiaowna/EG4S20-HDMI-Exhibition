`timescale 1ns/1ps
module tb_home_pixels;
 reg easter_toggle=0;wire easter_valid;
 reg scene_enable=0,scene_side=0;reg [2:0] scene_rate=3;
 reg clk=0,rst_n=0,de=0,vsync=1;reg [9:0] x=0,y=0;reg [14:0] home_word=0;
 wire [23:0] rgb_out;wire overlay_valid;
 integer fd,ppm,n,read_count,xx,yy,word,mask,checks=0,previous_word=-1;
 reg [23:0] expected;
 always #5 clk=~clk;
 video_home dut(.*);
 task tick;begin @(negedge clk);#1;end endtask
 initial begin
  tick();rst_n=1;tick();fd=$fopen("home_pixels.txt","r");if(!fd)$fatal(1,"no pixel vectors");
  ppm=$fopen("home.ppm","w");$fwrite(ppm,"P3\n640 480\n255\n");
  while(!$feof(fd))begin
   read_count=$fscanf(fd,"%d %d %h %h %d\n",xx,yy,word,expected,mask);
   if(read_count!=5)$fatal(1,"bad vector");
   if(word!=previous_word)begin
    home_word=word;vsync=0;tick();vsync=1;tick();previous_word=word;
   end
   x=xx;y=yy;de=1;tick();checks=checks+1;
   if(rgb_out!==expected||overlay_valid!==mask[0])$fatal(1,"home pixel x=%0d y=%0d word=%h got=%h/%b expected=%h/%b",x,y,word,rgb_out,overlay_valid,expected,mask[0]);
   if(word==15'h4000)$fwrite(ppm,"%0d %0d %0d\n",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
   // A sys-domain word update inside a frame must not tear the renderer.
   home_word=~word[14:0];
  end
  de=0;tick();if(overlay_valid)$fatal(1,"home over blanking");
  $fclose(fd);$fclose(ppm);$display("PASS home pixels: %0d independent pixels, all five cards, two directions, eased open/close masks and frame snapshots",checks);$finish;
 end
 initial begin #20000000;$fatal(1,"home pixel timeout");end
endmodule
