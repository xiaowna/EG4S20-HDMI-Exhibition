`timescale 1ns/1ps
module tb_shared_wav_catalog;
 reg clk=0,rn=0,start=0,rd_ready=1,rd_done=0,rd_error=0,rd_valid=0;
 always #5 clk=~clk;
 reg [8:0] rd_addr=0;reg [7:0] rd_data=0;
 wire req,done,error,wav_found,found_valid;wire [31:0] lba,wav_cluster,wav_size;
 wire [2:0] image_count;wire [31:0] fat_base,data_base,clusters,root_lba,root_cluster;
 wire [7:0] spc;reg [7:0] mem[0:1535];integer bank,k,requests=0,bmps=0,mode=0;
 fat32_card_catalog #(.MAX_FILES(4),.FIND_WAV(1),.TIMEOUT_CYCLES(500000)) dut(
  .clk(clk),.rst_n(rn),.start(start),.rd_ready(rd_ready),
  .rd_done(rd_done),.rd_error(rd_error),.rd_addr(rd_addr),.rd_data(rd_data),
  .rd_valid(rd_valid),.rd_start(req),.rd_lba(lba),.busy(),.done(done),.error(error),
  .found_valid(found_valid),.found_index(),.found_first_cluster(),.found_size(),
  .found_count(image_count),.volume_fat_lba(fat_base),.volume_data_lba(data_base),
  .volume_cluster_count(clusters),.volume_root_lba(root_lba),
  .volume_root_cluster(root_cluster),.volume_sectors_per_cluster(spc),
  .wav_found(wav_found),.wav_first_cluster(wav_cluster),.wav_size(wav_size));
 always @(posedge clk)if(found_valid)bmps=bmps+1;
 initial forever begin
  @(negedge clk);
  if(req)begin
   if(!rd_ready)$fatal(1,"overlap");rd_ready=0;requests=requests+1;
   if(lba==0)bank=0;else if(lba==1234)bank=1;
   else $fatal(1,"unexpected sector %0d",lba);
   repeat(2)@(negedge clk);
   for(k=0;k<512;k=k+1)begin
    rd_addr=k;rd_data=mem[bank*512+k];rd_valid=1;
    @(negedge clk);rd_valid=0;
   end
   repeat(2)@(negedge clk);
   rd_done=1;@(negedge clk);rd_done=0;rd_ready=1;
  end
 end
 initial begin
  if(!$value$plusargs("MODE=%d",mode))mode=0;
  if(mode==1)$readmemh("card_fixture_4bmp.hex",mem);
  else $readmemh("card_fixture.hex",mem);
  repeat(3)@(negedge clk);rn=1;
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(done);#1;
  if(error||!wav_found||wav_cluster!=5||wav_size!=52||
     bmps!=(mode==1?4:1)||image_count!=(mode==1?4:1)||requests!=3||root_lba!=1234||
     data_base!=1232||fat_base!=32||spc!=2)$fatal(1,"shared BMP/WAV scan failed");
  $display("PASS shared FAT32 catalog mode=%0d: BMP list and WAV from one mount/scan",mode);$finish;
 end
 initial begin #500000;$fatal(1,"catalog timeout req=%0d",requests);end
endmodule
