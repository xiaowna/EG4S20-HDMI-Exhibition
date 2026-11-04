`timescale 1ns/1ps
module tb_video_fade_lut;
 reg pix_clk=0,rst_n=0,vsync=1,cfg_valid=0;
 always #5 pix_clk=!pix_clk;
 reg [23:0] rgb_in=0;
 reg signed [8:0] brightness=0;
 reg [8:0] gain_q8=256;
 reg [5:0] fade=32;
 wire cfg_ready,cfg_applied;
 wire [23:0] rgb_out;
 video_brightness_lut dut(.pix_clk(pix_clk),.rst_n(rst_n),.vsync(vsync),
  .rgb_in(rgb_in),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.brightness(brightness),
  .gain_q8(gain_q8),.fade(fade),.cfg_applied(cfg_applied),.rgb_out(rgb_out));

 // Public handshake/timing model. No RAM, accumulator, build index or DUT
 // state is read. RGB expectations use direct multiplication and floor.
 integer cycles=0,checked=0,held_checks=0,accepted=0,applied=0,aborted=0;
 integer active_bias=0,active_gain=256,requested_bias=0,requested_gain=256;
 integer active_fade=32,requested_fade=32;
 integer complete_cycle=0,model_busy=0,model_vsync=1,expected_applied=0;
 integer low_clamps=0,high_clamps=0,negative_fractions=0,busy_requests=0;
 integer exhaustive_maps=0,sample_numerator=0;
 reg [23:0] expected_rgb;
 function automatic integer affine_integer(input integer value,input integer bias,input integer gain);
  integer numerator;
  begin
   numerator=(value-128)*gain+(128+bias)*256;
   // SV division truncates toward zero. Explicitly implement mathematical
   // floor for negative numerators rather than reusing the RTL recurrence.
   affine_integer=(numerator>=0)?numerator/256:-((-numerator+255)/256);
  end
 endfunction
 function automatic [7:0] affine(input [7:0] value,input integer bias,input integer gain,input integer fade_value);
  integer result;
  begin
   result=affine_integer(value,bias,gain);
   if(result<0)result=0;else if(result>255)result=255;
   affine=(result*fade_value)/32;
  end
 endfunction
 function automatic [23:0] affine_rgb(input [23:0] value,input integer bias,input integer gain);
  begin affine_rgb={affine(value[23:16],bias,gain,active_fade),affine(value[15:8],bias,gain,active_fade),affine(value[7:0],bias,gain,active_fade)};end
 endfunction
 function automatic [23:0] pattern(input integer number);
  reg [7:0] r,g,b;
  begin r=number;g=number*73+19;b=255-number;pattern={r,g,b};end
 endfunction
 always @(posedge pix_clk)begin
  cycles=cycles+1;
  if(!rst_n)begin
   if(model_busy)aborted=aborted+1;
   active_bias=0;active_gain=256;active_fade=32;requested_bias=0;requested_gain=256;requested_fade=32;complete_cycle=0;
   model_busy=0;model_vsync=1;expected_applied=0;
   #1;
   if(rgb_out!==24'd0||cfg_ready!==0||cfg_applied!==0)$fatal(1,"reset outputs cycle=%0d",cycles);
  end else begin
   expected_rgb=affine_rgb(rgb_in,active_bias,active_gain);
   if(affine_integer(rgb_in[23:16],active_bias,active_gain)<0)low_clamps=low_clamps+1;
   if(affine_integer(rgb_in[23:16],active_bias,active_gain)>255)high_clamps=high_clamps+1;
   sample_numerator=(rgb_in[23:16]-128)*active_gain+(128+active_bias)*256;
   if(sample_numerator<0 && sample_numerator%256!=0)
    negative_fractions=negative_fractions+1;
   expected_applied=0;
   if(cfg_valid&&model_busy)busy_requests=busy_requests+1;
   if(model_busy)begin
    if(cycles>complete_cycle&&model_vsync&&!vsync)begin
     active_bias=requested_bias;active_gain=requested_gain;active_fade=requested_fade;model_busy=0;expected_applied=1;applied=applied+1;
    end
   end else if(cfg_valid)begin
    requested_bias=$signed(brightness);requested_gain=gain_q8;requested_fade=fade;
    complete_cycle=cycles+256;model_busy=1;accepted=accepted+1;
   end
   model_vsync=vsync;
   #1;
   if(rgb_out!==expected_rgb)$fatal(1,"affine pixel cycle=%0d input=%h bias=%0d gain=%0d expected=%h got=%h",
                                    cycles,rgb_in,active_bias,active_gain,expected_rgb,rgb_out);
   if(cfg_applied!==expected_applied[0])$fatal(1,"atomic publication cycle=%0d",cycles);
   if(cfg_ready!==(model_busy==0))$fatal(1,"ready cycle=%0d",cycles);
   if($isunknown(rgb_out))$fatal(1,"RAM initialization leaked into public RGB");
   checked=checked+1;
  end
 end
 task automatic step(input [23:0] pixel,input integer frame_sync,input integer request,
                     input integer bias,input integer gain);
  reg [23:0] held;
  begin
   @(negedge pix_clk);held=rgb_out;rgb_in=pixel;vsync=frame_sync;
   cfg_valid=request;brightness=bias;gain_q8=gain;
   #1;if(rgb_out!==held)$fatal(1,"RGB changed between clock edges");held_checks=held_checks+1;
   @(posedge pix_clk);#2;
  end
 endtask
 task automatic reset_dut;
  begin
   @(negedge pix_clk);rst_n=0;cfg_valid=0;vsync=1;rgb_in=0;brightness=0;gain_q8=256;fade=32;
   #1;if(rgb_out!==0||cfg_ready!==0||cfg_applied!==0)$fatal(1,"asynchronous reset bypass");
   repeat(2)@(posedge pix_clk);
   @(negedge pix_clk);rst_n=1;
   step(24'h0080ff,1,0,0,256);step(24'hfa0207,1,0,0,256);
  end
 endtask
 task automatic apply_config(input integer bias,input integer gain,input integer fade_value,input integer first_fall);
  integer j,old_accepted,old_applied;
  begin
   if(!cfg_ready)$fatal(1,"configuration unexpectedly busy");
   old_accepted=accepted;old_applied=applied;
   @(negedge pix_clk);fade=fade_value;
   step(pattern(cycles),1,1,bias,gain);
   if(accepted!=old_accepted+1)$fatal(1,"request not accepted");
   for(j=1;j<first_fall;j=j+1)step(pattern(cycles),1,0,0,256);
   step(pattern(cycles),0,0,0,256);
   if(first_fall<=256&&applied!=old_applied)$fatal(1,"partial table publication");
   if(first_fall>256&&applied!=old_applied+1)$fatal(1,"complete table not published");
   if(model_busy)begin
    while(cycles<complete_cycle)step(pattern(cycles),1,0,0,256);
    step(pattern(cycles),1,0,0,256);step(pattern(cycles),0,0,0,256);
   end
   if(applied!=old_applied+1)$fatal(1,"publication not exactly once");
   step(pattern(cycles),1,0,0,256);
  end
 endtask
 task automatic exhaustive_pixels;
  integer j;
  reg [7:0] gray;
  begin
   for(j=0;j<256;j=j+1)begin gray=j;step({gray,gray,gray},1,0,0,256);end
   for(j=0;j<256;j=j+1)step(pattern(j),1,0,0,256);
   exhaustive_maps=exhaustive_maps+1;
  end
 endtask
 task automatic abort_after(input integer writes);
  integer j;
  begin
   @(negedge pix_clk);fade=11;
   step(pattern(cycles),1,1,-64,384);
   for(j=0;j<writes;j=j+1)step(pattern(cycles),1,0,0,256);
   reset_dut();step(24'hff8000,0,0,0,256);step(24'h0102fe,1,0,0,256);exhaustive_pixels();
  end
 endtask
 integer biases[0:8],gains[0:8];
 integer j,k,old_accepted,old_applied;
 initial begin
  // All 33 fade factors and every input value for representative affine pairs.
  // In particular, saturation occurs BEFORE fade, including +255 and -256.
  biases[0]=0;gains[0]=256;
  biases[1]=-64;gains[1]=128;
  biases[2]=64;gains[2]=384;
  biases[3]=-256;gains[3]=320;
  biases[4]=255;gains[4]=192;
  biases[5]=32;gains[5]=192;
  biases[6]=-1;gains[6]=320;
  biases[7]=127;gains[7]=384;
  biases[8]=-128;gains[8]=128;
  reset_dut();exhaustive_pixels();
  for(j=0;j<9;j=j+1)for(k=0;k<=32;k=k+1)begin
   apply_config(biases[j],gains[j],k,255+(j+k)%3);exhaustive_pixels();
  end
  $display("PASS: 297 affine/fade maps, every fade0..32 and all RGB inputs; clip-before-fade order");

  // A low level across build completion is not a second falling edge.
  old_applied=applied;step(pattern(cycles),0,1,32,192);
  for(j=0;j<270;j=j+1)step(pattern(cycles),0,0,0,256);
  if(applied!=old_applied||cfg_ready!==0)$fatal(1,"held-low VSYNC published");
  step(pattern(cycles),1,0,0,256);step(pattern(cycles),0,0,0,256);step(pattern(cycles),1,0,0,256);
  exhaustive_pixels();

  // Busy writes change both words, neither may overwrite the accepted pair.
  old_accepted=accepted;old_applied=applied;
  step(pattern(cycles),1,1,-32,320);
  for(j=0;j<100;j=j+1)step(pattern(j),1,1,255,128);
  while(cycles<=complete_cycle)step(pattern(cycles),1,0,0,256);
  for(j=0;j<37;j=j+1)step(pattern(cycles),1,1,-256,384);
  step(pattern(cycles),0,0,0,256);
  for(j=0;j<7;j=j+1)step(pattern(j),0,0,0,256);
  step(pattern(cycles),1,0,0,256);
  if(accepted!=old_accepted+1||applied!=old_applied+1)$fatal(1,"busy request replaced pair");
  exhaustive_pixels();

  step(pattern(cycles),1,1,64,128);
  while(cycles<=complete_cycle)step(pattern(cycles),1,0,0,256);
  old_accepted=accepted;step(pattern(cycles),0,1,-64,384);
  if(accepted!=old_accepted)$fatal(1,"accepted request on old pending publication edge");
  step(pattern(cycles),1,1,-64,384);
  if(accepted!=old_accepted+1)$fatal(1,"held request lost after ready");
  step(pattern(cycles),1,0,0,256);
  while(cycles<=complete_cycle)step(pattern(cycles),1,0,0,256);
  step(pattern(cycles),0,0,0,256);step(pattern(cycles),1,0,0,256);exhaustive_pixels();

  abort_after(0);abort_after(1);abort_after(127);abort_after(255);abort_after(256);abort_after(300);
  apply_config(64,320,32,257);exhaustive_pixels();
  reset_dut();exhaustive_pixels();apply_config(-1,192,17,257);exhaustive_pixels();
  if(accepted!=applied+aborted||aborted!=6||low_clamps==0||high_clamps==0||negative_fractions==0||busy_requests<100)
   $fatal(1,"coverage accepted=%0d applied=%0d aborted=%0d low=%0d high=%0d negfrac=%0d busy=%0d",
          accepted,applied,aborted,low_clamps,high_clamps,negative_fractions,busy_requests);
  $display("PASS: independent affine/fade LUT cycles=%0d checked=%0d held=%0d maps=%0d accepted=%0d applied=%0d reset_aborts=%0d low_clamps=%0d high_clamps=%0d negative_fractions=%0d busy_requests=%0d",
           cycles,checked,held_checks,exhaustive_maps,accepted,applied,aborted,low_clamps,high_clamps,negative_fractions,busy_requests);
  $finish;
 end
 initial begin #20000000;$fatal(1,"affine/fade LUT simulation timeout");end
endmodule
