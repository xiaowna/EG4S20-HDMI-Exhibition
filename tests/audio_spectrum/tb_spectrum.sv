`timescale 1ns/1ps
module tb_spectrum;
 reg pix_clk=0,rst_n=0,sample_rst_n=0,de=0,vsync=1,wave_enable=1,sample_valid=0;
 reg [23:0] rgb_in=0,rgb_background=0;reg [9:0] x=0;reg [8:0] y=0;reg signed [23:0] sample_left=0;
 wire [23:0] rgb_out;
 always #5 pix_clk=~pix_clk;
 video_audio_spectrum dut(.scene_rgb(24'd0),.scene_valid(1'b0),.*);
 reg [15:0] samples[0:4095];reg [6:0] levels[0:255];
 integer n,scenario,xx,yy,pixels=0,painted=0,transparent=0,handle;
 integer color_frames=0,expected_phase=0;
 reg [23:0] expected;integer band;
 reg expected_background_mode=0;
 function [23:0] palette;
  input integer b;integer h,r,f;
  begin
   h=(b*6+expected_phase)%192;r=64+(h%32)*6;f=250-(h%32)*6;
   case(h/32)
   0:palette={8'd250,r[7:0],8'd64};1:palette={f[7:0],8'd250,8'd64};
   2:palette={8'd64,8'd250,r[7:0]};3:palette={8'd64,f[7:0],8'd250};
   4:palette={r[7:0],8'd64,8'd250};default:palette={8'd250,8'd64,f[7:0]};
  endcase end
 endfunction
 task frame_marker;
  begin
   expected_background_mode=wave_enable;vsync=0;color_frames=color_frames+1;
   expected_phase=(color_frames/2)%192;
   @(negedge pix_clk);vsync=1;
  end
 endtask
 task pixel;
  input integer px,py,frame_id,enabled;
  begin
   @(negedge pix_clk);de=1;x=px;y=py;rgb_background={px[7:0],py[7:0],px[7:0]^py[7:0]};
   rgb_in=(py>=432&&py<464)?((rgb_background&24'hfefefe)>>1):rgb_background;
   expected=(expected_background_mode&&py>=345)?rgb_background:rgb_in;band=px/20;
   if(enabled&&py>=345&&(py>=476||
      (py>=480-(levels[frame_id*32+band]*45+16)/32&&px%20>=1&&px%20<19)))begin
    expected=palette(band);painted=painted+1;
   end else transparent=transparent+1;
   @(posedge pix_clk);#1;
   if(rgb_out!==expected)$fatal(1,"spectrum frame=%0d enabled=%0d xy=%0d,%0d expected=%h actual=%h",frame_id,enabled,px,py,expected,rgb_out);
   pixels=pixels+1;
   if(handle!=0)$fwrite(handle,"%0d %0d %0d\n",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
  end
 endtask
 task frame;
  input integer frame_id,enabled,edge_needed;
  begin
   @(negedge pix_clk);de=0;
   if(edge_needed)frame_marker;
   for(yy=0;yy<480;yy=yy+1)begin
    for(xx=0;xx<640;xx=xx+1)begin
     pixel(xx,yy,frame_id,enabled);
     // A mid-frame enable change must not tear the current raster.
     if(scenario==0&&yy==100&&xx==300)wave_enable=0;
    end
    @(negedge pix_clk);de=0;repeat(2)@(negedge pix_clk);
   end
  end
 endtask
 initial begin
  handle=0;$readmemh("samples.hex",samples);$readmemh("heights.hex",levels);
  repeat(4)@(negedge pix_clk);rst_n=1;sample_rst_n=1;
  // Blank uninitialized RAM and incomplete FFT snapshots must be invisible.
  pixel(0,479,0,0);@(negedge pix_clk);de=0;repeat(2)@(negedge pix_clk);
  for(scenario=0;scenario<8;scenario=scenario+1)begin
   wait(!dut.fft.busy&&!dut.pending);
   for(n=0;n<512;n=n+1)begin
    sample_valid=1;sample_left={samples[scenario*512+n],8'd0};@(negedge pix_clk);sample_valid=0;
    if(n%13==0)repeat(2)@(negedge pix_clk);
   end
   wait(dut.pending);@(negedge pix_clk);
   for(n=0;n<32;n=n+1)
    if(dut.bars[{dut.capture_bank,n[4:0]}]!==levels[scenario*32+n])
     $fatal(1,"band reduction/history frame=%0d band=%0d expected=%0d actual=%0d",scenario,n,levels[scenario*32+n],dut.bars[{dut.capture_bank,n[4:0]}]);
   if(scenario==1)begin wave_enable=1;frame(0,1,0);end
   if(scenario==7)begin handle=$fopen("spectrum.ppm","w");$fwrite(handle,"P3\n640 480\n255\n");end
   frame(scenario,1,1);
   if(scenario==7)begin $fclose(handle);handle=0;end
  end
  // One complete 384-frame hue cycle. All 640 bottom pixels must be colored,
  // including x=0/639 and each column gap, even when no new samples arrive.
  for(n=0;n<384;n=n+1)begin
   @(negedge pix_clk);de=0;frame_marker;
   for(xx=0;xx<640;xx=xx+1)pixel(xx,479,7,1);
   @(negedge pix_clk);de=0;
  end
  $display("PASS spectrum color: full 384-frame rainbow cycle, 245760 bottom-edge pixels, paused-height animation and frame-atomic colors");
  wave_enable=0;frame(7,0,1);
  // Invalidate complete and partial snapshots on an audio-source flush.
  @(negedge pix_clk);sample_rst_n=0;
  pixel(0,479,7,0);pixel(638,479,7,0);
  @(negedge pix_clk);sample_rst_n=1;wave_enable=1;frame(7,0,1);
  if(painted<30000||transparent<2000000)$fatal(1,"spectrum coverage too low");
  $display("PASS spectrum raster: %0d exact pixels, %0d colored, %0d transparent; 32 independent bands, slow decay, atomic publish/enable, source flush/reset",pixels,painted,transparent);$finish;
 end
 initial begin #60000000;$fatal(1,"spectrum timeout");end
endmodule
