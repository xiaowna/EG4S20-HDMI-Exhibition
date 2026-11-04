`timescale 1ns/1ps
module tb_audio_source;
 parameter integer CLK_HZ=50_000_000;
 reg clk=0,rst_n=0,enable=1,sample_ready=1;
 always #10 clk=~clk;
 wire valid,tick,overflow;
 wire signed [23:0] left,right;
 audio_test_tone #(.CLK_HZ(CLK_HZ)) dut(clk,rst_n,enable,sample_ready,valid,left,right,tick,overflow);
 longint cycles=0,previous_ticks=0,new_ticks=0;
 integer phase=0,total_ticks=0,accepted=0,dropped=0;
 integer previous_tick_cycle=0,spacing,old_accepted;
 reg expected_valid=0,expected_overflow=0,expected_tick;
 reg signed [23:0] expected_sample=0;
 real sine;
 integer value;
 // 参考节拍由累计经过时间计算，不复用被测模块的累加器实现。
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   cycles=0;previous_ticks=0;phase=0;total_ticks=0;accepted=0;dropped=0;
   expected_valid=0;expected_overflow=0;expected_sample=0;previous_tick_cycle=0;
   #1;
   if(valid!==0 || tick!==0 || overflow!==0 || left!==0 || right!==0)
    $fatal(1,"Reset failed");
  end else begin
   cycles=cycles+1;
   new_ticks=(cycles*48000)/CLK_HZ;
   expected_tick=(new_ticks!=previous_ticks);previous_ticks=new_ticks;
   if(expected_valid && sample_ready) begin expected_valid=0;accepted=accepted+1;end
   if(expected_tick) begin
    if(previous_tick_cycle!=0) begin
     spacing=cycles-previous_tick_cycle;
     if(spacing!=CLK_HZ/48000 && spacing!=(CLK_HZ+47999)/48000)
      $fatal(1,"Invalid sample spacing %0d",spacing);
    end
    previous_tick_cycle=cycles;total_ticks=total_ticks+1;
    sine=4096.0*$sin(6.283185307179586*phase/48.0);
    value=(sine>=0.0)?$rtoi(sine+0.5):$rtoi(sine-0.5);
    if(!expected_valid) begin
     expected_valid=1;expected_sample=enable?(value*256):0;
    end else begin expected_overflow=1;dropped=dropped+1;end
    phase=enable?((phase+1)%48):0;
   end
   #1;
   if(tick!==expected_tick) $fatal(1,"Sample time mismatch cycle=%0d",cycles);
   if(valid!==expected_valid || overflow!==expected_overflow)
    $fatal(1,"Handshake/overflow mismatch cycle=%0d",cycles);
   if(left!==expected_sample || right!==expected_sample)
    $fatal(1,"Sample mismatch cycle=%0d got=%0d expected=%0d",cycles,left,expected_sample);
  end
 end
 task segment(input integer ticks,input integer mode);
  integer n,clocks;
  begin
   clocks=(CLK_HZ/48000+1)*ticks;
   for(n=0;n<clocks;n=n+1) begin
    @(negedge clk);
    enable=(mode!=3);
    case(mode)
     1:sample_ready=(n%29>=14);
     2:sample_ready=0;
     default:sample_ready=1;
    endcase
   end
   @(negedge clk);
  end
 endtask
 initial begin
  repeat(3) @(negedge clk);rst_n=1;
  segment(192,0);
  if(total_ticks<192 || dropped!=0) $fatal(1,"Normal sample flow failed");
  $display("PASS clock=%0d normal 1kHz tone, samples=%0d",CLK_HZ,total_ticks);
  segment(96,1);
  if(CLK_HZ>=1000000 && dropped!=0) $fatal(1,"Short backpressure caused dropped samples");
  sample_ready=0;old_accepted=accepted;
  segment(5,2);
  if(dropped==0 || !overflow || accepted!=old_accepted) $fatal(1,"Backpressure overflow not detected");
  segment(48,0);
  if(!overflow || accepted==old_accepted) $fatal(1,"Recovery/sticky overflow failed");
  segment(96,3);
  if(left!==0 || right!==0) $fatal(1,"Mute failed");
  segment(96,0);
  $display("PASS clock=%0d stall, sticky overflow, mute and resume",CLK_HZ);
  // 在下游阻塞、存在待发样本时复位。
  segment(2,2);
  #3;rst_n=0;
  repeat(3) @(negedge clk);
  sample_ready=1;enable=1;rst_n=1;
  segment(96,0);
  if(overflow || dropped!=0 || total_ticks<96) $fatal(1,"Reset recovery failed");
  $display("PASS clock=%0d reset recovery and exact cadence",CLK_HZ);
  $finish;
 end
 initial begin #100000000;$fatal(1,"Test deadline");end
endmodule
