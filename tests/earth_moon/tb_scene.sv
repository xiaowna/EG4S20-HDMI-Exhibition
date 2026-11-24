`timescale 1ns/1ps
module tb_earth_moon;
 parameter integer CASES=49;
 reg sys_clk=0,pix_clk=0,rst_n=0,enable=1,de=0,vsync=1,scene_mode=1;
 reg [1:0] zoom=1;
 reg [6:0] yaw=12,pitch=83;reg [9:0] x=0,y=0;
 wire [23:0] rgb_out;wire valid_out,ready,fault;
 always #10 sys_clk=~sys_clk;always #20 pix_clk=~pix_clk;
 video_scene3d dut(.*);
 reg [23:0] before_phase[0:CASES*9-1],after_phase[0:CASES*9-1];
 reg [16:0] modes[0:CASES-1];reg [4:0] golden[0:CASES*16384-1];
 reg [23:0] pixels[0:307199];
 reg [13:0] labels[0:CASES*10-1];
 integer i,j,k,n,elapsed,max_budget=0;
 task ticks(input integer count);repeat(count)@(negedge sys_clk);endtask
 task frame;
 begin
  @(negedge pix_clk);vsync=0;ticks(12);vsync=1;ticks(5);
  elapsed=0;while(!ready&&elapsed<45010)begin ticks(1);elapsed=elapsed+1;end
  if(!ready||fault)$fatal(1,"render failed case=%0d state=%0d budget=%0d",i,dut.state,dut.budget);
  if(dut.budget>max_budget)max_budget=dut.budget;
 end endtask
 always @(posedge sys_clk)if(rst_n)begin
  if(dut.writing&&(ready||dut.budget>=45000||dut.write_address>=16384))$fatal(1,"unsafe canvas write");
  if(dut.phases.write_enable)begin
   if(dut.state!=3||dut.planet>8)$fatal(1,"write escaped the nine orbital phases");
  end
 end
 always @(posedge pix_clk)if(rst_n&&dut.label_loading)begin
  if(de)$fatal(1,"serial name load escaped blanking");
  if(dut.state==3||dut.state==5)$fatal(1,"serial name load overlaps projected-center writes");
 end
 initial begin
  $readmemh("phase_before.hex",before_phase);$readmemh("phase_after.hex",after_phase);
  $readmemh("modes.hex",modes);$readmemh("canvas.hex",golden);$readmemh("pixels.hex",pixels);$readmemh("labels.hex",labels);
  for(j=0;j<512;j=j+1)begin dut.phases.memory[j]=24'hdeadde;end
  ticks(4);rst_n=1;ticks(4);i=0;frame();
  for(j=0;j<9;j=j+1)if(dut.phases.memory[j]!==after_phase[j])$fatal(1,"cold phase %0d",j);
  for(j=0;j<16384;j=j+1)if(dut.canvas[j]!==golden[j])$fatal(1,"cold canvas %0d got=%0d expected=%0d",j,dut.canvas[j],golden[j]);
  for(i=0;i<CASES;i=i+1)begin
   scene_mode=modes[i][16];zoom=modes[i][15:14];yaw=modes[i][13:7];pitch=modes[i][6:0];
   for(j=0;j<9;j=j+1)begin dut.phases.memory[j]=before_phase[i*9+j];end
   frame();
   for(j=0;j<9;j=j+1)if(dut.phases.memory[j]!==after_phase[i*9+j])$fatal(1,"phase case=%0d n=%0d",i,j);
   for(j=9;j<512;j=j+1)if(dut.phases.memory[j]!==24'hdeadde)$fatal(1,"unused low RAM overwritten");

   for(j=0;j<16384;j=j+1)if(dut.canvas[j]!==golden[i*16384+j])$fatal(1,"canvas case=%0d a=%0d got=%0d expected=%0d",i,j,dut.canvas[j],golden[i*16384+j]);
   ticks(40);
   if(dut.label_loading)$fatal(1,"name anchor load did not finish in blanking");
   for(j=0;j<10;j=j+1)if((scene_mode&&(j==2||j==9))||(!scene_mode&&j<9))begin
    if({dut.label_y[j],dut.label_x[j]}!==labels[i*10+j])$fatal(1,"name anchor case=%0d index=%0d",i,j);
   end
  end
  i=0;scene_mode=1;zoom=1;yaw=12;pitch=83;
  for(j=0;j<9;j=j+1)begin dut.phases.memory[j]=before_phase[j];end
  frame();ticks(100);n=0;
  for(k=0;k<480;k=k+1)begin
   for(j=0;j<640;j=j+1)begin
    @(negedge pix_clk);x=j;y=k;de=1;@(posedge pix_clk);#1;
    if(!valid_out||rgb_out!==pixels[n])$fatal(1,"raster x=%0d y=%0d got=%h expected=%h",j,k,rgb_out,pixels[n]);
    n=n+1;
   end
   @(negedge pix_clk);de=0;x=640;repeat(160)@(negedge pix_clk);
  end
  // Changing model updates the same phases; no reset or learning cycle.
  scene_mode=0;frame();
  for(j=0;j<9;j=j+1)if(dut.phases.memory[j]!==((after_phase[j]+(after_phase[j]-before_phase[j]))&24'hffffff))$fatal(1,"mode switch reset orbit %0d",j);
  scene_mode=1;vsync=0;ticks(12);vsync=1;ticks(50);de=1;ticks(8);
  if(ready||!fault||dut.state!=0)$fatal(1,"early DE not rejected");
  de=0;rst_n=0;ticks(4);rst_n=1;ticks(4);
  vsync=0;ticks(12);vsync=1;ticks(50);force dut.budget=45000;ticks(2);release dut.budget;ticks(3);
  if(ready||!fault||dut.state!=0)$fatal(1,"deadline not rejected");
  $display("PASS Earth-Moon: %0d canvases, full raster, nine phases, shared RAM partition, guards; max_budget=%0d",CASES,max_budget);$finish;
 end
 initial begin #200000000;$fatal(1,"scene timeout");end
endmodule
