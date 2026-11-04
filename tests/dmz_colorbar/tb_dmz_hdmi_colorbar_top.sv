`timescale 1ns/1ps
// Behavioral stubs verify integration; real PLL/ODDR implementation is TD's job.
module board_pll(input wire refclk,reset,output wire extlock,
 output reg clk0_out,clk1_out,clk2_out);
 reg lock_enable=0;
 initial begin clk0_out=0;clk1_out=0;clk2_out=0;end
 assign extlock=lock_enable&&!reset;
 always #20 clk0_out=~clk0_out;
 always #4 clk1_out=~clk1_out;
 always #10 clk2_out=~clk2_out;
endmodule
module EG_LOGIC_ODDR(output wire q,input wire clk,d1,d0,rst);
 reg rise_bit,fall_bit;
 always @(posedge clk or posedge rst)
  if(rst)begin rise_bit<=0;fall_bit<=0;end
  else begin rise_bit<=d0;fall_bit<=d1;end
 assign q=clk?rise_bit:fall_bit;
endmodule
module tb_dmz_hdmi_colorbar_top;
 reg clk50=0,rst_n=0;
 always #10 clk50=~clk50;
 wire hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 wire [1:0] led;
 dmz_hdmi_colorbar_top dut(.clk50(clk50),.rst_n(rst_n),
  .hdmi_clk_p(hdmi_clk_p),.hdmi_d0_p(hdmi_d0_p),
  .hdmi_d1_p(hdmi_d1_p),.hdmi_d2_p(hdmi_d2_p),.led(led));
 task check_stopped;
  begin
   #1;
   if(led!==2'b00 || dut.core_rst_n!==0 || dut.de!==0 || dut.rgb!==0)
    $fatal(1,"reset/lock loss must stop video and clear LEDs");
  end
 endtask
 task check_release;
  integer cycle;
  begin
   #1;
   if(led[1]!==1 || dut.core_rst_n!==0)
    $fatal(1,"PLL lock indicator or initial reset release incorrect");
   for(cycle=0;cycle<4;cycle=cycle+1)begin
    @(negedge dut.pix_clk);#1;
    if(dut.core_rst_n!==(cycle==3))
     $fatal(1,"reset release must take four pixel falling edges");
   end
  end
 endtask
 initial begin
  check_stopped();
  #25;rst_n=1;
  repeat(6)@(negedge dut.pix_clk);
  check_stopped();
  #1;dut.u_pll.lock_enable=1;
  check_release();
  if(led!==2'b10)$fatal(1,"LED1 must light on lock, LED0 starts off");
  // Exercise the real 25,000,000-cycle rollover without half-second simulation.
  @(negedge dut.sys_clk);
  dut.heartbeat_count=25'd24999998;
  @(posedge dut.sys_clk);#1;
  if(led[0]!==0)$fatal(1,"heartbeat toggled before half-second boundary");
  @(posedge dut.sys_clk);#1;
  if(led!==2'b11 || dut.heartbeat_count!==0)
   $fatal(1,"heartbeat must light and restart counter at half-second boundary");
  repeat(6)@(posedge dut.sys_clk);
  #1;if(led!==2'b11)$fatal(1,"heartbeat must hold between boundaries");
  @(negedge dut.sys_clk);
  dut.heartbeat_count=25'd24999999;
  @(posedge dut.sys_clk);#1;
  if(led!==2'b10)$fatal(1,"heartbeat must toggle back off");
  dut.u_pll.lock_enable=0;
  check_stopped();
  repeat(3)@(negedge dut.pix_clk);
  #1;dut.u_pll.lock_enable=1;
  check_release();
  #3;rst_n=0;
  check_stopped();
  #25;rst_n=1;
  check_release();
  $display("PASS DMZ top: active-high LEDs, heartbeat boundary, reset and PLL lock recovery");
  $finish;
 end
 initial begin #10000;$fatal(1,"top test timeout");end
endmodule
