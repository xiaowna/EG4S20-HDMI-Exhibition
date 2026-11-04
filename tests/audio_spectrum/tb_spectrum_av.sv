`timescale 1ns/1ps
module tb_spectrum_av #(parameter ENABLE=1,parameter DIM=0);
 reg sys_clk=0,pix_clk=0,rst_n=0,start_raster=0,manual_vs=1;
 always #10 sys_clk=~sys_clk;
 always #20 pix_clk=~pix_clk;
 integer x=0,y=0,i,cycles=0,checks=0,painted=0,reads=0,transparent=0,band,level;
 integer color_frames=0,expected_phase=0;reg expected_prev_vs=1;
 wire de=start_raster&&x<640&&y<480;
 wire hs=!(x>=656&&x<752),vs=start_raster?!(y>=490&&y<492):manual_vs;
 wire [23:0] rgb={x[7:0],y[7:0],x[7:0]^y[7:0]};
 wire [9:0] red,green,blue,rr,rg,rb;wire fault,ref_fault;
 integer xx[0:10],yy[0:10];reg dd[0:10];reg [23:0] expected,color;
 wire signed [8:0] bright=DIM?-9'sd32:9'sd0;
 wire [8:0] gain=DIM?9'd128:9'd256;
 hdmi_av_output #(.SETTINGS_UI(1),.MODE_CONTROL(1),.CHINESE_SUBTITLE(1),.CHINESE_SETTINGS(1),.SPECTRUM_FFT(1)) dut(
  .sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.audio_enable(1'b1),.tone_sel(3'd2),
  .video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b0),.wav_error(1'b0),.audio_only(1'b0),.image_valid(1'b1),
  .image_count(3'd4),.image_index(2'd0),.wav_valid(1'b0),.wav_playing(1'b0),.wav_data(48'd0),.wav_ready(),
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.brightness(bright),.gain_q8(gain),.loading(1'b0),
  .fade_enabled(1'b0),.wave_enabled(ENABLE!=0),.settings_word(11'd0),.transition_ready(),
  .force_tone(1'b0),.audio_flush_request(1'b0),.mode_status(4'd5),.audio_flush_done(),
  .red(red),.green(green),.blue(blue),.audio_fault(fault),.audio_urgent());
 hdmi_av_output_v02 #(.SETTINGS_UI(1),.MODE_CONTROL(1),.CHINESE_SUBTITLE(1),.CHINESE_SETTINGS(1)) reference(
  .sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.audio_enable(1'b1),.tone_sel(3'd2),
  .video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b0),.wav_error(1'b0),.audio_only(1'b0),.image_valid(1'b1),
  .image_count(3'd4),.image_index(2'd0),.wav_valid(1'b0),.wav_playing(1'b0),.wav_data(48'd0),.wav_ready(),
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.brightness(bright),.gain_q8(gain),.loading(1'b0),
  .fade_enabled(1'b0),.wave_enabled(1'b0),.settings_word(11'd0),.transition_ready(),
  .force_tone(1'b0),.audio_flush_request(1'b0),.mode_status(4'd5),.audio_flush_done(),
  .red(rr),.green(rg),.blue(rb),.audio_fault(ref_fault),.audio_urgent());
 function [23:0] palette;
  input integer n;integer h,r,f;
  begin
   h=(n*6+expected_phase)%192;r=64+(h%32)*6;f=250-(h%32)*6;
   case(h/32)
   0:palette={8'd250,r[7:0],8'd64};1:palette={f[7:0],8'd250,8'd64};
   2:palette={8'd64,8'd250,r[7:0]};3:palette={8'd64,f[7:0],8'd250};
   4:palette={r[7:0],8'd64,8'd250};default:palette={8'd250,8'd64,f[7:0]};
  endcase end
 endfunction
 always @(posedge pix_clk)begin
  if(!rst_n||!start_raster)begin x<=0;y<=0;end
  else if(x==799)begin x<=0;if(y==524)y<=0;else y<=y+1;end else x<=x+1;
 end
 always @(posedge pix_clk)if(rst_n)begin
  if(expected_prev_vs&&!vs)begin color_frames=color_frames+1;expected_phase=(color_frames/2)%192;end
  expected_prev_vs=vs;
  for(i=10;i>0;i=i-1)begin xx[i]=xx[i-1];yy[i]=yy[i-1];dd[i]=dd[i-1];end
  xx[0]=x;yy[0]=y;dd[0]=de;cycles=cycles+1;#1;
  if(cycles>100)begin
   if({dut.dp,dut.hp,dut.vp,dut.x,dut.island,dut.phase,dut.fifo_read,dut.sample_request}!==
      {reference.dp,reference.hp,reference.vp,reference.x,reference.island,reference.phase,reference.fifo_read,reference.sample_request})
    $fatal(1,"FFT changed HDMI timing/audio scheduling cycle=%0d",cycles);
   if(dut.fifo_read)reads=reads+1;
   if(dd[9])begin
    expected=reference.pixels[9];band=xx[9]/20;
    if(ENABLE&&yy[9]>=345)begin
     color={xx[9][7:0],yy[9][7:0],xx[9][7:0]^yy[9][7:0]};
     expected=DIM?{(8'd32+{1'b0,color[23:17]}),(8'd32+{1'b0,color[15:9]}),(8'd32+{1'b0,color[7:1]})}:color;
    end
    level=dut.spectrum.visual.bars[{dut.spectrum.visual.active_bank,band[4:0]}];
    if(ENABLE&&dut.spectrum.visual.active_valid&&yy[9]>=345&&
       (yy[9]>=476||(yy[9]>=480-(level*45+16)/32&&xx[9]%20>=1&&xx[9]%20<19)))begin
     color=palette(band);
     expected=DIM?{(8'd32+{1'b0,color[23:17]}),(8'd32+{1'b0,color[15:9]}),(8'd32+{1'b0,color[7:1]})}:color;
     painted=painted+1;
    end else transparent=transparent+1;
    if(dut.pixels[9]!==expected)$fatal(1,"FFT AV pixel xy=%0d,%0d expected=%h actual=%h",xx[9],yy[9],expected,dut.pixels[9]);
   end
   if(!dd[10]&&{red,green,blue}!=={rr,rg,rb})$fatal(1,"FFT changed HDMI blanking/audio symbols");
   checks=checks+1;
  end
 end
 initial begin
  for(i=0;i<=10;i=i+1)begin xx[i]=0;yy[i]=0;dd[i]=0;end
  repeat(8)@(negedge pix_clk);rst_n=1;
  repeat(600000)@(negedge pix_clk);
  manual_vs=0;repeat(8)@(negedge pix_clk);manual_vs=1;repeat(8)@(negedge pix_clk);
  start_raster=1;
  repeat(800*525*3+16)@(negedge pix_clk);
  if((ENABLE&&painted<2000)||(!ENABLE&&painted!=0)||reads<1500||fault||ref_fault)
   $fatal(1,"FFT AV coverage/fault painted=%0d reads=%0d",painted,reads);
  $display("PASS spectrum AV ENABLE=%0d DIM=%0d: cycles=%0d colored=%0d transparent=%0d FIFO_reads=%0d; three 800x525 frames, exact 10-clock pixels and HDMI blanking/audio symbols",ENABLE,DIM,checks,painted,transparent,reads);$finish;
 end
 initial begin #90000000;$fatal(1,"FFT AV timeout");end
endmodule
