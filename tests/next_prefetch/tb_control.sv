`timescale 1ns/1ps
// Real buffer manager, delayed loader and write draining. The scoreboards use
// accepted memory words and committed identities, not controller state names.
module tb_prefetch_control;
 parameter integer COUNT=4,INTERVAL=257;
 reg clk=0,rst_n=0,card_ready=0,scan_done=0,error=0,pause=1,next_pulse=0,prev_pulse=0;
 reg [2:0] image_count=COUNT;
 wire scan_start,load_start,commit_enable,discard_cached,transition_active;
 wire transition_manual,transition_backward;
 wire [1:0] image_index;
 reg [1:0] display_index=0,loaded_index=0;
 wire front_valid,front_bank,frame_committed,frame_rejected,frame_prepared,frame_ready;
 reg busy=0,frame_start=0,image_done=0,pixel_valid=0;
 reg [31:0] pixel_addr=0;
 wire pixel_ready,wr_valid;
 wire [31:0] wr_addr,wr_data;
 integer cycles=0,load_count=0,commits=0,discards=0,rejects=0,writes=0,drain=0;
 integer loader_state=0,delay_count=0,fade_ticks=0,fail_slot=-1,failed_loads=0;
 reg fail_load=0,hold_fade=0;
 reg previous_commit_enable=0;
 wire transition_ready=transition_active && !hold_fade && fade_ticks>=3;
 wire load_ready=frame_ready&&!busy;
 wire wr_ready=(cycles%3!=0);
 wire [23:0] pixel_rgb={22'd0,loaded_index}+{pixel_addr[21:0],2'b00};
 reg [31:0] memory[0:11];
 reg [1:0] committed_log[0:127];
 reg [1:0] last_index=0;
 integer i,before_load,before_commit,start_cycle,latency=0;
 always #5 clk=~clk;
 always @(negedge clk)if($test$plusargs("TRACE") &&
  (load_start||next_pulse||prev_pulse||frame_committed||frame_prepared))
  $display("TRACE cycle=%0d state=%0d cursor=%0d fg=%b pending=%b prev=%b next=%b index=%0d shown=%0d ready=%b hold=%b commits=%0d",cycles,control.state,control.cursor,control.foreground,control.pending_request,prev_pulse,next_pulse,image_index,display_index,transition_ready,hold_fade,commits);
 media_prefetch_control #(.INTERVAL_CYCLES(INTERVAL)) control(.prefetch_enable(1'b1),.preparing(),.prepare_progress_valid(),.album_request(1'b0),.album_enable(1'b0),.album_first('0),.album_limit('0),.album_ready(),.album_error(),.auto_enable(1'b1),.*);
 frame_buffer_manager #(.FRAME_PIXELS(6),.ALLOW_DISCARD(1)) frame(
  .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.frame_done(image_done),.frame_error(error),
  .frame_ready(frame_ready),.pixel_valid(pixel_valid),.pixel_addr(pixel_addr),
  .pixel_rgb(pixel_rgb),.pixel_ready(pixel_ready),
  .wr_valid(wr_valid),.wr_addr(wr_addr),.wr_data(wr_data),.wr_ready(wr_ready),.wr_drained(drain==0),
  .swap_window((cycles%17==0)&&commit_enable),.front_valid(front_valid),.front_bank(front_bank),
  .frame_committed(frame_committed),.frame_rejected(frame_rejected),.swap_pending(frame_prepared),
  .discard_frame(discard_cached),.read_valid(1'b0),.read_addr(32'd0),.rgb_ready(1'b1),
  .mem_read_ready(1'b0),.mem_response_valid(1'b0),.mem_response_data(32'd0));
 always @(posedge clk)begin
  cycles<=cycles+1;
  previous_commit_enable<=commit_enable;
  if(!rst_n)begin
   busy<=0;frame_start<=0;image_done<=0;pixel_valid<=0;error<=0;
   loader_state<=0;pixel_addr<=0;drain<=0;display_index<=0;fade_ticks<=0;
  end else begin
   frame_start<=0;image_done<=0;
   if(transition_active)fade_ticks<=fade_ticks+1;else fade_ticks<=0;
   if(drain>0)drain<=drain-1;
   if(wr_valid&&wr_ready)begin
    if(front_valid && wr_addr/6==front_bank)$fatal(1,"write overwrote visible bank");
    memory[wr_addr]<=wr_data;writes<=writes+1;drain<=9;
   end
   if(load_start)begin
    if(!load_ready || image_index>=COUNT)$fatal(1,"bad/overlapping load");
    busy<=1;frame_start<=1;loaded_index<=image_index;fail_load<=image_index==fail_slot;
    load_count<=load_count+1;delay_count<=25;loader_state<=1;pixel_addr<=0;
   end
   case(loader_state)
    1:if(delay_count==0)begin pixel_valid<=1;loader_state<=2;end else delay_count<=delay_count-1;
    2:if(pixel_valid&&pixel_ready)begin
     if(pixel_addr==5)begin pixel_valid<=0;loader_state<=3;end else pixel_addr<=pixel_addr+1;
    end
    3:begin image_done<=1;error<=fail_load;busy<=0;loader_state<=0;if(fail_load)failed_loads<=failed_loads+1;end
   endcase
   if(frame_committed)begin
    if(!previous_commit_enable || drain!=0)$fatal(1,"commit without authorization/drain");
    display_index<=loaded_index;committed_log[commits]<=loaded_index;commits<=commits+1;
    for(integer k=0;k<6;k=k+1)
     if(memory[front_bank*6+k]!==loaded_index+k*4)$fatal(1,"incomplete/wrong committed memory");
   end
   if(frame_rejected)rejects<=rejects+1;
   if(discard_cached&&frame_prepared)discards<=discards+1;
   if(transition_active && !frame_prepared && !frame_committed)$fatal(1,"fade before prepared");
  end
 end
 task tick(input integer n);begin repeat(n)@(negedge clk);#1;end endtask
 task press(input bit back);begin @(negedge clk);#1;prev_pulse=back;next_pulse=!back;tick(1);prev_pulse=0;next_pulse=0;end endtask
 task committed(input integer expected,input integer old_count);begin
  wait(commits>old_count);tick(1);
  if(display_index!==expected || committed_log[old_count]!==expected)
   $fatal(1,"wrong commit expected=%0d got=%0d",expected,display_index);
 end endtask
 initial begin
  tick(3);rst_n=1;tick(8);if(scan_start||load_start)$fatal(1,"started without card");
  card_ready=1;wait(scan_start);tick(1);
  if(COUNT>1)begin
   // Retry bad, empty, and over-capacity catalogs without issuing a load.
   image_count=(COUNT==2)?5:0;error=(COUNT==4);scan_done=1;tick(1);scan_done=0;
   tick(12);if(load_count!=0)$fatal(1,"loaded an invalid catalog");
   wait(scan_start);tick(1);image_count=COUNT;error=0;
  end
  scan_done=1;tick(1);scan_done=0;
  committed(0,0);
  if(COUNT==1)begin
   tick(INTERVAL*2);before_load=load_count;press(0);tick(30);press(1);tick(30);
   if(load_count!=before_load || commits!=1)$fatal(1,"single image reloaded");
  end else begin
   wait(frame_prepared);tick(INTERVAL*2);
   if(commits!=1 || load_count!=2 || transition_active)$fatal(1,"background preload displayed/dimmed while paused");
   before_load=load_count;start_cycle=cycles;press(0);committed(1,1);latency=cycles-start_cycle;
   if(latency>32)$fatal(1,"cache hit waited for file I/O");
   // Immediately reverse during the next background load. For 3/4 pictures
   // that cache is the wrong target and must be drained/discarded first.
   before_commit=commits;press(1);committed(0,before_commit);
   if(COUNT>2 && discards==0)$fatal(1,"reverse miss never discarded wrong cache");
   wait(frame_prepared);hold_fade=1;before_commit=commits;press(0);wait(transition_active);tick(60);
   if(commits!=before_commit || display_index!=0)$fatal(1,"ignored fade acknowledgement");
   // Coalesced commands during the foreground operation: latest direction.
   if(!transition_manual || transition_backward)$fatal(1,"manual next classified incorrectly");
   press(0);press(1);
   if(!transition_manual || transition_backward)$fatal(1,"queued reverse changed current slide direction");
   hold_fade=0;committed(1,before_commit);
   wait(!transition_active);wait(transition_active);#1;
   if(!transition_manual || !transition_backward)$fatal(1,"queued reverse lost slide direction");
   committed(0,before_commit+1);
   // Reset to make the bad-next test independent of the in-flight load edge.
   rst_n=0;tick(3);rst_n=1;fail_slot=1;image_count=COUNT;card_ready=1;
   wait(scan_start);tick(1);scan_done=1;tick(1);scan_done=0;
   before_commit=commits;committed(0,before_commit);wait(failed_loads>0);tick(30);
   before_commit=commits;press(0);tick(70);
   if(commits!=before_commit || display_index!=0)$fatal(1,"bad cache replaced good frame");
   fail_slot=-1;
   if(COUNT>2)begin press(0);committed(2,before_commit);end
   else begin press(0);tick(30);if(display_index!=0)$fatal(1,"bad-file cursor did not wrap to visible frame");end
   pause=0;before_commit=commits;wait(transition_active);#1;
   if(transition_manual || transition_backward)$fatal(1,"automatic request classified as manual slide");
   wait(commits>before_commit);pause=1;tick(5);
   before_commit=commits;tick(INTERVAL*2);
   if(commits!=before_commit)$fatal(1,"paused autoplay advanced");
  end
  $display("PASS next-cache control COUNT=%0d INTERVAL=%0d loads=%0d commits=%0d discards=%0d rejects=%0d writes=%0d hit_cycles=%0d",COUNT,INTERVAL,load_count,commits,discards,rejects,writes,latency);$finish;
 end
 initial begin #2000000;$fatal(1,"cache control timeout count=%0d state=%0d index=%0d shown=%0d commits=%0d",COUNT,control.state,image_index,display_index,commits);end
endmodule
