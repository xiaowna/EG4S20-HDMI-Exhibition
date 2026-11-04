`timescale 1ns/1ps
module tb_menu_hdmi;
 reg sys=0,pix=0,rst_n=0;always #10 sys=~sys;always #20 pix=~pix;
 reg [9:0] x=0,y=0;
 wire de=x<640&&y<480;
 wire hs=!(x>=656&&x<752);
 wire vs=!(y>=490&&y<492);
 wire [9:0] r,g,b;
 wire fault;
 hdmi_av_output #(.SETTINGS_UI(1)) dut(.settings_word(11'b1_00_010_010_1_0),.brightness(9'sd0),.gain_q8(9'd256),.loading(1'b1),.fade_enabled(1'b1),.wave_enabled(1'b0),.audio_only(1'b0),.image_valid(1'b1),.sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),
 .audio_enable(1'b1),.tone_sel(3'd2),.video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b0),
 .wav_error(1'b0),.image_count(3'd0),.image_index(2'd0),
 .wav_valid(1'b0),.wav_playing(1'b0),
 .wav_data(48'd0),.wav_ready(),.de(de),.hsync(hs),.vsync(vs),
 .rgb({x[7:0],y[7:0],8'h5a}),.red(r),.green(g),.blue(b),.audio_fault(fault));
 always @(posedge pix)begin
  if(!rst_n)begin x<=0;y<=0;end
  else if(x==799)begin x<=0;if(y==524)y<=0;else y<=y+1'b1;end
  else x<=x+1'b1;
 end
 wire [23:0] gold_rgb;
 video_scroll_osd #(.SETTINGS_UI(1)) gold(.clk(pix),.rst_n(rst_n),.de(de),.vsync(vs),
  .rgb({x[7:0],y[7:0],8'h5a}),.settings_word(11'b1_00_010_010_1_0),
  .image_count(3'd0),.image_index(2'd0),.paused(1'b0),.wav_found(1'b0),.catalog_ready(1'b1),.image_valid(1'b1),.rgb_out(gold_rgb));
 reg [23:0] expected_pixels[0:9];reg [9:0] valid_pixels=0;
 integer pixel_checks=0,k;
 always @(posedge pix)begin
  if(!rst_n)begin valid_pixels=0;for(k=0;k<10;k=k+1)expected_pixels[k]=0;end
  else begin
   for(k=9;k>0;k=k-1)expected_pixels[k]=expected_pixels[k-1];expected_pixels[0]=gold_rgb;
   valid_pixels={valid_pixels[8:0],de && lines>525};
   #1;if(valid_pixels[9])begin
    if(dut.pixels[9]!==expected_pixels[9])$fatal(1,"menu ten-stage RGB alignment expected=%h actual=%h",expected_pixels[9],dut.pixels[9]);
    pixel_checks=pixel_checks+1;
   end
  end
 end
 integer lines=0,audio_packets=0,acr_packets=0,avi_packets=0,info_packets=0;
 integer nonzero=0,samples=0,video=0,j;
 reg first_fifo_read_seen=0;
 reg [6:0] check_phase;
 reg check_island,check_video;
 function [3:0] decode;input [9:0] word;begin
  case(word)
   10'b1010011100:decode=0; 10'b1001100011:decode=1;
   10'b1011100100:decode=2; 10'b1011100010:decode=3;
   10'b0101110001:decode=4; 10'b0100011110:decode=5;
   10'b0110001110:decode=6; 10'b0100111100:decode=7;
   10'b1011001100:decode=8; 10'b0100111001:decode=9;
   10'b0110011100:decode=10;10'b1011000110:decode=11;
   10'b1010001110:decode=12;10'b1001110001:decode=13;
   10'b0101100011:decode=14;10'b1011000011:decode=15;
   default:decode=4'hx;
  endcase
 end endfunction
 // 输出端逐符号解码：检查完整岛边界、ACR/InfoFrame 类型及实际样本流。
 always @(posedge pix)if(rst_n)begin
  if(dut.fifo_read && !first_fifo_read_seen)begin
   if(dut.fifo_level<1024)$fatal(1,"audio read before prebuffer filled");
   first_fifo_read_seen=1;
  end
  check_phase=dut.phase;check_island=dut.island;check_video=dut.vd;
  #1;
  if(fault)$fatal(1,"audio scheduling/overflow fault, y=%0d x=%0d phase=%0d",y,x,check_phase);
  if(check_video)video=video+1;
  if(check_island)begin
   if(check_phase==0)lines=lines+1;
   if(check_phase<8)begin
    if(r!==10'b0010101011||g!==10'b0010101011)$fatal(1,"island preamble %0d",check_phase);
   end else if(check_phase<10||check_phase>=74)begin
    if(r!==10'b0100110011||g!==10'b0100110011)$fatal(1,"island guard %0d",check_phase);
    if((decode(b)&4'hc)!==4'hc)$fatal(1,"channel 0 guard");
   end else begin
    if(^r===1'bx||^g===1'bx||^b===1'bx)$fatal(1,"undefined packet symbol");
    if(^decode(r)===1'bx||^decode(g)===1'bx||^decode(b)===1'bx)$fatal(1,"non TERC4 packet symbol");
    if(check_phase==10)begin
     if((decode(b)&4'h8)!==4'h0)$fatal(1,"first packet D3");
     if(dut.ah[7:0]!==8'h02)$fatal(1,"audio header");
     audio_packets=audio_packets+1;
     for(j=0;j<4;j=j+1)if(dut.ah[8+j])begin
      samples=samples+1;
      if(dut.ab[j*56 +: 48]!=0)nonzero=nonzero+1;
     end
    end
    if(check_phase==42)begin
     if((decode(b)&4'h8)!==4'h8)$fatal(1,"second packet D3");
     case(dut.bh[7:0])
      8'h01:acr_packets=acr_packets+1;
      8'h82:avi_packets=avi_packets+1;
      8'h84:info_packets=info_packets+1;
      8'h00:;
      default:$fatal(1,"unexpected auxiliary packet %h",dut.bh[7:0]);
     endcase
    end
   end
  end
 end
 initial begin
  repeat(8)@(negedge pix);rst_n=1;
  repeat(800*525*3)@(negedge pix);
  if(!first_fifo_read_seen||lines<1500||video<900000||audio_packets<1500||samples<2000||nonzero<1000)
   $fatal(1,"missing audio/video lines=%0d video=%0d packets=%0d samples=%0d nonzero=%0d",lines,video,audio_packets,samples,nonzero);
  if(acr_packets<30||avi_packets<3||info_packets<3)$fatal(1,"missing metadata acr=%0d avi=%0d info=%0d",acr_packets,avi_packets,info_packets);
  if(pixel_checks<300000 || dut.status_pix[19:9]!==11'b1_00_010_010_1_0 || dut.osd.settings_frame[10]!==1)$fatal(1,"menu CDC/pixels not exercised");
  if(dut.fade_level!==32)$fatal(1,"loading fade blacked out an open menu");
  $display("PASS menu AV pixels=%0d; active loading/fade keeps menu readable",pixel_checks);
  $display("PASS AV link lines=%0d video=%0d audio_packets=%0d samples=%0d nonzero=%0d ACR=%0d AVI=%0d AudioInfo=%0d",lines,video,audio_packets,samples,nonzero,acr_packets,avi_packets,info_packets);
  $finish;
 end
endmodule
