`timescale 1ns/1ps
module tb_wav_elastic #(parameter CASE=0,WIDTH=16);
 reg clk=0,rst_n=0,play_enable=1,sample_ready=1;
 always #5 clk=~clk;
 reg rd_ready=1,rd_done=0,rd_error=0,rd_valid=0;
 reg [8:0] rd_addr=0;reg [7:0] rd_data=0;
 reg [31:0] file_size=0;
 wire rd_start,sample_valid,playing,error,idle;wire [31:0] rd_lba;
 wire [47:0] sample_data;
 reg [7:0] source_a[0:511],source_b[0:511];reg [47:0] expected[0:3];
 integer requests=0,samples=0,expected_index=0,generation=0;
 integer k,bank,first_size,prior_requests;
 reg transfer_active=0,use_new=0;
 fat32_wav_player #(.TIMEOUT_CYCLES(100000),.CONTROLLED_STOP(1)) dut(
  .clk(clk),.rst_n(rst_n),.volume_ready(1'b1),.file_found(1'b1),
  .first_cluster(32'd5),.file_size(file_size),.fat_lba(32'd32),
  .data_lba(32'd1232),.cluster_count(32'd70000),.sectors_per_cluster(8'd2),
  .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),
  .rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),
  .rd_start(rd_start),.rd_lba(rd_lba),.sample_valid(sample_valid),
  .sample_ready(sample_ready),.sample_data(sample_data),.playing(playing),
  .error(error),.play_enable(play_enable),.idle(idle));

 // The actual reader sees complete sectors, including a late CRC/status edge.
 // It must not advertise idle or launch a new request while a stopped sector
 // transaction is still active.
 initial forever begin
  @(negedge clk);
  if(rd_start)begin
   if(!rd_ready||transfer_active||rd_lba!=1238)$fatal(1,"invalid/overlapping request %0d",rd_lba);
   rd_ready=0;transfer_active=1;requests=requests+1;bank=use_new;
   repeat(3)@(negedge clk);
   for(k=0;k<512;k=k+1)begin
    rd_addr=k;rd_data=bank?source_b[k]:source_a[k];rd_valid=1;
    @(negedge clk);rd_valid=0;
    if(k%7==0)@(negedge clk);
   end
   repeat(7)@(negedge clk);
   rd_done=1;@(negedge clk);rd_done=0;rd_ready=1;transfer_active=0;
  end
 end
 always @(posedge clk)if(rst_n)begin
  if(!play_enable&&sample_valid)$fatal(1,"sample leaked after controlled stop");
  if(!play_enable&&transfer_active&&idle)$fatal(1,"idle asserted during active stopped transaction");
  if(sample_valid&&sample_ready)begin
   if(sample_data!==expected[generation*2+expected_index])
    $fatal(1,"PCM duplicate/loss/stale data generation=%0d index=%0d got=%h expected=%h",generation,expected_index,sample_data,expected[generation*2+expected_index]);
   expected_index=1-expected_index;samples=samples+1;
  end
 end
 task ticks(input integer n);repeat(n)@(negedge clk);endtask
 task replay_new_file(input integer target);
  begin
   play_enable=0;sample_ready=0;ticks(3);
   wait(idle);@(negedge clk);
   if(dut.byte_pending||dut.file_done_pending||sample_valid)$fatal(1,"stale elastic state after stop");
   use_new=1;file_size=first_size;generation=1;expected_index=0;
   play_enable=1;sample_ready=1;
   wait(samples>=target);ticks(3);
   if(error||!playing)$fatal(1,"new file rejected after replay");
  end
 endtask
 initial begin
  if(WIDTH==16)begin
   $readmemh("a16.hex",source_a);$readmemh("b16.hex",source_b);$readmemh("expected16.hex",expected);
  end else begin
   $readmemh("a24.hex",source_a);$readmemh("b24.hex",source_b);$readmemh("expected24.hex",expected);
  end
  first_size=44+WIDTH/8*4;file_size=first_size;
  ticks(3);rst_n=1;
  if(CASE==5)begin
   wait(transfer_active&&rd_valid&&rd_addr==120);@(negedge clk);
   play_enable=0;prior_requests=requests;ticks(10);
   if(idle||samples!=0||requests!=prior_requests)$fatal(1,"mid-sector stop did not wait for CRC");
   replay_new_file(2);
  end else begin
   wait(samples==1);@(negedge clk);sample_ready=0;
   if(CASE==0||CASE==1)begin
    // The reader completes after delivering the last byte to the elastic
    // register, while the parser is deliberately unable to consume that byte.
    while(!(dut.reader.out_valid&&dut.reader.out_offset==first_size-1&&!dut.byte_pending))@(negedge clk);
    force dut.byte_ready=1'b0;ticks(12);
    if(!dut.byte_pending||!dut.file_done_pending||dut.parser_data_done||error)
     $fatal(1,"EOF was lost or rejected before final queued byte retired");
    ticks(13);release dut.byte_ready;
   end
   wait(dut.state==3);@(negedge clk);
   if(CASE==2)file_size=1;
   if(CASE==3)file_size=0;
   if(CASE==4)file_size=first_size-3;
   if(CASE==3)begin
    wait(dut.file_done_pending);ticks(10);
    if(dut.byte_pending)$fatal(1,"zero-byte file produced phantom header");
   end else begin
    wait(dut.byte_pending);ticks(20);
    if(dut.byte_buffer!==8'h52)$fatal(1,"queued next header lost R");
    if(CASE==2)begin
     if(!dut.file_done_pending||dut.reader.busy)$fatal(1,"one-byte EOF event lost in DRAIN");
    end else if(dut.reader.out_offset!=1||dut.reader.out_data!==8'h49)
     $fatal(1,"reader advanced beyond the one queued header byte");
   end
   if(!sample_valid||sample_data!==expected[1]||samples!=1||error||!playing)
    $fatal(1,"old final sample not retained during prefetch");
   if(CASE==6)replay_new_file(3);
   else begin
    sample_ready=1;
    if(CASE>=2&&CASE<=4)begin
     wait(error);ticks(20);
     if(samples!=2||playing||sample_valid||dut.byte_pending||dut.reader.busy)
      $fatal(1,"bad next file leaked sample/header or did not stop count=%0d",samples);
     replay_new_file(4);
    end else begin
     wait(samples>=4);ticks(3);
     if(error||!playing||requests<2)$fatal(1,"valid loop did not recover after stalls");
    end
   end
  end
  $display("PASS WAV elastic case=%0d bits=%0d requests=%0d samples=%0d",CASE,WIDTH,requests,samples);$finish;
 end
 initial begin #5000000;$fatal(1,"elastic timeout case=%0d width=%0d state=%0d samples=%0d req=%0d pending=%b filedone=%b error=%b",CASE,WIDTH,dut.state,samples,requests,dut.byte_pending,dut.file_done_pending,error);end
endmodule
