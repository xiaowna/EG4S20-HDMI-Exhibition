`timescale 1ns/1ps
module tb_solar_scene;
 reg scene_mode=0;reg [1:0] zoom=1;
 parameter integer CASES=48;
 localparam integer DRAW_LIMIT=45000;
 reg sys_clk=0,pix_clk=0,rst_n=0,enable=1,de=0,vsync=1;
 reg [6:0] yaw=12,pitch=83;reg [9:0] x=0,y=0;
 wire [23:0] rgb_out;wire valid_out,ready,fault;
 always #10 sys_clk=~sys_clk;always #20 pix_clk=~pix_clk;
 video_scene3d dut(.*);
 reg [23:0] before_phase[0:CASES*8-1],after_phase[0:CASES*8-1];
 reg [13:0] modes[0:CASES-1];reg [2:0] golden[0:CASES*16384-1];
 reg [23:0] pixels[0:307199];
 reg [13:0] labels[0:CASES*10-1];
 integer i,j,k,n,elapsed,max_elapsed=0,max_budget=0;
 integer anchor_center,anchor_radius,anchor_above,anchor_expected,divide_input,divide_quotient,divide_remainder;
 task ticks(input integer count);repeat(count)@(negedge sys_clk);endtask
 task frame;
 begin
  @(negedge pix_clk);vsync=0;ticks(12);vsync=1;ticks(5);
  elapsed=0;while(!ready&&elapsed<DRAW_LIMIT+10)begin ticks(1);elapsed=elapsed+1;end
  if(!ready||fault)$fatal(1,"solar render failed case %0d elapsed %0d",i,elapsed);
  if(elapsed>max_elapsed)max_elapsed=elapsed;
  if(dut.budget>max_budget)max_budget=dut.budget;
 end endtask
 always @(posedge sys_clk)if(rst_n&&dut.writing)begin
  if(ready||dut.budget>=DRAW_LIMIT)$fatal(1,"write after publish/deadline");
  if(dut.write_address>=16384)$fatal(1,"canvas write out of bounds");
 end
 always @(posedge pix_clk)if(rst_n&&dut.label_loading)begin
  if(de)$fatal(1,"serial name load escaped vertical blanking");
  if(dut.state==3||dut.state==5)$fatal(1,"projected centers changed before serial name load completed");
 end
 initial begin
  for(divide_input=0;divide_input<1024;divide_input=divide_input+1)begin
   divide_quotient=(divide_input/3)%128;divide_remainder=divide_input%3;
   if(dut.canvas_divmod3(divide_input[9:0])!=={divide_quotient[6:0],divide_remainder[1:0]})
    $fatal(1,"radix-8 display coordinate mismatch input=%0d",divide_input);
  end
  $display("PASS display divmod3: all 1024 inputs, exact quotient bits and subpixel remainder, no extra latency");
  // Independently exercise every input of the shared vertical anchor adder.
  for(anchor_center=0;anchor_center<128;anchor_center=anchor_center+1)
   for(anchor_radius=0;anchor_radius<32;anchor_radius=anchor_radius+1)
    for(anchor_above=0;anchor_above<2;anchor_above=anchor_above+1)begin
     anchor_expected=anchor_above?anchor_center-anchor_radius-5:anchor_center+anchor_radius+2;
     if(anchor_expected<0)anchor_expected=0;
     if(anchor_expected>124)anchor_expected=124;
     if(dut.name_y(anchor_center[6:0],anchor_radius[4:0],anchor_above[0])!==anchor_expected[6:0])
      $fatal(1,"vertical name clamp mismatch center=%0d radius=%0d above=%0d",anchor_center,anchor_radius,anchor_above);
    end
  $display("PASS vertical label placement: all 8192 input combinations, lower and upper clamps retained");
  $readmemh("phase_before.hex",before_phase);$readmemh("phase_after.hex",after_phase);
  $readmemh("modes.hex",modes);$readmemh("canvas.hex",golden);$readmemh("pixels.hex",pixels);$readmemh("labels.hex",labels);
  ticks(4);rst_n=1;ticks(4);
  // Cold boot does not rely on phase RAM contents or a memory reset.
  i=3;frame();
  for(j=0;j<8;j=j+1)if(dut.phases.memory[j]!==after_phase[24+j])
   $fatal(1,"cold phase initialization planet=%0d",j);
  for(j=0;j<16384;j=j+1)if(dut.canvas[j]!==golden[3*16384+j])$fatal(1,"cold canvas initialization");
  for(i=0;i<CASES;i=i+1)begin
   dut.phase_initialized=1;
   yaw=modes[i][13:7];pitch=modes[i][6:0];
   for(j=0;j<8;j=j+1)begin
    dut.phases.memory[j]=before_phase[i*8+j];
   end
   frame();
   for(j=0;j<8;j=j+1)if(dut.phases.memory[j]!==after_phase[i*8+j])
    $fatal(1,"phase increment case=%0d planet=%0d got=%h expected=%h",i,j,dut.phases.memory[j],after_phase[i*8+j]);
   for(j=0;j<16384;j=j+1)if(dut.canvas[j]!==golden[i*16384+j])
    $fatal(1,"canvas mismatch case=%0d address=%0d got=%0d expected=%0d",i,j,dut.canvas[j],golden[i*16384+j]);
   ticks(40);
   if(dut.label_loading)$fatal(1,"name anchors not ready within 20 blanking pixel clocks");
   for(j=0;j<9;j=j+1)if({dut.label_y[j],dut.label_x[j]}!==labels[i*10+j])
    $fatal(1,"name did not follow projected body case=%0d index=%0d",i,j);
  end
  // Produce the exact same nominal view for independent full pixel checking.
  i=3;yaw=12;pitch=83;for(j=0;j<8;j=j+1)begin dut.phases.memory[j]=before_phase[24+j];end frame();ticks(100);
  n=0;
  for(k=0;k<480;k=k+1)begin
   for(j=0;j<640;j=j+1)begin
    @(negedge pix_clk);x=j;y=k;de=1;@(posedge pix_clk);#1;
    if(!valid_out||rgb_out!==pixels[n])$fatal(1,"raster x=%0d y=%0d got=%h expected=%h valid=%b",j,k,rgb_out,pixels[n],valid_out);
    n=n+1;
   end
   @(negedge pix_clk);de=0;x=640;repeat(160)@(negedge pix_clk);
  end
  // The canvas is held while active video scans. A truncated blank is rejected.
  vsync=0;ticks(12);vsync=1;ticks(50);de=1;ticks(8);
  if(ready||!fault||dut.state!=0)$fatal(1,"early DE not rejected");
  de=0;rst_n=0;ticks(4);rst_n=1;ticks(4);
  vsync=0;ticks(12);vsync=1;ticks(50);force dut.budget=DRAW_LIMIT;ticks(2);release dut.budget;ticks(3);
  if(ready||!fault||dut.state!=0)$fatal(1,"deadline not rejected");
  rst_n=0;ticks(4);rst_n=1;ticks(4);enable=0;
  for(j=0;j<8;j=j+1)begin dut.phases.memory[j]=before_phase[j];end dut.phase_initialized=1;frame();
  for(j=0;j<8;j=j+1)if(dut.phases.memory[j]!==before_phase[j])$fatal(1,"hidden orbit advanced");
  // Keep the normal blanking allowance even when the overlay is disabled.
  // Ready crosses domains, then ten pixel clocks latch the name anchors.
  ticks(40);de=1;@(posedge pix_clk);#1;
  if(valid_out)$fatal(1,"disabled scene covered video");
  $display("PASS XYZ wireframe solar: %0d canvas oracles (%0d pixels), 307200 raster pixels, independent phases, guards; max wait %0d clocks draw_budget=%0d",CASES,CASES*16384,max_elapsed,max_budget);
  $finish;
 end
 initial begin #200000000;$fatal(1,"scene timeout");end
endmodule
