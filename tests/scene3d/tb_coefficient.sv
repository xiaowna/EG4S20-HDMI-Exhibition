`timescale 1ns/1ps
module tb_cube_coefficient;
 reg scene_mode=0;reg [1:0] zoom=1;
 reg sys_clk=0,pix_clk=0,rst_n=0,enable=0,de=0,vsync=1;
 reg [6:0] yaw=0,pitch=0;reg [9:0] x=0,y=0;
 wire [23:0] rgb_out;wire valid_out,ready,fault;
 video_scene3d dut(.*);
 reg signed [7:0] oracle[0:127];integer yy,pp,op,idx,checks=0;
 initial begin
  $readmemh("sine.hex",oracle);
  for(yy=0;yy<128;yy=yy+1)for(pp=0;pp<128;pp=pp+1)for(op=0;op<8;op=op+1)begin
   dut.yaw_q=yy;dut.pitch_q=pp;dut.operation=op;
   case(op)
    0,2:idx=(yy+32)%128;1,3:idx=yy;4,7:idx=(pp+32)%128;default:idx=pp;
   endcase
   #1;if(dut.coefficient!==oracle[idx])$fatal(1,"coefficient mismatch yaw=%0d pitch=%0d operation=%0d",yy,pp,op);
   checks=checks+1;
  end
  $display("PASS shared cube coefficient: %0d exact signed Q7 values, every yaw/pitch/operation",checks);$finish;
 end
endmodule
