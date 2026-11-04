`timescale 1ns/1ps
module tb_settings_av #(parameter DIM=0);
 reg sys_clk=0,pix_clk=0,rst_n=0,start_raster=0,manual_vs=1;
 always #10 sys_clk=~sys_clk;
 always #20 pix_clk=~pix_clk;
 integer x=0,y=0,i,cycles=0,checks=0,menu_checks=0,reads=0;
 wire de=start_raster&&x<640&&y<480;
 wire hs=!(x>=656&&x<752),vs=start_raster?!(y>=490&&y<492):manual_vs;
 wire [23:0] rgb={x[7:0],y[7:0],x[7:0]^y[7:0]};
 wire [9:0] red,green,blue,rr,rg,rb;wire fault,ref_fault;
 reg [24:0] golden[0:307199];reg [14:0] states[0:8];
 reg [10:0] settings_word;reg [3:0] mode_status;
 integer xx[0:10],yy[0:10];reg dd[0:10];reg [24:0] expected;
 hdmi_av_output #(.SETTINGS_UI(1),.MODE_CONTROL(1),.CHINESE_SUBTITLE(1),.CHINESE_SETTINGS(1)) dut(
  .sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.audio_enable(1'b1),.tone_sel(3'd2),
  .video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b0),.wav_error(1'b0),.audio_only(1'b0),.image_valid(1'b1),
  .image_count(3'd4),.image_index(2'd0),.wav_valid(1'b0),.wav_playing(1'b0),.wav_data(48'd0),.wav_ready(),
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.brightness(DIM? -9'sd64:9'sd0),.gain_q8(DIM?9'd128:9'd256),.loading(1'b0),
  .fade_enabled(1'b0),.wave_enabled(1'b0),.settings_word(settings_word),.transition_ready(),
  .force_tone(1'b0),.audio_flush_request(1'b0),.mode_status(mode_status),.audio_flush_done(),
  .red(red),.green(green),.blue(blue),.audio_fault(fault),.audio_urgent());
 hdmi_av_output_v01 #(.SETTINGS_UI(1),.MODE_CONTROL(1),.CHINESE_SUBTITLE(1)) reference(
  .sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.audio_enable(1'b1),.tone_sel(3'd2),
  .video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b0),.wav_error(1'b0),.audio_only(1'b0),.image_valid(1'b1),
  .image_count(3'd4),.image_index(2'd0),.wav_valid(1'b0),.wav_playing(1'b0),.wav_data(48'd0),.wav_ready(),
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.brightness(DIM? -9'sd64:9'sd0),.gain_q8(DIM?9'd128:9'd256),.loading(1'b0),
  .fade_enabled(1'b0),.wave_enabled(1'b0),.settings_word(settings_word),.transition_ready(),
  .force_tone(1'b0),.audio_flush_request(1'b0),.mode_status(mode_status),.audio_flush_done(),
  .red(rr),.green(rg),.blue(rb),.audio_fault(ref_fault),.audio_urgent());
 always @(posedge pix_clk)begin
  if(!rst_n||!start_raster)begin x<=0;y<=0;end
  else if(x==799)begin x<=0;if(y==524)y<=0;else y<=y+1;end else x<=x+1;
 end
 always @(posedge pix_clk)if(rst_n)begin
  for(i=10;i>0;i=i-1)begin xx[i]=xx[i-1];yy[i]=yy[i-1];dd[i]=dd[i-1];end
  xx[0]=x;yy[0]=y;dd[0]=de;cycles=cycles+1;#1;
  if(cycles>100)begin
   if({dut.dp,dut.hp,dut.vp,dut.x,dut.island,dut.phase,dut.fifo_read,dut.sample_request}!==
      {reference.dp,reference.hp,reference.vp,reference.x,reference.island,reference.phase,reference.fifo_read,reference.sample_request})
    $fatal(1,"V02 changed HDMI timing/audio scheduling cycle=%0d",cycles);
   if(dut.fifo_read)reads=reads+1;
   if(dd[9])begin
    expected=golden[yy[9]*640+xx[9]];
    if(expected[24])begin
     // The opaque menu stays readable even at minimum brightness/gain.
     // Only its external shadow follows the adjusted background picture.
     if(DIM&&!(xx[9]>=112&&xx[9]<528&&yy[9]>=80&&yy[9]<424&&
        ((xx[9]>=120&&xx[9]<520)||(yy[9]>=88&&yy[9]<416))))
      expected[23:0]=(reference.pixels[9]&24'hfefefe)>>1;
     if(dut.pixels[9]!==expected[23:0])$fatal(1,"V02 HDMI menu alignment xy=%0d,%0d expected=%h actual=%h",xx[9],yy[9],expected[23:0],dut.pixels[9]);
     menu_checks=menu_checks+1;
    end else if(dut.pixels[9]!==reference.pixels[9])
     $fatal(1,"V02 changed RGB outside menu/subtitle xy=%0d,%0d",xx[9],yy[9]);
   end
   if(!dd[10]&&{red,green,blue}!=={rr,rg,rb})$fatal(1,"V02 changed HDMI blanking/audio symbols");
   checks=checks+1;
  end
 end
 initial begin
  $readmemh("ui_states.hex",states);$readmemh("menu_golden_0.hex",golden);
  {mode_status,settings_word}=states[0];
  for(i=0;i<=10;i=i+1)begin xx[i]=0;yy[i]=0;dd[i]=0;end
  repeat(8)@(negedge pix_clk);rst_n=1;
  repeat(600000)@(negedge pix_clk);
  manual_vs=0;repeat(8)@(negedge pix_clk);manual_vs=1;repeat(8)@(negedge pix_clk);
  start_raster=1;
  dut.chinese.subtitle.scroll=448;reference.chinese.subtitle.scroll=448;
  repeat(800*480+16)@(negedge pix_clk);
  if(menu_checks<140000||reads<100||fault||ref_fault)$fatal(1,"V02 AV coverage/fault menu=%0d reads=%0d",menu_checks,reads);
  $display("PASS Chinese settings AV DIM=%0d: %0d cycles, %0d exact menu pixels, %0d FIFO reads; unchanged 10-clock pipeline and all HDMI blanking/audio symbols",DIM,checks,menu_checks,reads);
  $finish;
 end
 initial begin #50000000;$fatal(1,"V02 AV timeout");end
endmodule
