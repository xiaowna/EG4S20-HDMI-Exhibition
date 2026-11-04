`timescale 1ns/1ps
// Real 512-byte transactions. Frozen output equivalence is supplemented by
// independent LBA, directory-event and final-metadata expectations.
module tb_bpb_share;
 parameter integer LIMIT=2048,FOUR=0;
 reg clk=0,rst_n=0,start=0,rd_ready=1,rd_done=0,rd_error=0,rd_valid=0;
 reg [8:0] rd_addr=0;reg [7:0] rd_data=0;
 wire rd_start,busy,done,error,found_valid,wav_found;
 wire [31:0] rd_lba,found_first_cluster,found_size,volume_fat_lba,volume_data_lba;
 wire [31:0] volume_cluster_count,volume_root_lba,volume_root_cluster,wav_first_cluster,wav_size;
 wire [1:0] found_index;wire [2:0] found_count;wire [7:0] volume_sectors_per_cluster;
 wire old_rd_start,old_busy,old_done,old_error,old_found_valid,old_wav_found;
 wire [31:0] old_rd_lba,old_found_first_cluster,old_found_size,old_volume_fat_lba,old_volume_data_lba;
 wire [31:0] old_volume_cluster_count,old_volume_root_lba,old_volume_root_cluster,old_wav_first_cluster,old_wav_size;
 wire [1:0] old_found_index;wire [2:0] old_found_count;wire [7:0] old_volume_sectors_per_cluster;
 wire [338:0] outputs={rd_start,rd_lba,busy,done,error,found_valid,found_index,
  found_first_cluster,found_size,found_count,volume_fat_lba,volume_data_lba,
  volume_cluster_count,volume_root_lba,volume_root_cluster,volume_sectors_per_cluster,
  wav_found,wav_first_cluster,wav_size};
 wire [338:0] old_outputs={old_rd_start,old_rd_lba,old_busy,old_done,old_error,old_found_valid,old_found_index,
  old_found_first_cluster,old_found_size,old_found_count,old_volume_fat_lba,old_volume_data_lba,
  old_volume_cluster_count,old_volume_root_lba,old_volume_root_cluster,old_volume_sectors_per_cluster,
  old_wav_found,old_wav_first_cluster,old_wav_size};
 fat32_card_catalog #(.TIMEOUT_CYCLES(LIMIT),.FIND_WAV(1)) dut(.wav_index(2'd0),.wav_count(),.folder_info(),.*);
 fat32_card_catalog_baseline #(.TIMEOUT_CYCLES(LIMIT),.FIND_WAV(1)) baseline(
  .clk(clk),.rst_n(rst_n),.start(start),.rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),
  .rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),.rd_start(old_rd_start),.rd_lba(old_rd_lba),
  .busy(old_busy),.done(old_done),.error(old_error),.found_valid(old_found_valid),.found_index(old_found_index),
  .found_first_cluster(old_found_first_cluster),.found_size(old_found_size),.found_count(old_found_count),
  .volume_fat_lba(old_volume_fat_lba),.volume_data_lba(old_volume_data_lba),.volume_cluster_count(old_volume_cluster_count),
  .volume_root_lba(old_volume_root_lba),.volume_root_cluster(old_volume_root_cluster),
  .volume_sectors_per_cluster(old_volume_sectors_per_cluster),.wav_found(old_wav_found),
  .wav_first_cluster(old_wav_first_cluster),.wav_size(old_wav_size));
 always #5 clk=~clk;
 reg [7:0] mem[0:1535];reg [31:0] requests_expected[0:15];
 reg [31:0] part=0,total=141232,fatlen=600,rootcl=3,spc=2;reg active_fat=0;
 reg active=0,done_seen=0;string label_text="initial";
 integer cycles=0,checks=0,successes=0,failures=0,request_count=0,event_count=0;
 integer completed_requests=0,planned_requests=0,reset_aborts=0,crc_paths=0,short_paths=0;
 integer order_paths=0,extra_paths=0,timeout_paths=0,rescans=0,stalls=0,busy_starts=0;
 integer orphan_probe=0,orphan_boot=0,provisional=0,accelerations=0;
 integer expect_events=0,expect_error=0,expect_meta=0,which=0,n=0;
 reg [338:0] held_outputs;

 task fail(input string text);
  begin $display("FAIL BPB share LIMIT=%0d FOUR=%0d case=%s cycle=%0d requests=%0d/%0d: %s",LIMIT,FOUR,label_text,cycles,request_count,planned_requests,text);$fatal(1);end
 endtask
 always @(posedge clk)begin
  #1;cycles=cycles+1;
  if(outputs!==old_outputs)begin
   $display("candidate=%085h baseline=%085h",outputs,old_outputs);fail("all public outputs differ");
  end
  if((^outputs)===1'bx)fail("unknown public output");
  if(rst_n&&active)begin
   if(rd_start)begin
    if(request_count>=planned_requests||rd_lba!==requests_expected[request_count])
     fail($sformatf("independent LBA expected %0d got %0d",requests_expected[request_count],rd_lba));
    request_count=request_count+1;
   end
   if(found_valid)begin
    if(event_count>=expect_events||found_index!==event_count[1:0]||
       found_first_cluster!==32'(10+event_count)||found_size!==32'(1024+event_count))
     fail("independent provisional BMP event");
    event_count=event_count+1;provisional=provisional+1;
   end
   if(done)begin
    if(done_seen)fail("repeated done");done_seen=1;
    if(error!==expect_error[0]||busy!==0||request_count!=planned_requests||event_count!=expect_events)
     fail("independent terminal status/request/event count");
    if(expect_meta)begin
     if(found_count!=(FOUR?4:1)||!wav_found||wav_first_cluster!=25||wav_size!=52||
        volume_fat_lba!=(part+32+(active_fat?fatlen:0))||volume_data_lba!=(part+32+2*fatlen)||
        volume_root_lba!=(part+32+2*fatlen+(rootcl-2)*spc)||volume_root_cluster!=rootcl||
        volume_cluster_count!=70000||volume_sectors_per_cluster!=spc)
      fail("independent successful volume/WAV metadata");
    end
   end
  end
 end
 task tick;begin @(negedge clk);#2;end endtask
 task quiet;begin start=0;rd_valid=0;rd_done=0;rd_error=0;rd_addr=0;rd_data=0;end endtask
 task reset_device;
  begin active=0;quiet();rst_n=0;rd_ready=1;repeat(3)tick();rst_n=1;repeat(3)tick();end
 endtask
 task put16(input integer a,input reg[15:0]v);begin mem[a]=v[7:0];mem[a+1]=v[15:8];end endtask
 task put32(input integer a,input reg[31:0]v);begin mem[a]=v[7:0];mem[a+1]=v[15:8];mem[a+2]=v[23:16];mem[a+3]=v[31:24];end endtask
 task partition(input integer slot,input reg[7:0]status,kind,input reg[31:0]first,length);
  integer p;begin p=446+16*slot;mem[p]=status;mem[p+4]=kind;put32(p+8,first);put32(p+12,length);end
 endtask
 task image(input integer a,input reg[7:0]first,input reg[31:0]cluster,size,input reg[23:0]extension);
  integer j;begin for(j=0;j<32;j=j+1)mem[a+j]=0;mem[a]=first;mem[a+8]=extension[23:16];mem[a+9]=extension[15:8];mem[a+10]=extension[7:0];
   mem[a+11]=8'h20;put16(a+20,cluster[31:16]);put16(a+26,cluster[15:0]);put32(a+28,size);end
 endtask
 task fixture(input integer superfloppy,input reg[31:0]partition_start,input integer alternate);
  integer j;begin
   for(j=0;j<1536;j=j+1)mem[j]=0;
   part=partition_start;spc=alternate?4:2;fatlen=alternate?700:600;rootcl=alternate?4:3;active_fat=alternate;
   total=32+2*fatlen+70000*spc;
   mem[510]=8'h55;mem[511]=8'haa;partition(0,0,8'h0c,part,total);
   put16(512+11,512);mem[512+13]=spc;put16(512+14,32);mem[512+16]=2;
   put32(512+32,total);put32(512+36,fatlen);put32(512+44,rootcl);put16(512+40,alternate?16'h0081:16'h0000);
   mem[512+510]=8'h55;mem[512+511]=8'haa;
   if(superfloppy)begin part=0;for(j=0;j<512;j=j+1)mem[j]=mem[512+j];end
   for(j=0;j<(FOUR?4:1);j=j+1)image(1024+j*32,8'h41+j,10+j,1024+j,24'h424d50);
   image(1024+(FOUR?4:1)*32,8'h57,25,52,24'h574156);
  end
 endtask
 task begin_case(input string name,input integer reqs,err,events,metadata);
  begin label_text=name;request_count=0;completed_requests=0;event_count=0;planned_requests=reqs;
   expect_error=err;expect_events=events;expect_meta=metadata;done_seen=0;active=1;checks=checks+1;
   requests_expected[0]=0;requests_expected[1]=part;requests_expected[2]=part+32+2*fatlen+(rootcl-2)*spc;
   quiet();start=1;tick();start=0;if(!busy)fail("start ignored while idle");
  end
 endtask
 task await_request;
  integer guard;begin guard=0;while(!rd_start&&!done&&guard<1000)begin tick();guard=guard+1;end
   if(!rd_start||done||request_count!=completed_requests+1)fail("expected request not reached");
   rd_ready=0;completed_requests=completed_requests+1;repeat(2)tick();
  end
 endtask
 // mode: 0 normal,1 CRC,2 short,3 order,4 extra,5 done with byte511,
 // 6 ready stalls/input gaps/busy start,7 early transport error.
 task sector(input integer bank,mode);
  integer k,limitbytes;begin
   await_request();limitbytes=(mode==2||mode==7)?128:512;
   for(k=0;k<limitbytes;k=k+1)begin
    rd_addr=(mode==3&&k==10)?11:k;rd_data=mem[bank*512+k];rd_valid=1;
    if(mode==6&&k==20)begin start=1;busy_starts=busy_starts+1;end
    if(mode==5&&k==511)rd_done=1;
    tick();rd_valid=0;start=0;rd_done=0;
    if(mode==6&&k%23==0)repeat(2)tick();
   end
   if(mode==4)begin rd_addr=0;rd_data=0;rd_valid=1;tick();rd_valid=0;end
   if(mode!=5)begin repeat(2)tick();rd_done=1;rd_error=(mode==1||mode==7);tick();rd_done=0;rd_error=0;end
   rd_ready=1;
   if(mode==1||mode==7)crc_paths=crc_paths+1;
   if(mode==2)short_paths=short_paths+1;
   if(mode==3)order_paths=order_paths+1;
   if(mode==4)extra_paths=extra_paths+1;
  end
 endtask
 task finish_case;
  integer guard;begin
   guard=0;while(!done_seen&&guard<(LIMIT>8192?12000:LIMIT*4+100))begin tick();guard=guard+1;end
   if(!done_seen)fail("no terminal result");if(expect_error)failures=failures+1;else successes=successes+1;
   active=0;tick();held_outputs=outputs;repeat(5)begin tick();if(outputs!==held_outputs)fail("idle public outputs changed");end
  end
 endtask
 task good_scan(input string name,input integer mode);
  begin begin_case(name,3,0,FOUR?4:1,1);sector(0,mode);sector(1,mode);sector(2,mode);finish_case();end
 endtask
 // Natural endpoint tests run at 2048 and8192. At the real default only,
 // deposit elapsed counters into both systems, leaving all datapaths untouched.
 task accelerate(input integer target);
  begin if(LIMIT>8192)begin
   accelerations=accelerations+1;
   if(target==0)begin dut.u_locator.timer=LIMIT-2;baseline.u_locator.timer=LIMIT-2;end
   if(target==1)begin dut.u_catalog.timer=LIMIT-2;baseline.u_catalog.timer=LIMIT-2;end
   if(target==2)begin dut.u_catalog.u_directory.timer=LIMIT-2;baseline.u_catalog.u_directory.timer=LIMIT-2;end
  end end
 endtask
 initial begin
  reset_device();fixture(1,0,0);good_scan("SF initial",0);
  fixture(0,2048,1);rescans=rescans+1;good_scan("SF to MBR changed geometry no reset",0);
  fixture(1,0,0);rescans=rescans+1;good_scan("MBR to SF no reset",5);
  reset_device();fixture(1,0,0);partition(2,0,8'hee,1,99);good_scan("valid SF overrides protective entry",0);
  reset_device();fixture(0,2048,0);partition(0,0,8'h0b,2048,total);partition(1,8'h80,8'h0c,4096,total);good_scan("first FAT32 table entry beats active",0);
  reset_device();fixture(0,4096,0);partition(0,1,8'h0c,2048,total);partition(1,0,8'h0b,4096,total);good_scan("skip invalid status then 0B",0);
  reset_device();fixture(0,4096,0);partition(0,0,8'h0c,32'hfffffff0,32'h30);partition(1,0,8'h0c,4096,total);good_scan("skip overflowing entry",0);
  reset_device();fixture(0,32'hfffdd850,0);part=64'h100000000-total;partition(0,0,8'h0c,part,total);good_scan("partition endpoint exactly 2^32",0);
  reset_device();fixture(0,2048,0);partition(3,0,8'hee,1,99);begin_case("protective MBR refusal",1,1,0,0);sector(0,0);finish_case();
  reset_device();fixture(0,2048,0);partition(0,0,8'h0c,2048,total-1);begin_case("BPB exceeds partition length",2,1,0,0);sector(0,0);sector(1,0);finish_case();
  reset_device();fixture(0,2048,0);partition(1,0,8'h0c,4096,total);mem[512+12]=1;
  begin_case("chosen BPB invalid does not try next",2,1,0,0);sector(0,0);sector(1,0);finish_case();
  reset_device();fixture(0,2048,0);put32(512+36,1);
  begin_case("FAT capacity smaller than cluster range",2,1,0,0);sector(0,0);sector(1,0);finish_case();
  reset_device();fixture(0,2048,0);put32(512+44,70002);
  begin_case("root cluster outside volume",2,1,0,0);sector(0,0);sector(1,0);finish_case();
  for(which=0;which<3;which=which+1)begin
   reset_device();fixture(0,2048,0);begin_case($sformatf("CRC full sector phase %0d",which),which+1,1,0,0);
   for(n=0;n<=which;n=n+1)sector(n,n==which?1:0);finish_case();
  end
  for(n=2;n<=4;n=n+1)begin
   reset_device();fixture(0,2048,0);begin_case($sformatf("directory transport mode %0d",n),3,1,0,0);
   sector(0,0);sector(1,0);sector(2,n);finish_case();
  end
  // Each malformed transport is reached at both independent boot parsers.
  for(which=0;which<2;which=which+1)begin
   for(n=2;n<=4;n=n+1)begin
    reset_device();fixture(0,2048,0);
    // The legacy formal parser completes at byte511 and ignores a later extra
    // byte; unlike locator's independent count, catalog has no extra-byte gate.
    // Cover this existing behavior honestly rather than claim extra rejection.
    if(which==1&&n==4)begin_case("formal parser ignores extra byte after completion",3,0,FOUR?4:1,1);
    else begin_case($sformatf("malformed phase %0d mode %0d",which,n),which+1,1,0,0);
    if(which==1)sector(0,0);sector(which,n);if(which==1&&n==4)sector(2,0);finish_case();
    if(n==2)begin
     if(which==0)begin if(!dut.u_locator.u_probe.busy)fail("short probe did not leave parser busy");orphan_probe=orphan_probe+1;end
     else begin if(!dut.u_catalog.u_boot.busy)fail("short formal boot did not leave parser busy");orphan_boot=orphan_boot+1;end
    end
    // Actual no-reset recovery: short formal BPB still busy rejects a fresh
    // boot start; the following ordered sector makes it fail and releases it.
    if(which==1&&n==2)begin
     rescans=rescans+1;begin_case("short formal boot immediate no reset",2,1,0,0);sector(0,0);sector(1,0);finish_case();
     rescans=rescans+1;good_scan("short formal boot second no-reset recovers",0);
    end else begin rescans=rescans+1;good_scan("malformed no-reset recovery",0);end
   end
  end
  reset_device();fixture(0,2048,0);begin_case("probe early CRC no reset",1,1,0,0);sector(0,7);finish_case();
  if(!dut.u_locator.u_probe.busy)fail("early probe CRC did not leave busy");orphan_probe=orphan_probe+1;
  rescans=rescans+1;good_scan("early probe CRC no-reset recovery",0);
  reset_device();fixture(0,2048,0);begin_case("formal early CRC no reset",2,1,0,0);sector(0,0);sector(1,7);finish_case();
  if(!dut.u_catalog.u_boot.busy)fail("early formal CRC did not leave busy");orphan_boot=orphan_boot+1;
  rescans=rescans+1;begin_case("early formal CRC immediate no reset",2,1,0,0);sector(0,0);sector(1,0);finish_case();
  rescans=rescans+1;good_scan("early formal CRC second no-reset recovers",0);
  reset_device();fixture(0,2048,0);rd_ready=0;begin_case("ready stall and busy starts",3,0,FOUR?4:1,1);
  repeat(23)begin tick();if(rd_start)fail("request while not ready");end stalls=stalls+1;rd_ready=1;
  sector(0,6);sector(1,6);sector(2,6);finish_case();
  // Timeouts reach locator, formal boot and directory independently.
  reset_device();fixture(0,2048,0);rd_ready=0;begin_case("locator request timeout",0,1,0,0);repeat(8)tick();accelerate(0);timeout_paths=timeout_paths+1;finish_case();
  reset_device();fixture(0,2048,0);begin_case("formal boot transfer timeout",2,1,0,0);sector(0,0);await_request();repeat(8)tick();accelerate(1);timeout_paths=timeout_paths+1;finish_case();
  reset_device();fixture(0,2048,0);begin_case("directory receive timeout",3,1,0,0);sector(0,0);sector(1,0);await_request();repeat(8)tick();accelerate(2);timeout_paths=timeout_paths+1;finish_case();
  // Reset separately interrupts both parser personalities and root transfer.
  for(which=0;which<3;which=which+1)begin
   reset_device();fixture(0,2048,0);begin_case("reset transfer",which+1,1,0,0);
   for(n=0;n<which;n=n+1)sector(n,0);await_request();rd_valid=1;rd_addr=0;rd_data=mem[which*512];tick();
   reset_device();reset_aborts=reset_aborts+1;fixture(0,2048,0);good_scan("post reset recovery",0);
  end
  if(successes<18||failures<23||crc_paths!=5||short_paths!=3||order_paths!=3||extra_paths!=3||
     timeout_paths!=3||orphan_probe!=2||orphan_boot!=2||reset_aborts!=3||busy_starts!=3||stalls!=1)
   fail("coverage branch counters missing");
  $display("PASS BPB share LIMIT=%0d FOUR=%0d cycles=%0d checks=%0d successes=%0d failures=%0d crc_paths=%0d short_paths=%0d order_paths=%0d extra_paths=%0d timeout_paths=%0d orphan_probe=%0d orphan_boot=%0d rescans=%0d provisional=%0d reset_aborts=%0d busy_starts=%0d stalls=%0d accelerations=%0d; all public outputs match frozen card catalog",LIMIT,FOUR,cycles,checks,successes,failures,crc_paths,short_paths,order_paths,extra_paths,timeout_paths,orphan_probe,orphan_boot,rescans,provisional,reset_aborts,busy_starts,stalls,accelerations);$finish;
 end
 initial begin #100000000;$fatal(1,"BPB share bench watchdog");end
endmodule
