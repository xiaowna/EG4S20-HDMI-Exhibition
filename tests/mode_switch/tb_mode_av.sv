`timescale 1ns/1ps
module tb_mode_av;
 reg sys_clk=0,pix_clk=0,rst_n=1,mode_sw7=1,wav_idle=1,paused=0;
 wire product_mode,switching,wav_enable,audio_flush_request,audio_flush_done,mode_change;
 wire wav_ready,audio_fault,audio_urgent;
 wire [9:0] red,green,blue;
 reg [9:0] x=0,y=0;
 wire de=x<640&&y<480,hsync=!(x>=656&&x<752),vsync=!(y>=490&&y<492);
 reg [15:0] sample_index=0;
 reg [3:0] session=0;
 wire [47:0] wav_data={4'ha,session,sample_index,4'h5,session,sample_index};
 reg [223:0] captured_audio_body;
 reg [23:0] captured_audio_header;
 // Observe the encoder's public input handshake; its private payload
 // registers may be reused while BCH is calculated.
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)begin captured_audio_body<=0;captured_audio_header<=0;end
  else if(dut.packet_valid&&dut.ar)begin
   captured_audio_body<=dut.ab;captured_audio_header<=dut.ah;
  end
 reg [47:0] expected[0:65535];
 integer head=0,tail=0,reads=0,writes=0,tone_writes=0,wav_packets=0,tone_packets=0,commits=0,k,t;
 always #10 sys_clk=~sys_clk;
 always #20 pix_clk=~pix_clk;
 always @(posedge pix_clk)begin
  if(!rst_n)begin x<=0;y<=0;end
  else if(x==799)begin x<=0;y<=y==524?0:y+1'b1;end
  else x<=x+1'b1;
 end
 media_mode_control #(.DEBOUNCE_CYCLES(3)) control(.restart_audio(1'b0),.clk(sys_clk),.music_request(1'b0),.music_index(2'd0),.active_music_index(),.controls_block(),.*);
 hdmi_av_output #(.SETTINGS_UI(1),.MODE_CONTROL(1)) dut(
  .sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.audio_enable(!switching&&!paused),
  .tone_sel(3'd2),.video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b1),.wav_error(1'b0),
  .audio_only(1'b0),.image_valid(1'b1),.image_count(3'd4),.image_index(2'd0),
  .wav_valid(wav_enable),.wav_playing(wav_enable),.wav_data(wav_data),.wav_ready(wav_ready),
  .de(de),.hsync(hsync),.vsync(vsync),.rgb(24'h315a82),.brightness(9'sd0),.gain_q8(9'd256),
  .loading(1'b0),.fade_enabled(1'b0),.wave_enabled(1'b0),.settings_word(11'd0),
  .red(red),.green(green),.blue(blue),.audio_fault(audio_fault),.audio_urgent(audio_urgent),
  .transition_ready(),.force_tone(!product_mode),.audio_flush_request(audio_flush_request),
  .audio_flush_done(audio_flush_done),.mode_status({switching,product_mode,1'b0,!product_mode&&!switching}));
 always @(negedge dut.fifo_rst_n)begin head=0;tail=0;end
 always @(posedge sys_clk)if(rst_n)begin
  if(mode_change)begin session<=session+1'b1;sample_index<=0;commits=commits+1;paused<=0;end
  else if(wav_enable&&wav_ready)sample_index<=sample_index+1'b1;
  if(dut.fifo.wr_en&&!dut.fifo.wr_full)begin
   expected[tail]=dut.fifo.wr_data;tail=tail+1;writes=writes+1;
   if(product_mode)begin
    if(dut.fifo.wr_data!==wav_data)$fatal(1,"product selected wrong source");
   end else begin
    if(dut.use_wav || wav_ready || dut.fifo.wr_data!=={dut.sample_left,dut.sample_right})$fatal(1,"demo accepted WAV despite force-tone");
    tone_writes=tone_writes+1;
   end
  end
 end
 reg [47:0] expected_read;
 always @(posedge pix_clk)if(rst_n)begin
  if(dut.fifo_read)begin
   if(head>=tail)$fatal(1,"FIFO read without matching source write");
   expected_read=expected[head];head=head+1;reads=reads+1;
   #1;if(dut.fifo_data!==expected_read)$fatal(1,"FIFO source order crossed flush");
  end
  if(audio_fault)$fatal(1,"mode change caused HDMI/audio fault");
  if(dut.island&&dut.phase==10)begin
   for(integer slot=0;slot<2;slot=slot+1)begin
    if(captured_audio_header[8+slot] && captured_audio_body[slot*56 +: 48]!=0)begin
     if(product_mode)begin
      if(captured_audio_body[slot*56+16 +: 8]!=={4'ha,session} ||
         captured_audio_body[slot*56+40 +: 8]!=={4'h5,session})$fatal(1,"old source reached a new product HDMI packet");
      wav_packets=wav_packets+1;
     end else begin
      if(captured_audio_body[slot*56+20 +: 4]===4'ha)$fatal(1,"old WAV reached demo HDMI output");
      tone_packets=tone_packets+1;
     end
    end
   end
  end
 end
 task sys_ticks(input integer n);begin repeat(n)@(negedge sys_clk);#1;end endtask
 task pix_ticks(input integer n);begin repeat(n)@(negedge pix_clk);#1;end endtask
 task await_mode(input bit value);integer timeout;begin
  timeout=0;
  while(switching||product_mode!==value)begin pix_ticks(1);timeout=timeout+1;if(timeout>1800)$fatal(1,"packet-boundary mode switch stalled");end
 end endtask
 task seek_phase(input integer phase);integer timeout;begin
  timeout=0;
  while((phase==0&&dut.packets.state!=1)||(phase==1&&dut.packets.state!=2)||
        (phase==2&&!dut.ap)||(phase==3&&!dut.av))begin
   pix_ticks(1);timeout=timeout+1;if(timeout>1800)$fatal(1,"requested packet phase not reached");
  end
 end endtask
 initial begin
  #1;rst_n=0;sys_ticks(5);rst_n=1;await_mode(1);pix_ticks(800*4);
  if(wav_packets<2)$fatal(1,"product WAV never reached HDMI");
  for(k=0;k<4;k=k+1)begin
   seek_phase(k);wav_idle=0;mode_sw7=0;sys_ticks(20);
   if(!switching||audio_flush_request)$fatal(1,"WAV transaction was not drained before flush");
   sys_ticks(100);wav_idle=1;await_mode(0);
   if(k==0)begin
    // Actual 50MHz/48kHz tone generation and 1024-sample prefill, without
    // accelerating or changing the production clock/sample-rate constants.
    t=0;while(tone_packets<4)begin pix_ticks(1);t=t+1;if(t>600000)$fatal(1,"forced demo tone did not prime and reach HDMI");end
   end else pix_ticks(800*2);
   seek_phase(3);mode_sw7=1;await_mode(1);pix_ticks(800*4);
  end
  paused=1;sys_ticks(30);mode_sw7=0;await_mode(0);
  if(paused)$fatal(1,"mode entry retained pause");
  if(writes<4000 || tone_writes<1024 || wav_packets<10 || tone_packets<4 || commits!=10)$fatal(1,"mode AV coverage incomplete");
  $display("PASS mode_av: real 800x525 HDMI, both sources, 1024-sample 48kHz tone prefill, READ/CAPTURE/READY/SEND switching, no stale encoded PCM, writes=%0d reads=%0d tone_writes=%0d WAV_samples=%0d tone_samples=%0d commits=%0d",writes,reads,tone_writes,wav_packets,tone_packets,commits);$finish;
 end
 initial begin #100000000;$fatal(1,"mode AV timeout");end
endmodule
