// Full-width transparent 32-band FFT overlay, replacing the optional waveform.
// Only accepted audio FIFO samples are observed. Complete bar banks publish
// at VSYNC; the audio-source reset invalidates partial/mismatched spectra.
module video_audio_spectrum #(parameter SCENE_3D=0,GALLERY_LAYOUT=0)(
 input wire pix_clk,rst_n,sample_rst_n,
 input wire [23:0] rgb_in,rgb_background,input wire de,vsync,
 input wire [9:0] x,input wire [8:0] y,input wire wave_enable,
 input wire sample_valid,input wire signed [23:0] sample_left,
 output wire [23:0] rgb_out,input wire [23:0] scene_rgb,input wire scene_valid);
 wire bin_valid;wire [7:0] bin_index;
 wire signed [15:0] bin_real,bin_imag;
 reg pending,active_bank,capture_bank,active_valid,history_valid;
 audio_fft512 fft(.clk(pix_clk),.rst_n(sample_rst_n),.capture_enable(!pending),
  .sample_valid(sample_valid),.sample_left(sample_left),.bin_valid(bin_valid),
  .bin_index(bin_index),.bin_real(bin_real),.bin_imag(bin_imag),.busy());
 wire [15:0] abs_r=bin_real[15]?(~bin_real+16'd1):bin_real;
 wire [15:0] abs_i=bin_imag[15]?(~bin_imag+16'd1):bin_imag;
 wire [15:0] larger=(abs_r>=abs_i)?abs_r:abs_i;
 wire [15:0] smaller=(abs_r>=abs_i)?abs_i:abs_r;
 // Bounded magnitude approximation after a real FFT; no square-root DSP.
 wire [16:0] magnitude={1'b0,larger}+{2'b0,smaller[15:1]};
 reg [16:0] band_peak;
 reg [4:0] band_index;
 function [8:0] band_end;
  input [4:0] n;
  begin case(n)
   0:band_end=2;1:band_end=3;2:band_end=4;3:band_end=5;
   4:band_end=6;5:band_end=7;6:band_end=8;7:band_end=9;
   8:band_end=10;9:band_end=12;10:band_end=14;11:band_end=16;
   12:band_end=19;13:band_end=22;14:band_end=26;15:band_end=30;
   16:band_end=35;17:band_end=41;18:band_end=48;19:band_end=56;
   20:band_end=65;21:band_end=76;22:band_end=88;23:band_end=102;
   24:band_end=118;25:band_end=137;26:band_end=159;27:band_end=184;
   28:band_end=213;29:band_end=232;30:band_end=244;default:band_end=256;
  endcase end
 endfunction
 function [6:0] height;
  input [16:0] value;integer n;reg [7:0] mapped;
  begin
   mapped=0;
   for(n=3;n<17;n=n+1)if(value[n])mapped=n*8-24+((value>>(n-3))&7);
   height=(mapped>96)?7'd96:mapped[6:0];
  end
 endfunction
 wire [16:0] peak_next=(magnitude>band_peak)?magnitude:band_peak;
 reg commit_pending;reg [4:0] commit_index;reg [6:0] commit_height;
 // Small spectrum memories use block RAM to leave logic for the home UI.
 // Synchronous reads and frame-bank ownership retain the original latency.
 (* ram_style="bram" *) reg [6:0] history[0:31];reg [6:0] history_read;
 (* ram_style="bram" *) reg [6:0] bars[0:63];reg [6:0] bar_read;
 wire [6:0] decay=(history_read>2)?history_read-7'd2:7'd0;
 wire [6:0] level_next=(history_valid&&decay>commit_height)?decay:commit_height;
 reg vsync_prev,display_enabled,color_half;
 reg [7:0] color_phase;
 wire frame_edge=vsync_prev&&!vsync;
 // Divide the raster into 32 adjacent twenty-pixel cells without a divider.
 reg [4:0] column,cell_x;
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin column<=0;cell_x<=0;end
  else if(!de||x==639)begin column<=0;cell_x<=0;end
  else if(cell_x==19)begin cell_x<=0;column<=column+1'b1;end
  else cell_x<=cell_x+1'b1;
 end
 always @(posedge pix_clk)begin
  bar_read<=bars[{active_bank,column}];
  history_read<=history[band_index];
  if(sample_rst_n&&commit_pending)begin
   history[commit_index]<=level_next;
   bars[{capture_bank,commit_index}]<=level_next;
  end
 end
 always @(posedge pix_clk or negedge sample_rst_n)begin
  if(!sample_rst_n)begin
   pending<=0;active_bank<=0;capture_bank<=1;active_valid<=0;history_valid<=0;
   band_index<=0;band_peak<=0;commit_pending<=0;commit_index<=0;commit_height<=0;
  end else begin
   commit_pending<=0;
   if(bin_valid)begin
    if(bin_index==0)begin band_index<=0;band_peak<=0;end
    else if({1'b0,bin_index}+9'd1==band_end(band_index))begin
     commit_index<=band_index;commit_height<=height(peak_next);commit_pending<=1;
     band_index<=band_index+1'b1;band_peak<=0;
    end else band_peak<=peak_next;
   end
   if(commit_pending&&commit_index==31)begin pending<=1;history_valid<=1;end
   if(frame_edge&&pending)begin
    active_bank<=capture_bank;capture_bank<=active_bank;pending<=0;active_valid<=1;
   end
  end
 end
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin vsync_prev<=1;display_enabled<=0;color_half<=0;color_phase<=0;end
  else begin
   vsync_prev<=vsync;
   if(frame_edge)begin
    display_enabled<=wave_enable;color_half<=!color_half;
    if(color_half)color_phase<=(color_phase==191)?8'd0:color_phase+1'b1;
   end
  end
 end
 function [23:0] palette;
  input [7:0] hue;reg [7:0] ramp,rise,fall;
  begin
   ramp={1'b0,hue[4:0],2'b0}+{2'b0,hue[4:0],1'b0};
   rise=8'd64+ramp;fall=8'd250-ramp;
   case(hue[7:5])
   0:palette={8'd250,rise,8'd64};1:palette={fall,8'd250,8'd64};
   2:palette={8'd64,8'd250,rise};3:palette={8'd64,fall,8'd250};
   4:palette={rise,8'd64,8'd250};default:palette={8'd250,8'd64,fall};
  endcase end
 endfunction
 // Six hue steps per band span the complete rainbow. Advance only during
 // vertical blanking: 192 steps / one step per two frames is about 6.45 s.
 wire [7:0] band_hue={1'b0,column,2'b0}+{2'b0,column,1'b0};
 wire [8:0] hue_sum={1'b0,color_phase}+{1'b0,band_hue};
 wire [7:0] hue=(hue_sum>=192)?hue_sum-9'd192:hue_sum[7:0];
 // 45/32 = 1.40625: rounded display gain uses shifts/adds, no extra DSP.
 // Keep the FFT values/history unchanged; only stretch the drawn height.
 wire [12:0] scaled_height={1'b0,bar_read,5'd0}+{3'd0,bar_read,3'd0}+
  {4'd0,bar_read,2'd0}+{6'd0,bar_read}+13'd16;
 wire [7:0] display_height=scaled_height[12:5];
 reg [23:0] bypass_q,color_q;
 reg window_q,compact_q;reg [8:0] y_q;
 wire compact_gallery=GALLERY_LAYOUT&&!(SCENE_3D&&scene_valid);
 wire [8:0] spectrum_top=compact_gallery?9'd416:9'd345;
 wire [7:0] compact_height=(display_height==0)?8'd0:
  ((display_height<2)?8'd1:((display_height>120)?8'd60:{1'b0,display_height[7:1]}));
 wire [7:0] drawn_height=compact_q?compact_height:display_height;
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin bypass_q<=0;color_q<=0;window_q<=0;y_q<=0;compact_q<=0;end
  else begin
   // The inherited status strip dims y=432..463. While the spectrum is
   // enabled, keep the entire bottom background intact between the bars.
   bypass_q<=(display_enabled&&de&&y>=spectrum_top&&y<480)?rgb_background:rgb_in;
   color_q<=palette(hue);y_q<=y;compact_q<=compact_gallery;
   window_q<=display_enabled&&active_valid&&sample_rst_n&&de&&
    y>=spectrum_top&&y<480&&(y>=476||(cell_x>=1&&cell_x<19));
  end
 end
 // The four-pixel visual baseline reaches both edges, including silent bands.
 // It is decoration, not a minimum FFT energy, and disappears when disabled.
 assign rgb_out=(window_q&&(y_q>=476||(bar_read!=0&&y_q>=9'd480-{1'b0,drawn_height})))?color_q:((SCENE_3D&&scene_valid)?scene_rgb:bypass_q);
endmodule
