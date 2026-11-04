// DMZ-EG4S20: TF pictures plus 48 kHz stereo WAV/test tone.
// SW0 is low-active reset. SW1/SW2 use the existing low-active press pulses;
// put both UP before releasing reset. DMZ LEDs are active high.
// The board ADC allocates the physical LVDS negative pads.
module dmz_hdmi_media_top(
 input wire clk50,rst_n,key_next_n,key_pause_n,sd_miso,
 output wire sd_sck,sd_mosi,sd_cs,
 output wire hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p,
 output wire [3:0] led);
 wire sys_clk,pix_clk,ser_clk,locked;
 board_pll u_pll(.refclk(clk50),.reset(!rst_n),.extlock(locked),
  .clk0_out(pix_clk),.clk1_out(ser_clk),.clk2_out(sys_clk));
 wire reset_ok=rst_n&&locked;
 // Keep the original related-clock reset release phase and instance hierarchy.
 reg [3:0] release_pipe;
 always @(negedge pix_clk or negedge reset_ok)
  if(!reset_ok)release_pipe<=0;else release_pipe<={release_pipe[2:0],1'b1};
 wire core_rst_n=release_pipe[3];
 // The SPI consumer reads the old second-stage value on the same system edge.
 // The external return-path budget must be verified for the selected board/card.
 (* async_reg="true" *) reg miso1,miso2;
 always @(posedge sys_clk or negedge core_rst_n)
  if(!core_rst_n)begin miso1<=1;miso2<=1;end
  else begin miso1<=sd_miso;miso2<=miso1;end
 wire next_press,pause_press;reg paused;
 board_key kn(.clk(sys_clk),.rst_n(core_rst_n),.key_n(key_next_n),.press(next_press));
 board_key kp(.clk(sys_clk),.rst_n(core_rst_n),.key_n(key_pause_n),.press(pause_press));
 always @(posedge sys_clk or negedge core_rst_n)
  if(!core_rst_n)paused<=0;else if(pause_press)paused<=!paused;
 wire de,hs,vs,card_ready,card_error,mem_ready,mem_error,prefetch_error,underflow,loading,image_error;
 wire [23:0] rgb;wire [2:0] image_count;wire [1:0] image_index;
 wire wav_valid,wav_ready,wav_playing,wav_error,audio_urgent,video_started,catalog_ready,wav_found;
 wire [47:0] wav_data;
 wire [1:0] display_index;wire display_valid,audio_only;
 sd_media_player u_player(.clk(sys_clk),.pix_clk(pix_clk),.rst_n(core_rst_n),.prev_pulse(1'b0),
  .sd_miso(miso2),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_cs(sd_cs),
  .next_pulse(next_press),.pause(paused),.de(de),.hsync(hs),.vsync(vs),.rgb(rgb),
  .card_ready(card_ready),.card_error(card_error),.sdram_ready(mem_ready),.memory_fault(mem_error),
  .prefetch_error(prefetch_error),.frame_underflow(underflow),.loading(loading),.image_error(image_error),
  .image_count(image_count),.image_index(image_index),
  .wav_valid(wav_valid),.wav_ready(wav_ready),.wav_data(wav_data),.wav_playing(wav_playing),
  .wav_error(wav_error),.audio_urgent(audio_urgent),.video_started(video_started),
  .catalog_ready(catalog_ready),.wav_found(wav_found),
  .display_index(display_index),.display_valid(display_valid),.audio_only(audio_only));
 wire [9:0] tr,tg,tb;
 wire audio_fault;
 hdmi_av_output av(.sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(core_rst_n),
  .audio_enable(!paused),.tone_sel(3'd2),
  .image_count(image_count),.image_index(display_index),.image_valid(display_valid),.audio_only(audio_only),
  .wav_valid(wav_valid),.wav_ready(wav_ready),.wav_data(wav_data),.wav_playing(wav_playing),
  .video_started(video_started),.catalog_ready(catalog_ready),.wav_found(wav_found),.wav_error(wav_error),
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.red(tr),.green(tg),.blue(tb),
  .audio_fault(audio_fault),.audio_urgent(audio_urgent));
 tmds_ddr_tx tx(.pix_clk(pix_clk),.ser_clk(ser_clk),.rst_n(core_rst_n),
  .red(tr),.green(tg),.blue(tb),.clk_p(hdmi_clk_p),
  .d0_p(hdmi_d0_p),.d1_p(hdmi_d1_p),.d2_p(hdmi_d2_p));
 assign led={card_error|mem_error|prefetch_error|underflow|image_error|wav_error|audio_fault,
  loading,card_ready,mem_ready};
endmodule
