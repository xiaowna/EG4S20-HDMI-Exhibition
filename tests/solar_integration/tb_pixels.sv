`timescale 1ns/1ps
module tb_solar_home_pixels;
 reg clk=0,rst_n=0,de=0,vsync=1,scene_enable=0,scene_side=0;
 reg [2:0] scene_rate=3;reg [9:0] x=0,y=0;reg [14:0] home_word=0;
 wire [23:0] rgb_out,legacy_rgb;wire overlay_valid,legacy_valid;
 integer file,k,matched,xx,yy,rr,mask,scan,case_id,rate,side,scene,word,cases;
 reg [255:0] filename;
 always #5 clk=~clk;
 video_home #(.EXHIBIT(1)) dut(.*);
 video_home #(.EXHIBIT(0)) legacy(.clk(clk),.rst_n(rst_n),.de(de),.vsync(vsync),.x(x),.y(y),
  .home_word(home_word),
  .rgb_out(legacy_rgb),.overlay_valid(legacy_valid));
 task ticks(input integer n);repeat(n)begin @(negedge clk);#1;end endtask
 task frame_tick;begin vsync=0;ticks(3);vsync=1;ticks(3);end endtask
 initial begin
  ticks(2);rst_n=1;ticks(2);matched=0;
  for(case_id=0;case_id<12;case_id=case_id+1)begin
   $sformat(filename,"pixels_%0d.txt",case_id);file=$fopen(filename,"r");
   if(!file)$fatal(1,"missing pixel fixture %0d",case_id);
   scan=$fscanf(file,"%h %d %d %d\n",word,scene,rate,side);
   home_word=word;scene_enable=scene;scene_rate=rate;scene_side=side;frame_tick();
   // Inputs are changed after the frame snapshot; they must not tear pixels.
   home_word=~word;scene_enable=!scene;scene_rate=~rate;scene_side=!side;
   de=1;
   while(!$feof(file))begin
    scan=$fscanf(file,"%d %d %h %d\n",xx,yy,rr,mask);
    if(scan==4)begin
     x=xx;y=yy;@(posedge clk);#1;
     if(overlay_valid!==mask[0]||(mask!=0&&rgb_out!==rr[23:0]))
      $fatal(1,"solar overlay mismatch case=%0d x=%0d y=%0d mask=%b/%0d rgb=%h/%h",case_id,xx,yy,overlay_valid,mask,rgb_out,rr[23:0]);
     if(word==0&&legacy_valid!==1'b0)$fatal(1,"EXHIBIT=0 unexpectedly drew solar sidebar");
     matched=matched+1;@(negedge clk);#1;
    end
   end
   de=0;@(posedge clk);#1;if(overlay_valid)$fatal(1,"overlay drew during DE=0");
   $fclose(file);ticks(2);
  end
  $display("PASS solar home overlay: %0d independent pixels, unchanged home and no solar sidebar coverage",matched);$finish;
 end
endmodule
