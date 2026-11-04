`timescale 1ns/1ps
module tb_fft_ram_core;
 reg clk=0,rst_n=0,capture_enable=1,sample_valid=0;
 reg signed [23:0] sample_left=0;
 always #5 clk=~clk;
 wire bin_valid,busy;wire [7:0] bin_index;wire signed [15:0] bin_real,bin_imag;
 wire reference_valid,reference_busy;wire [7:0] reference_index;
 wire signed [15:0] reference_real,reference_imag;
 reg [15:0] samples[0:4095];reg [31:0] golden[0:2047];
 reg [15:0] capture_before_reset[0:511];reg [31:0] work_before_reset[0:511];
 integer n,scenario=0,seen=0,total=0,cycles=0,resets=0;
 reg count_bins=0;
 audio_fft512 dut(.*);
 audio_fft512_reference reference(.clk(clk),.rst_n(rst_n),.capture_enable(capture_enable),
  .sample_valid(sample_valid),.sample_left(sample_left),.bin_valid(reference_valid),.busy(reference_busy),
  .bin_index(reference_index),.bin_real(reference_real),.bin_imag(reference_imag));
 function [15:0] capture_word;
  input integer address;
  begin
`ifdef FFT_NATIVE_RAM_TEST
   capture_word=dut.capture_storage.native.storage.memory[address];
`else
   capture_word=dut.capture_storage.behavioral.memory[address];
`endif
  end
 endfunction
 function [31:0] work_word;
  input integer address;
  begin
`ifdef FFT_NATIVE_RAM_TEST
   work_word={dut.fft_storage.native.storage.memory[address*2+1],dut.fft_storage.native.storage.memory[address*2]};
`else
   work_word=dut.fft_storage.behavioral.memory[address];
`endif
  end
 endfunction
 always @(posedge clk)begin #1;
  cycles=cycles+1;
  if(busy!==reference_busy||bin_valid!==reference_valid||dut.state!==reference.state||
   dut.capture_index!==reference.capture_index||dut.load_index!==reference.load_index)
   $fatal(1,"baseline timing/state mismatch cycle=%0d",cycles);
  if(!rst_n&&bin_valid!==1'b0)$fatal(1,"bin_valid survived reset");
  if(rst_n)begin
   // Compare the memory outputs only at the states that consume them.
   if(dut.state==2&&dut.capture_read!==reference.capture_read)
    $fatal(1,"capture consumer mismatch cycle=%0d",cycles);
   if((dut.state==5||dut.state==7||dut.state==16)&&dut.fft_read!==reference.fft_read)
    $fatal(1,"work consumer mismatch cycle=%0d",cycles);
   if(bin_valid)begin
    if({bin_index,bin_real,bin_imag}!=={reference_index,reference_real,reference_imag})
     $fatal(1,"baseline output mismatch cycle=%0d",cycles);
    if(count_bins)begin
     if(bin_index!==seen[7:0]||{bin_real,bin_imag}!==golden[scenario*256+seen])
      $fatal(1,"FFT scenario=%0d bin=%0d expected=%h actual=%h",scenario,seen,golden[scenario*256+seen],{bin_real,bin_imag});
     seen=seen+1;total=total+1;
    end
   end
  end
 end
 task reset_and_check;
  integer address;
  begin
   for(address=0;address<512;address=address+1)begin
    capture_before_reset[address]=capture_word(address);work_before_reset[address]=work_word(address);
   end
   rst_n=0;sample_valid=1;capture_enable=1;
   repeat(4)@(negedge clk);
   for(address=0;address<512;address=address+1)begin
    if(capture_word(address)!==capture_before_reset[address]||work_word(address)!==work_before_reset[address])
     $fatal(1,"reset altered RAM address=%0d",address);
   end
   if(bin_valid||busy)$fatal(1,"reset metadata not idle");
   sample_valid=0;rst_n=1;resets=resets+1;
  end
 endtask
 initial begin
  $readmemh("samples.hex",samples);$readmemh("bins.hex",golden);
  repeat(4)@(negedge clk);rst_n=1;
  capture_enable=0;sample_valid=1;repeat(20)@(negedge clk);
  if(dut.capture_index!=0)$fatal(1,"disabled capture advanced");sample_valid=0;capture_enable=1;
  sample_valid=1;repeat(123)@(negedge clk);sample_valid=0;reset_and_check;
  sample_valid=1;repeat(512)@(negedge clk);sample_valid=0;
  wait(busy);repeat(100)@(negedge clk);reset_and_check;
  // Abort while bin_valid is asserted; reset must suppress the remaining bins.
  sample_valid=1;repeat(512)@(negedge clk);sample_valid=0;
  wait(bin_valid&&bin_index==31);@(negedge clk);reset_and_check;
  count_bins=1;
  for(scenario=0;scenario<8;scenario=scenario+1)begin
   seen=0;
   for(n=0;n<512;n=n+1)begin
    sample_left={samples[scenario*512+n],8'd0};sample_valid=1;
    @(negedge clk);sample_valid=0;
    if(n%7==0)repeat(3)@(negedge clk);
   end
   sample_left=24'h7fff00;sample_valid=1;
   wait(seen==256);@(negedge clk);sample_valid=0;
   wait(!busy);repeat(3)@(negedge clk);
  end
  if(total!=2048||resets!=3)$fatal(1,"incomplete FFT/reset coverage");
  $display("PASS FFT RAM core: 2048 exact complex bins; cycle-identical frozen baseline; capture, processing, valid-output resets retain all 1024 RAM words; gating/busy bursts");
  $finish;
 end
 initial begin #10000000;$fatal(1,"FFT timeout");end
endmodule
