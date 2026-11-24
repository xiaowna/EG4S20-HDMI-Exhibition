// RGB888 in one 32-bit word per pixel. The gallery retains up to six frames.
// All ports are synchronous to clk. No RAM, SDRAM PHY or CDC is inferred here.
// Producer supplies each pixel address exactly once per successful frame.
// wr_drained means every previously accepted write is committed and visible.
// swap_window must remain true only while display reads are safely quiescent.
module frame_buffer_manager #(parameter integer FRAME_PIXELS=640*480,ALLOW_DISCARD=0,CACHE_FRAMES=0,INDEX_BITS=5)(
 input wire clk,rst_n,
 input wire frame_start,frame_done,frame_error,output wire frame_ready,
 input wire pixel_valid,input wire [31:0] pixel_addr,input wire [23:0] pixel_rgb,
 output wire pixel_ready,
 output wire wr_valid,output wire [31:0] wr_addr,wr_data,input wire wr_ready,wr_drained,
 input wire swap_window,output reg front_valid,front_bank,frame_committed,frame_rejected,
 output wire swap_pending,
 input wire read_valid,input wire [31:0] read_addr,output wire read_ready,
 output reg rgb_valid,output reg [23:0] rgb_data,input wire rgb_ready,
 output wire mem_read_valid,output wire [31:0] mem_read_addr,input wire mem_read_ready,
 input wire mem_response_valid,input wire [31:0] mem_response_data,
 input wire discard_frame,output wire [6:0] prepare_pixels,
 input wire [INDEX_BITS-1:0] image_index,retain_first,
 input wire retain_album,reuse_frame,front_matches,output wire cache_hit,
 output wire [20:0] front_base,back_base);
 localparam IDLE=0,WRITE=1,DRAIN=2,PENDING=3;
 // Restrict address arithmetic to the configured number of frame slots.
 localparam integer ADDRESS_BITS=(FRAME_PIXELS<2)?1:$clog2(FRAME_PIXELS*(CACHE_FRAMES?6:2));
 localparam [ADDRESS_BITS-1:0] BANK_OFFSET=FRAME_PIXELS;
 reg [1:0] state;
 reg back_bank,bad_frame,read_pending;
 // The counter saturates at FRAME_PIXELS, including the final accepted pixel.
 localparam integer ACCEPTED_BITS=(FRAME_PIXELS>0)?$clog2(FRAME_PIXELS+1):1;
 reg [ACCEPTED_BITS-1:0] accepted;
 // Board progress: one unit per 4096 accepted output pixels, 75 per frame.
 // Reuse the safety counter; never count stalled/invalid memory writes twice.
 assign prepare_pixels=(state==IDLE)?7'd0:(accepted>>12);
 wire address_ok=(pixel_addr<FRAME_PIXELS);
 wire pixel_take=pixel_valid && pixel_ready;
 wire read_take=mem_read_valid && mem_read_ready;
 assign frame_ready=(state==IDLE);
 assign swap_pending=(state==PENDING);
 // Invalid addresses are consumed and invalidate the frame, never sent to RAM.
 assign pixel_ready=(state==WRITE) && (address_ok?wr_ready:1'b1);
 assign wr_valid=(state==WRITE) && pixel_valid && address_ok;
 wire [ADDRESS_BITS-1:0] wr_word=pixel_addr[ADDRESS_BITS-1:0]+back_base[ADDRESS_BITS-1:0];
 assign wr_addr={{(32-ADDRESS_BITS){1'b0}},wr_word};
 assign wr_data={8'b0,pixel_rgb};
 assign mem_read_valid=read_valid && front_valid && !swap_window &&
                       !read_pending && !rgb_valid && read_addr<FRAME_PIXELS;
 assign read_ready=front_valid && !swap_window && !read_pending && !rgb_valid &&
                   read_addr<FRAME_PIXELS && mem_read_ready;
 wire [ADDRESS_BITS-1:0] read_word=read_addr[ADDRESS_BITS-1:0]+front_base[ADDRESS_BITS-1:0];
 assign mem_read_addr={{(32-ADDRESS_BITS){1'b0}},read_word};
 wire reuse=CACHE_FRAMES&&reuse_frame;
 wire back_bit;
 generate if(CACHE_FRAMES)begin:cache
  reg [5:0] valid;
  reg [INDEX_BITS-1:0] group_first;
  reg [2:0] front_slot,back_slot;
  reg cache_write;
  reg [20:0] active_base,write_base;
  function [20:0] slot_base;
   input [2:0] slot;
   begin
    case(slot)
     0:slot_base=0;
     1:slot_base=FRAME_PIXELS;
     2:slot_base=2*FRAME_PIXELS;
     3:slot_base=3*FRAME_PIXELS;
     4:slot_base=4*FRAME_PIXELS;
     default:slot_base=5*FRAME_PIXELS;
    endcase
   end
  endfunction
  // Map a topic's six ordinals directly. On album change, rotate the
  // mapping so the first new write cannot touch the still-visible page.
  reg [2:0] origin;
  wire same_group=group_first==retain_first;
  wire [2:0] page=image_index-retain_first;
  wire [2:0] next_origin=same_group?origin:
   (front_matches?front_slot:((front_slot==5)?3'd0:front_slot+1'b1));
  wire [3:0] raw_slot={1'b0,next_origin}+{1'b0,page};
  wire [2:0] album_slot=(raw_slot>=6)?raw_slot-4'd6:raw_slot;
  wire front_collision=front_valid&&album_slot==front_slot;
  wire [2:0] write_slot=(retain_album&&!front_collision)?album_slot:{2'b0,!front_bank};
  wire [2:0] target_slot=(reuse&&front_matches)?front_slot:(reuse?album_slot:write_slot);
  assign cache_hit=retain_album&&(front_matches||(same_group&&valid[album_slot]));
  assign front_base=active_base;assign back_base=write_base;
  assign back_bit=back_slot[0];
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
    valid<=0;cache_write<=0;group_first<={INDEX_BITS{1'b1}};origin<=0;front_slot<=0;back_slot<=0;active_base<=0;write_base<=0;
   end else begin
    if(state==IDLE&&frame_start)begin
     back_slot<=target_slot;
     write_base<=slot_base(target_slot);
     cache_write<=retain_album&&!front_collision;
     if(!retain_album)begin valid<=0;group_first<={INDEX_BITS{1'b1}};end
     else if(!same_group)begin
      valid<=front_matches?(6'b1<<front_slot):6'd0;group_first<=retain_first;origin<=next_origin;
     end else if(!reuse)valid[target_slot]<=0;
    end
    if(state==DRAIN&&wr_drained&&!bad_frame&&cache_write)valid[back_slot]<=1;
    if(state==PENDING&&!(ALLOW_DISCARD&&discard_frame)&&swap_window&&!read_pending&&!rgb_valid)begin
     front_slot<=back_slot;active_base<=write_base;
    end
   end
  end
 end else begin:legacy_banks
  assign cache_hit=0;
  assign front_base=front_bank?BANK_OFFSET:21'd0;
  assign back_base=back_bank?BANK_OFFSET:21'd0;
  assign back_bit=back_bank;
 end endgenerate
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;back_bank<=1;front_bank<=0;front_valid<=0;
   accepted<=0;bad_frame<=0;frame_committed<=0;frame_rejected<=0;
   read_pending<=0;rgb_valid<=0;rgb_data<=0;
  end else begin
   frame_committed<=0;frame_rejected<=0;
   if(rgb_valid && rgb_ready)rgb_valid<=0;
   if(read_take)read_pending<=1;
   // Also accept a zero-latency response on the request handshake edge.
   if(mem_response_valid && (read_pending || read_take))begin
    read_pending<=0;rgb_valid<=1;rgb_data<=mem_response_data[23:0];
   end
   case(state)
    IDLE:if(frame_start)begin
     back_bank<=!front_bank;accepted<=0;bad_frame<=0;state<=reuse?PENDING:WRITE;
    end
    WRITE:begin
     if(pixel_take)begin
      if(!address_ok || accepted>=FRAME_PIXELS)bad_frame<=1;
      if(accepted<FRAME_PIXELS)accepted<=accepted+1'b1;
     end
     if(frame_done)begin
      // Includes a final pixel accepted on the same edge as frame_done.
      if(frame_error || (pixel_valid && !pixel_ready) ||
         (pixel_take && (!address_ok || accepted>=FRAME_PIXELS)) ||
         (accepted+(pixel_take?32'd1:32'd0))!=FRAME_PIXELS)bad_frame<=1;
      state<=DRAIN;
     end
    end
    DRAIN:if(wr_drained)begin
     if(bad_frame)begin frame_rejected<=1;state<=IDLE;end
     else state<=PENDING;
    end
    PENDING:if(ALLOW_DISCARD && discard_frame)state<=IDLE;
    else if(swap_window && !read_pending && !rgb_valid)begin
     front_bank<=back_bit;front_valid<=1;frame_committed<=1;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
