// Checked 24-bit BITMAPINFOHEADER BMP stream -> addressed RGB pixels.
// Default dimensions match the competition. Negative height (top-down) accepted.
// All inputs/outputs use ready/valid. No byte after EOF is required to complete.
// Invalid headers are drained; a transport error aborts. Commit only done&&!error.
module bmp_stream_decoder #(parameter integer FRAME_WIDTH=640,FRAME_HEIGHT=480)(
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
 reg [2:0] state;
 reg [31:0] length,expected,bmp_size,pixel_offset,height;
 reg bad_signature,bad_header,eof_seen,top_down;
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
 wire [63:0] pixel_end={32'b0,pixel_offset}+STRIDE*FRAME_HEIGHT;
 assign byte_ready=busy && state!=CHECK && state!=IDLE && (!pixel_valid || pixel_ready);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;length<=0;expected<=0;bmp_size<=0;pixel_offset<=0;
   height<=0;bad_signature<=0;bad_header<=0;eof_seen<=0;top_down<=0;
   phase<=0;pad_left<=0;blue<=0;green<=0;column<=0;rows_left<=0;row_base<=0;pixel_count<=0;
   pixel_valid<=0;pixel_addr<=0;pixel_rgb<=0;busy<=0;done<=0;error<=0;
  end else begin
   done<=0;
   if(pixel_valid && pixel_ready) pixel_valid<=0;
   if(start && !busy) begin
    length<=file_size;expected<=0;bmp_size<=0;pixel_offset<=0;
    height<=0;bad_signature<=0;bad_header<=0;eof_seen<=0;
    phase<=0;pad_left<=0;column<=0;rows_left<=FRAME_HEIGHT;pixel_count<=0;row_base<=0;
    pixel_valid<=0;busy<=1;error<=(file_size<54);state<=(file_size<54)?DRAIN:HEADER;
   end else if(busy) begin
    if(stream_done && stream_error) begin
     error<=1;busy<=0;done<=1;pixel_valid<=0;state<=IDLE;
    end else if(eof_seen && !pixel_valid) begin
     done<=1;busy<=0;state<=IDLE;
     if(state!=TAIL || expected!=length || pixel_count!=FRAME_WIDTH*FRAME_HEIGHT) error<=1;
    end else begin
     if(stream_done) eof_seen<=1;
     if(state==CHECK) begin
      if(bad_signature || bad_header || !(height==FRAME_HEIGHT || height==(-FRAME_HEIGHT)) ||
         pixel_offset<54 || pixel_end>{32'b0,length} || pixel_end>{32'b0,bmp_size} || bmp_size>length) begin
       error<=1;state<=DRAIN;
      end else begin
       top_down<=height[31];row_base<=height[31]?0:(FRAME_HEIGHT-1)*FRAME_WIDTH;
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
         18:if(byte_data!=EXPECTED_WIDTH[7:0])bad_header<=1;
         19:if(byte_data!=EXPECTED_WIDTH[15:8])bad_header<=1;
         20:if(byte_data!=EXPECTED_WIDTH[23:16])bad_header<=1;
         21:if(byte_data!=EXPECTED_WIDTH[31:24])bad_header<=1;
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
         pixel_rgb<={byte_data,green,blue};pixel_addr<=row_base+column;pixel_valid<=1;
         pixel_count<=pixel_count+1'b1;phase<=0;
         if(column==FRAME_WIDTH-1)begin
          column<=0;rows_left<=rows_left-1'b1;row_base<=top_down?row_base+FRAME_WIDTH:row_base-FRAME_WIDTH;
          if(ROW_PAD!=0)begin pad_left<=ROW_PAD;state<=PADDING;end
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
