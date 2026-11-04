`timescale 1ns/1ps
module tb_dmz_seg_test_top;
 reg clk50=0,rst_n=0;
 always #10 clk50=~clk50;
 wire [7:0] seg_led;
 wire [3:0] seg_sel;
 dmz_seg_test_top dut(.clk50(clk50),.rst_n(rst_n),
  .seg_led(seg_led),.seg_sel(seg_sel));
 reg [7:0] previous_seg=0;
 reg [3:0] previous_sel=4'b1111;
 integer cycle,digit,phase,closures=0;
 reg [7:0] expected_seg;
 reg [3:0] expected_sel;
 function [7:0] segments(input integer selected_digit);
  case(selected_digit)
   0:segments=8'h66; // Rightmost 4.
   1:segments=8'h4f; // 3.
   2:segments=8'h5b; // 2.
   3:segments=8'h06; // Leftmost 1.
   default:segments=8'hxx;
  endcase
 endfunction
 task check_cycle(input integer elapsed_cycles);
  begin
   digit=((elapsed_cycles-1)/50000)%4;
   phase=elapsed_cycles%50000;
   expected_seg=segments(digit);
   expected_sel=(phase==0 || phase==1)?4'b1111:
    (4'b1111^(4'b0001<<digit));
   if(seg_led!==expected_seg || seg_sel!==expected_sel)
    $fatal(1,"cycle %0d: segments=%h select=%b expected=%h/%b",
     elapsed_cycles,seg_led,seg_sel,expected_seg,expected_sel);
   case(seg_sel)
    4'b1111,4'b1110,4'b1101,4'b1011,4'b0111:begin end
    default:$fatal(1,"multiple digit commons active or unknown: %b",seg_sel);
   endcase
   if(seg_led[7]!==0)$fatal(1,"decimal point must remain off");
   // Segment data may change only after the previous cycle closed all digits.
   if(seg_led!==previous_seg &&
      (previous_sel!==4'b1111 || seg_sel!==4'b1111))
    $fatal(1,"segment data changed without a preceding all-off cycle");
   if(seg_sel!==4'b1111 && seg_sel!==previous_sel &&
      (previous_sel!==4'b1111 || seg_led!==previous_seg))
    $fatal(1,"digit reopened before its segment data was stable");
   if(previous_sel!==4'b1111 && seg_sel===4'b1111)begin
    if(phase!=0)$fatal(1,"digit closed outside the 50000-cycle boundary");
    closures=closures+1;
   end
   previous_seg=seg_led;
   previous_sel=seg_sel;
  end
 endtask
 task check_reset;
  begin
   #1;
   if(seg_sel!==4'b1111 || seg_led!==8'h00)
    $fatal(1,"asynchronous reset must immediately blank all digits and segments");
   previous_seg=seg_led;
   previous_sel=seg_sel;
  end
 endtask
 initial begin
  check_reset();
  repeat(3)@(negedge clk50);
  #3;rst_n=1;
  // Two complete four-digit scans, including the return to the rightmost 4.
  for(cycle=1;cycle<=400002;cycle=cycle+1)begin
   @(posedge clk50);#1;
   check_cycle(cycle);
  end
  if(closures!=8)$fatal(1,"expected eight 1ms digit intervals, got %0d",closures);
  if(seg_led!==8'h66 || seg_sel!==4'b1110)
   $fatal(1,"second full scan must return to the rightmost 4");
  // Reset during the next digit's visible interval rather than at a clock edge.
  for(cycle=400003;cycle<=450139;cycle=cycle+1)begin
   @(posedge clk50);#1;
   check_cycle(cycle);
  end
  if(seg_led!==8'h4f || seg_sel!==4'b1101)
   $fatal(1,"reset exercise must interrupt an illuminated 3");
  #4;rst_n=0;
  check_reset();
  repeat(5)begin
   @(posedge clk50);
   check_reset();
  end
  @(negedge clk50);#3;rst_n=1;
  // A reset must restart with 4, hold it for 1ms, then select 3 normally.
  for(cycle=1;cycle<=50002;cycle=cycle+1)begin
   @(posedge clk50);#1;
   check_cycle(cycle);
  end
  if(seg_led!==8'h4f || seg_sel!==4'b1101)
   $fatal(1,"post-reset scan must progress from 4 to 3");
  $display("PASS DMZ seven-segment: two complete 1234 scans, 50000-cycle digit periods, blank-before-update, asynchronous reset recovery");
  $finish;
 end
 initial begin #20000000;$fatal(1,"seven-segment test timeout");end
endmodule
