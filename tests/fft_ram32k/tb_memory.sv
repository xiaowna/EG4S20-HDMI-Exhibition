`timescale 1ns/1ps
module tb_fft_memory;
 reg clk=0;
 always #5 clk=~clk;
 reg [8:0] capture_write_address=0,capture_read_address=0,work_address=0;
 reg capture_write=0,work_write=0;
 reg [15:0] capture_data=0;
 reg [31:0] work_data=0;
 wire [15:0] capture_native,capture_behavioral;
 wire [31:0] work_native,work_behavioral;
 reg [15:0] capture_expected[0:511];
 reg [31:0] work_expected[0:511];
 reg [15:0] expected_capture;
 reg [31:0] expected_work;
 integer n,checked=0;
 reg [31:0] random_state=32'h51232abc;
 audio_fft_capture_ram #(.USE_NATIVE(1)) cap_native(.clk(clk),.write_address(capture_write_address),
  .write_enable(capture_write),.write_data(capture_data),.read_address(capture_read_address),.read_data(capture_native));
 audio_fft_capture_ram #(.USE_NATIVE(0)) cap_behavioral(.clk(clk),.write_address(capture_write_address),
  .write_enable(capture_write),.write_data(capture_data),.read_address(capture_read_address),.read_data(capture_behavioral));
 audio_fft_work_ram #(.USE_NATIVE(1)) fft_native(.clk(clk),.address(work_address),
  .write_enable(work_write),.write_data(work_data),.read_data(work_native));
 audio_fft_work_ram #(.USE_NATIVE(0)) fft_behavioral(.clk(clk),.address(work_address),
  .write_enable(work_write),.write_data(work_data),.read_data(work_behavioral));
 function [31:0] next_random;
  input [31:0] value;
  reg [31:0] v;
  begin v=value^(value<<13);v=v^(v>>17);next_random=v^(v<<5);end
 endfunction
 task check_edge;
  begin
   expected_capture=capture_expected[capture_read_address];expected_work=work_expected[work_address];
   @(posedge clk);#1;
   if(capture_native!==expected_capture||capture_behavioral!==expected_capture)
    $fatal(1,"capture read latency/data addr=%0d expected=%h native=%h behavioral=%h",capture_read_address,expected_capture,capture_native,capture_behavioral);
   if(work_native!==expected_work||work_behavioral!==expected_work)
    $fatal(1,"work read latency/data addr=%0d expected=%h native=%h behavioral=%h",work_address,expected_work,work_native,work_behavioral);
   if(capture_write)capture_expected[capture_write_address]=capture_data;
   if(work_write)work_expected[work_address]=work_data;
   checked=checked+1;
   @(negedge clk);
  end
 endtask
 initial begin
  @(negedge clk);
  // Initialize through the public write ports; RAM itself has no reset.
  for(n=0;n<512;n=n+1)begin
   capture_write=1;work_write=1;capture_write_address=n;work_address=n;
   capture_data=(n*173)^16'ha55a;work_data={16'(n*331),16'(n*719)^16'hacdc};
   capture_expected[n]=capture_data;work_expected[n]=work_data;
   @(negedge clk);
  end
  capture_write=0;work_write=0;
  for(n=0;n<512;n=n+1)begin capture_read_address=n;work_address=n;check_edge;end
  for(n=0;n<4096;n=n+1)begin
   random_state=next_random(random_state);capture_write_address=random_state[8:0];
   capture_read_address=random_state[17:9];work_address=random_state[26:18];
   // Cross-port read/write collisions have no useful FFT consumer; avoid them.
   if(capture_write_address==capture_read_address)capture_read_address=capture_read_address+1'b1;
   capture_write=random_state[27];work_write=random_state[28];
   random_state=next_random(random_state);capture_data=random_state[15:0];work_data=random_state;
   check_edge;
  end
  capture_write=0;work_write=0;
  for(n=0;n<512;n=n+1)begin capture_read_address=n;work_address=n;check_edge;end
  if(checked!=5120)$fatal(1,"incomplete memory coverage");
  $display("PASS FFT RAM: native/behavioral equal, all 512 capture and complex words, 4096 randomized simultaneous port operations, one-cycle reads");
  $finish;
 end
 initial begin #1000000;$fatal(1,"memory timeout");end
endmodule
