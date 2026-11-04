// Isolated F4 prototype: one registered overlay stage, one 512x8 memory.
// Input RGB, DE, VSYNC and x/y must already describe the SAME pixel sample.
// Recommended AV placement is OSD -> waveform -> brightness/contrast/fade LUT.
// OSD exposes its existing active_x/y; raw timing and osd_rgb already align.
// sample_valid is an OBSERVATION of an accepted FIFO read, delayed one clock;
// sample_left is the corresponding synchronous fifo_data[47:24]. This module
// neither requests samples nor changes the audio FIFO/packet handshake.
// wave_enable is already synchronized to pix_clk and is applied at VSYNC.
module video_audio_waveform(
 input wire pix_clk,rst_n,
 input wire [23:0] rgb_in,
 input wire de,vsync,
 input wire [9:0] x,
 input wire [8:0] y,
 input wire wave_enable,
 input wire sample_valid,
 input wire signed [23:0] sample_left,
 output wire [23:0] rgb_out);
 reg [7:0] sample_mem[0:511];
 reg [7:0] sample_read;
 reg active_bank,capture_bank,active_valid,capture_pending;
 reg [7:0] capture_index;
 reg [1:0] decimation;
 reg vsync_prev,display_enabled;
 wire frame_edge=vsync_prev && !vsync;
 wire take_sample=!capture_pending && sample_valid && decimation==2'd3;
 wire [7:0] capture_value=sample_left[23:16]^8'h80;
 wire [7:0] read_index=x[7:0]-8'd16;

 // Keep reset away from RAM/read output so a synchronous block RAM can map.
 // A complete snapshot alone can become active; valid metadata masks RAM
 // contents after reset. Read and write always address different banks.
 always @(posedge pix_clk)begin
  sample_read<=sample_mem[{active_bank,read_index}];
  if(rst_n && take_sample)
   sample_mem[{capture_bank,capture_index}]<=capture_value;
 end
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin
   active_bank<=0;capture_bank<=1;active_valid<=0;capture_pending<=0;
   capture_index<=0;decimation<=0;vsync_prev<=1;display_enabled<=0;
  end else begin
   vsync_prev<=vsync;
   if(!capture_pending && sample_valid)begin
    if(decimation==2'd3)begin
     decimation<=0;
     if(capture_index==8'd255)capture_pending<=1;
     else capture_index<=capture_index+1'b1;
    end else decimation<=decimation+1'b1;
   end
   if(frame_edge)begin
    display_enabled<=wave_enable;
    // The final write on this same edge cannot publish a partial snapshot:
    // capture_pending is the OLD value, as in the affine LUT bank switch.
    if(capture_pending)begin
     active_bank<=capture_bank;capture_bank<=active_bank;active_valid<=1;
     capture_pending<=0;capture_index<=0;decimation<=0;
    end
   end
  end
 end

 // The RAM read and this metadata/bypass are ONE common pipeline stage.
 // The output is combinational from these registers; do not register it again.
 reg [23:0] bypass_pixel;
 reg window_q;
 reg [8:0] y_q;
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin bypass_pixel<=0;window_q<=0;y_q<=0;end
  else begin
   bypass_pixel<=rgb_in;y_q<=y;
   window_q<=display_enabled && active_valid && de &&
    x>=10'd16 && x<10'd272 && y>=9'd336 && y<9'd416;
  end
 end
 wire [8:0] trace_y=9'd410-{3'b000,sample_read[7:2]};
 wire [23:0] window_rgb=(y_q==trace_y)?24'h00ff60:
  ((y_q==9'd378)?24'h214438:24'h081018);
 assign rgb_out=window_q?window_rgb:bypass_pixel;
endmodule
