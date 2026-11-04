`timescale 1ns/1ps
module tb_board_key_default;
 reg clk=0,rst_n=0,key_n=1;
 always #10 clk=~clk;
 wire press;
 board_key dut(.clk(clk),.rst_n(rst_n),.key_n(key_n),.press(press));
 integer cycle;
 initial begin
  // Assert a real reset edge before checking asynchronous reset state.
  rst_n=1;#1;rst_n=0;
  #1;if(press!==0)$fatal(1,"debounce press must reset low");
  repeat(3)@(negedge clk);
  #1;rst_n=1;
  repeat(8)@(negedge clk);
  key_n=0;
  repeat(3)begin @(posedge clk);#1;if(press!==0)$fatal(1,"short glitch accepted");end
  @(negedge clk);key_n=1;
  repeat(8)begin @(posedge clk);#1;if(press!==0)$fatal(1,"glitch tail accepted");end
  @(negedge clk);key_n=0;
  // Two synchronizer cycles precede the 1,000,000 stable-level samples.
  for(cycle=1;cycle<=1000002;cycle=cycle+1)begin
   @(posedge clk);#1;
   if(press!==(cycle==1000002))
    $fatal(1,"default 20ms debounce boundary incorrect at cycle %0d",cycle);
  end
  repeat(8)begin @(posedge clk);#1;if(press!==0)$fatal(1,"held DOWN repeated press");end
  #3;rst_n=0;key_n=1;
  #1;if(press!==0)$fatal(1,"asynchronous reset failed");
  repeat(3)@(negedge clk);
  #1;rst_n=1;
  repeat(16)begin @(posedge clk);#1;if(press!==0)$fatal(1,"UP restart operated key");end
  $display("PASS board_key default: 1000000-cycle debounce, two-stage sampling, glitch rejection and one-shot press");
  $finish;
 end
 initial begin #50000000;$fatal(1,"default debounce test timeout");end
endmodule
