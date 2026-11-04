`timescale 1ns/1ps
// Check the public handshake/reply contract while inputs change after capture.
module tb_sdram_command_guard #(parameter RESPONSE=4);
 reg clk=0,rst_n=0,valid=0,write_op=0;
 reg [31:0] address=0,word_data=0;reg [8:0] words=1;
 wire ready,reply,error,init,dvalid,last,oe;wire [2:0] command;
 wire [31:0] data;integer active=0,reads=0,writes=0,replies=0,returned=0;
 integer cases=0,k,before_active,before_reads,before_writes,before_replies;
 always #10 clk=~clk;
 em638325_stream_controller #(.POWERUP_CYCLES(2),.REFRESH_CYCLES(100),
  .READ_RESPONSE_CYCLES(RESPONSE)) dut(
  .clk(clk),.rst_n(rst_n),.cmd_valid(valid),.cmd_write(write_op),.cmd_addr(address),
  .cmd_data(word_data),.cmd_words(words),.cmd_ready(ready),.backend_valid(reply),
  .backend_error(error),.backend_data(data),.init_done(init),.data_valid(dvalid),.data_last(last),
  .sd_ras_n(command[2]),.sd_cas_n(command[1]),.sd_we_n(command[0]),.dq_oe(oe),
  .dq_in(32'h9abc1234));
 always @(negedge clk)if(init)begin
  if(command==3'b011)active=active+1;
  if(command==3'b101)reads=reads+1;
  if(command==3'b100)writes=writes+1;
 end
 always @(posedge clk)begin
  #1;
  if(reply)replies=replies+1;
  if(dvalid)begin
   if(data!==32'h9abc1234 || last!==(returned==words_expected-1))
    $fatal(1,"read data/last mismatch");
   returned=returned+1;
  end
 end
 integer words_expected=0;
 task transaction(input [31:0] a,input [8:0] n,input w,input bad);
 integer limit;
 begin
  wait(ready);@(negedge clk);
  before_active=active;before_reads=reads;before_writes=writes;before_replies=replies;
  address=a;words=n;write_op=w;word_data=32'hbeef1234;valid=1;returned=0;words_expected=n;
  @(posedge clk);#2;
  if(ready||reply||command!=3'b111||oe)$fatal(1,"command acted before validation");
  @(negedge clk);valid=0;address=~a;words=0;write_op=!w;word_data=0;
  limit=0;
  while(!reply&&limit<100)begin @(posedge clk);#2;limit=limit+1;end
  if(!reply||error!==bad||replies!=before_replies+1)$fatal(1,"bad command reply");
  if(bad)begin
   if(active!=before_active||reads!=before_reads||writes!=before_writes||returned||oe)
    $fatal(1,"invalid command touched SDRAM or produced data");
  end else begin
   if(active!=before_active+1 || reads!=before_reads+(w?0:n) ||
      writes!=before_writes+(w?1:0) || returned!=(w?0:n))$fatal(1,"valid command lost/duplicated");
  end
  repeat(3)begin @(posedge clk);#2;if(reply||error||dvalid)$fatal(1,"duplicate completion");end
  cases=cases+1;
 end endtask
 initial begin
  #13;rst_n=1;wait(init);
  for(k=21;k<32;k=k+1)transaction(32'd1<<k,1,0,1);
  transaction(0,0,0,1);transaction(0,33,0,1);transaction(0,511,0,1);
  transaction(255,2,0,1);transaction(225,32,0,1);
  transaction(0,0,1,1);transaction(0,2,1,1);transaction(0,32,1,1);
  transaction(255,1,0,0);transaction(224,32,0,0);transaction(2097151,1,0,0);
  transaction(0,1,1,0);transaction(2097151,1,1,0);
  $display("PASS SDRAM command guard RESPONSE=%0d: %0d boundary/invalid/valid commands, changing inputs, single replies",RESPONSE,cases);
  $finish;
 end
 initial begin #200000;$fatal(1,"command guard timeout");end
endmodule
