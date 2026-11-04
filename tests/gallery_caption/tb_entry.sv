`timescale 1ns/1ps
module tb_gallery_cache_entry;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg card_ready=1,load_ready=1,scan_done=0,image_done=0,error=0,prefetch_enable=0;
 reg [4:0] display_index=0,album_first=0;
 reg [4:0] image_count=24,album_limit=6;
 reg front_valid=0,frame_prepared=0,frame_committed=0,album_request=0;
 wire scan_start,load_start,commit_enable,discard_cached,transition_active;
 wire transition_manual,transition_backward,album_ready,album_error,preparing,prepare_progress_valid;
 wire [4:0] image_index;
 integer starts=0,discards=0,prior_starts,prior_discards;
 media_prefetch_control #(.ALBUMS(1),.MAX_IMAGES(24),.CONTROLLED_AUTOPLAY(1),.CONTROLLED_PREFETCH(1),.INTERVAL_CYCLES(100000)) dut(
  .prefetch_enable(prefetch_enable),
  .clk(clk),.rst_n(rst_n),.card_ready(card_ready),.load_ready(load_ready),
  .scan_done(scan_done),.image_done(image_done),.error(error),.image_count(image_count),
  .next_pulse(1'b0),.prev_pulse(1'b0),.pause(1'b0),.front_valid(front_valid),.display_index(display_index),
  .frame_prepared(frame_prepared),.frame_committed(frame_committed),.transition_ready(transition_active),
  .scan_start(scan_start),.load_start(load_start),.image_index(image_index),.commit_enable(commit_enable),
  .discard_cached(discard_cached),.transition_active(transition_active),.auto_enable(1'b0),
  .transition_manual(transition_manual),.transition_backward(transition_backward),
  .album_request(album_request),.album_enable(1'b1),.album_first(album_first),.album_limit(album_limit),
  .album_ready(album_ready),.album_error(album_error),.preparing(preparing),.prepare_progress_valid(prepare_progress_valid));
 always @(posedge clk)if(rst_n)begin
  if(load_start)starts=starts+1;
  if(discard_cached)discards=discards+1;
 end
 task tick;begin @(negedge clk);#1;end endtask
 task request_album(input integer first_value,input integer end_value);
  begin tick;album_first=first_value;album_limit=end_value;album_request=1;tick;album_request=0;end
 endtask
 task finish_image(input integer bad);
  begin tick;error=bad;image_done=1;frame_prepared=!bad;load_ready=bad;tick;image_done=0;end
 endtask
 task commit_image(input integer number);
  begin wait(commit_enable);tick;front_valid=1;display_index=number;frame_committed=1;
   frame_prepared=0;load_ready=1;tick;frame_committed=0;end
 endtask
 initial begin
  repeat(3)tick;rst_n=1;wait(scan_start);tick;scan_done=1;tick;scan_done=0;
  wait(load_start);if(image_index!=0)$fatal(1,"cold first image wrong");load_ready=0;
  finish_image(0);commit_image(0);
  repeat(20)begin tick;if(load_start||starts!=1)$fatal(1,"home started an unwanted background file");end
  prefetch_enable=1;
  wait(load_start);if(image_index!=1)$fatal(1,"next image not prefetched");load_ready=0;
  repeat(2)tick;prior_starts=starts;prior_discards=discards;
  request_album(0,6);
  if(!album_ready||album_error||preparing)$fatal(1,"validated front cache not acknowledged immediately");
  repeat(20)begin tick;
   if(starts!=prior_starts||discards!=prior_discards||commit_enable||transition_active||image_index!=1)
    $fatal(1,"front cache hit restarted/discarded background transaction starts=%0d prior=%0d discards=%0d prior=%0d commit=%b transition=%b index=%0d",starts,prior_starts,discards,prior_discards,commit_enable,transition_active,image_index);
  end
  finish_image(0);wait(dut.state==6);prior_starts=starts;prior_discards=discards;
  request_album(1,7);wait(commit_enable);
  if(starts!=prior_starts||discards!=prior_discards||image_index!=1)
   $fatal(1,"validated back cache was needlessly reloaded");
  commit_image(1);wait(load_start);load_ready=0;
  request_album(24,30);if(!album_error||album_ready)$fatal(1,"invalid album accepted");
  prior_starts=starts;request_album(6,12);
  repeat(15)begin tick;if(album_ready||starts!=prior_starts||discard_cached)$fatal(1,"uncached request aborted in-flight load");end
  finish_image(0);wait(discard_cached);tick;frame_prepared=0;load_ready=1;
  wait(load_start);if(image_index!=6)$fatal(1,"cache miss did not load requested first image");
  load_ready=0;finish_image(1);wait(album_error);
  if(album_ready||display_index!=1||!front_valid)$fatal(1,"failed first image published over valid front");
  $display("PASS gallery entry cache: front hit during background load, back hit without reload, invalid range, safe miss drain and failed-load retention");
  $finish;
 end
 initial begin #100000;$fatal(1,"cache entry timeout state=%0d starts=%0d",dut.state,starts);end
endmodule

module tb_gallery_home_speed;
 reg clk=0,rst_n=0,vsync=1,switching=0,album_ready=0,home_request=0;
 reg [3:0] key_press=0;
 wire visible,starting,view_active,play_request,autoplay_request;
 wire [2:0] index;wire [14:0] home_word;
 integer frames=0;
 always #5 clk=~clk;
 media_home_control #(.VIEW_3D(1),.EXHIBIT(0)) dut(
  .clk(clk),.rst_n(rst_n),.vsync(vsync),.product_mode(1'b1),.mode_change(1'b0),
  .setting_active(1'b0),.home_request(home_request),.key_press(key_press),.catalog_ready(1'b1),
  .image_count(6'd24),.first_image(5'd0),.image_limit(6'd6),.switching(switching),
  .album_ready(album_ready),.album_error(1'b0),.view_ready(1'b1),.view_active(view_active),
  .visible(visible),.starting(starting),.index(index),.home_word(home_word),
  .play_request(play_request),.autoplay_request(autoplay_request));
 task tick;begin @(negedge clk);#1;end endtask
 task frame;begin vsync=0;repeat(5)tick;vsync=1;repeat(5)tick;end endtask
 initial begin
  repeat(3)tick;rst_n=1;tick;key_press=2;tick;key_press=0;album_ready=1;
  repeat(8)tick;if(!visible||dut.state!=1)$fatal(1,"opened before music handoff acknowledgement");
  switching=1;repeat(4)tick;switching=0;wait(autoplay_request);tick;
  while(visible)begin frame;frames=frames+1;if(frames>6)$fatal(1,"entry animation remains unnecessarily slow");end
  if(frames!=6)$fatal(1,"entry duration not six complete frames: %0d",frames);
  home_request=1;tick;home_request=0;tick;key_press=1;tick;key_press=0;
  repeat(18)begin frame;if(index!=0)$fatal(1,"home carousel changed timing");end
  frame;if(index!=1)$fatal(1,"home carousel did not finish at original19frames");
  $display("PASS home entry6frames=100.8ms; music acknowledgement retained; carousel19frames unchanged");$finish;
 end
 initial begin #100000;$fatal(1,"home speed timeout");end
endmodule
