`timescale 1ns/1ps
module tb_fat32_wav_player;
 reg clk=0,rn=0;always #5 clk=~clk;
 reg rd_ready=1,rd_done=0,rd_error=0,rd_valid=0,sample_ready=1;
 reg [8:0] rd_addr=0;reg [7:0] rd_data=0;
 wire rd_start,playing,error,sample_valid;wire [31:0] rd_lba;
 wire [47:0] sample_data;
 reg [7:0] mem[0:1535];integer bank,k,requests=0,samples=0;
 fat32_wav_player #(.TIMEOUT_CYCLES(500000)) dut(
 .clk(clk),.rst_n(rn),.volume_ready(1'b1),.file_found(1'b1),
 // data 块在字节 51 结束；文件尾仍有数据，循环时不应请求后续扇区。
 .first_cluster(32'd5),.file_size(32'd1536),.fat_lba(32'd32),
 .data_lba(32'd1232),.cluster_count(32'd70000),.sectors_per_cluster(8'd2),
 .rd_ready(rd_ready),
 .rd_done(rd_done),.rd_error(rd_error),.rd_addr(rd_addr),
 .rd_data(rd_data),.rd_valid(rd_valid),.rd_start(rd_start),.rd_lba(rd_lba),
 .sample_valid(sample_valid),.sample_ready(sample_ready),.sample_data(sample_data),
 .playing(playing),.error(error));
 initial forever begin
  @(negedge clk);
  if(rd_start)begin
   if(!rd_ready)$fatal(1,"overlapping sector");
   rd_ready=0;requests=requests+1;
   if(rd_lba==1238)bank=2;
   else $fatal(1,"unexpected LBA %0d",rd_lba);
   repeat(2)@(negedge clk);
   for(k=0;k<512;k=k+1)begin
    rd_addr=k;rd_data=mem[bank*512+k];rd_valid=1;
    @(negedge clk);rd_valid=0;
   end
   repeat(2)@(negedge clk);
   rd_done=1;@(negedge clk);rd_done=0;rd_ready=1;
  end
 end
 always @(posedge clk)if(rn&&sample_valid&&sample_ready)begin
  if(samples%2==0&&sample_data!==48'h123400fedc00)$fatal(1,"first WAV sample %h",sample_data);
  if(samples%2==1&&sample_data!==48'h000100800000)$fatal(1,"second WAV sample %h",sample_data);
  samples=samples+1;
 end
 initial begin
  $readmemh("card_fixture.hex",mem);
  repeat(3)@(negedge clk);rn=1;
  wait(samples==1);@(negedge clk);sample_ready=0;
  wait(dut.state==3);
  wait(dut.reader.out_valid);repeat(20)@(negedge clk);
  if(!sample_valid||samples!=1||requests!=2||!dut.byte_pending||
     dut.byte_buffer!==8'h52||dut.reader.out_offset!=1||dut.reader.out_data!==8'h49)
   $fatal(1,"next header not prefetched while final sample is held");
  // The queued 'R' is retained; downstream readiness must not propagate back
  // into the reader or consume the next header before parser_start.
  force dut.byte_ready=1'b1;#1;
  if(dut.file_byte_ready||dut.parser_byte_valid)$fatal(1,"ready path bypassed elastic byte");
  repeat(3)@(negedge clk);release dut.byte_ready;
  if(!dut.byte_pending||dut.byte_buffer!==8'h52)$fatal(1,"prefetched header lost before restart");
  sample_ready=1;
  wait(samples>=4);repeat(3)@(negedge clk);
  if(!playing||error||requests<2)$fatal(1,"WAV file discovery failed requests=%0d",requests);
  $display("PASS FAT32 WAV: next header prefetched during final-sample backpressure, no dropped loop samples");
  $finish;
 end
 initial begin #500000;$fatal(1,"WAV card simulation timeout req=%0d samples=%0d",requests,samples);end
endmodule
