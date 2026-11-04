`timescale 1ns/1ps

module tb_dir_bram;
 parameter integer MAX_FILES=4, FIND_WAV=1;
 localparam integer TIMEOUT=4000;
 reg clk=0;
 always #5 clk=~clk;
 reg rst_n=1,start=0;
 reg [31:0] root_lba=100,fat_lba=20,data_lba=100,root_cluster=2,cluster_count=1000;
 reg [7:0] sectors_per_cluster=1;
 reg rd_ready=1,rd_done=0,rd_error=0,rd_valid=0;
 reg [8:0] rd_addr=0;
 reg [7:0] rd_data=0;
 wire rd_start,found_valid,busy,done,error,wav_found;
 wire [31:0] rd_lba,found_first_cluster,found_size,wav_first_cluster,wav_size;
 wire [1:0] found_index;
 wire [2:0] found_count;
 fat32_dir_scan #(.MAX_FILES(MAX_FILES),.FIND_WAV(FIND_WAV),
  .TIMEOUT_CYCLES(TIMEOUT),.MAX_DIR_CLUSTERS(4)) dut (.wav_index(2'd0),.wav_count(),.folder_info(),.*);
`ifdef COMPARE_BASELINE
 wire b_rd_start,b_found_valid,b_busy,b_done,b_error,b_wav_found;
 wire [31:0] b_rd_lba,b_found_first_cluster,b_found_size,b_wav_first_cluster,b_wav_size;
 wire [1:0] b_found_index;
 wire [2:0] b_found_count;
 fat32_dir_scan_baseline #(.MAX_FILES(MAX_FILES),.FIND_WAV(FIND_WAV),
  .TIMEOUT_CYCLES(TIMEOUT),.MAX_DIR_CLUSTERS(4)) baseline (
  .clk(clk),.rst_n(rst_n),.start(start),.root_lba(root_lba),
  .fat_lba(fat_lba),.data_lba(data_lba),.root_cluster(root_cluster),
  .cluster_count(cluster_count),.sectors_per_cluster(sectors_per_cluster),
  .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.rd_valid(rd_valid),
  .rd_addr(rd_addr),.rd_data(rd_data),.rd_start(b_rd_start),.rd_lba(b_rd_lba),
  .found_valid(b_found_valid),.found_index(b_found_index),
  .found_first_cluster(b_found_first_cluster),.found_size(b_found_size),
  .busy(b_busy),.done(b_done),.error(b_error),.found_count(b_found_count),
  .wav_found(b_wav_found),.wav_first_cluster(b_wav_first_cluster),.wav_size(b_wav_size));
`endif

 reg [7:0] sector[0:511];
 reg [31:0] expected_clusters[0:3],expected_sizes[0:3],expected_lbas[0:15];
 integer checks=0,scenarios=0,events=0,requests=0,expected_events=0,expected_requests=0;
 integer consumed_requests=0,done_seen=0;
 reg active=0,allow_events=0;
 reg [31:0] expected_wav_cluster=0,expected_wav_size=0;
 reg expected_error=0;
 reg [8*80-1:0] case_name;
 always @(posedge clk) begin
  #1;
  checks=checks+1;
`ifdef COMPARE_BASELINE
  if ({rd_start,rd_lba,found_valid,found_index,found_first_cluster,found_size,
       busy,done,error,found_count,wav_found,wav_first_cluster,wav_size} !==
      {b_rd_start,b_rd_lba,b_found_valid,b_found_index,b_found_first_cluster,b_found_size,
       b_busy,b_done,b_error,b_found_count,b_wav_found,b_wav_first_cluster,b_wav_size})
   $fatal(1,"Public output cycle mismatch t=%0t case=%0s",$time,case_name);
