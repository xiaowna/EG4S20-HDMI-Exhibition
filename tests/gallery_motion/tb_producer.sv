`timescale 1ns/1ps
// Actual asset ROMs, text shader and scanline producer. Expected rasters are
// independently generated from absolute source-coordinate and font equations.
module tb_gallery_motion_producer;
 parameter integer CACHE=0;
 reg intro_active=1,slide_active=0,slide_right=0;
 reg [15:0] slide_offset=0;reg [5:0] slide_alpha=32;
 localparam N=640*480;
 reg sys_clk=0,rst_n=0,start=0;
 always #10 sys_clk=~sys_clk;
 reg [31:0] frame_base=0;
 reg [20:0] back_base=0;
 localparam BASE_OFFSET=CACHE?4*N:0;
 reg [1:0] topic=0;
 reg [5:0] phase=0;
 wire start_ready,busy,done,error,burst_valid,pixel_valid,pixel_last;
 wire [31:0] burst_addr,pixel_addr;
 wire [8:0] burst_words;
 wire [23:0] pixel_rgb;
 reg burst_data_valid=0,burst_last=0,burst_error=0;
 reg [31:0] burst_data=0;
 integer cycles=0,pixels=0,commands=0,responses=0,cases=0;
 integer command_address=0,response=0,length=0,mode=0;
 integer case_topic=0,case_phase=0,case_bank=0,last_stall=0;
 integer case_count=0,number=0,check_pixels=0;
 reg responding=0,checking=0,hold_output=0;
 reg [56:0] held_output=0;
 reg held=0;
 string golden_path;
 reg [23:0] golden[0:N-1];
 reg [21:0] metadata[0:31];integer before_responses;
 wire burst_ready=!responding&&cycles%7!=0&&mode!=4;
 wire pixel_ready=!hold_output&&cycles%11!=0&&cycles%1501<1373&&
  !(pixel_valid&&pixel_last&&last_stall<512);
 frame_intro_prefetch #(.TIMEOUT_CYCLES(1024),.GALLERY_CAPTIONS(1),.CACHE_FRAMES(CACHE)) dut(.*);
 function automatic [23:0] color(input integer address);
  color=(address*37)^(address<<7)^24'h5a39c7;
 endfunction
 always @(posedge sys_clk)begin
  cycles<=cycles+1;
  if(!rst_n)begin responding=0;burst_data_valid=0;held=0;end
  if(rst_n&&burst_valid&&burst_ready)begin
   if(burst_words==0||burst_words>32||burst_addr[7:0]+burst_words>256||
      burst_addr<BASE_OFFSET||burst_addr+burst_words>BASE_OFFSET+2*N||burst_addr/N!=(burst_addr+burst_words-1)/N)
    $fatal(1,"invalid source burst");
   command_address=burst_addr;response=0;length=burst_words;responding=1;commands=commands+1;
  end
  if(rst_n&&checking)begin
   if(error)$fatal(1,"unexpected producer error phase=%0d topic=%0d pixels=%0d",case_phase,case_topic,pixels);
   if(pixel_valid&&pixel_last&&last_stall<512)begin
    last_stall<=last_stall+1;
    if(done||start_ready)$fatal(1,"retired before stalled last output");
   end
   if(held&&{pixel_last,pixel_addr,pixel_rgb}!==held_output)$fatal(1,"output changed under backpressure");
   held=pixel_valid&&!pixel_ready;held_output={pixel_last,pixel_addr,pixel_rgb};
   if(pixel_valid&&pixel_ready)begin
    if(pixel_addr!==pixels||pixel_rgb!==golden[pixels]||pixel_last!==(pixels==N-1))
     $fatal(1,"pixel mismatch case=%0d topic=%0d phase=%0d pixel=%0d x=%0d y=%0d got=%h expected=%h addr=%0d",number,case_topic,case_phase,pixels,pixels%640,pixels/640,pixel_rgb,golden[pixels],pixel_addr);
    pixels=pixels+1;check_pixels=check_pixels+1;
   end
   if(dut.lines.write_enable&&dut.lines.read_enable&&dut.lines.write_bank==dut.lines.read_bank)
    $fatal(1,"source bank overwritten while its RAM read is active");
   if(dut.read_line&&(dut.emit_bank?dut.line_row1:dut.line_row0)!=dut.emit_row)
    $fatal(1,"stale source row label");
  end
 end
 always @(negedge sys_clk)begin
  burst_data_valid=0;burst_last=0;burst_error=0;
  if(rst_n&&responding&&mode!=5)begin
   if(cycles%5!=0)begin
    burst_data_valid=1;burst_data={8'd0,color(command_address+response-BASE_OFFSET)};
    burst_last=response==length-1;
    if(mode==1)burst_last=1;
    if(mode==2&&response==length-1)burst_last=0;
    if(mode==3)burst_error=1;
    response=response+1;responses=responses+1;
    if(response==length)responding=0;
   end
  end
 end
 task reset_all;
  begin
   checking=0;@(negedge sys_clk);rst_n=0;start=0;intro_active=1;slide_active=0;slide_right=0;slide_offset=0;slide_alpha=32;
   repeat(4)@(negedge sys_clk);rst_n=1;mode=0;hold_output=0;
   repeat(4)@(negedge sys_clk);
   if(!start_ready||busy||error)$fatal(1,"common reset did not clear transaction");
  end
 endtask
 task launch(input integer t,p,b);
  begin
   wait(start_ready);@(negedge sys_clk);topic=t;phase=p;frame_base=BASE_OFFSET+b*N;back_base=BASE_OFFSET+(1-b)*N;start=1;
   @(negedge sys_clk);start=0;
  end
 endtask
 task expect_fault(input integer fault_mode);
  integer before_commands;
  begin
   reset_all();mode=fault_mode;launch(0,63,0);wait(error);before_commands=commands;
   @(negedge sys_clk);burst_data_valid=1;burst_last=1;burst_data=32'h12345678;
   @(negedge sys_clk);burst_data_valid=0;
   repeat(20)@(negedge sys_clk);
   if(!error||busy||start_ready||burst_valid||pixel_valid||done||commands!=before_commands)
    $fatal(1,"fault did not remain sticky mode=%0d",fault_mode);
  end
 endtask
 initial begin
  if(!$value$plusargs("CASES=%d",case_count))case_count=10;
  $readmemh("cases.hex",metadata);
  reset_all();
  for(number=0;number<case_count;number=number+1)begin
   case_bank=metadata[number][19];case_topic=metadata[number][21:20];case_phase=18;
   intro_active=0;slide_active=1;slide_right=metadata[number][18];
   slide_offset={4'd0,metadata[number][17:16],metadata[number][15:6]};slide_alpha=metadata[number][5:0];
   before_responses=responses;
   golden_path=$sformatf("golden_%0d.hex",number);$readmemh(golden_path,golden);
   pixels=0;last_stall=0;held=0;checking=1;
   launch(case_topic,case_phase,case_bank);
   // Bundled transaction inputs are deliberately changed while it is busy.
   repeat(40)@(negedge sys_clk);topic=3-case_topic;phase=63-case_phase;frame_base=(1-case_bank)*N;back_base=0;intro_active=!intro_active;slide_active=!slide_active;slide_offset=640-slide_offset;slide_alpha=0;
   wait(done);@(negedge sys_clk);checking=0;
   if(pixels!=N||responses-before_responses!=N||!start_ready||busy||error)$fatal(1,"incomplete frame");
   cases=cases+1;
   $display("PASS gallery producer frame topic=%0d phase=%0d bank=%0d pixels=%0d cycles=%0d",case_topic,case_phase,case_bank,pixels,cycles);
  end
  expect_fault(1);expect_fault(2);expect_fault(3);expect_fault(4);expect_fault(5);
  // Reserved tags and out-of-range distance fail before a memory command.
  for(integer bad=0;bad<3;bad=bad+1)begin
   reset_all();intro_active=0;slide_active=1;
   case(bad)0:slide_offset=16'h0c01;1:slide_offset=16'h1001;2:slide_offset=16'h0280;endcase
   before_responses=commands;launch(0,18,0);repeat(4)@(negedge sys_clk);
   if(!error||busy||burst_valid||commands!=before_responses)$fatal(1,"unsafe gallery descriptor accepted");
  end
  reset_all();@(negedge sys_clk);frame_base=CACHE?32'd2097152:32'd1;start=1;@(negedge sys_clk);start=0;
  if(!error||busy||burst_valid)$fatal(1,"invalid frame base accepted");
  reset_all();launch(0,63,1);wait(burst_data_valid);reset_all();
  if(error||!start_ready||pixel_valid)$fatal(1,"reset during burst left stale data");
  $display("PASS gallery motion producer CACHE=%0d totals frames=%0d pixels=%0d commands=%0d responses=%0d; actual text/geometry, both banks, stalls, last-output retirement, row ownership, malformed responses, timeouts, reset",CACHE,cases,check_pixels,commands,responses);
  $finish;
 end
 initial begin #3000000000;$fatal(1,"intro producer timeout pixels=%0d cases=%0d",pixels,cases);end
endmodule
