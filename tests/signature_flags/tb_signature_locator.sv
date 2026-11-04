`timescale 1ns/1ps
// Independent sector-content oracle, transport fault injection, and a complete
// public-output comparison. No hierarchical state or candidate storage is read.
module tb_signature_locator;
 parameter integer SHARED=0;
 parameter integer TIMEOUT_CYCLES=800;
 wire [255:0] bpb_fields,old_bpb_fields;
 wire [128:0] bpb_result,old_bpb_result;
 fat32_bpb_math math_new(.clk(clk),.bpb_fields(bpb_fields),.bpb_result(bpb_result));
 fat32_bpb_math_baseline math_old(.clk(clk),.bpb_fields(old_bpb_fields),.bpb_result(old_bpb_result));
 reg clk=0,rst_n=0,start=0,rd_ready=1,rd_done=0,rd_error=0,rd_valid=0;
 reg [8:0] rd_addr=0;
 reg [7:0] rd_data=0;
 wire rd_start,busy,done,error,valid;
 wire [31:0] rd_lba,partition_lba,partition_sectors;
 wire [100:0] public_outputs={rd_start,rd_lba,busy,done,error,valid,partition_lba,partition_sectors};
 fat32_volume_locator #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.SHARED_BPB(SHARED)) dut(.*);
`ifdef COMPARE_BASELINE
 wire old_rd_start,old_busy,old_done,old_error,old_valid;
 wire [31:0] old_rd_lba,old_partition_lba,old_partition_sectors;
 wire [100:0] old_outputs={old_rd_start,old_rd_lba,old_busy,old_done,old_error,
                         old_valid,old_partition_lba,old_partition_sectors};
 fat32_volume_locator_baseline #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.SHARED_BPB(SHARED)) baseline(
  .bpb_fields(old_bpb_fields),.bpb_result(old_bpb_result),
  .clk(clk),.rst_n(rst_n),.start(start),.rd_ready(rd_ready),.rd_done(rd_done),
  .rd_error(rd_error),.rd_valid(rd_valid),.rd_addr(rd_addr),.rd_data(rd_data),
  .rd_start(old_rd_start),.rd_lba(old_rd_lba),.busy(old_busy),.done(old_done),
  .error(old_error),.valid(old_valid),.partition_lba(old_partition_lba),
  .partition_sectors(old_partition_sectors));
`endif
 always #5 clk=~clk;
 reg [7:0] sector[0:511];
 integer cycles=0,scenarios=0,completed=0,resets=0,requests=0,age=0;
 integer oracle_successes=0,oracle_failures=0;
 reg transaction=0,expected_success=0,old_done_seen=0;
 reg held_valid=0,held_error=0;
 reg [31:0] expected_lba=0,expected_size=0,held_lba=0,held_size=0;
 string case_name="initial reset";

 task fail(input string message);
  begin $display("FAIL timeout=%0d case=%s cycle=%0d: %s",TIMEOUT_CYCLES,case_name,cycles,message);
   $fatal(1); end
 endtask

 always @(posedge clk) begin
  #1;
  cycles=cycles+1;
`ifdef COMPARE_BASELINE
  if(bpb_fields!==old_bpb_fields)fail("all 256 bpb_fields bits differ from frozen RTL");
  if(public_outputs!==old_outputs) begin
   $display("candidate=%026h baseline=%026h",public_outputs,old_outputs);
   fail("all-public-output cycle equivalence");
  end
