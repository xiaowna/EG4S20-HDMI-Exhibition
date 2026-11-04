`timescale 1ns/1ps
module tb_scene;
 reg scene_mode=0;reg [1:0] zoom=1;
 reg sys_clk=0,pix_clk=0,rst_n=0,enable=1,de=0,vsync=1;
 reg [6:0] yaw=12,pitch=10;reg [9:0] x=0,y=0;
 wire [23:0] rgb_out;wire valid_out,ready,fault;
 always #10 sys_clk=~sys_clk;always #20 pix_clk=~pix_clk;
 video_scene3d dut(.*);
 reg [13:0] poses[0:31];reg [1:0] golden[0:524287];reg [23:0] pixels[0:307199];
 integer i,j,k,n,elapsed,max_elapsed=0,outfile;
 task ticks(input integer count);repeat(count)@(negedge sys_clk);endtask
 task frame;
 begin
  @(negedge pix_clk);vsync=0;ticks(12);vsync=1;ticks(5);
  elapsed=0;while(!ready&&elapsed<22010)begin ticks(1);elapsed++;end
  if(!ready||fault)$fatal(1,"cube render failed pose %0d elapsed %0d",i,elapsed);
  if(elapsed>max_elapsed)max_elapsed=elapsed;
 end endtask
 // A completed image must not be modified between blanking intervals.
 always @(posedge sys_clk)if(rst_n&&dut.writing)begin
  if(ready||dut.budget>=22000)$fatal(1,"write after publish or deadline");
 end
 initial begin
  $readmemh("poses.hex",poses);$readmemh("canvas.hex",golden);$readmemh("pixels.hex",pixels);
  ticks(4);rst_n=1;ticks(4);
  for(i=0;i<32;i++)begin
   {yaw,pitch}=poses[i];frame();
   for(j=0;j<16384;j++)if(dut.canvas[j]!==golden[i*16384+j])
    $fatal(1,"independent canvas mismatch pose=%0d address=%0d got=%0d expected=%0d",i,j,dut.canvas[j],golden[i*16384+j]);
   ticks(20);
  end
  // A shortened blanking interval is rejected and never published.
  @(negedge pix_clk);vsync=0;ticks(10);vsync=1;ticks(100);de=1;ticks(8);
  if(ready||!fault||dut.state!=0)$fatal(1,"early video did not abort incomplete frame");
  de=0;rst_n=0;ticks(4);rst_n=1;ticks(4);yaw=12;pitch=10;
  frame();force dut.budget=22000;ticks(1);release dut.budget;
  // Real deadline failure while rendering, independent of normal completion.
  vsync=0;ticks(10);vsync=1;ticks(30);force dut.budget=22000;ticks(2);release dut.budget;ticks(3);
  if(ready||!fault||dut.state!=0)$fatal(1,"deadline did not invalidate frame");
  rst_n=0;ticks(4);rst_n=1;ticks(4);frame();
  if(dut.hue!=1)$fatal(1,"preview hue");
  // Realistic blanking remainder before the active raster; 50/25 MHz clocks.
  ticks(40000);outfile=$fopen("cube.ppm","w");$fwrite(outfile,"P3\n640 480\n255\n");
  n=0;
  for(k=0;k<480;k++)begin
   for(j=0;j<640;j++)begin
    @(negedge pix_clk);x=j;y=k;de=1;
    @(posedge pix_clk);#1;
    if(!valid_out||rgb_out!==pixels[n])$fatal(1,"cube raster mismatch x=%0d y=%0d got=%h expected=%h valid=%b",j,k,rgb_out,pixels[n],valid_out);
    $fwrite(outfile,"%0d %0d %0d\n",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);n++;
   end
   @(negedge pix_clk);de=0;x=640;repeat(160)@(negedge pix_clk);
  end
  $fclose(outfile);enable=0;repeat(4)@(negedge pix_clk);de=1;@(posedge pix_clk);#1;
  if(valid_out)$fatal(1,"disabled scene covered legacy video");
  $display("PASS cube: 32 full canvas oracles (524288 pixels), 307200 raster pixels, deadline/early-DE protection, max render %0d clocks",max_elapsed);
  $finish;
 end
 initial begin #100000000;$fatal(1,"scene timeout");end
endmodule
