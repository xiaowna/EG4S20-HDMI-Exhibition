`timescale 1ns/1ps
module tb_catalog_timer;
 parameter integer LIMIT=800,FOUR_FILES=0;
 localparam TIMER_BITS=(LIMIT>1)?$clog2(LIMIT):1;
 reg clk=0,rst_n=0,start=0,rd_ready=1,rd_done=0,rd_error=0,rd_valid=0;
 reg [8:0] rd_addr=0;reg [7:0] rd_data=0;
 reg [31:0] partition_lba=0,partition_sectors=0;
 wire rd_start,busy,done,error,found_valid,wav_found;
 wire [31:0] rd_lba,found_first_cluster,found_size,volume_fat_lba,volume_data_lba;
 wire [31:0] volume_cluster_count,volume_root_lba,volume_root_cluster,wav_first_cluster,wav_size;
 wire [1:0] found_index;wire [2:0] found_count;wire [7:0] volume_sectors_per_cluster;
 reg [7:0] mem[0:1535];
 integer mode=0,requests=0,completed=0,failures=0,successes=0,wraps=0,root_stalls=0,bank,k,limit_bytes,begin_requests,count;
 fat32_bmp_catalog #(.TIMEOUT_CYCLES(LIMIT),.FIND_WAV(1)) dut(.wav_index(2'd0),.wav_count(),.folder_info(),.*);
 always #5 clk=~clk;
 task tick;begin @(negedge clk);#2;end endtask
 initial forever begin
  @(negedge clk);
  if(rd_start)begin
   if(!rd_ready)$fatal(1,"overlapping sector");rd_ready=0;requests=requests+1;
   if(rd_lba==0)bank=0;else if(rd_lba==1234)bank=1;else $fatal(1,"unexpected LBA %0d",rd_lba);
   if(bank==1&&mode==8)begin
    // Exercise the ignored counter's boundary in directory phase. A candidate
    // may wrap or hold it; neither value is allowed to affect public results.
    dut.timer=(64'd1<<TIMER_BITS)-2;
    dut.__safety_reference.timer=(64'd1<<TIMER_BITS)-2;wraps=wraps+1;
   end
   repeat(2)@(negedge clk);
   if(bank==1&&mode==5)begin
    root_stalls=root_stalls+1;
    if(LIMIT>2048)begin
     dut.u_directory.timer=LIMIT-2;
     dut.__safety_reference.u_directory.timer=LIMIT-2;
    end
    wait(done||!rst_n);@(negedge clk);
   end else begin
    limit_bytes=(bank==0&&mode==3)?128:512;
    for(k=0;k<limit_bytes&&rst_n;k=k+1)begin
     rd_addr=(mode==6&&bank==0&&k==10)?11:k;
     rd_data=mem[bank*512+k];rd_valid=1;
     if(mode==7&&k==10)start=1;
     @(negedge clk);rd_valid=0;if(mode==7)start=0;
    end
    if(rst_n)begin
     repeat(2)@(negedge clk);
     rd_error=(mode==1&&bank==0)||(mode==2&&bank==1);
     rd_done=1;@(negedge clk);rd_done=0;rd_error=0;
    end
   end
   rd_valid=0;rd_ready=1;
  end
 end
 task begin_scan;
  begin begin_requests=requests;start=1;tick();start=0;if(!busy)$fatal(1,"catalog did not start");end
 endtask
 task await_result(input integer expected_error);
  begin
   count=0;
   while(!done&&count<(LIMIT>2048?6000:LIMIT*4+100))begin tick();count=count+1;end
   if(!done||busy||error!==expected_error[0])$fatal(1,"catalog result LIMIT=%0d mode=%0d done=%0d error=%0d",LIMIT,mode,done,error);
   if(!expected_error)begin
    if(!wav_found||wav_first_cluster!=5||wav_size!=52||found_count!=(FOUR_FILES?4:1)||
       requests-begin_requests!=2||volume_root_lba!=1234||volume_fat_lba!=32||volume_data_lba!=1232||volume_sectors_per_cluster!=2)
     $fatal(1,"successful catalog metadata");
    successes=successes+1;
   end else failures=failures+1;
   completed=completed+1;repeat(3)tick();
  end
 endtask
 initial begin
  if(FOUR_FILES)$readmemh("card_fixture_4bmp.hex",mem);else $readmemh("card_fixture.hex",mem);
  repeat(3)tick();rst_n=1;tick();
  for(mode=0;mode<=8;mode=mode+1)begin
   if(mode==4)rd_ready=0;
   begin_scan();
   if(mode==4&&LIMIT>2048)begin
    repeat(3)tick();dut.timer=LIMIT-2;dut.__safety_reference.timer=LIMIT-2;
   end
   await_result(mode>=1&&mode<=6);rd_ready=1;
   // A short, falsely successful sector leaves the frozen BPB engine active.
   // Isolate this malformed-transport case so the following no-response test
   // must actually reach the directory instead of merely failing boot.
   if(mode==3)begin rst_n=0;repeat(3)tick();rst_n=1;repeat(2)tick();end
  end
  // Abort a real root-sector transfer, then recover through a fresh scan.
  mode=9;begin_scan();wait(rd_start&&rd_lba==1234);repeat(32)tick();
  rst_n=0;#1;if(busy||done||error||found_count||wav_found)$fatal(1,"catalog reset");
  repeat(4)tick();rst_n=1;repeat(3)tick();mode=0;begin_scan();await_result(0);
  if(completed!=10||successes!=4||failures!=6||wraps!=1||root_stalls!=1)$fatal(1,"coverage missing");
  $display("PASS catalog timer LIMIT=%0d FOUR=%0d completed=%0d successes=%0d failures=%0d wraps=%0d root_stalls=%0d reset_aborts=1; all public outputs match",LIMIT,FOUR_FILES,completed,successes,failures,wraps,root_stalls);$finish;
 end
 initial begin #2000000;$fatal(1,"catalog timer bench watchdog");end
endmodule
