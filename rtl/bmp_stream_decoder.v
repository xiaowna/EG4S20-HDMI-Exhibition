// Checked 24-bit BITMAPINFOHEADER BMP stream -> addressed RGB pixels.
// Default dimensions match the competition. Negative height (top-down) accepted.
// All inputs/outputs use ready/valid. No byte after EOF is required to complete.
// Invalid headers are drained; a transport error aborts. Commit only done&&!error.
module bmp_stream_decoder #(parameter integer FRAME_WIDTH=640,FRAME_HEIGHT=480,ALLOW_HALF=0)(
 input wire clk,rst_n,start,input wire [31:0] file_size,
 input wire [7:0] byte_data,input wire [31:0] byte_offset,input wire byte_valid,
 output wire byte_ready,input wire stream_done,stream_error,
 input wire pixel_ready,output reg pixel_valid,output reg [31:0] pixel_addr,
 output reg [23:0] pixel_rgb,output reg busy,done,error);
 localparam IDLE=0,HEADER=1,CHECK=2,SKIP=3,PIXELS=4,PADDING=5,TAIL=6,DRAIN=7;
 localparam integer ROW_BYTES=FRAME_WIDTH*3;
 localparam integer ROW_PAD=(4-(ROW_BYTES%4))%4;
 localparam integer STRIDE=ROW_BYTES+ROW_PAD;
 localparam [31:0] EXPECTED_WIDTH=FRAME_WIDTH;
 // A bounded runtime choice, not an arbitrary-size scaler. Each source pixel
 // in half-size mode produces a 2x2 block directly in the output frame bank.
 localparam integer HALF_ALLOWED=ALLOW_HALF && FRAME_WIDTH>=2 && FRAME_HEIGHT>=2 &&
  (FRAME_WIDTH%2==0) && (FRAME_HEIGHT%2==0);
 localparam integer HALF_WIDTH=FRAME_WIDTH/2,HALF_HEIGHT=FRAME_HEIGHT/2;
 localparam integer HALF_PAD=(4-((HALF_WIDTH*3)%4))%4;
 localparam integer HALF_STRIDE=HALF_WIDTH*3+HALF_PAD;
 localparam [31:0] EXPECTED_HALF_WIDTH=HALF_WIDTH;
 reg [2:0] state;
 reg [31:0] length,expected,bmp_size,pixel_offset,height;
 reg bad_signature,bad_header,eof_seen,top_down;
 reg bad_width,bad_half_width,half_mode;
 reg [1:0] repeat_left;
 reg [1:0] phase,pad_left;
 reg [7:0] blue,green;
 localparam integer COLUMN_BITS=(FRAME_WIDTH<2)?1:$clog2(FRAME_WIDTH);
 localparam integer ROW_BITS=(FRAME_HEIGHT<1)?1:$clog2(FRAME_HEIGHT+1);
 localparam integer PIXEL_BITS=(FRAME_WIDTH*FRAME_HEIGHT<1)?1:$clog2(FRAME_WIDTH*FRAME_HEIGHT+1);
 // Include the terminal row/pixel count; keep row_base wide for the
 // bottom-up subtraction after the final row, which is never published.
 reg [COLUMN_BITS-1:0] column;
 reg [ROW_BITS-1:0] rows_left;
 reg [PIXEL_BITS-1:0] pixel_count;
 reg [31:0] row_base;
 wire select_half=HALF_ALLOWED && bad_width && !bad_half_width;
 wire [63:0] pixel_end={32'b0,pixel_offset}+
  (select_half?HALF_STRIDE*HALF_HEIGHT:STRIDE*FRAME_HEIGHT);
 wire [PIXEL_BITS-1:0] source_pixels=half_mode?HALF_WIDTH*HALF_HEIGHT:FRAME_WIDTH*FRAME_HEIGHT;
 assign byte_ready=busy && state!=CHECK && state!=IDLE && repeat_left==0 && (!pixel_valid || pixel_ready);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;length<=0;expected<=0;bmp_size<=0;pixel_offset<=0;
   height<=0;bad_signature<=0;bad_header<=0;eof_seen<=0;top_down<=0;
   bad_width<=0;bad_half_width<=0;half_mode<=0;repeat_left<=0;
   phase<=0;pad_left<=0;blue<=0;green<=0;column<=0;rows_left<=0;row_base<=0;pixel_count<=0;
   pixel_valid<=0;pixel_addr<=0;pixel_rgb<=0;busy<=0;done<=0;error<=0;
  end else begin
   done<=0;
   if(pixel_valid && pixel_ready)begin
    if(repeat_left!=0)begin
     repeat_left<=repeat_left-1'b1;
     pixel_addr<=pixel_addr+((repeat_left==2)?FRAME_WIDTH-1:32'd1);
    end else pixel_valid<=0;
   end
   if(start && !busy) begin
    length<=file_size;expected<=0;bmp_size<=0;pixel_offset<=0;
    height<=0;bad_signature<=0;bad_header<=0;eof_seen<=0;
    bad_width<=0;bad_half_width<=0;half_mode<=0;repeat_left<=0;
    phase<=0;pad_left<=0;column<=0;rows_left<=FRAME_HEIGHT;pixel_count<=0;row_base<=0;
    pixel_valid<=0;busy<=1;error<=(file_size<54);state<=(file_size<54)?DRAIN:HEADER;
   end else if(busy) begin
    if(stream_done && stream_error) begin
     error<=1;busy<=0;done<=1;pixel_valid<=0;repeat_left<=0;state<=IDLE;
    end else if(eof_seen && !pixel_valid) begin
     done<=1;busy<=0;state<=IDLE;
     if(state!=TAIL || expected!=length || pixel_count!=source_pixels) error<=1;
    end else begin
     if(stream_done) eof_seen<=1;
     if(state==CHECK) begin
      if(bad_signature || bad_header || (bad_width && (!HALF_ALLOWED || bad_half_width)) ||
         !(select_half?(height==HALF_HEIGHT || height==(-HALF_HEIGHT)):
                       (height==FRAME_HEIGHT || height==(-FRAME_HEIGHT))) ||
         pixel_offset<54 || pixel_end>{32'b0,length} || pixel_end>{32'b0,bmp_size} || bmp_size>length) begin
       error<=1;state<=DRAIN;
      end else begin
       top_down<=height[31];half_mode<=select_half;
       rows_left<=select_half?HALF_HEIGHT:FRAME_HEIGHT;
       row_base<=height[31]?0:(select_half?(FRAME_HEIGHT-2)*FRAME_WIDTH:(FRAME_HEIGHT-1)*FRAME_WIDTH);
       state<=(pixel_offset==54)?PIXELS:SKIP;
      end
     end
     if(byte_valid && byte_ready) begin
      expected<=expected+1'b1;
      if(byte_offset!=expected || expected>=length) begin error<=1;state<=DRAIN;end
      else case(state)
       HEADER:begin
        case(expected)
         0:if(byte_data!=8'h42)bad_signature<=1;
         1:if(byte_data!=8'h4d)bad_signature<=1;
         2:bmp_size[7:0]<=byte_data;3:bmp_size[15:8]<=byte_data;4:bmp_size[23:16]<=byte_data;5:bmp_size[31:24]<=byte_data;
         10:pixel_offset[7:0]<=byte_data;11:pixel_offset[15:8]<=byte_data;12:pixel_offset[23:16]<=byte_data;13:pixel_offset[31:24]<=byte_data;
         // Ordered header bytes are all received before CHECK. Keep a sticky
         // mismatch instead of storing fields used only for fixed comparisons.
         14:if(byte_data!=8'd40)bad_header<=1;
         15,16,17,27,29,30,31,32,33:if(byte_data!=0)bad_header<=1;
         18:begin
          if(byte_data!=EXPECTED_WIDTH[7:0])bad_width<=1;
          if(byte_data!=EXPECTED_HALF_WIDTH[7:0])bad_half_width<=1;
         end
         19:begin
          if(byte_data!=EXPECTED_WIDTH[15:8])bad_width<=1;
          if(byte_data!=EXPECTED_HALF_WIDTH[15:8])bad_half_width<=1;
         end
         20:begin
          if(byte_data!=EXPECTED_WIDTH[23:16])bad_width<=1;
          if(byte_data!=EXPECTED_HALF_WIDTH[23:16])bad_half_width<=1;
         end
         21:begin
          if(byte_data!=EXPECTED_WIDTH[31:24])bad_width<=1;
          if(byte_data!=EXPECTED_HALF_WIDTH[31:24])bad_half_width<=1;
         end
         22:height[7:0]<=byte_data;23:height[15:8]<=byte_data;24:height[23:16]<=byte_data;25:height[31:24]<=byte_data;
         26:if(byte_data!=8'd1)bad_header<=1;
         28:if(byte_data!=8'd24)bad_header<=1;
         53:state<=CHECK;
        endcase
       end
       SKIP:if(expected+1'b1==pixel_offset)state<=PIXELS;
       PIXELS:case(phase)
        0:begin blue<=byte_data;phase<=1;end
        1:begin green<=byte_data;phase<=2;end
        2:begin
         pixel_rgb<={byte_data,green,blue};
         pixel_addr<=row_base+(half_mode?{column,1'b0}:column);pixel_valid<=1;
         repeat_left<=half_mode?2'd3:2'd0;
         pixel_count<=pixel_count+1'b1;phase<=0;
         if(column==(half_mode?HALF_WIDTH-1:FRAME_WIDTH-1))begin
          column<=0;rows_left<=rows_left-1'b1;
          row_base<=top_down?row_base+(half_mode?FRAME_WIDTH*2:FRAME_WIDTH):
                            row_base-(half_mode?FRAME_WIDTH*2:FRAME_WIDTH);
          if((half_mode?HALF_PAD:ROW_PAD)!=0)begin pad_left<=half_mode?HALF_PAD:ROW_PAD;state<=PADDING;end
          else if(rows_left==1)state<=TAIL;
         end else column<=column+1'b1;
        end
       endcase
       PADDING:begin pad_left<=pad_left-1'b1;if(pad_left==1)state<=(rows_left==0)?TAIL:PIXELS;end
       TAIL:;
       DRAIN:;
       default:begin error<=1;state<=DRAIN;end
      endcase
     end
    end
   end
  end
 end
endmodule
