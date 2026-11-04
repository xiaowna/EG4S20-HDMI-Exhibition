`timescale 1ns/1ps
// Independent directory bytes, including WAVs AFTER the 32-image limit.
module tb_music_catalog #(parameter integer CAP=32);
 reg clk=0,rst_n=0,start=0,rd_done=0,rd_error=0,rd_valid=0;
 reg [8:0] rd_addr=0;reg [7:0] rd_data=0;reg [1:0] wav_index=0;
 wire rd_start,busy,done,error,found_valid,wav_found;
 wire [31:0] rd_lba,found_first_cluster,found_size,wav_first_cluster,wav_size;
 wire [4:0] found_index;wire [$clog2(CAP+1)-1:0] found_count;wire [2:0] wav_count;
 reg [7:0] bytes[0:2047];
 integer scenarios=0,requests=0,events=0,responding=0,pos=0,base=0,delay=0,bad=0;
 always #5 clk=~clk;
 fat32_dir_scan #(.MAX_FILES(CAP),.FIND_WAV(1),.MAX_WAVS(4),.TIMEOUT_CYCLES(4000)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.root_lba(32'd100),.fat_lba(32'd20),
  .data_lba(32'd100),.root_cluster(32'd2),.cluster_count(32'h0fffff00),.sectors_per_cluster(8'd4),
  .rd_ready(!responding),.rd_done(rd_done),.rd_error(rd_error),.rd_start(rd_start),.rd_lba(rd_lba),
  .rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),.found_valid(found_valid),
  .found_index(found_index),.found_first_cluster(found_first_cluster),.found_size(found_size),
  .busy(busy),.done(done),.error(error),.found_count(found_count),.wav_found(wav_found),
  .wav_first_cluster(wav_first_cluster),.wav_size(wav_size),.wav_index(wav_index),.wav_count(wav_count));
 function [31:0] cluster(input integer i);cluster=32'h01234560+i;endfunction
 function [31:0] size(input integer i);size=32'h87654321+i*32'h10203;endfunction
 always @(posedge clk)begin
  if(rd_start)begin
   if(responding || rd_lba<100 || rd_lba>103)$fatal(1,"bad directory sector request");
   base=(rd_lba-100)*512;pos=0;delay=3;responding=1;requests=requests+1;
  end
  if(found_valid)begin
   if(found_index!==events || found_first_cluster!==10+events || found_size!==100+events)
    $fatal(1,"BMP catalogue changed while collecting music");
   events=events+1;
  end
 end
 always @(negedge clk)begin
  rd_valid=0;rd_done=0;rd_error=0;
  if(responding)begin
   if(delay>0)delay=delay-1;
   else if(pos<512)begin
    rd_valid=1;rd_addr=(bad==2&&base==1024&&pos==20)?19:pos;
    rd_data=bytes[base+pos];pos=pos+1;
   end else begin rd_done=1;rd_error=(bad==1&&base==1024);responding=0;end
  end
 end
 task entry(input integer n,input [23:0] ext,input [31:0] c,s);
  integer a;begin a=n*32;bytes[a]="A";bytes[a+8]=ext[23:16];bytes[a+9]=ext[15:8];bytes[a+10]=ext[7:0];
   bytes[a+20]=c[23:16];bytes[a+21]=c[31:24];bytes[a+26]=c[7:0];bytes[a+27]=c[15:8];
   for(integer j=0;j<4;j=j+1)bytes[a+28+j]=s>>(8*j);
  end
 endtask
 task scenario(input integer songs,failed,noise);
  integer offset,expected_count;begin
   for(integer j=0;j<2048;j=j+1)bytes[j]=0;
   for(integer j=0;j<32;j=j+1)entry(j,24'h424d50,10+j,100+j);
   offset=32;
   if(noise)begin
    entry(offset,24'h574156,2,1);bytes[offset*32]=8'he5;offset=offset+1;
    entry(offset,24'h574156,2,1);bytes[offset*32+11]=8'h10;offset=offset+1;
    entry(offset,24'h574156,2,1);bytes[offset*32+11]=8'h0f;offset=offset+1;
    entry(offset,24'h574156,0,1);offset=offset+1;
    entry(offset,24'h574156,2,0);offset=offset+1;
   end
   for(integer j=0;j<songs;j=j+1)entry(offset+j,(j%2)?24'h776176:24'h574156,cluster(j),size(j));
   @(negedge clk);bad=failed;events=0;requests=0;start=1;
   @(negedge clk);start=0;wait(done);#1;
   if(error!==(failed!=0) || events!=CAP || found_count!=CAP)$fatal(1,"directory completion/count failure");
   expected_count=failed?0:((songs>4)?4:songs);
   if(wav_count!=expected_count || wav_found!==(expected_count!=0))$fatal(1,"bad WAV count");
   if(requests!=3)$fatal(1,"WAV scan stopped at BMP limit or unnecessary sector");
   if(!failed)for(integer j=0;j<expected_count;j=j+1)begin
    @(negedge clk);wav_index=j;repeat(3)@(negedge clk);
    if(wav_first_cluster!==cluster(j) || wav_size!==size(j))$fatal(1,"truncated/wrong music metadata slot=%0d",j);
   end
   scenarios=scenarios+1;repeat(3)@(negedge clk);
  end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  for(integer j=0;j<=5;j=j+1)scenario(j,0,0);
  scenario(4,0,1);scenario(4,1,0);scenario(4,2,0);scenario(1,0,0);scenario(0,0,0);
  $display("PASS four-WAV catalog cap=%0d scenarios=%0d: 0..5 files, after 32 BMPs, ignored entries, full 60-bit metadata, rescan, CRC/order failure",CAP,scenarios);$finish;
 end
 initial begin #5000000;$fatal(1,"music catalogue timeout");end
endmodule
