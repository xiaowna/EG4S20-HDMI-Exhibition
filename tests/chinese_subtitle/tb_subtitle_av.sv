`timescale 1ns/1ps
module tb_subtitle_av;
 reg sys_clk=0,pix_clk=0,rst_n=0,start_raster=0;
 always #10 sys_clk=~sys_clk;
 always #20 pix_clk=~pix_clk;
 integer x=0,y=0,i,cycles=0,checks=0,caption_checks=0,reads=0;
 wire de=start_raster&&x<640&&y<480,hsync=!(x>=656&&x<752),vsync=!(y>=490&&y<492);
 wire [23:0] rgb={x[7:0],y[7:0],x[7:0]^y[7:0]};
 wire [9:0] red,green,blue,ref_red,ref_green,ref_blue;
 wire fault,ref_fault;
 reg [1:0] golden[0:4095];
 integer xx[0:10],yy[0:10];reg dd[0:10];
 reg [23:0] expected;integer tx,addr;
 hdmi_av_output #(.SETTINGS_UI(1),.MODE_CONTROL(1),.CHINESE_SUBTITLE(1)) dut(
  .sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.audio_enable(1'b1),.tone_sel(3'd2),
  .video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b0),.wav_error(1'b0),.audio_only(1'b0),.image_valid(1'b1),
  .image_count(3'd4),.image_index(2'd0),.wav_valid(1'b0),.wav_playing(1'b0),.wav_data(48'd0),.wav_ready(),
  .de(de),.hsync(hsync),.vsync(vsync),.rgb(rgb),.brightness(9'sd0),.gain_q8(9'd256),.loading(1'b0),
  .fade_enabled(1'b0),.wave_enabled(1'b0),.settings_word(11'd0),.transition_ready(),
  .force_tone(1'b1),.audio_flush_request(1'b0),.mode_status(4'b0001),.audio_flush_done(),
  .red(red),.green(green),.blue(blue),.audio_fault(fault),.audio_urgent());
 hdmi_av_output_reference #(.SETTINGS_UI(1),.MODE_CONTROL(1)) ref_dut(
  .sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.audio_enable(1'b1),.tone_sel(3'd2),
  .video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b0),.wav_error(1'b0),.audio_only(1'b0),.image_valid(1'b1),
  .image_count(3'd4),.image_index(2'd0),.wav_valid(1'b0),.wav_playing(1'b0),.wav_data(48'd0),.wav_ready(),
  .de(de),.hsync(hsync),.vsync(vsync),.rgb(rgb),.brightness(9'sd0),.gain_q8(9'd256),.loading(1'b0),
  .fade_enabled(1'b0),.wave_enabled(1'b0),.settings_word(11'd0),.transition_ready(),
  .force_tone(1'b1),.audio_flush_request(1'b0),.mode_status(4'b0001),.audio_flush_done(),
  .red(ref_red),.green(ref_green),.blue(ref_blue),.audio_fault(ref_fault),.audio_urgent());
 always @(posedge pix_clk)begin
  if(!rst_n||!start_raster)begin x<=0;y<=0;end
  else if(x==799)begin x<=0;if(y==524)y<=0;else y<=y+1;end else x<=x+1;
 end
 always @(posedge pix_clk)if(rst_n)begin
  for(i=10;i>0;i=i-1)begin xx[i]=xx[i-1];yy[i]=yy[i-1];dd[i]=dd[i-1];end
  xx[0]=x;yy[0]=y;dd[0]=de;
  cycles=cycles+1;
  if(cycles%100000==0)$display("PROGRESS Chinese AV cycles=%0d reads=%0d caption_pixels=%0d",cycles,reads,caption_checks);
  #1;
  if(cycles>100)begin
   if({dut.dp,dut.hp,dut.vp,dut.x,dut.island,dut.phase,dut.fifo_read,dut.sample_request}!==
      {ref_dut.dp,ref_dut.hp,ref_dut.vp,ref_dut.x,ref_dut.island,ref_dut.phase,ref_dut.fifo_read,ref_dut.sample_request})
    $fatal(1,"HDMI timing/audio schedule changed cycle=%0d",cycles);
   if(dut.fifo_read)reads=reads+1;
   // The frozen pre-V01 reference still dims its old y=32..63 caption bar.
   // Check the union of old and new header areas against the RGB/font oracle.
   if(dd[9]&&yy[9]<72)begin
    expected={xx[9][7:0],yy[9][7:0],xx[9][7:0]^yy[9][7:0]};
    tx=xx[9]+224-304;
    if(xx[9]>=16&&xx[9]<304&&yy[9]>=8&&yy[9]<24&&tx>=0&&tx<224)begin
     addr=(tx/16)*256+(yy[9]-8)*16+tx%16;
     if(golden[addr]==2)expected=24'he7efec;
     else if(golden[addr]==1)expected=24'h0b1420;
    end
    if(dut.pixels[9]!==expected)$fatal(1,"AV subtitle alignment xy=%0d,%0d expected=%h actual=%h",xx[9],yy[9],expected,dut.pixels[9]);
    caption_checks=caption_checks+1;
   end else if(dut.pixels[9]!==ref_dut.pixels[9])$fatal(1,"RGB outside caption changed xy=%0d,%0d",xx[9],yy[9]);
   // Every blanking symbol, including audio islands/guards, remains exact.
   if(!dd[10]&&{red,green,blue}!=={ref_red,ref_green,ref_blue})$fatal(1,"HDMI blanking symbol changed");
   checks=checks+1;
  end
 end
 initial begin
  $readmemh("font_golden.hex",golden);
  for(i=0;i<=10;i=i+1)begin xx[i]=0;yy[i]=0;dd[i]=0;end
  repeat(8)@(negedge pix_clk);rst_n=1;
  // Real 48kHz tone samples prefill the production 1024-sample threshold.
  repeat(600000)@(negedge pix_clk);start_raster=1;
  // Accelerate only the starting scroll position; timing thereafter is real.
  dut.chinese.subtitle.scroll=224;
  repeat(800*480)@(negedge pix_clk);
  // Keep this first-frame geometry fixed for the pixel oracle. The standalone
  // renderer separately verifies 513 real VSYNC updates including wrap.
  if(caption_checks!=640*72||reads<100||fault||ref_fault)$fatal(1,"AV coverage/fault checks=%0d reads=%0d faults=%b%b",caption_checks,reads,fault,ref_fault);
  $display("PASS production Chinese AV: %0d cycles, %0d exact caption pixels, identical HDMI scheduling/symbols",checks,caption_checks);$finish;
 end
 initial begin #50000000;$fatal(1,"AV subtitle timeout");end
endmodule
