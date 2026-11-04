`timescale 1ns/1ps
module tb_home_restart;
 reg clk=0,rst_n=0,mode_sw7=1,wav_idle=1,restart_audio=0,music_request=0;
 reg [1:0] music_index=0;wire [1:0] active_music_index;
 wire audio_flush_request,audio_flush_done,mode_change,product_mode,switching,wav_enable,controls_block;
 reg [1:0] ack=0;integer flushes=0,changes=0;reg old_flush=0;
 always #5 clk=~clk;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)ack<=0;else ack<={ack[0],audio_flush_request};
 assign audio_flush_done=ack[1];
 media_mode_control #(.DEBOUNCE_CYCLES(2),.MUSIC_SELECT(1),.HOME_UI(1)) dut(.*);
 always @(posedge clk)if(rst_n)begin
  if(audio_flush_request&&!wav_idle)$fatal(1,"restart aborted sector");
  if(audio_flush_request&&!old_flush)flushes<=flushes+1;
  old_flush<=audio_flush_request;if(mode_change)changes<=changes+1;
  if(wav_enable&&switching)$fatal(1,"restart enabled WAV before release");
 end
 always @(negedge clk)if($test$plusargs("TRACE"))$display("T %0t st=%0d restart=%b pending=%b req=%b want=%0d active=%0d ack=%b switching=%b",$time,dut.state,restart_audio,dut.restart_pending,music_request,dut.requested_music,active_music_index,audio_flush_done,switching);
 task ticks(input integer n);repeat(n)begin @(negedge clk);#1;end endtask
 task select_song(input [1:0] song);begin @(negedge clk);#1;music_index=song;music_request=1;restart_audio=1;ticks(1);music_request=0;restart_audio=0;ticks(1);end endtask
 integer before_flush;
 initial begin
  ticks(3);rst_n=1;wait(!switching);ticks(2);before_flush=flushes;
  wav_idle=0;select_song(0);ticks(20);
  if(!switching||audio_flush_request||flushes!=before_flush)$fatal(1,"same-song restart bypassed drain");
  wav_idle=1;wait(!switching);ticks(2);
  if(flushes!=before_flush+1||active_music_index!=0||changes!=0)$fatal(1,"same-song did not restart cleanly");
  wav_idle=0;select_song(1);select_song(3);select_song(2);ticks(5);wav_idle=1;
  wait(!switching);ticks(2);if(active_music_index!=2||changes!=0)$fatal(1,"latest album music did not win");
  // A new request coincident with completion must remain pending, not vanish.
  select_song(2);wait(audio_flush_done);select_song(1);wait(!switching);ticks(3);
  if(active_music_index!=1||changes!=0)$fatal(1,"flush-boundary request vanished");
  $display("PASS home audio restart: same-track restart, drain fence, latest track and flush-boundary request; flushes=%0d",flushes);$finish;
 end
 initial begin #1000000;$fatal(1,"home restart timeout");end
endmodule
