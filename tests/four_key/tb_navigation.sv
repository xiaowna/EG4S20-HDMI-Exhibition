`timescale 1ns/1ps
module tb_navigation;
 reg clk=0,rst_n=1,card_ready=0,load_ready=0,scan_done=0,image_done=0,error=0;
 reg [2:0] image_count=0;
 reg next_pulse=0,prev_pulse=0,pause=1;
 wire scan_start,load_start;wire [1:0] image_index;
 integer checks=0,n,k;
 always #5 clk=~clk;
 media_playlist_control #(.INTERVAL_CYCLES(12)) dut(.*);
 task tick;begin @(negedge clk);#1;end endtask
 task pulse(input bit backwards);begin
  prev_pulse=backwards;next_pulse=!backwards;tick;prev_pulse=0;next_pulse=0;
 end endtask
 task loaded(input integer expected);begin
  wait(load_start);#1;
  if(image_index!==expected)$fatal(1,"navigation expected %0d actual %0d",expected,image_index);
  tick;checks=checks+1;
 end endtask
 task finish_image;begin image_done=1;tick;image_done=0;tick;end endtask
 task quiet(input integer cycles);integer i;begin
  for(i=0;i<cycles;i=i+1)begin tick;if(load_start)$fatal(1,"unexpected/repeated request");end
 end endtask
 task setup(input integer count);begin
  rst_n=0;card_ready=0;load_ready=0;next_pulse=0;prev_pulse=0;pause=1;image_count=count;tick;rst_n=1;tick;card_ready=1;
  wait(scan_start);tick;scan_done=1;tick;scan_done=0;quiet(4);load_ready=1;loaded(0);finish_image;quiet(15);
 end endtask
 initial begin
  #1;
  for(n=1;n<=4;n=n+1)begin
   setup(n);
   pulse(1);loaded(n-1);finish_image;quiet(15);
   pulse(0);loaded(0);finish_image;
   // Walk each direction through two full wraps, while paused.
   for(k=1;k<=2*n;k=k+1)begin pulse(1);loaded((2*n-k)%n);finish_image;end
   for(k=1;k<=2*n;k=k+1)begin pulse(0);loaded(k%n);finish_image;end
   // Pending commands coalesce while loading; most recent direction wins.
   pulse(0);loaded(1%n);pulse(0);pulse(1);finish_image;loaded(0);finish_image;quiet(20);
   pulse(1);loaded(n-1);pulse(1);pulse(0);finish_image;loaded(0);finish_image;
   // Backpressure retains a valid index and direction, with no extra loads.
   load_ready=0;pulse(1);quiet(8);
   if(image_index!=n-1)$fatal(1,"index changed under load backpressure");
   load_ready=1;loaded(n-1);finish_image;
   // Automatic playback always advances forward, after a manual previous.
   pause=0;loaded(0);pause=1;finish_image;quiet(15);
  end
  $display("PASS four-key navigation: %0d loads, 1..4 images, both wraps, paused manual commands, latest direction, load backpressure and forward autoplay",checks);$finish;
 end
 initial begin #200000;$fatal(1,"navigation timeout");end
endmodule
