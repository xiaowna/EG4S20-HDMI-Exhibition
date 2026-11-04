`timescale 1ns/1ps
module tb_mode_control;
 parameter integer COUNT=7;
 reg clk=0,rst_n=1,mode_sw7=0,wav_idle=1;
 reg [1:0] ack=0;
 wire audio_flush_done=ack[1];
 wire product_mode,switching,wav_enable,audio_flush_request,mode_change;
 integer changes=0,cycles=0,last_change=-10;
 always #5 clk=~clk;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)ack<=0;else ack<={ack[0],audio_flush_request};
 media_mode_control #(.DEBOUNCE_CYCLES(COUNT)) dut(.restart_audio(1'b0),.music_request(1'b0),.music_index(2'd0),.active_music_index(),.controls_block(),.*);
 always @(posedge clk)if(rst_n)begin
  cycles=cycles+1;
  if(wav_enable!==(product_mode&&!switching))$fatal(1,"source enabled during switch");
  if(audio_flush_request&&!wav_idle)$fatal(1,"flush before WAV transaction drained");
  if(mode_change)begin
   if(!audio_flush_done || !switching || cycles-last_change<3)$fatal(1,"unsafe or repeated mode commit");
   changes=changes+1;last_change=cycles;
  end
 end
 task ticks(input integer n);begin repeat(n)@(negedge clk);#1;end endtask
 task await_mode(input bit value);integer timeout;begin
  timeout=0;
  while(switching || product_mode!==value)begin
   ticks(1);timeout=timeout+1;if(timeout>COUNT+100)$fatal(1,"mode did not settle");
  end
 end endtask
 integer previous_changes;
 initial begin
  #1;rst_n=0;ticks(3);rst_n=1;
  if(!switching || wav_enable)$fatal(1,"boot used assumed SW7 level");
  await_mode(0);
  mode_sw7=1;await_mode(1);
  previous_changes=changes;
  if(COUNT>=4)begin
   mode_sw7=0;ticks(COUNT/2);mode_sw7=1;ticks(COUNT+10);
   if(switching || changes!=previous_changes || !product_mode)$fatal(1,"short bounce changed mode");
  end
  wav_idle=0;mode_sw7=0;ticks(COUNT+10);
  if(!switching || !product_mode || audio_flush_request)$fatal(1,"WAV drain barrier bypassed");
  // Coalesce complete switch movements while the old sector is still active.
  mode_sw7=1;ticks(COUNT+10);mode_sw7=0;ticks(COUNT+10);
  wav_idle=1;await_mode(0);
  if(changes!=previous_changes+1)$fatal(1,"queued obsolete switch movements");
  mode_sw7=1;await_mode(1);
  wav_idle=0;mode_sw7=0;ticks(COUNT+10);
  rst_n=0;#1;if(wav_enable||audio_flush_request)$fatal(1,"async reset did not stop switch");
  ticks(2);wav_idle=1;mode_sw7=1;rst_n=1;await_mode(1);
  $display("PASS mode_control COUNT=%0d: both boot levels, debounce, drain, coalescing and reset; commits=%0d",COUNT,changes);$finish;
 end
 initial begin #200000000;$fatal(1,"mode controller timeout");end
endmodule
