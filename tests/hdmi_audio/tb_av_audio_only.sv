`timescale 1ns/1ps
module tb_av_audio_only;
 reg sys=0,pix=0,rst_n=0,allow=0,enable=1,wvalid=0,build_tick=0;
 wire ready,fault;reg [47:0] data=0;integer reads=0,i;
 always #10 sys=~sys;always #20 pix=~pix;
 hdmi_av_output dut(.brightness(9'sd0),.gain_q8(9'd256),.loading(1'b0),.fade_enabled(1'b0),.wave_enabled(1'b0),.sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),
  .audio_only(allow),.image_valid(1'b0),.video_started(1'b0),
  .audio_enable(enable),.tone_sel(3'd2),.catalog_ready(1'b1),.wav_found(1'b1),.wav_error(1'b0),
  .image_count(3'd0),.image_index(2'd0),.wav_valid(wvalid),.wav_playing(1'b1),
  .wav_data(data),.wav_ready(ready),.de(1'b0),.hsync(1'b1),.vsync(1'b1),.rgb(24'd0),
  .red(),.green(),.blue(),.audio_fault(fault),.audio_urgent());
 // 加速包构建请求；仍经过真实 FIFO、包取样状态机和欠载判断。
 initial begin force dut.build=build_tick;end
 always begin repeat(20)@(negedge pix);build_tick=1;@(negedge pix);build_tick=0;end
 always @(posedge pix)if(rst_n && dut.fifo_read)reads=reads+1;
 initial begin
  repeat(4)@(negedge sys);rst_n=1;
  repeat(100)@(negedge pix);
  if(fault || reads!=0)$fatal(1,"startup falsely flagged or consumed audio");
  for(i=0;i<1100;i=i+1)begin
   @(negedge sys);wvalid=1;data=i;
   if(!ready)$fatal(1,"unexpected producer backpressure");
  end
  @(negedge sys);wvalid=0;
  repeat(100)@(negedge pix);
  if(reads!=0 || fault)$fatal(1,"first-frame wait not preserved");
  @(negedge sys);allow=1;enable=0;
  repeat(100)@(negedge pix);
  if(reads!=0 || fault)$fatal(1,"pause consumed audio or reported underrun");
  @(negedge sys);enable=1;
  wait(reads==1100);repeat(100)@(negedge pix);
  if(!dut.audio_underflow || !fault)$fatal(1,"real underrun not reported");
  @(negedge sys);rst_n=0;repeat(4)@(negedge pix);
  if(fault)$fatal(1,"reset did not clear underrun");
  $display("PASS audio-only startup, first-frame wait, pause and latched underrun");$finish;
 end
 initial begin #2000000;$fatal(1,"audio-only timeout reads=%0d",reads);end
endmodule
