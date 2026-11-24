`timescale 1ns/1ps
module tb_solar_smoke;
 reg scene_mode=0;reg [1:0] zoom=1;
 reg sys_clk=0,pix_clk=0,rst_n=0,enable=1,de=0,vsync=1;
 reg [6:0] yaw=12,pitch=83;reg [9:0] x=0,y=0;
 wire [23:0] rgb_out;wire valid_out,ready,fault;
 always #10 sys_clk=~sys_clk;always #20 pix_clk=~pix_clk;
 video_scene3d dut(.*);
 integer n,t,p;
 initial begin
  repeat(5)@(negedge sys_clk);rst_n=1;
  if(dut.body_radius(7,2)-dut.body_radius(7,1)<4)
   $fatal(1,"Neptune zoom must gain at least four canvas pixels of body radius");
  for(n=0;n<8;n=n+1)
   if(dut.orbital_radius(n[2:0],2)<=dut.orbital_radius(n[2:0],1)||
      dut.body_radius(n[3:0],2)<=dut.body_radius(n[3:0],1))
    $fatal(1,"planet %0d did not enlarge its orbit and body",n);
  for(n=0;n<18;n=n+1)begin
   zoom=(n<8)?1:2;
   yaw=(n<16)?12:(n-15);pitch=(((n<8)?10:((n<16)?3:15))<<3)|(n%8);
   repeat(5)@(negedge sys_clk);vsync=0;
   repeat(12)@(negedge sys_clk);vsync=1;
   t=0;
   while(!ready&&t<45010)begin @(negedge sys_clk);t=t+1;end
   if(!ready||fault)$fatal(1,"render failed case %0d clocks %0d state %0d",n,t,dut.state);
   p=0;for(t=0;t<16384;t=t+1)if(dut.canvas[t]!=0)p=p+1;
   if(p<400)$fatal(1,"canvas unexpectedly empty %0d",p);
   $display("case %0d render clocks %0d occupied %0d",n,dut.budget,p);
  end
  $display("PASS solar smoke: all speeds/views complete without fault");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
