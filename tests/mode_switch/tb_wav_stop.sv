`timescale 1ns/1ps
module tb_wav_stop;
 reg clk=0,rst_n=1,play_enable=0,allow_samples=1;
 wire rd_ready,rd_done,rd_error,rd_valid,rd_start,sample_valid,playing,error,idle,card_busy;
 wire [8:0] rd_addr;wire [7:0] rd_data;wire [31:0] rd_lba;wire [47:0] sample_data;
 integer cycles=0,samples=0,expected_index=0,starts=0,cases=0,n,timeout,previous_starts,first_samples;
 wire sample_ready=allow_samples&&(cycles%7!=0);
 always #5 clk=~clk;
 mode_wav_sector_model card(.clk(clk),.rst_n(rst_n),.rd_start(rd_start),.rd_lba(rd_lba),
  .extra_delay(16'd3),.rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),
  .rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),.busy(card_busy));
 fat32_wav_player #(.CONTROLLED_STOP(1),.TIMEOUT_CYCLES(10000)) dut(
  .clk(clk),.rst_n(rst_n),.volume_ready(1'b1),.file_found(1'b1),.first_cluster(32'd2),
  .file_size(32'd684),.fat_lba(32'd20),.data_lba(32'd100),.cluster_count(32'd100),
  .sectors_per_cluster(8'd1),.rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),
  .rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),.rd_start(rd_start),.rd_lba(rd_lba),
  .sample_valid(sample_valid),.sample_ready(sample_ready),.sample_data(sample_data),
  .playing(playing),.error(error),.play_enable(play_enable),.idle(idle));
 function [47:0] expected_sample(input integer index);
  reg [15:0] l,r;
  begin l=16'h1000+index;r=16'h6000+index;expected_sample={l,8'd0,r,8'd0};end
 endfunction
 always @(posedge clk)if(rst_n)begin
  cycles=cycles+1;if(rd_start)starts=starts+1;
  if(sample_valid&&sample_ready)begin
   if(sample_data!==expected_sample(expected_index))$fatal(1,"WAV restart/order expected index=%0d actual=%h",expected_index,sample_data);
   expected_index=(expected_index==159)?0:expected_index+1;samples=samples+1;
  end
  if(error)$fatal(1,"valid WAV reported error");
 end
 task tick;begin @(negedge clk);#1;end endtask
 task wait_idle;integer t;begin
  t=0;while(!idle || card_busy)begin tick;t=t+1;if(t>2000)$fatal(1,"stop did not drain complete sector");end
 end endtask
 initial begin
  #1;rst_n=0;tick;rst_n=1;tick;
  // Reader's START_CHECK/REQUEST/RECEIVE/CHECK/FETCH/SEND/ADVANCE/FAT phases,
  // plus the player's FILE_START and final-sample/header-prefetch DRAIN.
  for(n=0;n<11;n=n+1)begin
   play_enable=1;allow_samples=1;expected_index=0;timeout=0;
   while((n<9 && dut.reader.state!=n+1) || (n==9&&dut.state!=1) || (n==10&&dut.state!=3))begin
    tick;timeout=timeout+1;
    if(n==10 && expected_index==159)allow_samples=0;
    if(timeout>15000)$fatal(1,"target stop phase not reached n=%0d",n);
   end
   play_enable=0;allow_samples=0;wait_idle;
   previous_starts=starts;repeat(20)tick;
   if(starts!=previous_starts || playing || sample_valid)$fatal(1,"disabled WAV restarted or emitted samples");
   expected_index=0;first_samples=samples;allow_samples=1;play_enable=1;
   timeout=0;while(samples<first_samples+10)begin tick;timeout=timeout+1;if(timeout>3000)$fatal(1,"restart did not parse fresh header");end
   play_enable=0;allow_samples=0;wait_idle;cases=cases+1;
  end
  $display("PASS wav_stop: %0d file/sector/FAT/prefetch phases drained without cancellation; every restart begins at sample zero; samples=%0d sectors=%0d",cases,samples,starts);$finish;
 end
 initial begin #3000000;$fatal(1,"WAV stop timeout");end
endmodule
