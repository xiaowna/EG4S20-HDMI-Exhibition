`timescale 1ns/1ps

module tb_bmp_header;
 parameter integer FRAME_WIDTH=3,FRAME_HEIGHT=2;
 localparam integer STRIDE=(FRAME_WIDTH*3+3)/4*4;
 localparam integer IMAGE_BYTES=STRIDE*FRAME_HEIGHT;
 localparam integer MAX_BYTES=IMAGE_BYTES+512;
 reg clk=0;
 always #5 clk=~clk;
 reg rst_n=1,start=0;
 reg [31:0] file_size=0,byte_offset=0;
 reg [7:0] byte_data=0;
 reg byte_valid=0,stream_done=0,stream_error=0,pixel_ready=1;
 wire byte_ready,pixel_valid,busy,done,error;
 wire [31:0] pixel_addr;
 wire [23:0] pixel_rgb;
 bmp_stream_decoder #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT)) dut (.*);
`ifdef COMPARE_BASELINE
 wire b_byte_ready,b_pixel_valid,b_busy,b_done,b_error;
 wire [31:0] b_pixel_addr;
 wire [23:0] b_pixel_rgb;
 bmp_stream_decoder_baseline #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT)) baseline (
  .clk(clk),.rst_n(rst_n),.start(start),.file_size(file_size),
  .byte_data(byte_data),.byte_offset(byte_offset),.byte_valid(byte_valid),
  .byte_ready(b_byte_ready),.stream_done(stream_done),.stream_error(stream_error),
  .pixel_ready(pixel_ready),.pixel_valid(b_pixel_valid),.pixel_addr(b_pixel_addr),
  .pixel_rgb(b_pixel_rgb),.busy(b_busy),.done(b_done),.error(b_error));
`endif

 reg [7:0] image[0:MAX_BYTES-1];
 reg active=0,allow_pixels=0,expected_top=0,prior_stall=0;
 reg [31:0] stalled_addr=0;
 reg [23:0] stalled_rgb=0;
 reg [31:0] random_state=32'hc47a96d3;
 reg [8*96-1:0] case_name;
 integer total_length=0,offset=54,pixels=0,done_seen=0;
 integer checks=0,scenarios=0,field_mutations=0,header_checks=0;
 integer expect_addr=0;
 reg accepted=0;

 function [23:0] rgb_for_addr(input integer address);
  reg [7:0] r,g,b;
  begin
   r=address*7+3;g=address*11+5;b=address*13+9;
   rgb_for_addr={r,g,b};
  end
 endfunction

 always @(posedge clk) begin
  if(rst_n && active) begin
   if(pixel_valid && !allow_pixels)
    $fatal(1,"Pixel exposed for an invalid/unchecked header case=%0s",case_name);
   if(prior_stall && !(stream_done && stream_error) &&
      (!pixel_valid || pixel_addr!==stalled_addr || pixel_rgb!==stalled_rgb))
    $fatal(1,"Pixel changed under backpressure case=%0s",case_name);
   if(pixel_valid && pixel_ready) begin
    if(pixels>=FRAME_WIDTH*FRAME_HEIGHT)
     $fatal(1,"Extra pixel case=%0s",case_name);
    expect_addr=(expected_top ? pixels/FRAME_WIDTH : FRAME_HEIGHT-1-pixels/FRAME_WIDTH)*FRAME_WIDTH+
                pixels%FRAME_WIDTH;
    if(pixel_addr!==expect_addr || pixel_rgb!==rgb_for_addr(expect_addr))
     $fatal(1,"Pixel #%0d got addr=%0d rgb=%h expected addr=%0d rgb=%h case=%0s",
            pixels,pixel_addr,pixel_rgb,expect_addr,rgb_for_addr(expect_addr),case_name);
    pixels=pixels+1;
   end
   prior_stall=pixel_valid && !pixel_ready && !(stream_done && stream_error);
   stalled_addr=pixel_addr;stalled_rgb=pixel_rgb;
  end else prior_stall=0;
  #1;
  checks=checks+1;
`ifdef COMPARE_BASELINE
  if({byte_ready,pixel_valid,pixel_addr,pixel_rgb,busy,done,error} !==
     {b_byte_ready,b_pixel_valid,b_pixel_addr,b_pixel_rgb,b_busy,b_done,b_error})
   $fatal(1,"Public output cycle mismatch t=%0t case=%0s",$time,case_name);
