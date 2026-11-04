`timescale 1ns/1ps
// The arithmetic oracle classifies complete sectors using unsigned 64-bit
// software-style calculations. A separate transport model predicts every
// public output on every clock, including invalid-sector SPC and held metadata.
// No DUT internal state or intermediate arithmetic is inspected.
module tb_signature_boot;
 parameter integer SHARED=0;
 parameter integer TIMEOUT_CYCLES=800;
 wire [255:0] bpb_fields,old_bpb_fields;
 wire [128:0] bpb_result,old_bpb_result;
 fat32_bpb_math math_new(.clk(clk),.bpb_fields(bpb_fields),.bpb_result(bpb_result));
 fat32_bpb_math_baseline math_old(.clk(clk),.bpb_fields(old_bpb_fields),.bpb_result(old_bpb_result));
 reg clk=0,rst_n=0,start=0,byte_valid=0;
 reg [31:0] partition_lba=0;
 reg [8:0] byte_addr=0;
 reg [7:0] byte_in=0;
 wire [31:0] fat_lba,root_lba,root_cluster,data_lba,cluster_count,volume_sectors;
 wire [7:0] sectors_per_cluster;
 wire valid,busy,done,error;
 wire [203:0] public_outputs={fat_lba,root_lba,root_cluster,sectors_per_cluster,
                             valid,busy,done,error,data_lba,cluster_count,volume_sectors};
 fat32_boot_parser #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.SHARED_BPB(SHARED)) dut(.*);
`ifdef COMPARE_BASELINE
 wire [31:0] old_fat_lba,old_root_lba,old_root_cluster,old_data_lba,old_cluster_count,old_volume_sectors;
 wire [7:0] old_sectors_per_cluster;
 wire old_valid,old_busy,old_done,old_error;
 wire [203:0] old_outputs={old_fat_lba,old_root_lba,old_root_cluster,old_sectors_per_cluster,
                         old_valid,old_busy,old_done,old_error,
                         old_data_lba,old_cluster_count,old_volume_sectors};
 fat32_boot_parser_baseline #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.SHARED_BPB(SHARED)) baseline(
  .bpb_fields(old_bpb_fields),.bpb_result(old_bpb_result),
  .clk(clk),.rst_n(rst_n),.start(start),.partition_lba(partition_lba),
  .byte_addr(byte_addr),.byte_in(byte_in),.byte_valid(byte_valid),
  .fat_lba(old_fat_lba),.root_lba(old_root_lba),.root_cluster(old_root_cluster),
  .sectors_per_cluster(old_sectors_per_cluster),.valid(old_valid),.busy(old_busy),
  .done(old_done),.error(old_error),.data_lba(old_data_lba),
  .cluster_count(old_cluster_count),.volume_sectors(old_volume_sectors));
