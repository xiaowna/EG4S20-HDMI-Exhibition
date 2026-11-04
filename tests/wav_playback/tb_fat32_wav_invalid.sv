`timescale 1ns/1ps
// An unsupported long WAV must stop after its first header sector and report
// an error promptly, so the board can fall back to its internal test tone.
module tb_fat32_wav_invalid;
 reg clk=0,rst_n=0,rd_ready=1,rd_done=0,rd_error=0,rd_valid=0;
 reg [8:0] rd_addr=0;reg [7:0] rd_data=0;
 wire rd_start,playing,error,sample_valid;wire [31:0] rd_lba;
 wire [47:0] sample_data;
 reg [7:0] mem[0:1535];integer i,requests=0;
 always #5 clk=~clk;
 fat32_wav_player #(.TIMEOUT_CYCLES(100000)) dut(
  .clk(clk),.rst_n(rst_n),.volume_ready(1'b1),.file_found(1'b1),
  .first_cluster(32'd5),.file_size(32'h00100000),.fat_lba(32'd32),
  .data_lba(32'd1232),.cluster_count(32'd70000),.sectors_per_cluster(8'd2),
  .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.rd_addr(rd_addr),
  .rd_data(rd_data),.rd_valid(rd_valid),.rd_start(rd_start),.rd_lba(rd_lba),
  .sample_valid(sample_valid),.sample_ready(1'b1),.sample_data(sample_data),
  .playing(playing),.error(error));
 initial begin
  $readmemh("card_fixture.hex",mem);
  // Keep the fixture otherwise valid, but change 48 kHz to 44.1 kHz.
  mem[1024+24]=8'h44;mem[1024+25]=8'hac;
  repeat(3)@(negedge clk);rst_n=1;
  wait(error);
  repeat(8)@(negedge clk);
  if(requests!=1||playing||sample_valid||dut.reader.busy)
   $fatal(1,"invalid WAV did not stop after its header: requests=%0d",requests);
  $display("PASS invalid WAV: error before second sector; test-tone fallback can start");
  $finish;
 end
 initial forever begin
  @(negedge clk);
  if(rd_start)begin
   if(!rd_ready||rd_lba!=32'd1238||requests!=0)
    $fatal(1,"unexpected WAV sector request lba=%0d count=%0d",rd_lba,requests);
   requests=requests+1;rd_ready=0;
   repeat(2)@(negedge clk);
   for(i=0;i<512;i=i+1)begin
    rd_addr=i;rd_data=mem[1024+i];rd_valid=1;
    @(negedge clk);rd_valid=0;
   end
   repeat(2)@(negedge clk);
   rd_done=1;@(negedge clk);rd_done=0;rd_ready=1;
  end
 end
 initial begin #100000;$fatal(1,"invalid WAV error timeout requests=%0d",requests);end
endmodule