`endif
  if(active && rst_n) begin
   if(rd_start) begin
    if(requests>=expected_requests || rd_lba!==expected_lbas[requests])
     $fatal(1,"Unexpected request #%0d LBA=%0d case=%0s",requests,rd_lba,case_name);
    requests=requests+1;
   end
   if(found_valid) begin
    if(!allow_events || events>=expected_events || found_index!==events[1:0] ||
       found_first_cluster!==expected_clusters[events] || found_size!==expected_sizes[events] ||
       found_count!==events+1)
     $fatal(1,"Bad/unchecked result #%0d index=%0d cluster=%0d size=%0d case=%0s",
            events,found_index,found_first_cluster,found_size,case_name);
    events=events+1;
   end
   if(done) done_seen=done_seen+1;
  end
 end

 task tick(input reg valid,input integer address,input reg [7:0] value,
           input reg completed,input reg failed);
  begin
   @(negedge clk);
   rd_valid=valid;rd_addr=address;rd_data=value;rd_done=completed;rd_error=failed;
   @(posedge clk);#2;
  end
 endtask
 task idle_tick;
  begin tick(0,0,0,0,0);end
 endtask
 task reset_scan(input reg [8*80-1:0] label_name);
  integer i;
  begin
   active=0;start=0;rd_ready=1;
   @(negedge clk);#2;rst_n=0;
   repeat(3) idle_tick;
   @(negedge clk);#2;rst_n=1;
   idle_tick;
   case_name=label_name;
   events=0;requests=0;consumed_requests=0;done_seen=0;
   expected_events=0;expected_requests=1;expected_lbas[0]=100;
   expected_wav_cluster=0;expected_wav_size=0;expected_error=0;
   sectors_per_cluster=1;root_lba=100;root_cluster=2;cluster_count=1000;
   allow_events=0;
   for(i=0;i<4;i=i+1) begin expected_clusters[i]=0;expected_sizes[i]=0;end
   active=1;
  end
 endtask
 task begin_scan;
  begin start=1;idle_tick;start=0;end
 endtask
 task wait_request;
  integer spins;
  begin
   spins=0;
   while(requests<=consumed_requests && spins<TIMEOUT+20) begin idle_tick;spins=spins+1;end
   if(requests<=consumed_requests) $fatal(1,"Missing sector request case=%0s",case_name);
   consumed_requests=consumed_requests+1;
   allow_events=0;
  end
 endtask
 task clear_sector(input reg fill_deleted);
  integer i;
  begin
   for(i=0;i<512;i=i+1) sector[i]=0;
   if(fill_deleted) for(i=0;i<16;i=i+1) sector[i*32]=8'he5;
  end
 endtask
 task entry(input integer slot,input reg [7:0] name0,input reg [23:0] extension,
            input reg [31:0] cluster,input reg [31:0] size,input reg [7:0] attr);
  integer p,j;
  begin
   p=slot*32;
   for(j=0;j<32;j=j+1) sector[p+j]=0;
   sector[p]=name0;
   for(j=1;j<8;j=j+1) sector[p+j]=8'h20;
   sector[p+8]=extension[23:16];sector[p+9]=extension[15:8];sector[p+10]=extension[7:0];
   sector[p+11]=attr;
   sector[p+20]=cluster[23:16];sector[p+21]=cluster[31:24];
   sector[p+26]=cluster[7:0];sector[p+27]=cluster[15:8];
   sector[p+28]=size[7:0];sector[p+29]=size[15:8];
   sector[p+30]=size[23:16];sector[p+31]=size[31:24];
  end
 endtask
 task expect_bmp(input reg [31:0] cluster,input reg [31:0] size);
  begin
   expected_clusters[expected_events]=cluster;expected_sizes[expected_events]=size;
   expected_events=expected_events+1;
  end
 endtask
 // Modes: normal, short, out-of-order, duplicate, CRC failure, extra byte.
 // The last rd_valid and rd_done can share a clock, as in the SD receiver.
 task send_sector(input integer mode,input reg final_done,input reg gaps);
  integer i,count,address;
  begin
   count=(mode==1)?511:512;
   for(i=0;i<count;i=i+1) begin
    address=(mode==2 && i==10)?11:i;
    tick(1,address,sector[i],final_done && i==count-1,mode==4);
    if(mode==3 && i==64) tick(1,64,sector[64],0,0);
    if(gaps && i%37==17 && i!=count-1) idle_tick;
   end
   if(mode==5) tick(1,0,8'h33,0,0);
   if(!final_done) tick(0,0,0,1,mode==4);
   // Only a valid, complete sector is allowed to produce directory events.
   allow_events=(mode==0);
   idle_tick;
  end
 endtask
 task finish_scan;
  integer spins;
  begin
   spins=0;
   while(done_seen==0 && spins<TIMEOUT+3000) begin idle_tick;spins=spins+1;end
   if(done_seen!=1 || busy || error!==expected_error || events!=expected_events ||
      found_count!==expected_events || requests!=expected_requests ||
      wav_found!==(expected_wav_cluster!=0))
    $fatal(1,"Final status mismatch case=%0s done=%0d busy=%b error=%b events=%0d/%0d requests=%0d/%0d wav=%b",
           case_name,done_seen,busy,error,events,expected_events,requests,expected_requests,wav_found);
   if(expected_wav_cluster!=0 &&
      (wav_first_cluster!==expected_wav_cluster || wav_size!==expected_wav_size))
    $fatal(1,"WAV result mismatch case=%0s",case_name);
   repeat(4) idle_tick;
   if(done_seen!=1 || busy || events!=expected_events)
    $fatal(1,"Completion is not a single pulse case=%0s",case_name);
   scenarios=scenarios+1;
   $display("PASS directory scenario %0d: %0s",scenarios,case_name);
   active=0;
  end
 endtask
 task put_fat(input reg [31:0] cluster,input reg [31:0] next_cluster);
  integer p;
  begin
   clear_sector(0);p=(cluster%128)*4;
   sector[p]=next_cluster[7:0];sector[p+1]=next_cluster[15:8];
   sector[p+2]=next_cluster[23:16];sector[p+3]=next_cluster[31:24];
  end
 endtask

 integer i,mode;
 initial begin
  #2;rst_n=0;
  reset_scan("parameterized BMP and WAV scan");
  clear_sector(0);entry(0,"A",24'h424d50,10,921654,0);expect_bmp(10,921654);
  entry(1,"S",24'h574156,22,15924848,0);
  if(FIND_WAV) begin expected_wav_cluster=22;expected_wav_size=15924848;end
  begin_scan;wait_request;send_sector(0,1,1);finish_scan;
  if(MAX_FILES==4 && FIND_WAV) begin
   reset_scan("four BMP files followed by WAV");clear_sector(0);
   for(i=0;i<4;i=i+1) begin entry(i,"A"+i,24'h424d50,10+i,921654+i,0);expect_bmp(10+i,921654+i);end
   entry(4,"S",24'h574156,22,15924848,0);expected_wav_cluster=22;expected_wav_size=15924848;
   begin_scan;wait_request;send_sector(0,0,1);finish_scan;

   reset_scan("first WAV retained and four BMP limit");clear_sector(0);
   entry(0,"S",24'h574156,22,15924848,0);entry(1,"T",24'h574156,23,777,0);
   for(i=0;i<4;i=i+1) begin entry(i+2,"A"+i,24'h424d50,10+i,800+i,0);expect_bmp(10+i,800+i);end
   expected_wav_cluster=22;expected_wav_size=15924848;
   begin_scan;wait_request;send_sector(0,1,0);finish_scan;

   reset_scan("deleted LFN volume directory range size and lowercase filtering");clear_sector(0);
   entry(0,8'he5,24'h424d50,10,123,0);entry(1,"A",24'h424d50,10,123,8'h0f);
   entry(2,"A",24'h424d50,10,123,8'h08);entry(3,"A",24'h424d50,10,123,8'h10);
   entry(4,"A",24'h424d50,1,123,0);entry(5,"A",24'h424d50,1002,123,0);
   entry(6,"A",24'h424d50,10,0,0);entry(7,"A",24'h545854,10,123,0);
   entry(8,"L",24'h626d70,99,32'h81234567,0);expect_bmp(99,32'h81234567);
   entry(9,"S",24'h776176,31,32'hfedcba98,0);expected_wav_cluster=31;expected_wav_size=32'hfedcba98;
   begin_scan;wait_request;send_sector(0,1,1);finish_scan;

   reset_scan("directory crosses sectors within one cluster");sectors_per_cluster=2;
   expected_requests=2;expected_lbas[1]=101;
   expect_bmp(12,111);expect_bmp(13,222);expected_wav_cluster=22;expected_wav_size=333;
   begin_scan;wait_request;clear_sector(1);entry(15,"A",24'h424d50,12,111,0);send_sector(0,1,1);
   wait_request;clear_sector(0);entry(0,"S",24'h574156,22,333,0);entry(1,"B",24'h424d50,13,222,0);
   send_sector(0,0,1);finish_scan;

   reset_scan("three directory clusters and two FAT sectors");
   expected_requests=5;expected_lbas[1]=20;expected_lbas[2]=228;expected_lbas[3]=21;expected_lbas[4]=229;
   for(i=0;i<4;i=i+1) expect_bmp(12+i,111+i);
   expected_wav_cluster=30;expected_wav_size=777;
   begin_scan;wait_request;clear_sector(1);entry(15,"A",24'h424d50,12,111,0);send_sector(0,1,1);
   wait_request;put_fat(2,130);send_sector(0,1,1);
   wait_request;clear_sector(1);entry(15,"B",24'h424d50,13,112,0);send_sector(0,0,1);
   wait_request;put_fat(130,131);send_sector(0,1,1);
   wait_request;clear_sector(0);entry(0,"S",24'h574156,30,777,0);
   entry(1,"C",24'h424d50,14,113,0);entry(2,"D",24'h424d50,15,114,0);send_sector(0,1,1);finish_scan;

   reset_scan("end-of-chain after a full directory sector");expected_requests=2;expected_lbas[1]=20;
   expect_bmp(12,111);begin_scan;wait_request;clear_sector(1);entry(15,"A",24'h424d50,12,111,0);
   send_sector(0,1,0);wait_request;put_fat(2,32'h0fffffff);send_sector(0,1,0);finish_scan;

   reset_scan("cyclic directory cluster chain hits hop bound");expected_error=1;expected_requests=8;
   expected_lbas[1]=20;expected_lbas[2]=228;expected_lbas[3]=21;
   expected_lbas[4]=100;expected_lbas[5]=20;expected_lbas[6]=228;expected_lbas[7]=21;
   begin_scan;
   for(i=0;i<4;i=i+1) begin
    wait_request;clear_sector(1);send_sector(0,1,0);
    wait_request;if(i%2==0) put_fat(2,130);else put_fat(130,2);
    send_sector(0,1,0);
   end
   finish_scan;

   reset_scan("CRC-failed FAT sector cannot advance directory cluster");expected_error=1;
   expected_requests=2;expected_lbas[1]=20;expect_bmp(12,111);
   begin_scan;wait_request;clear_sector(1);entry(15,"A",24'h424d50,12,111,0);send_sector(0,1,0);
   wait_request;put_fat(2,130);send_sector(4,1,0);finish_scan;

   for(mode=0;mode<4;mode=mode+1) begin
    reset_scan("invalid FAT next cluster");expected_requests=2;expected_lbas[1]=20;expected_error=1;
    begin_scan;wait_request;clear_sector(1);send_sector(0,1,0);wait_request;
    case(mode) 0:put_fat(2,1);1:put_fat(2,2);2:put_fat(2,32'h0ffffff0);3:put_fat(2,1002);endcase
    send_sector(0,1,0);finish_scan;
   end
   for(mode=1;mode<=5;mode=mode+1) begin
    reset_scan("bad directory sector must not be parsed");expected_error=1;
    clear_sector(0);entry(0,"A",24'h424d50,10,999,0);entry(1,"S",24'h574156,22,777,0);
    begin_scan;wait_request;send_sector(mode,mode==4,1);finish_scan;
   end
   reset_scan("empty short sector");expected_error=1;
   begin_scan;wait_request;tick(0,0,0,1,0);finish_scan;

   reset_scan("timeout during sector reception");expected_error=1;
   begin_scan;wait_request;clear_sector(0);entry(0,"A",24'h424d50,10,999,0);
   for(i=0;i<37;i=i+1) tick(1,i,sector[i],0,0);
   idle_tick;finish_scan;

   reset_scan("timeout while reader unavailable");expected_error=1;expected_requests=0;rd_ready=0;
   begin_scan;finish_scan;

   reset_scan("reset discards incomplete sector");
   begin_scan;wait_request;clear_sector(0);entry(0,"A",24'h424d50,10,999,0);
   for(i=0;i<256;i=i+1) tick(1,i,sector[i],0,0);
   reset_scan("clean scan after mid-sector reset");clear_sector(0);
   entry(0,"B",24'h424d50,44,12345,0);expect_bmp(44,12345);
   begin_scan;wait_request;send_sector(0,1,0);finish_scan;

   reset_scan("bad later sector cannot emit a second result");sectors_per_cluster=2;
   expected_requests=2;expected_lbas[1]=101;expected_error=1;expect_bmp(12,111);
   begin_scan;wait_request;clear_sector(1);entry(15,"A",24'h424d50,12,111,0);send_sector(0,1,0);
   wait_request;clear_sector(0);entry(0,"B",24'h424d50,13,222,0);send_sector(4,1,0);finish_scan;
  end
  $display("PASS dir_bram: MAX_FILES=%0d FIND_WAV=%0d scenarios=%0d cycle_checks=%0d",MAX_FILES,FIND_WAV,scenarios,checks);
  $finish;
 end
 initial begin #10000000;$fatal(1,"Global simulation deadline exceeded");end
endmodule
