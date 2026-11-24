`timescale 1ns/1ps
// Production FAT/BMP loader, SDRAM controller/model, raster, and SD arbiter.
// Two distinct 3x2 images expose mixed banks. A concurrent urgent audio client
// checks complete-sector ownership while image prefetch runs in the background.
module tb_slide_pipeline;
 parameter integer BAD=0,FAST=0;
 localparam integer LEGACY=0;
 reg clk=0,pix=0,rst_n=0,pause=1,next_pulse=0,prev_pulse=0;
 always #10 clk=~clk;always #60 pix=~pix;
 wire scan_start,load_start,load_ready,scan_done,image_done,error,front_valid,front_bank;
 wire frame_prepared,frame_committed,frame_rejected,commit_enable,discard_cached,transition_active,cancel_load;
 wire transition_manual,transition_backward,slide_ready;
 wire [1:0] image_index;reg [1:0] display_index=0,loading_index=0;
 wire [2:0] image_count;
 wire de,hsync,vsync,frame_underflow,video_started,sdram_ready,memory_fault,prefetch_error;
 wire [23:0] rgb;
 wire rd_start,rd_ready,rd_done,rd_error,rd_valid;wire [31:0] rd_lba;wire [8:0] rd_addr;wire [7:0] rd_data;
 wire card_start;wire [31:0] card_lba;
 reg card_ready=1,card_done=0,card_error=0,card_valid=0;
 reg [8:0] card_addr=0;reg [7:0] card_data=0;
 reg audio_start=0,audio_busy=0;
 wire audio_ready,audio_done,audio_error,audio_valid;wire [8:0] audio_addr;wire [7:0] audio_data;
 integer cycles=0,requests=0,image_requests=0,audio_sectors=0,audio_bytes=0;
 integer commits=0,good_frames=0,seen=0,lit=0,frame_id=-1,bank,k,request_at_commit=0;
 integer start_cycle,start_requests,hit_cycles=0,hit_reads=0,cold_cycles=0,cold_reads=0,goal,before_commit,cancelled=0;
 reg reverse_wait=0;
 reg bad_image=BAD;reg [7:0] mem[0:4095];
 integer animation_serial=0,seen_animation=0,animation_frames=0,animations=0;
 integer animation_phase=0,old_id=0,new_id=1,shift=0,source_x=0,source_id=0,source_pixel=0;
 reg animation_armed=0,animating=0,direction=0;
 generate if(LEGACY)begin
  media_playlist_control #(.INTERVAL_CYCLES(100000)) control(
   .clk(clk),.rst_n(rst_n),.card_ready(sdram_ready),.load_ready(load_ready),.scan_done(scan_done),
   .image_done(image_done),.error(error),.image_count(image_count),.next_pulse(next_pulse),.prev_pulse(prev_pulse),
   .pause(pause),.scan_start(scan_start),.load_start(load_start),.image_index(image_index));
  assign commit_enable=1;assign discard_cached=0;assign transition_active=0;assign cancel_load=0;
 end else begin:prefetched
  media_prefetch_control #(.INTERVAL_CYCLES(100000),.AUTOPLAY_CYCLES(600),.FAST_MANUAL(FAST)) control(
   .fast_pulse(FAST!=0),
   .clk(clk),.rst_n(rst_n),.card_ready(sdram_ready),.load_ready(load_ready),.scan_done(scan_done),
   .image_done(image_done),.error(error),.image_count(image_count),.next_pulse(next_pulse),.prev_pulse(prev_pulse),
   .pause(pause),.front_valid(front_valid),.display_index(display_index),.frame_prepared(frame_prepared),
   .frame_committed(frame_committed),.transition_ready(transition_manual?slide_ready:transition_active),.scan_start(scan_start),
   .load_start(load_start),.image_index(image_index),.commit_enable(commit_enable),
   .discard_cached(discard_cached),.transition_active(transition_active),
   .transition_manual(transition_manual),.transition_backward(transition_backward),.cancel_load(cancel_load));
 end endgenerate
 media_stream_pipeline #(.FRAME_WIDTH(3),.FRAME_HEIGHT(2),.TIMEOUT_CYCLES(50000),
  .H_FP(2),.H_SYNC(2),.H_BP(2),.V_FP(2),.V_SYNC(2),.V_BP(2),.FIFO_ADDR_BITS(3),.CONTROLLED_SWAP(!LEGACY),.SLIDE_TRANSITIONS(1),.ABORTABLE(FAST)) media(
  .clk(clk),.pix_clk(pix),.rst_n(rst_n),.scan_start(scan_start),.load_start(load_start),.image_index(image_index),
  .load_ready(load_ready),.scan_done(scan_done),.image_done(image_done),.error(error),.image_count(image_count),
  .rd_start(rd_start),.rd_lba(rd_lba),.rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),
  .rd_valid(rd_valid),.rd_addr(rd_addr),.rd_data(rd_data),.front_valid(front_valid),.front_bank(front_bank),
  .frame_committed(frame_committed),.frame_rejected(frame_rejected),.frame_prepared(frame_prepared),
  .commit_enable(commit_enable),.discard_cached(discard_cached),.abort_load(cancel_load),.intro_instant(1'b0),.de(de),.hsync(hsync),.vsync(vsync),.rgb(rgb),
  .frame_underflow(frame_underflow),.video_started(video_started),.sdram_ready(sdram_ready),
  .memory_fault(memory_fault),.prefetch_error(prefetch_error),
  .slide_request(transition_manual),.slide_right(transition_backward),.slide_ready(slide_ready));
 sd_sector_arbiter arbiter(.clk(clk),.rst_n(rst_n),.card_ready(card_ready),.audio_urgent(1'b1),
  .card_done(card_done),.card_error(card_error),.card_addr(card_addr),.card_data(card_data),.card_valid(card_valid),
  .card_start(card_start),.card_lba(card_lba),.image_start(rd_start),.image_lba(rd_lba),.image_ready(rd_ready),
  .image_done(rd_done),.image_error(rd_error),.image_addr(rd_addr),.image_data(rd_data),.image_valid(rd_valid),
  .audio_start(audio_start),.audio_lba(32'd900000),.audio_ready(audio_ready),.audio_done(audio_done),
  .audio_error(audio_error),.audio_addr(audio_addr),.audio_data(audio_data),.audio_valid(audio_valid));
 always @(posedge clk)if(rst_n)begin
  cycles<=cycles+1;audio_start<=0;
  if(audio_ready&&!audio_busy)begin audio_start<=1;audio_busy<=1;end
  if(audio_done)begin
   if(audio_error||audio_bytes!=512)$fatal(1,"audio sector damaged/interleaved");
   audio_busy<=0;audio_sectors<=audio_sectors+1;audio_bytes<=0;
  end
  if(audio_valid)begin
   if(audio_addr!==audio_bytes || audio_data!==(audio_bytes&255))$fatal(1,"wrong audio ownership/data");
   audio_bytes<=audio_bytes+1;
  end
  if(load_start&&load_ready)loading_index<=image_index;
  if(cancel_load&&image_done)begin
   if(!error)$fatal(1,"cancelled frame completed successfully");
   cancelled<=cancelled+1;
  end
  if(!transition_manual)animation_armed=0;
  if(media.swap_window&&transition_manual&&frame_prepared&&!animation_armed)begin
   animation_serial=animation_serial+1;animation_armed=1;animation_frames=0;
  end
  if(FAST&&commits!=0&&transition_active)$fatal(1,"fast gallery emitted an animation request");
  if(transition_manual&&media.wr_valid)$fatal(1,"a sliding source bank became writable");
  if(frame_committed)begin
   if(!FAST && commits!=0 && animation_frames!=18)$fatal(1,"bank released before all 18 mixed frames retired: %0d",animation_frames);
   display_index<=loading_index;commits<=commits+1;request_at_commit<=image_requests;
  end
  if(memory_fault||prefetch_error||frame_underflow)$fatal(1,"SDRAM/raster fault");
 end
 always @(posedge pix)begin
  #1;
  if(rst_n&&de)begin
   if(rgb!=0)begin
    if(lit==0)begin
     frame_id=display_index;
     if(animation_serial!=seen_animation)begin
      seen_animation=animation_serial;animating=1;animation_phase=0;
      old_id=display_index;new_id=1-display_index;direction=transition_backward;
     end
     // Independent integer smoothstep (round Q8, then floor source pixels).
     shift=(3*((256*(3*animation_phase*animation_phase*18-2*animation_phase*animation_phase*animation_phase)+2916)/5832))/256;
    end
    source_x=seen%3;source_id=frame_id;
    if(animating)begin
     source_id=old_id;
     if(direction)begin
      if(source_x<shift)begin source_id=new_id;source_x=source_x+3-shift;end
      else source_x=source_x-shift;
     end else begin
      if(source_x<3-shift)source_x=source_x+shift;
      else begin source_id=new_id;source_x=source_x-(3-shift);end
     end
    end
    source_pixel=(seen/3)*3+source_x;
    if(rgb!==(((source_pixel+10+source_id*64)<<16)|((source_pixel+20)<<8)|(source_pixel+30)))
     $fatal(1,"wrong slide pixel phase=%0d right=%b d=%0d pixel=%0d source=%0d image=%0d got=%h",animation_phase,direction,shift,seen,source_pixel,source_id,rgb);
    lit=lit+1;
   end
   seen=seen+1;
   if(seen==6)begin
    if(lit==6)begin
     good_frames=good_frames+1;
     if(animating)begin
      animation_frames=animation_frames+1;
      if(animation_phase==17)begin animating=0;animations=animations+1;end
      else animation_phase=animation_phase+1;
     end
    end else if(lit!=0)$fatal(1,"partial raster frame");
    lit=0;seen=0;
   end
  end
 end
 initial forever begin
  @(posedge clk);
  if(rst_n&&card_start)begin
   if(!card_ready)$fatal(1,"overlapped card transaction");#1;card_ready=0;requests=requests+1;
   if(reverse_wait&&card_lba==3408)$fatal(1,"cancelled prefetch read the next BMP data sector");
   if(card_lba!=900000)image_requests=image_requests+1;
   case(card_lba)0:bank=0;2048:bank=1;3281:bank=2;2080:bank=3;3283:bank=4;3408:bank=5;3287:bank=6;2081:bank=7;
    900000:bank=8;3288:bank=9;default:$fatal(1,"unexpected LBA %d",card_lba);endcase
   repeat(7)@(negedge clk);
   for(k=0;k<512;k=k+1)begin
    card_valid=1;card_addr=k;card_data=(bank==7)?8'hff:((bank==8)?k[7:0]:mem[((bank==9)?7:bank)*512+k]);@(negedge clk);
   end
   card_valid=0;card_error=(bad_image&&bank==6);card_done=1;@(negedge clk);card_done=0;card_error=0;card_ready=1;
  end
 end
 task press(input bit back);begin
  @(negedge clk);prev_pulse=back;next_pulse=!back;@(negedge clk);prev_pulse=0;next_pulse=0;
 end endtask
 initial begin
  $readmemh("fixture.hex",mem,0,3583);
  if(FAST&&!BAD)begin
   // A third one-sector BMP makes reverse navigation compete against the
   // two-sector slot 0 prefetch after slot 2 becomes visible.
   for(k=0;k<32;k=k+1)mem[2*512+64+k]=mem[2*512+32+k];
   mem[2*512+64+4]="2";mem[2*512+64+26]=10;
   for(k=0;k<512;k=k+1)mem[7*512+k]=mem[6*512+k];
   for(k=0;k<6;k=k+1)mem[7*512+54+(k/3)*12+(k%3)*3+2]=mem[7*512+54+(k/3)*12+(k%3)*3+2]+128;
  end
  for(k=0;k<6;k=k+1)mem[6*512+54+(k/3)*12+(k%3)*3+2]=mem[6*512+54+(k/3)*12+(k%3)*3+2]+64;
  repeat(4)@(negedge pix);rst_n=1;
  wait(commits==1);wait(good_frames>=2);
  if(display_index!=0)$fatal(1,"initial display index");
  if(BAD)begin
   wait(image_done&&error);repeat(40)@(negedge clk);before_commit=commits;press(0);repeat(500)@(negedge clk);
   if(commits!=before_commit||display_index!=0)$fatal(1,"bad background image became visible");
   bad_image=0;press(1);repeat(20)@(negedge clk);press(0);wait(commits>before_commit);
  end else begin
   if(!LEGACY)begin wait(frame_prepared);repeat(1000)@(negedge clk);if(commits!=1||transition_active)$fatal(1,"prefetch auto-published");end
   start_cycle=cycles;start_requests=image_requests;press(0);wait(commits==2);#1;
   hit_cycles=cycles-start_cycle;hit_reads=request_at_commit-start_requests;
   if(display_index!=1 || (!LEGACY&&hit_reads!=0) || (LEGACY&&hit_reads<1))$fatal(1,"cache hit re-read SD / baseline did not load legacy=%0d shown=%0d reads=%0d total=%0d before=%0d",LEGACY,display_index,hit_reads,request_at_commit,start_requests);
   if(FAST)begin
    wait(frame_prepared);press(0);wait(commits==3);#1;
    if(display_index!=2)$fatal(1,"third picture did not become visible");
    // The real sector reader is busy with the two-sector next picture while
    // AUTO claims it. Manual left must replace it before the next data sector.
    pause=0;
    wait(card_start&&card_lba==3283);reverse_wait=1;
    wait(prefetched.control.foreground);#1;pause=1;
   end
   // Reverse during the first sector of the unrelated two-sector prefetch.
   start_cycle=cycles;start_requests=image_requests;press(1);wait(commits==(FAST?4:3));#1;
   cold_cycles=cycles-start_cycle;cold_reads=request_at_commit-start_requests;
   if(display_index!=(FAST?1:0))$fatal(1,"reverse miss wrong image");
   if(FAST&&cancelled!=1)$fatal(1,"reverse miss did not cancel the ongoing prefetch");
  end
  goal=good_frames+3;wait(good_frames>=goal);
  if(audio_sectors<6)$fatal(1,"audio concurrency not exercised");
  if(FAST?(animations!=0):(animations<1))$fatal(1,"wrong animation count for selected path");
  $display("PASS slide pipeline FAST=%0d BAD=%0d frames=%0d animations=%0d commits=%0d image_requests=%0d audio_sectors=%0d hit_cycles=%0d hit_reads=%0d cold_cycles=%0d cold_reads=%0d; real FAT/BMP/SDRAM, complete frames and both banks protected",FAST,BAD,good_frames,animations,commits,image_requests,audio_sectors,hit_cycles,hit_reads,cold_cycles,cold_reads);$finish;
 end
 initial begin #30000000;$fatal(1,"cache pipeline timeout commits=%0d requests=%0d good=%0d error=%b catalog=%b arbiter=%0d audio_busy=%b",commits,requests,good_frames,error,media.u_loader.catalog_ready,arbiter.state,audio_busy);end
endmodule