`endif
  if((^public_outputs)===1'bx) fail("unknown public output");
  if(rd_lba!==32'd0) fail("locator must request LBA zero");
  if(!rst_n) begin
   if(public_outputs!==101'd0) fail("reset output value");
   old_done_seen=0;
  end else begin
   if(done && old_done_seen) fail("done is not a one-clock pulse");
   old_done_seen=done;
   if(transaction) begin
    age=age+1;
    if(rd_start) begin
     requests=requests+1;
     if(requests!=1) fail("repeated sector request");
    end
    if(done) begin
     if(busy!==0 || valid!==expected_success || error!==!expected_success ||
        partition_lba!==expected_lba || partition_sectors!==expected_size)
      fail($sformatf("oracle completion: got valid/error=%b/%b metadata=%08h/%08h expected=%b/%08h/%08h",
            valid,error,partition_lba,partition_sectors,expected_success,expected_lba,expected_size));
     transaction=0;completed=completed+1;
     held_valid=expected_success;held_error=!expected_success;
     held_lba=expected_lba;held_size=expected_size;
    end else if(busy!==1 || valid!==0 || error!==0 ||
                partition_lba!==0 || partition_sectors!==0)
     fail("startup/in-flight metadata and status");
   end else if(busy!==0 || valid!==held_valid || error!==held_error ||
               partition_lba!==held_lba || partition_sectors!==held_size || rd_start!==0)
    fail("idle status/metadata retention");
  end
 end

 task tick;
  begin @(negedge clk);@(posedge clk);#2;end
 endtask
 task quiet;
  begin start=0;rd_valid=0;rd_done=0;rd_error=0;rd_addr=0;rd_data=0;end
 endtask
 task reset_device(input string label_text);
  begin
   case_name=label_text;transaction=0;held_valid=0;held_error=0;held_lba=0;held_size=0;
   quiet();rd_ready=1;rst_n=0;resets=resets+1;tick();tick();rst_n=1;tick();
  end
 endtask
 task clear_sector;
  integer n;
  begin for(n=0;n<512;n=n+1) sector[n]=0;sector[510]=8'h55;sector[511]=8'haa;end
 endtask
 task put16(input integer address,input reg [15:0] value);
  begin sector[address]=value[7:0];sector[address+1]=value[15:8];end
 endtask
 task put32(input integer address,input reg [31:0] value);
  begin sector[address]=value[7:0];sector[address+1]=value[15:8];
   sector[address+2]=value[23:16];sector[address+3]=value[31:24];end
 endtask
 function [15:0] get16(input integer address);
  get16={sector[address+1],sector[address]};
 endfunction
 function [31:0] get32(input integer address);
  get32={sector[address+3],sector[address+2],sector[address+1],sector[address]};
 endfunction
 task partition(input integer index,input reg [7:0] status_byte,kind_byte,
                input reg [31:0] first_lba,sector_count);
  integer p;
  begin p=446+16*index;sector[p]=status_byte;sector[p+4]=kind_byte;
   put32(p+8,first_lba);put32(p+12,sector_count);end
 endtask
 task make_mbr;
  begin clear_sector();partition(0,0,8'h0c,2048,100000);end
 endtask
 task make_bpb(input reg [31:0] cluster_total,input reg [7:0] spc_value);
  reg [63:0] fat_length,total_length;
  begin
   clear_sector();fat_length=({32'b0,cluster_total}+129)/128;
   total_length=32+2*fat_length+{32'b0,cluster_total}*spc_value;
   put16(11,512);sector[13]=spc_value;put16(14,32);sector[16]=2;
   put32(32,total_length[31:0]);put32(36,fat_length[31:0]);put32(44,2);
  end
 endtask

 // Parse the entire input sector with software-style unsigned arithmetic.
 // This is intentionally independent of RTL pipeline/candidate machinery.
 task classify_sector;
  reg [63:0] overhead,clusters,root_start,total,fat_length,first_lba,length_lba;
  reg [31:0] root_number;
  reg [15:0] flags;
  integer shift,n,p;
  reg bpb_ok,protective,chosen;
  begin
   expected_success=0;expected_lba=0;expected_size=0;
   shift=0;for(n=0;n<8;n=n+1) if(sector[13][n]) shift=n;
   total={32'b0,get32(32)};fat_length={32'b0,get32(36)};
   overhead=get16(14)+fat_length*((sector[16]==2)?2:1);
   clusters=(total-overhead)>>shift;root_number=get32(44);flags=get16(40);
   root_start=overhead+(({32'b0,root_number}-2)<<shift);
   bpb_ok=(get16(11)==512 && sector[13]!=0 &&
          (sector[13]&(sector[13]-1))==0 && get16(14)!=0 &&
          (sector[16]==1 || sector[16]==2) && fat_length!=0 && get16(42)==0 &&
          get16(17)==0 && get16(19)==0 && get16(22)==0 && total>overhead &&
          clusters>=65525 && clusters<64'h0ffffff5 && root_number>=2 &&
          {32'b0,root_number}<clusters+2 && (fat_length<<7)>=clusters+2 &&
          (!flags[7] || flags[3:0]<sector[16]) &&
          total<=64'h100000000 && root_start<64'h100000000);
   protective=0;chosen=0;
   for(n=0;n<4;n=n+1) begin
    p=446+16*n;first_lba={32'b0,get32(p+8)};length_lba={32'b0,get32(p+12)};
    if(sector[p+4]==8'hee) protective=1;
    if(!chosen && (sector[p+4]==8'h0b || sector[p+4]==8'h0c) &&
       (sector[p]==0 || sector[p]==8'h80) && first_lba!=0 && length_lba!=0 &&
       first_lba+length_lba<=64'h100000000) begin
     chosen=1;expected_lba=first_lba[31:0];expected_size=length_lba[31:0];
    end
   end
   if(sector[510]==8'h55 && sector[511]==8'haa) begin
    if(bpb_ok) begin expected_success=1;expected_lba=0;expected_size=total[31:0];end
    else if(chosen && !protective) expected_success=1;
   end
   if(!expected_success) begin expected_lba=0;expected_size=0;end
  end
 endtask

 task begin_transaction(input string label_text,input integer force_error,input integer ready_now);
  begin
   case_name=label_text;classify_sector();
   if(force_error) begin expected_success=0;expected_lba=0;expected_size=0;end
   if(expected_success) oracle_successes=oracle_successes+1;else oracle_failures=oracle_failures+1;
   scenarios=scenarios+1;requests=0;age=0;transaction=1;
   quiet();rd_ready=ready_now;start=1;tick();start=0;
  end
 endtask
 task await_request;
  integer guard;
  begin
   guard=0;
   while(!rd_start && transaction && guard<10) begin tick();guard=guard+1;end
   if(!rd_start || !transaction) fail("no request after ready");
   // After a truncated previous transfer the probe may still be busy until
   // its own timeout, so the existing public launch latency is three clocks
   // rather than four. Exact old/new latency is checked by public equivalence.
   if(age<3 || age>4) fail("request launch latency outside existing semantics");
  end
 endtask
 task await_completion;
  integer guard;
  begin
   quiet();guard=0;
   while(transaction && guard<TIMEOUT_CYCLES+8) begin tick();guard=guard+1;end
   if(transaction) fail("completion missing");
   quiet();tick();tick();
  end
 endtask
 task send_byte(input integer address,input integer busy_start);
  begin rd_valid=1;rd_addr=address;rd_data=sector[address];start=busy_start;tick();start=0;end
 endtask

 // mode: 0 simultaneous done; 1 delayed done; 2/3 CRC errors; 4 short;
 // 5 extra; 6 duplicate; 7 swapped addresses; 8 empty; 9 receive timeout;
 // 10 unqualified rd_error; 11 done/error in REQUEST; 12 start in every busy stage.
 task run_sector(input string label_text,input integer mode,input integer bubbles);
  integer n,limit,delay_count;
  begin
   begin_transaction(label_text,(mode>=2 && mode<=9),1);
   if(mode==11) begin rd_done=1;rd_error=1;tick();tick();quiet();end
   if(mode==12) start=1;
   await_request();
   limit=512;if(mode==4) limit=511;if(mode==8) limit=0;if(mode==9) limit=37;
   for(n=0;n<limit;n=n+1) begin
    if(bubbles && ((n*13+scenarios*7)%11==0)) begin quiet();tick();end
    if(mode==7 && n==100) send_byte(101,0);
    else if(mode==7 && n==101) send_byte(100,0);
    else begin
     rd_done=(n==limit-1 && (mode==0 || mode==2 || mode==4 || mode>=10));
     rd_error=(mode==2 || (mode==10 && n==37));
     send_byte(n,(mode==12 || n==8 || n==73 || n==400));
    end
    if(mode==6 && n==100) begin rd_done=0;send_byte(100,1);end
   end
   if(mode==5) begin rd_done=1;rd_error=0;send_byte(511,0);end
   else if(mode==1 || mode==3 || mode==6 || mode==7 || mode==8) begin
    quiet();for(delay_count=0;delay_count<3;delay_count=delay_count+1) tick();
    rd_done=1;rd_error=(mode==3);tick();
   end
   if(mode==12) begin quiet();start=1;tick();start=0;end
   await_completion();
  end
 endtask

 integer i,j,n;
 initial begin
  reset_device("initial reset");
  // Both superfloppy and MBR: every possible byte at each signature position.
  for(i=0;i<2;i=i+1)for(j=0;j<2;j=j+1)for(n=0;n<256;n=n+1)begin
   if(i==0)make_mbr();else make_bpb(70000,8);
   sector[510+j]=n;
   run_sector($sformatf("signature format=%0d byte=%0d value=%0d",i,j,n),n%2,n%3==0);
  end
  // Every table position, both accepted kinds, both accepted statuses.
  for(i=0;i<4;i=i+1) begin
   clear_sector();partition(i,(i%2)?8'h80:0,(i%2)?8'h0b:8'h0c,2048+100*i,100000+i);
   run_sector($sformatf("only valid partition at %0d",i),i%2,1);
  end
  clear_sector();partition(1,0,8'h0b,1234,56789);
  run_sector("type 0B with inactive status",0,1);
  clear_sector();partition(2,8'h80,8'h0c,5678,12345);
  run_sector("type 0C with active status",0,1);
  clear_sector();
  for(i=0;i<4;i=i+1) partition(i,(i==0)?0:8'h80,8'h0c,2048+100*i,100000+i);
  run_sector("first structural partition wins over later active",0,1);
  // Independent invalid-entry reasons must allow a later valid candidate.
  for(i=0;i<7;i=i+1) begin
   clear_sector();partition(0,0,8'h0c,2048,100000);partition(1,8'h80,8'h0b,4096,123456);
   case(i)
    0:sector[446]=1;
    1:sector[450]=8'h83;
    2:put32(454,0);
    3:put32(458,0);
    4:begin put32(454,32'hffffff00);put32(458,257);end
    5:sector[450]=8'h05;
    6:sector[450]=8'h1c;
   endcase
   run_sector($sformatf("invalid earlier partition reason %0d",i),0,1);
  end
  clear_sector();run_sector("empty partition table",0,0);
  clear_sector();partition(3,0,8'h0c,32'h100,32'hffffff00);
  run_sector("partition endpoint exactly 2^32",0,1);
  put32(506,32'hffffff01);run_sector("partition endpoint 2^32 plus one",0,1);
  clear_sector();partition(0,0,8'h0c,32'hf0000000,32'h10000000);
  run_sector("length high byte at legal endpoint",1,1);
  put32(458,32'h11000000);run_sector("length high byte makes overflow",0,1);
  clear_sector();
  for(i=0;i<3;i=i+1) partition(i,0,8'h0c,32'hffffffff,32'hffffffff);
  partition(3,0,8'h0b,9999,88888);
  run_sector("three maximum overflowing entries then valid",0,1);
  // An EE type vetoes an MBR regardless of status/start/length validity.
  for(i=0;i<4;i=i+1) begin
   clear_sector();partition((i+1)%4,0,8'h0c,2048,100000);
   partition(i,8'h7f,8'hee,0,0);
   run_sector($sformatf("protective GPT veto at %0d",i),0,1);
  end
  // All legal cluster powers and FAT32 cluster-count boundaries.
  for(i=0;i<8;i=i+1) begin
   make_bpb(65525,1<<i);run_sector($sformatf("superfloppy SPC %0d",1<<i),i%2,1);
  end
  make_bpb(65524,1);run_sector("BPB below FAT32 cluster minimum",0,1);
  make_bpb(65526,1);run_sector("BPB above FAT32 minimum",0,1);
  make_bpb(32'h0ffffff4,1);run_sector("BPB largest accepted cluster count",0,1);
  make_bpb(32'h0ffffff5,1);run_sector("BPB first rejected large cluster count",0,1);
  // Valid superfloppy takes precedence over an incidental EE table byte.
  for(i=0;i<4;i=i+1) begin
   make_bpb(65525,8);partition(i,8'h7f,8'hee,0,0);
   run_sector($sformatf("superfloppy precedence over EE %0d",i),0,1);
  end
  // Malformed BPB falls back to the table, never falsely to a superfloppy.
  for(i=0;i<18;i=i+1) begin
   make_bpb(65525,1);partition(2,0,8'h0c,2048,100000);
   case(i)
    0:put16(11,1024);
    1:sector[13]=0;
    2:sector[13]=3;
    3:put16(14,0);
    4:sector[16]=0;
    5:sector[16]=3;
    6:put32(36,0);
    7:put16(42,1);
    8:put16(17,1);
    9:put16(19,1);
    10:put16(22,1);
    11:put32(32,32);
    12:put32(44,1);
    13:put32(44,65527);
    14:put32(36,1);
    15:put16(40,16'h0082);
    16:begin sector[16]=1;put16(40,16'h0081);end
    17:put32(44,32'hffffffff);
   endcase
   run_sector($sformatf("invalid BPB fallback reason %0d",i),0,1);
  end
  // Single FAT and selecting the second FAT are both valid BPB variants.
  make_bpb(65525,2);sector[16]=1;put32(32,32+get32(36)+65525*2);
  put16(40,16'h0080);run_sector("valid single FAT active zero",0,1);
  make_bpb(65525,4);put16(40,16'h0081);run_sector("valid second active FAT",0,1);
  for(i=0;i<2;i=i+1) begin
   make_mbr();sector[510+i]=0;run_sector($sformatf("bad signature byte %0d",i),0,1);
  end
  // Transport status has priority over plausible content and metadata.
  for(i=0;i<=12;i=i+1) begin
   make_mbr();run_sector($sformatf("transport mode %0d",i),i,i%2);
  end
  make_bpb(65525,1);run_sector("valid BPB but CRC fails",2,1);
  // Wait for ready must time out without ever requesting the card.
  make_mbr();begin_transaction("ready timeout",1,0);
  start=1;tick();start=0;await_completion();
  if(requests!=0) fail("request made while card not ready");
  // Timeout must win even if a complete sector's done arrives on the
  // terminal cycle, or CHECK would otherwise commit on that cycle.
  for(i=0;i<2;i=i+1) begin
   make_mbr();begin_transaction($sformatf("timeout priority terminal offset %0d",i),1,1);
   await_request();
   for(n=0;n<512;n=n+1) begin rd_done=0;send_byte(n,0);end
   quiet();while(age<TIMEOUT_CYCLES-i) tick();
   rd_done=1;tick();await_completion();
  end
  // Restart bad -> good -> good -> bad without a reset, checking retained idle
  // metadata first and start-time clearing on every launch.
  clear_sector();run_sector("restart bad empty table",0,1);
  make_mbr();run_sector("restart good after bad",0,1);
  clear_sector();partition(3,8'h80,8'h0b,7777,54321);run_sector("restart different good",1,1);
  run_sector("restart bad transport after good",3,1);
  // Reset the five externally reachable FSM stages, including CHECK before
  // its result is committed. Every reset is followed by a successful restart.
  reset_device("reset in IDLE");
  make_mbr();begin_transaction("reset in PROBE",0,1);reset_device("reset in PROBE");
  make_mbr();run_sector("good after PROBE reset",0,0);
  make_mbr();begin_transaction("reset in REQUEST",0,0);tick();tick();
  reset_device("reset in REQUEST");make_mbr();run_sector("good after REQUEST reset",0,0);
  make_mbr();begin_transaction("reset in RECEIVE",0,1);await_request();
  for(n=0;n<37;n=n+1) send_byte(n,0);
  reset_device("reset in RECEIVE");make_mbr();run_sector("good after RECEIVE reset",0,0);
  make_mbr();begin_transaction("reset in CHECK",0,1);await_request();
  for(n=0;n<512;n=n+1) begin rd_done=(n==511);send_byte(n,0);end
  if(!transaction) fail("CHECK reset must precede completion");
  reset_device("reset in CHECK");make_mbr();run_sector("good after CHECK reset",0,0);
  quiet();repeat(5) tick();
  $display("PASS signature locator SHARED=%0d timeout=%0d scenarios=%0d completed=%0d successes=%0d failures=%0d resets=%0d cycles=%0d public_bits=357 signature_mutations=1024",
           SHARED,TIMEOUT_CYCLES,scenarios,completed,oracle_successes,oracle_failures,resets,cycles);
  $finish;
 end
 initial begin #20000000;$fatal(1,"MBR test watchdog");end
endmodule