`endif
 always #5 clk=~clk;
 reg [7:0] sector[0:511];
 reg [31:0] rng=32'hb0b42017;
 integer cycles=0,scenarios=0,completed=0,accepted=0,reset_pulses=0,aborted=0;
 integer success_count=0,failure_count=0,model_timer=0,model_expected=0;
 reg model_busy=0,model_valid=0,model_done=0,model_error=0;
 reg [31:0] model_fat=0,model_root=0,model_root_cluster=0;
 reg [31:0] model_data=0,model_clusters=0,model_volume=0;
 reg [7:0] model_spc=0;
 reg oracle_ok=0;
 reg [31:0] oracle_fat=0,oracle_root=0,oracle_data=0,oracle_clusters=0;
 wire [203:0] model_outputs={model_fat,model_root,model_root_cluster,model_spc,
                            model_valid,model_busy,model_done,model_error,
                            model_data,model_clusters,model_volume};
 string case_name="initial reset";

 task fail(input string message);
  begin
   $display("FAIL timeout=%0d case=%s cycle=%0d: %s",TIMEOUT_CYCLES,case_name,cycles,message);
   $fatal(1);
  end
 endtask
 function [15:0] get16(input integer address);
  get16={sector[address+1],sector[address]};
 endfunction
 function [31:0] get32(input integer address);
  get32={sector[address+3],sector[address+2],sector[address+1],sector[address]};
 endfunction
 function [31:0] next_random;
  begin rng=rng*32'd1664525+32'd1013904223;next_random=rng;end
 endfunction
 task put16(input integer address,input reg [15:0] value);
  begin sector[address]=value[7:0];sector[address+1]=value[15:8];end
 endtask
 task put32(input integer address,input reg [31:0] value);
  begin sector[address]=value[7:0];sector[address+1]=value[15:8];
   sector[address+2]=value[23:16];sector[address+3]=value[31:24];end
 endtask
 task classify_sector;
  reg [63:0] total,fat_length,overhead,clusters,first_fat,first_data,first_root;
  reg [63:0] root_number,partition_end,capacity;
  reg [15:0] flags;
  integer shift,n;
  begin
   shift=0;for(n=0;n<8;n=n+1) if(sector[13][n]) shift=n;
   total={32'b0,get32(32)};fat_length={32'b0,get32(36)};
   root_number={32'b0,get32(44)};flags=get16(40);
   overhead={48'b0,get16(14)}+fat_length*((sector[16]==2)?64'd2:64'd1);
   clusters=(total-overhead)>>shift;
   first_data={32'b0,partition_lba}+overhead;
   first_fat={32'b0,partition_lba}+{48'b0,get16(14)};
   if(flags[7] && flags[3:0]!=0) first_fat=first_fat+fat_length;
   first_root=first_data+((root_number-64'd2)<<shift);
   partition_end={32'b0,partition_lba}+total;capacity=fat_length<<7;
   oracle_ok=(sector[510]==8'h55 && sector[511]==8'haa && get16(11)==512 &&
      sector[13]!=0 && (sector[13]&(sector[13]-1))==0 && get16(14)!=0 &&
      (sector[16]==1 || sector[16]==2) && fat_length!=0 && get16(42)==0 &&
      get16(17)==0 && get16(19)==0 && get16(22)==0 && total>overhead &&
      clusters>=65525 && clusters<64'h0ffffff5 && root_number>=2 &&
      root_number<clusters+2 && capacity>=clusters+2 &&
      (!flags[7] || flags[3:0]<sector[16]) &&
      partition_end<=64'h100000000 && first_root<64'h100000000);
   oracle_fat=first_fat[31:0];oracle_data=first_data[31:0];
   oracle_root=first_root[31:0];oracle_clusters=clusters[31:0];
  end
 endtask

 // Independent protocol model: completion is on byte 511, an address fault,
 // or timeout. Metadata is published only on successful final-byte validation;
 // SPC is deliberately checked even while incomplete or invalid.
 always @(posedge clk) begin
  cycles=cycles+1;
  if(!rst_n) begin
   if(model_busy) aborted=aborted+1;
   model_busy=0;model_valid=0;model_done=0;model_error=0;model_spc=0;
   model_fat=0;model_root=0;model_root_cluster=0;
   model_data=0;model_clusters=0;model_volume=0;model_timer=0;model_expected=0;
  end else begin
   model_done=0;
   if(start && !model_busy) begin
    accepted=accepted+1;model_busy=1;model_valid=0;model_error=0;
    model_spc=0;model_fat=0;model_root=0;model_root_cluster=0;
    model_data=0;model_clusters=0;model_volume=0;model_timer=0;model_expected=0;
   end else if(model_busy) begin
    if(model_timer>=TIMEOUT_CYCLES-1) begin
     model_busy=0;model_done=1;model_error=1;model_valid=0;
    end else begin
     model_timer=model_timer+1;
     if(byte_valid) begin
      if({1'b0,byte_addr}!=model_expected) begin
       model_busy=0;model_done=1;model_error=1;model_valid=0;
      end else begin
       model_expected=model_expected+1;
       if(byte_addr==13) model_spc=byte_in;
       if(byte_addr==511) begin
        model_busy=0;model_done=1;
        if(oracle_ok) begin
         model_valid=1;model_fat=oracle_fat;model_data=oracle_data;
         model_root=oracle_root;model_root_cluster=get32(44);
         model_clusters=oracle_clusters;model_volume=get32(32);
        end else begin model_valid=0;model_error=1;end
       end
      end
     end
    end
   end
   if(model_done) begin
    completed=completed+1;
    if(model_valid) success_count=success_count+1;else failure_count=failure_count+1;
   end
  end
  #1;
`ifdef COMPARE_BASELINE
  if(bpb_fields!==old_bpb_fields)fail("all 256 bpb_fields bits differ from frozen RTL");
  if(public_outputs!==old_outputs) begin
   $display("candidate=%051h baseline=%051h",public_outputs,old_outputs);
   fail("all 204 public bits differ from old RTL");
  end
