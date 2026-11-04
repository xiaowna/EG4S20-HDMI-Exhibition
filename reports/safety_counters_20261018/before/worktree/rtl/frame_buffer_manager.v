// Two external-memory banks, RGB888 in one 32-bit WORD per pixel.
// All ports are synchronous to clk. No RAM, SDRAM PHY or CDC is inferred here.
// Producer supplies each pixel address exactly once per successful frame.
// wr_drained means every previously accepted write is committed and visible.
// swap_window must remain true only while display reads are safely quiescent.
module frame_buffer_manager #(parameter integer FRAME_PIXELS=640*480)(
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
 input wire mem_response_valid,input wire [31:0] mem_response_data);
 localparam IDLE=0,WRITE=1,DRAIN=2,PENDING=3;
 // Both banks occupy [0, 2*FRAME_PIXELS). Valid requests never need the
 // upper bits of a 32-bit adder; drive them to zero for the SDRAM controller.
 localparam integer ADDRESS_BITS=(FRAME_PIXELS<2)?1:$clog2(FRAME_PIXELS*2);
 localparam [ADDRESS_BITS-1:0] BANK_OFFSET=FRAME_PIXELS;
 reg [1:0] state;
 reg back_bank,bad_frame,read_pending;
 reg [31:0] accepted;
 wire address_ok=(pixel_addr<FRAME_PIXELS);
 wire pixel_take=pixel_valid && pixel_ready;
 wire read_take=mem_read_valid && mem_read_ready;
 assign frame_ready=(state==IDLE);
 assign swap_pending=(state==PENDING);
 // Invalid addresses are consumed and invalidate the frame, never sent to RAM.
 assign pixel_ready=(state==WRITE) && (address_ok?wr_ready:1'b1);
 assign wr_valid=(state==WRITE) && pixel_valid && address_ok;
 wire [ADDRESS_BITS-1:0] wr_word=pixel_addr[ADDRESS_BITS-1:0]+(back_bank?BANK_OFFSET:{ADDRESS_BITS{1'b0}});
 assign wr_addr={{(32-ADDRESS_BITS){1'b0}},wr_word};
 assign wr_data={8'b0,pixel_rgb};
 assign mem_read_valid=read_valid && front_valid && !swap_window &&
                       !read_pending && !rgb_valid && read_addr<FRAME_PIXELS;
 assign read_ready=front_valid && !swap_window && !read_pending && !rgb_valid &&
                   read_addr<FRAME_PIXELS && mem_read_ready;
 wire [ADDRESS_BITS-1:0] read_word=read_addr[ADDRESS_BITS-1:0]+(front_bank?BANK_OFFSET:{ADDRESS_BITS{1'b0}});
 assign mem_read_addr={{(32-ADDRESS_BITS){1'b0}},read_word};
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
     back_bank<=!front_bank;accepted<=0;bad_frame<=0;state<=WRITE;
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
    PENDING:if(swap_window && !read_pending && !rgb_valid)begin
     front_bank<=back_bank;front_valid<=1;frame_committed<=1;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
