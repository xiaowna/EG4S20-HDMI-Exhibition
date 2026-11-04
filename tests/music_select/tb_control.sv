`timescale 1ns/1ps
module tb_music_control;
 reg clk=0,rst_n=0;reg [3:0] key_press=0;reg [2:0] music_count=4;
 reg wav_idle=1;reg [1:0] ack=0;
 wire audio_flush_done=ack[1];
 wire product_mode,switching,wav_enable,audio_flush_request,mode_change;
 wire music_page,cfg_music_request,setting_active;wire [1:0] cfg_music_index,active_music_index;
 wire [1:0] setting_page;wire signed [8:0] cfg_value;wire [8:0] cfg_gain_q8;
 wire cfg_fade_enabled,cfg_wave_enabled,cfg_update,cfg_autoplay,autoplay_page,next_event,prev_event,pause_event;
 integer requests=0,changes=0,checks=0;reg [1:0] previous_index=0;
 always #5 clk=~clk;
 always @(posedge clk or negedge rst_n)if(!rst_n)ack<=0;else ack<={ack[0],audio_flush_request};
 media_mode_control #(.DEBOUNCE_CYCLES(2),.MUSIC_SELECT(1)) fence(
  .clk(clk),.rst_n(rst_n),.mode_sw7(1'b1),.wav_idle(wav_idle),.audio_flush_done(audio_flush_done),
  .product_mode(product_mode),.switching(switching),.wav_enable(wav_enable),.audio_flush_request(audio_flush_request),
  .mode_change(mode_change),.music_request(cfg_music_request),.music_index(cfg_music_index),.active_music_index(active_music_index));
 media_adjust_control #(.AUTOPLAY_MENU(1),.MUSIC_MENU(1)) menu(.home_play(1'b0),.home_music_index(2'd0),.frame_tick(1'b0),.held_key_n(4'hf),.contrast_index(),.*,.rtc_page(),.rtc_exit(1'b0));
 always @(posedge clk)if(rst_n)begin
  if(cfg_music_request)requests=requests+1;
  if(mode_change)changes=changes+1;
  if(audio_flush_request&&!wav_idle)$fatal(1,"music flush before sector/CRC retirement");
  if(wav_enable&&(switching||!product_mode))$fatal(1,"music enabled before flush/release");
  #1;if(active_music_index!=previous_index)begin
   if(!audio_flush_done || wav_enable)$fatal(1,"music metadata changed before FIFO flush");
   previous_index=active_music_index;
  end
 end
 task ticks(input integer n);repeat(n)begin @(negedge clk);#1;end endtask
 task press(input [3:0] p);begin key_press=p;ticks(1);key_press=0;ticks(1);end endtask
 task settled;begin wait(!switching);ticks(2);checks=checks+1;end endtask
 integer old_requests;
 initial begin
  ticks(3);rst_n=1;settled;
  press(8);repeat(5)press(2);if(!music_page)$fatal(1,"music item unreachable by existing four keys");
  for(integer j=1;j<=4;j=j+1)begin
   press(1);settled;if(active_music_index!=(j%4)||cfg_music_index!=(j%4)||!music_page)$fatal(1,"next song wrap/focus");
  end
  press(4);settled;if(active_music_index!=3)$fatal(1,"previous song wrap");
  // Latest direction while the old card owner has not completed must win.
  wav_idle=0;press(1);ticks(10);
  if(!switching || audio_flush_request || active_music_index!=3)$fatal(1,"bypassed old WAV drain");
  press(1);press(1);press(4);wav_idle=1;settled;
  if(active_music_index!=1 || !music_page || cfg_value!=0 || cfg_gain_q8!=256 || cfg_autoplay)
   $fatal(1,"coalescing changed unrelated settings or selected obsolete song");
  if(changes!=0)$fatal(1,"song changes masqueraded as SW7 changes");
  press(2);if(setting_active)$fatal(1,"OK did not leave last menu item");
  for(integer count=0;count<=1;count=count+1)begin
   rst_n=0;ticks(3);music_count=count;rst_n=1;previous_index=0;settled;
   press(8);repeat(5)press(2);old_requests=requests;
   press(1);press(4);ticks(5);
   if(requests!=old_requests || cfg_music_index!=0)$fatal(1,"empty/single-song menu requested invalid index");
  end
  $display("PASS music control: 4-song wraps, queued latest, drain/flush/release, preserved focus/settings, empty/single files checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"music control timeout");end
endmodule