`endif
  if((^public_outputs)===1'bx) fail("unknown public output");
  if(public_outputs!==model_outputs) begin
   $display("candidate=%051h oracle=%051h",public_outputs,model_outputs);
   fail("independent arithmetic/transport oracle");
  end
 end
 task tick;
  begin @(negedge clk);@(posedge clk);#2;end
 endtask
 task quiet;
  begin start=0;byte_valid=0;byte_addr=0;byte_in=0;end
 endtask
 task reset_device(input string label_text);
  begin case_name=label_text;quiet();rst_n=0;reset_pulses=reset_pulses+1;
   tick();tick();rst_n=1;tick();end
 endtask
 task make_bpb(input reg [31:0] cluster_total,input reg [7:0] spc_value,
               input reg [7:0] fat_copies,input reg [31:0] root_value);
  integer n;
  reg [63:0] fat_length,total_length;
  begin
   for(n=0;n<512;n=n+1) sector[n]=0;
   fat_length=({32'b0,cluster_total}+129)/128;
   total_length=32+fat_copies*fat_length+{32'b0,cluster_total}*spc_value;
   put16(11,512);sector[13]=spc_value;put16(14,32);sector[16]=fat_copies;
   put32(32,total_length[31:0]);put32(36,fat_length[31:0]);put32(44,root_value);
   sector[510]=8'h55;sector[511]=8'haa;partition_lba=2048;
  end
 endtask
 task begin_transaction(input string label_text);
  begin
   if(busy) fail("test attempted a new transaction while busy");
   case_name=label_text;classify_sector();scenarios=scenarios+1;
   quiet();start=1;tick();start=0;
  end
 endtask
 task send_byte(input integer address,input integer pulse_start);
  begin byte_valid=1;byte_addr=address;byte_in=sector[address];start=pulse_start;
   tick();start=0;end
 endtask
 task await_completion;
  integer guard;
  begin quiet();guard=0;
   while(busy && guard<TIMEOUT_CYCLES+3) begin tick();guard=guard+1;end
   if(busy) fail("missing completion");
   quiet();tick();tick();
  end
 endtask
 // 0 normal, 1 bubbles/start while busy, 2 duplicate address, 3 skip address,
 // 4 byte 511 first, 5 short at 511, 6 empty timeout, 7 extra bytes after done,
 // 8 short before SPC, 9 timeout beats an arriving byte.
 task run_sector(input string label_text,input integer mode);
  integer n,limit;
  begin
   begin_transaction(label_text);limit=512;
   if(mode==4) begin send_byte(511,0);limit=0;end
   if(mode==5) limit=511;
   if(mode==6 || mode==9) limit=0;
   if(mode==8) limit=13;
   for(n=0;n<limit;n=n+1) begin
    if(mode==1 && n%17==0) begin quiet();tick();end
    if(mode==3 && n==73) send_byte(74,1);
    else send_byte(n,(mode==1 || n==14 || n==47));
    if(mode==2 && n==100) send_byte(100,1);
   end
   if(mode==7) begin send_byte(511,0);send_byte(0,0);end
   if(mode==9) begin
    quiet();repeat(TIMEOUT_CYCLES-1) tick();send_byte(0,1);
   end
   await_completion();
  end
 endtask

 integer i,j,k,n,reset_at,success_before;
 reg [31:0] clusters,random_value;
 reg [63:0] total_length;
 initial begin
  reset_device("initial reset");
  // Every encoded low/high signature byte, with independent good-sector oracle.
  for(i=0;i<2;i=i+1)for(j=0;j<256;j=j+1)begin
   make_bpb(70000,8,2,2);sector[510+i]=j;
   run_sector($sformatf("signature byte=%0d value=%0d",i,j),j%2);
  end
  // All eight legal SPC powers, both FAT counts, and mirroring/active FAT modes.
  for(i=0;i<8;i=i+1) for(j=1;j<=2;j=j+1) for(k=0;k<3;k=k+1) begin
   make_bpb(65525+137*i,8'b1<<i,j,2+i);
   case(k) 0:put16(40,0);1:put16(40,16'h80);2:put16(40,16'h81);endcase
   run_sector($sformatf("SPC=%0d FATs=%0d flags-mode=%0d",1<<i,j,k),1);
  end
  // Exact cluster and root bounds; large totals may wrap the 32-bit BPB field,
  // and the independent oracle classifies the encoded sector, not the intent.
  for(i=0;i<8;i=i+1) for(j=0;j<7;j=j+1) begin
   case(j) 0:clusters=0;1:clusters=65524;2:clusters=65525;3:clusters=65526;
    4:clusters=32'h0ffffff4;5:clusters=32'h0ffffff5;6:clusters=32'hffffffff;endcase
   make_bpb(clusters,8'b1<<i,2,2);partition_lba=0;
   run_sector($sformatf("cluster threshold SPC=%0d case=%0d",1<<i,j),0);
  end
  for(j=1;j<=2;j=j+1) for(i=0;i<16;i=i+1) begin
   make_bpb(70000,1,j,2);put16(40,16'h80|i);
   run_sector($sformatf("active FAT low nibble=%0d copies=%0d",i,j),0);
  end
  for(i=0;i<5;i=i+1) begin
   make_bpb(70000,8,2,2);
   case(i) 0:put32(44,0);1:put32(44,1);2:put32(44,70001);
    3:put32(44,70002);4:put32(44,32'hffffffff);endcase
   run_sector($sformatf("root boundary %0d",i),0);
  end
  // partition + total exactly 2^32 is legal; one sector beyond is rejected.
  for(i=0;i<3;i=i+1) begin
   make_bpb(70000,8,2,70001);total_length={32'b0,get32(32)};
   partition_lba=(64'h100000000-total_length+i-1);
   run_sector($sformatf("partition endpoint offset=%0d",i-1),0);
  end
  // Independent malformed fields, including invalid powers and signatures.
  for(i=0;i<22;i=i+1) begin
   make_bpb(70000,8,2,2);
   case(i)
    0:put16(11,0);1:put16(11,1024);2:sector[13]=0;3:sector[13]=3;
    4:sector[13]=255;5:put16(14,0);6:sector[16]=0;7:sector[16]=3;
    8:put32(36,0);9:put16(42,1);10:put16(17,1);11:put16(19,1);
    12:put16(22,1);13:put32(32,0);14:put32(32,1);15:sector[510]=0;
    16:sector[511]=0;17:put32(36,1);18:put16(40,16'h8f);
    19:partition_lba=32'hffffffff;
    20:begin put16(14,16'hffff);put32(36,32'hffffffff);put32(32,32'hffffffff);end
    21:begin put32(44,1);sector[13]=128;end
   endcase
   run_sector($sformatf("malformed field %0d",i),i%2);
  end
  // Wide arithmetic extremes: all-ones/zero lengths, double-FAT carry into bit
  // 33, valid/invalid SPC, low and high root values, partition overflow.
  for(i=0;i<32;i=i+1) begin
   make_bpb(70000,(i[0]?128:1),(i[1]?2:1),i[2]?32'hffffffff:0);
   put16(14,i[3]?16'hffff:1);put32(36,i[4]?32'hffffffff:32'h80000000);
   put32(32,i[2]?32'hffffffff:0);partition_lba=i[0]?32'hffffffff:0;
   run_sector($sformatf("wide arithmetic extremes %0d",i),0);
  end
  // Reproducible valid/near-valid/full-random sectors. The random stream is
  // local and fixed; classification does not depend on simulator random seeds.
  for(i=0;i<320;i=i+1) begin
   random_value=next_random();clusters=65525+(random_value%1000000);
   make_bpb(clusters,8'b1<<(i%8),1+(i%2),2);
   partition_lba=next_random()&32'h000fffff;
   if(i%4==0) begin
    put16(14,next_random());sector[16]=next_random();put32(32,next_random());
    put32(36,next_random());put32(44,next_random());put16(40,next_random());
    partition_lba=next_random();
   end else if(i%4==1) begin
    case((i/4)%8)
     0:put32(32,next_random());1:put32(36,next_random());
     2:put32(44,next_random());3:put16(14,next_random());
     4:put16(40,next_random());5:sector[13]=next_random();
     6:sector[16]=next_random();7:partition_lba=next_random();
    endcase
   end else if(i%4==2) begin
    put32(44,clusters+1);put16(40,(i%2)?16'h81:16'h80);
   end
   run_sector($sformatf("fixed-seed random sector %0d",i),i%2);
  end
  for(i=0;i<10;i=i+1) begin
   make_bpb(70000,8,2,2);run_sector($sformatf("transport mode %0d",i),i);
   make_bpb(70001,16,1,2);run_sector("valid restart without reset",0);
  end
  // Reset while idle, throughout fields/pipeline settling, and at signature.
  for(i=0;i<17;i=i+1) begin
   case(i) 0:reset_at=0;1:reset_at=1;2:reset_at=12;3:reset_at=13;
    4:reset_at=14;5:reset_at=35;6:reset_at=36;7:reset_at=39;
    8:reset_at=40;9:reset_at=43;10:reset_at=44;11:reset_at=47;
    12:reset_at=48;13:reset_at=509;14:reset_at=510;15:reset_at=511;
    16:reset_at=512;endcase
   make_bpb(70000,8,2,2);begin_transaction($sformatf("reset after %0d bytes",reset_at));
   for(n=0;n<reset_at;n=n+1) send_byte(n,0);
   reset_device($sformatf("assert reset after %0d bytes",reset_at));
   make_bpb(70003,128,2,2);run_sector("valid restart after reset",1);
  end
  // Start has priority over data when idle. The simultaneous byte zero must
  // be ignored, so retransmitting byte zero is required and remains legal.
  make_bpb(70000,1,1,2);classify_sector();scenarios=scenarios+1;
  case_name="start plus byte valid while idle";start=1;byte_valid=1;byte_addr=0;byte_in=sector[0];
  tick();start=0;for(n=0;n<512;n=n+1) send_byte(n,0);await_completion();
  // SPC and published metadata must remain stable in idle even with stray data.
  for(n=0;n<16;n=n+1) begin byte_valid=1;byte_addr=13;byte_in=n;tick();end
  quiet();tick();reset_device("final reset");
  if(accepted!=scenarios || accepted!=completed+aborted)
   fail("transaction accounting");
  if(success_count<100 || failure_count<100 || aborted!=16)
   fail("coverage/accounting floor");
  $display("PASS signature boot SHARED=%0d timeout=%0d scenarios=%0d accepted=%0d completed=%0d aborted=%0d resets=%0d success=%0d failure=%0d cycles=%0d public_bits=460 signature_mutations=512",
           SHARED,TIMEOUT_CYCLES,scenarios,accepted,completed,aborted,reset_pulses,success_count,failure_count,cycles);
  $finish;
 end
endmodule