`endif
  if(active && rst_n && done) done_seen=done_seen+1;
 end

 // eof_mode: 0 = no EOF, 1 = unconditional EOF, 2 = EOF only when this byte is accepted.
 task tick(input reg valid,input integer address,input reg [7:0] value,
           input integer eof_mode,input reg failed,input reg ready,input reg begin_again);
  begin
   @(negedge clk);
   byte_valid=valid;byte_offset=address;byte_data=value;
   stream_error=failed;pixel_ready=ready;start=begin_again;stream_done=0;
   #1;
   stream_done=(eof_mode==1 || (eof_mode==2 && byte_valid && byte_ready));
   @(posedge clk);
   accepted=byte_valid && byte_ready;
   #2;
  end
 endtask

 task idle_tick;
  begin tick(0,0,0,0,0,1,0);end
 endtask

 task reset_decoder;
  begin
   active=0;
   @(negedge clk);rst_n=0;start=0;byte_valid=0;stream_done=0;stream_error=0;pixel_ready=1;
   repeat(3) idle_tick;
   @(negedge clk);rst_n=1;
   idle_tick;
   if(busy || done || error || pixel_valid || byte_ready)
    $fatal(1,"Reset did not clear public status");
  end
 endtask

 task put32(input integer address,input reg [31:0] value);
  begin
   image[address]=value[7:0];image[address+1]=value[15:8];
   image[address+2]=value[23:16];image[address+3]=value[31:24];
  end
 endtask

 task make_image(input reg top,input integer skip,input integer tail);
  integer i,row,col,address,p;
  reg [23:0] rgb;
  begin
   offset=54+skip;total_length=offset+IMAGE_BYTES+tail;expected_top=top;
   for(i=0;i<total_length+8;i=i+1) image[i]=8'hc9;
   for(i=0;i<54;i=i+1) image[i]=0;
   image[0]=8'h42;image[1]=8'h4d;
   put32(2,total_length);put32(10,offset);put32(14,40);put32(18,FRAME_WIDTH);
   put32(22,top ? -FRAME_HEIGHT : FRAME_HEIGHT);image[26]=1;image[28]=24;
   put32(34,IMAGE_BYTES);
   for(row=0;row<FRAME_HEIGHT;row=row+1) begin
    for(col=0;col<FRAME_WIDTH;col=col+1) begin
     address=(top ? row : FRAME_HEIGHT-1-row)*FRAME_WIDTH+col;
     rgb=rgb_for_addr(address);p=offset+row*STRIDE+col*3;
     image[p]=rgb[7:0];image[p+1]=rgb[15:8];image[p+2]=rgb[23:16];
    end
   end
  end
 endtask

 task begin_file(input reg [8*96-1:0] label_name,input integer length,input reg permit_pixels);
  begin
   if(busy) $fatal(1,"Previous file still busy");
   case_name=label_name;file_size=length;pixels=0;done_seen=0;
   prior_stall=0;allow_pixels=permit_pixels;active=1;scenarios=scenarios+1;
   tick(0,0,0,0,0,1,1);
   if(!busy || done || error!==(length<54) || pixel_valid)
    $fatal(1,"Start status wrong case=%0s",case_name);
  end
 endtask

 task wait_finished(input reg failed,input integer expected_pixels);
  integer spins;
  begin
   spins=0;
   while(done_seen==0 && spins<40) begin idle_tick;spins=spins+1;end
   if(done_seen!=1 || busy || error!==failed || pixel_valid || pixels!=expected_pixels)
    $fatal(1,"Completion done=%0d busy=%b error=%b pixels=%0d expected=%0d case=%0s",
           done_seen,busy,error,pixels,expected_pixels,case_name);
   idle_tick;
   if(done || done_seen!=1 || byte_ready)
    $fatal(1,"done must be a single pulse, ready low while idle case=%0s",case_name);
   active=0;
  end
 endtask

 // order_mode: 0 ordered, 1 skip an offset at byte 20, 2 repeat byte-20 offset at byte 21.
 task send_bytes(input integer count,input reg gaps,input reg final_eof,
                 input integer order_mode,input reg inspect_check,input reg header_bad,
                 input reg busy_start);
  integer i,address,spins;
  reg valid,ready;
  begin
   i=0;spins=0;
   while(i<count) begin
    random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
    valid=!gaps || random_state[3:0]!=0;
    ready=!gaps || random_state[5] || random_state[9];
    address=i;
    if(order_mode==1 && i==20) address=21;
    if(order_mode==2 && i==21) address=20;
    tick(valid,address,image[i],final_eof && i==count-1 ? 2 : 0,0,ready,
         busy_start && (i==12 || i==53 || i==offset+5));
    spins=spins+1;
    if(done_seen || !busy)
     $fatal(1,"Premature completion before EOF case=%0s byte=%0d",case_name,i);
    if(accepted) begin
     i=i+1;
     if(i==54 && inspect_check) begin
      if(error || byte_ready || pixel_valid)
       $fatal(1,"Header rejected before CHECK or failed to stall CHECK case=%0s",case_name);
      idle_tick;
      if(error!==header_bad || !busy || done || pixel_valid)
       $fatal(1,"Header CHECK timing/result wrong case=%0s",case_name);
      header_checks=header_checks+1;
     end
    end
    if(spins>count*8+100)
     $fatal(1,"Input did not drain case=%0s byte=%0d",case_name,i);
   end
   if(!final_eof) begin
    repeat(3) begin
     idle_tick;
     if(!busy || done) $fatal(1,"Completed without EOF case=%0s",case_name);
    end
    tick(0,0,0,1,0,1,0);
   end
  end
 endtask

 task invalid_field(input integer address,input integer bit_index);
  begin
   make_image(0,0,0);image[address]=image[address]^(8'b1<<bit_index);
   begin_file("single header-field bit mutation",total_length,0);
   send_bytes(total_length,1,1,0,1,1,0);
   wait_finished(1,0);field_mutations=field_mutations+1;
  end
 endtask

 task valid_file(input reg top,input integer skip,input integer tail,input reg eof_same);
  begin
   make_image(top,skip,tail);
   begin_file("valid pixels, row padding, random backpressure",total_length,1);
   send_bytes(total_length,1,eof_same,0,1,0,1);
   wait_finished(0,FRAME_WIDTH*FRAME_HEIGHT);
  end
 endtask

 integer i,j;
 initial begin
  reset_decoder;
  valid_file(0,0,0,1);
  valid_file(1,19,11,0);
  if(FRAME_WIDTH<10) begin
   valid_file(0,67,7,0);
   // Finish a sticky fixed-field rejection, then accept a clean file with only
   // start between them. This must clear bad_header independently of reset.
   make_image(0,0,0);image[30]=1;
   begin_file("bad compression drained before clean restart",total_length,0);
   send_bytes(total_length,1,1,0,1,1,0);wait_finished(1,0);
   valid_file(1,3,0,1);
   // Every bit of the 32/32/16/16/32-bit fixed fields, not merely byte extremes.
   for(i=14;i<=21;i=i+1) for(j=0;j<8;j=j+1) invalid_field(i,j);
   for(i=26;i<=33;i=i+1) for(j=0;j<8;j=j+1) invalid_field(i,j);
   for(i=0;i<2;i=i+1) for(j=0;j<8;j=j+1) invalid_field(i,j);
   for(i=0;i<4;i=i+1) begin
    make_image(0,0,0);
    case(i)
     0:put32(22,0);
     1:put32(22,FRAME_HEIGHT+1);
     2:put32(22,-FRAME_HEIGHT-1);
     3:put32(22,32'h80000000);
    endcase
    begin_file("invalid height",total_length,0);
    send_bytes(total_length,1,1,0,1,1,0);wait_finished(1,0);
   end
   for(i=0;i<5;i=i+1) begin
    make_image(0,0,0);
    case(i)
     0:put32(10,53);
     1:put32(10,32'hfffffffe);
     2:put32(2,total_length-1);
     3:put32(2,total_length+1);
     4:put32(10,55);
    endcase
    begin_file("invalid size or pixel offset",total_length,0);
    send_bytes(total_length,1,1,0,1,1,0);wait_finished(1,0);
   end
   // file_size, independent of the header's size, remains a hard outer boundary.
   make_image(0,0,0);
   begin_file("outer length less than header",53,0);
   send_bytes(53,1,1,0,0,0,0);wait_finished(1,0);
   make_image(0,0,0);
   begin_file("truncated header",total_length,0);
   send_bytes(30,1,1,0,0,0,0);wait_finished(1,0);
   make_image(0,0,0);
   begin_file("truncated pixel data",total_length,1);
   send_bytes(offset+4,1,1,0,1,0,0);wait_finished(1,1);
   for(i=1;i<=2;i=i+1) begin
    make_image(0,0,0);
    begin_file("out-of-order or duplicate header offset",total_length,0);
    send_bytes(total_length,1,1,i,0,0,0);wait_finished(1,0);
   end
   make_image(0,0,0);
   begin_file("byte after declared length",total_length,1);
   send_bytes(total_length+1,1,1,0,1,0,0);wait_finished(1,FRAME_WIDTH*FRAME_HEIGHT);
   make_image(0,0,0);
   begin_file("transport abort during header",total_length,0);
   for(i=0;i<20;i=i+1) tick(1,i,image[i],0,0,1,0);
   tick(0,0,0,1,1,1,0);wait_finished(1,0);
   // stream_error without stream_done is ignored, as before the optimization.
   make_image(0,0,0);
   begin_file("error flag without completion",total_length,1);
   tick(0,0,0,0,1,1,0);
   send_bytes(total_length,1,1,0,1,0,0);wait_finished(0,FRAME_WIDTH*FRAME_HEIGHT);
   // Abort while an output pixel is held, then immediately restart a valid file.
   make_image(0,0,0);
   begin_file("transport abort with stalled pixel",total_length,1);
   for(i=0;i<54;i=i+1) tick(1,i,image[i],0,0,1,0);
   idle_tick;
   for(i=54;i<57;i=i+1) tick(1,i,image[i],0,0,0,0);
   if(!pixel_valid) $fatal(1,"Expected held first pixel");
   repeat(4) tick(0,0,0,0,0,0,0);
   tick(0,0,0,1,1,0,0);wait_finished(1,0);
   valid_file(1,1,0,1);
   // A dirty partial header and sticky rejection must never survive reset/start.
   make_image(0,0,0);image[14]=41;
   begin_file("reset during malformed header",total_length,0);
   for(i=0;i<30;i=i+1) tick(1,i,image[i],0,0,1,0);
   reset_decoder;
   valid_file(0,0,0,1);
  end
  $display("PASS BMP %0dx%0d: %0d scenarios, %0d field/signature bit mutations, %0d CHECK timing checks, %0d public-output cycles",
           FRAME_WIDTH,FRAME_HEIGHT,scenarios,field_mutations,header_checks,checks);
  $finish;
 end
 initial begin #100000000;$fatal(1,"BMP header regression timeout");end
endmodule
