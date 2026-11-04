// One-clock parallel overlay; keeps the HDMI pipeline at ten clocks.
// 0 hidden, 1 init, 2 catalogue, 3 measured image pixels, 4 audio,
// 5 scene/RTC, 6 error. Stage 7 is generated locally only after a wait ends.
// No estimated percentage: each image unit is 4096/307200 pixels (4/300 px).
module video_prepare_overlay(input wire clk,rst_n,de,vsync,
 input wire [9:0] x,y,input wire [9:0] prepare_word,
 output reg [23:0] rgb_out,output reg overlay_valid);
 reg [9:0] frame_word;
 reg vs_prev;reg [7:0] phase;reg [3:0] done_frames;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin frame_word<=0;vs_prev<=1;phase<=0;done_frames<=0;end
  else begin
   vs_prev<=vsync;
   if(vs_prev&&!vsync)begin
    phase<=phase+8'd4;
    if(prepare_word[9:7]!=0)begin frame_word<=prepare_word;done_frames<=0;end
    else if(frame_word[9:7]!=0&&frame_word[9:7]!=6&&frame_word[9:7]!=7)begin
     frame_word<={3'd7,7'd75};done_frames<=7;
    end else if(done_frames!=0)done_frames<=done_frames-1'b1;
    else frame_word<=0;
   end
  end
 wire [2:0] stage=frame_word[9:7];
 wire measured=stage==3,failed=stage==6,done=stage==7;
 // The decoder can finish before drained writes are safe to publish. Keep
 // measured loading below full until its owning wait actually retires.
 wire [6:0] units=frame_word[6:0]>=75?7'd74:frame_word[6:0];
 wire [8:0] fill=done?9'd300:{units,2'b00};
 wire [7:0] sweep={phase[7]?~phase[6:0]:phase[6:0],1'b0};
 wire [9:0] relative_x=x-10'd170;
 wire card=x>=160&&x<480&&y>=440&&y<472&&
  ((x>=164&&x<476)||(y>=444&&y<468));
 wire border=card&&(x<162||x>=478||y<442||y>=470);
 wire rail=x>=170&&x<470&&y>=454&&y<462;
 wire lit=done||(measured?(relative_x<{1'b0,fill}):
  (!failed&&relative_x>={2'b0,sweep}&&relative_x<{2'b0,sweep}+10'd48));
 wire dot=y>=446&&y<449&&x>=304&&x<336&&x[2:0]<4;
 reg [23:0] color;
 always @*begin
  color=24'h162737;
  if(border)color=failed?24'h86534f:24'h3b5363;
  if(dot)color=failed?24'he5a89b:((done||x[4:3]==phase[5:4])?24'hb6e7d7:24'h3b5363);
  if(rail)color=failed?24'h86534f:(lit?24'h70d6bc:24'h243b47);
  if(rail&&lit&&y==454&&!failed)color=24'hb6e7d7;
 end
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin rgb_out<=0;overlay_valid<=0;end
  else begin rgb_out<=color;overlay_valid<=de&&stage!=0&&card;end
endmodule
