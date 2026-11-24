// Fixed 640x480 introduction producer, synchronous to sys_clk. The caller
// shares its existing asynchronous pixel FIFO with the ordinary/slide engine.
// A full source scanline is fetched while the previous scanline is composed.
// Quotient/remainder DDAs select exact floor-scaled source coordinates.
module frame_intro_prefetch #(parameter MAX_BURST=32,TIMEOUT_CYCLES=1000000,GALLERY_CAPTIONS=0,CACHE_FRAMES=0)(
 input wire rst_n,sys_clk,start,input wire [31:0] frame_base,input wire [20:0] back_base,
 input wire [1:0] topic,input wire [5:0] phase,
 output wire start_ready,output reg busy,done,error,
 output wire burst_valid,output wire [31:0] burst_addr,
 output wire [8:0] burst_words,input wire burst_ready,
 input wire burst_data_valid,burst_last,burst_error,input wire [31:0] burst_data,
 output wire pixel_valid,output wire [31:0] pixel_addr,
 output wire [23:0] pixel_rgb,output wire pixel_last,input wire pixel_ready,
 input wire intro_active,slide_active,slide_right,input wire [15:0] slide_offset,
 input wire [5:0] slide_alpha);
 localparam integer FRAME_PIXELS=640*480;
 localparam integer TIMER_BITS=(TIMEOUT_CYCLES>1)?$clog2(TIMEOUT_CYCLES):1;
 localparam C_IDLE=0,C_REQUEST=1,C_CAPTURE=2,C_CHECK=3,C_READY=4;
 localparam F_IDLE=0,F_PREP=1,F_ISSUE=2,F_RECEIVE=3;
 reg [2:0] config_state;
 reg [1:0] fetch_state,topic_hold;
 reg [5:0] phase_hold;
 reg [20:0] base,source_cursor,request_address;
 reg [2:0] config_index;
 reg config_bad,config_source,intro_hold,sliding_hold,direction_hold;
 reg [1:0] style_hold;
 reg [9:0] distance_hold,segment_left;
 reg segment_first;
 reg [20:0] second_address;
 reg [5:0] caption_alpha;
 reg [6:0] caption_offset;
 function [11:0] caption_entrance;
  input [5:0] p;
  begin case(p)
   0,1:caption_entrance={6'd16,6'd16};2:caption_entrance={6'd17,6'd15};
   3:caption_entrance={6'd19,6'd13};4:caption_entrance={6'd20,6'd12};
   5:caption_entrance={6'd22,6'd10};6:caption_entrance={6'd24,6'd8};
   7:caption_entrance={6'd26,6'd6};8:caption_entrance={6'd28,6'd4};
   9:caption_entrance={6'd30,6'd2};10:caption_entrance={6'd31,6'd1};
   default:caption_entrance={6'd32,6'd0};
  endcase end
 endfunction
 wire [11:0] entrance=caption_entrance(phase);
 wire select_intro=!GALLERY_CAPTIONS||intro_active;
 reg [9:0] source_x,source_width,dest_x,dest_width,x_remainder;
 reg [8:0] source_y,source_height,dest_y,dest_height,y_remainder;
 reg [1:0] x_quotient,y_quotient;
 reg [5:0] text_alpha;
 reg [6:0] text_offset;
 wire [15:0] geometry_data;
 wire geometry_enable=busy&&!error&&config_state==C_REQUEST;
 intro_geometry_rom geometry(.clk(sys_clk),.en(geometry_enable),
  .address({topic_hold,config_source?6'd0:phase_hold,config_index}),.data(geometry_data));

 reg [1:0] line_ready;
 reg [8:0] line_row0,line_row1;
 reg fetch_bank,emit_bank;
 reg [8:0] fetch_row,emit_row,image_source_y,y_error;
 reg [9:0] fetch_column,emit_column,image_source_x,x_error;
 reg [8:0] reserved,received;
 reg [TIMER_BITS-1:0] timer;
 reg [18:0] output_offset;
 reg request_valid,request_background,request_line_last,request_bank,request_caption;
 reg [18:0] output_address;
 reg [9:0] output_x;
 reg [8:0] output_y;
 wire [23:0] line_rgb;
 wire shader_valid;
 wire [18:0] shader_address;
 wire [23:0] shader_rgb;
 // A stalled final shader pixel freezes RAM reads and every pixel metadata
 // register. The independent fill engine can still finish the other bank.
 wire pipeline_ce=error||!shader_valid||pixel_ready;
 wire emit_row_ready=line_ready[emit_bank]&&
  ((emit_bank?line_row1:line_row0)==emit_row);
 wire image_row=emit_row>=dest_y&&{1'b0,emit_row}<{1'b0,dest_y}+dest_height;
 wire image_pixel=image_row&&emit_column>=dest_x&&
  {1'b0,emit_column}<{1'b0,dest_x}+dest_width;
 wire [8:0] caption_top=9'd352+caption_offset;
 wire caption_row=GALLERY_CAPTIONS&&emit_row>=caption_top&&emit_row<416;
 wire caption_pixel=caption_row&&emit_column>=18&&emit_column<622;
 wire plain_picture=!intro_hold&&emit_row<352;
 wire issue_pixel=busy&&!error&&config_state==C_READY&&emit_row<480&&emit_row_ready;
 wire read_line=pipeline_ce&&issue_pixel;
 wire [9:0] read_column=(plain_picture||caption_row)?emit_column:(image_pixel?image_source_x:10'd0);
 wire release_line=pipeline_ce&&request_valid&&request_line_last;
 wire [10:0] x_sum={1'b0,x_error}+{1'b0,x_remainder};
 wire x_carry=x_sum>={1'b0,dest_width};
 wire [9:0] y_sum={1'b0,y_error}+{1'b0,y_remainder};
 wire y_carry=y_sum>={1'b0,dest_height};
 wire fetch_image_row=fetch_row>=dest_y&&{1'b0,fetch_row}<{1'b0,dest_y}+dest_height;
 wire fetch_caption_row=GALLERY_CAPTIONS&&fetch_row>=caption_top&&fetch_row<416;
 wire [8:0] selected_source_row=fetch_caption_row?(9'd384+fetch_row-caption_top):
  ((intro_hold&&fetch_image_row)?image_source_y:fetch_row);
 wire [20:0] selected_row_base=base+({12'd0,selected_source_row}<<9)+({12'd0,selected_source_row}<<7);
 wire [9:0] row_remaining=10'd640-fetch_column;
 wire [8:0] sdram_row_remaining=9'd256-{1'b0,source_cursor[7:0]};
 wire [9:0] limit1=(row_remaining<MAX_BURST)?row_remaining:MAX_BURST;
 wire [9:0] limit2=(limit1<{1'b0,sdram_row_remaining})?limit1:{1'b0,sdram_row_remaining};
 wire [9:0] planned=(segment_left<limit2)?segment_left:limit2;
 reg [20:0] alternate_base;
 wire [20:0] other_base=CACHE_FRAMES?alternate_base:((base==0)?21'd307200:21'd0);
 wire [20:0] output_row_base=({12'd0,fetch_row}<<9)+({12'd0,fetch_row}<<7);
 // Every style still fetches exactly two source segments per picture row.
 // Reveal keeps both photographs fixed. Banded reveal reverses alternate
 // 32-pixel strips, producing a curtain effect without another frame bank.
 wire line_direction=direction_hold^((style_hold==2)&&fetch_row[5]);
 wire [9:0] first_length=line_direction?distance_hold:10'd640-distance_hold;
 wire [9:0] first_column=(style_hold!=0)?10'd0:
  (line_direction?10'd640-distance_hold:distance_hold);
 wire [9:0] second_column=(style_hold!=0)?first_length:10'd0;
 wire bad_response=burst_data_valid&&
  (fetch_state!=F_RECEIVE||received>=reserved||burst_last!=(received==reserved-1'b1));
 wire take_data=busy&&!error&&fetch_state==F_RECEIVE&&burst_data_valid&&!bad_response&&!burst_error;
 wire [9:0] write_column=fetch_column+{1'b0,received};
 intro_line_store lines(.clk(sys_clk),.write_enable(take_data),.write_bank(fetch_bank),
  .write_addr(write_column),.write_rgb(burst_data[23:0]),.read_enable(read_line),
  .read_bank(emit_bank),.read_addr(read_column),.read_rgb(line_rgb));
 intro_text_layer #(.CAPTION_BITMAP(GALLERY_CAPTIONS)) text_layer(.clk(sys_clk),.rst_n(rst_n),.ce(pipeline_ce),
  .valid_in(request_valid),.pixel_addr(output_address),.pixel_x(output_x),.pixel_y(output_y),
  .rgb_in(request_background?24'h060c14:line_rgb),.topic(topic_hold),
  .text_offset(text_offset),.text_alpha(text_alpha),
  .caption_pixel(request_caption),.caption_alpha(caption_alpha),
  .valid_out(shader_valid),.addr_out(shader_address),.rgb_out(shader_rgb));
 assign start_ready=!busy&&!error&&fetch_state==F_IDLE&&!request_valid&&!shader_valid;
 assign burst_valid=busy&&!error&&fetch_state==F_ISSUE;
 assign burst_addr={11'd0,request_address};
 assign burst_words=reserved;
 assign pixel_valid=busy&&!error&&shader_valid;
 assign pixel_addr={13'd0,shader_address};
 assign pixel_rgb=shader_rgb;
 assign pixel_last=shader_address==FRAME_PIXELS-1;

 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin
   config_state<=C_IDLE;fetch_state<=F_IDLE;topic_hold<=0;phase_hold<=0;
   base<=0;alternate_base<=0;source_cursor<=0;request_address<=0;config_index<=0;config_bad<=0;
   config_source<=0;intro_hold<=0;sliding_hold<=0;direction_hold<=0;style_hold<=0;
   distance_hold<=0;segment_left<=0;segment_first<=0;second_address<=0;
   caption_alpha<=0;caption_offset<=0;request_caption<=0;
   source_x<=0;source_y<=0;source_width<=0;source_height<=0;
   dest_x<=0;dest_y<=0;dest_width<=0;dest_height<=0;
   x_quotient<=0;y_quotient<=0;x_remainder<=0;y_remainder<=0;text_alpha<=0;text_offset<=0;
   line_ready<=0;line_row0<=0;line_row1<=0;fetch_bank<=0;emit_bank<=0;
   fetch_row<=0;emit_row<=0;fetch_column<=0;emit_column<=0;
   image_source_y<=0;y_error<=0;image_source_x<=0;x_error<=0;
   reserved<=0;received<=0;timer<=0;output_offset<=0;output_address<=0;output_x<=0;output_y<=0;
   request_valid<=0;request_background<=0;request_line_last<=0;request_bank<=0;
   busy<=0;done<=0;error<=0;
  end else begin
   done<=0;
   if(!error)begin
    if(burst_error||bad_response)begin error<=1;busy<=0;end
    else if(start&&start_ready)begin
     if((CACHE_FRAMES?({32'b0,frame_base}+FRAME_PIXELS>64'd2097152 ||
          (slide_active&&({11'd0,back_base}+FRAME_PIXELS>32'd2097152||back_base==frame_base))):
          (frame_base!=0&&frame_base!=FRAME_PIXELS))||MAX_BURST<1||MAX_BURST>32||
        (GALLERY_CAPTIONS&&slide_active&&
         (slide_offset[15:12]!=0||slide_offset[11:10]==3||slide_offset[9:0]>=640)))begin error<=1;end
     else begin
      busy<=1;base<=frame_base[20:0];alternate_base<=back_base;topic_hold<=topic;phase_hold<=phase;
      config_state<=select_intro?C_REQUEST:C_READY;config_index<=0;config_bad<=0;config_source<=select_intro;fetch_state<=F_IDLE;
      intro_hold<=select_intro;
      sliding_hold<=GALLERY_CAPTIONS&&slide_active&&slide_offset[9:0]!=0;
      direction_hold<=slide_right;distance_hold<=slide_offset[9:0];
      style_hold<=GALLERY_CAPTIONS?slide_offset[11:10]:2'd0;
      // Immediately visible at half opacity, easing upward over 12 frames.
      // Exit slides retain their separate old-caption fade and fixed position.
      caption_alpha<=GALLERY_CAPTIONS?(slide_active?slide_alpha:(select_intro?6'd32:entrance[11:6])):6'd0;
      caption_offset<=GALLERY_CAPTIONS?((slide_active||select_intro)?7'd0:{1'b0,entrance[5:0]}):7'd64;
      line_ready<=0;fetch_bank<=0;emit_bank<=0;fetch_row<=0;emit_row<=0;
      fetch_column<=0;emit_column<=0;x_error<=0;y_error<=0;output_offset<=0;
      request_valid<=0;reserved<=0;received<=0;timer<=0;
      source_x<=0;source_y<=0;source_width<=640;source_height<=352;
      dest_x<=0;dest_y<=0;dest_width<=640;dest_height<=352;
      x_quotient<=1;y_quotient<=1;x_remainder<=0;y_remainder<=0;
      text_alpha<=0;text_offset<=64;image_source_x<=0;image_source_y<=0;
     end
    end else if(busy)begin
     case(config_state)
      C_REQUEST:config_state<=C_CAPTURE;
      C_CAPTURE:begin
       if(config_source)begin
        case(config_index)
         0:begin source_x<=geometry_data[9:0];if(geometry_data[15:10]!=0)config_bad<=1;end
         1:begin source_y<=geometry_data[8:0];if(geometry_data[15:9]!=0)config_bad<=1;end
         2:begin source_width<=geometry_data[9:0];if(geometry_data[15:10]!=0)config_bad<=1;end
         3:begin source_height<=geometry_data[8:0];if(geometry_data[15:9]!=0)config_bad<=1;end
        endcase
        if(config_index==3)begin config_source<=0;config_index<=0;end
        else config_index<=config_index+1'b1;
        config_state<=C_REQUEST;
       end else begin
       case(config_index)
        0:begin dest_x<=geometry_data[9:0];if(geometry_data[15:10]!=0)config_bad<=1;end
        1:begin dest_y<=geometry_data[8:0];if(geometry_data[15:9]!=0)config_bad<=1;end
        2:begin dest_width<=geometry_data[9:0];if(geometry_data[15:10]!=0)config_bad<=1;end
        3:begin dest_height<=geometry_data[8:0];if(geometry_data[15:9]!=0)config_bad<=1;end
        4:begin x_quotient<=geometry_data[11:10];x_remainder<=geometry_data[9:0];if(geometry_data[15:12]!=0)config_bad<=1;end
        5:begin y_quotient<=geometry_data[10:9];y_remainder<=geometry_data[8:0];if(geometry_data[15:11]!=0)config_bad<=1;end
        6:begin text_alpha<=geometry_data[12:7];text_offset<=geometry_data[6:0];if(geometry_data[15:13]!=0)config_bad<=1;end
        7:if(geometry_data!=0)config_bad<=1;
       endcase
       if(config_index==7)config_state<=C_CHECK;
       else begin config_index<=config_index+1'b1;config_state<=C_REQUEST;end
       end
      end
      C_CHECK:begin
       if(config_bad||dest_width==0||dest_height==0||
          {1'b0,dest_x}+dest_width>640||{1'b0,dest_y}+dest_height>352||
          source_width==0||source_height==0||{1'b0,source_x}+source_width>640||{1'b0,source_y}+source_height>352||
          x_quotient==0||y_quotient==0||x_remainder>=dest_width||y_remainder>=dest_height||
          (dest_width*x_quotient+x_remainder)!=source_width||
          (dest_height*y_quotient+y_remainder)!=source_height||text_alpha>32)begin
        error<=1;busy<=0;
       end else begin
        config_state<=C_READY;image_source_x<=source_x;image_source_y<=source_y;
       end
      end
      default:;
     endcase

     if(release_line)line_ready[request_bank]<=0;
     case(fetch_state)
      F_IDLE:if(config_state==C_READY&&fetch_row<480&&!line_ready[fetch_bank])begin
       fetch_column<=0;fetch_state<=F_PREP;
       if(sliding_hold&&fetch_row<352)begin
        segment_first<=1;segment_left<=first_length;
        source_cursor<=(line_direction?other_base:base)+output_row_base+first_column;
        second_address<=(line_direction?base:other_base)+output_row_base+second_column;
       end else begin
        source_cursor<=selected_row_base;segment_first<=0;segment_left<=640;
       end
      end
      F_PREP:begin
       request_address<=source_cursor;reserved<=planned[8:0];received<=0;timer<=0;fetch_state<=F_ISSUE;
      end
      F_ISSUE:if(burst_ready)begin timer<=0;fetch_state<=F_RECEIVE;end
       else if(timer>=TIMEOUT_CYCLES-1)begin error<=1;busy<=0;end else timer<=timer+1'b1;
      F_RECEIVE:if(take_data)begin
       timer<=0;
       if(burst_last)begin
        if(fetch_column+reserved==640)begin
         line_ready[fetch_bank]<=1;
         if(fetch_bank)line_row1<=fetch_row;else line_row0<=fetch_row;
         fetch_row<=fetch_row+1'b1;fetch_bank<=!fetch_bank;fetch_state<=F_IDLE;
         if(intro_hold&&fetch_image_row)begin
          image_source_y<=image_source_y+y_quotient+y_carry;
          y_error<=y_carry?y_sum-dest_height:y_sum;
         end
        end else begin
         fetch_column<=fetch_column+reserved;fetch_state<=F_PREP;
         if(segment_first&&segment_left==reserved)begin
          source_cursor<=second_address;segment_first<=0;
          segment_left<=line_direction?(10'd640-distance_hold):distance_hold;
         end else begin source_cursor<=source_cursor+reserved;segment_left<=segment_left-reserved;end
        end
       end else received<=received+1'b1;
      end else if(timer>=TIMEOUT_CYCLES-1)begin error<=1;busy<=0;end else timer<=timer+1'b1;
      default:begin error<=1;busy<=0;end
     endcase

     if(pipeline_ce)begin
      request_valid<=issue_pixel;
      if(issue_pixel)begin
       output_address<=output_offset;output_offset<=output_offset+1'b1;
       output_x<=emit_column;output_y<=emit_row;
       request_caption<=caption_pixel;
       request_background<=!(caption_pixel||plain_picture||(intro_hold&&image_pixel));
       request_line_last<=emit_column==639;request_bank<=emit_bank;
       if(emit_column==639)begin
        emit_column<=0;emit_row<=emit_row+1'b1;emit_bank<=!emit_bank;
        image_source_x<=source_x;x_error<=0;
       end else begin
        emit_column<=emit_column+1'b1;
        if(intro_hold&&image_pixel)begin
         image_source_x<=image_source_x+x_quotient+x_carry;
         x_error<=x_carry?x_sum-dest_width:x_sum;
        end
       end
      end
     end
     if(pixel_valid&&pixel_ready&&pixel_last)begin
      if(fetch_state!=F_IDLE||fetch_row!=480||request_valid)begin error<=1;busy<=0;end
      else begin busy<=0;done<=1;config_state<=C_IDLE;end
     end
    end
   end
  end
 end
endmodule
