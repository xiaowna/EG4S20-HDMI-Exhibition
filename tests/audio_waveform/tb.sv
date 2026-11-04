`timescale 1ns/1ps
module tb_video_audio_waveform;
 reg pix_clk=0,rst_n=0,de=0,vsync=1,wave_enable=0,sample_valid=0;
 reg [23:0] rgb_in=0;
 reg [9:0] x=0;
 reg [8:0] y=0;
 reg signed [23:0] sample_left=0;
 wire [23:0] rgb_out;
 always #5 pix_clk=!pix_clk;
 video_audio_waveform dut(.pix_clk(pix_clk),.rst_n(rst_n),.rgb_in(rgb_in),
  .de(de),.vsync(vsync),.x(x),.y(y),.wave_enable(wave_enable),
  .sample_valid(sample_valid),.sample_left(sample_left),.rgb_out(rgb_out));

 // An abstract ordered sample stream and two software snapshots. No DUT RAM,
 // internal bank, counter, address, pending flag, or control is inspected.
 // Every FOURTH accepted observation contributes a signed integer amplitude;
 // a snapshot is published only if it was already complete BEFORE this edge.
 integer building[0:255],front[0:255],seen_amplitude[0:255];
 integer observations=0,ready_snapshot=0,front_valid=0,enabled=0,last_vsync=1;
 integer cycles=0,checked=0,held=0,samples=0,stored=0,ignored=0;
 integer completed=0,published=0,reset_partial=0,reset_pending=0,reset_active=0;
 integer trace_checks=0,center_checks=0,background_checks=0,bypass_checks=0;
 integer frame_edges=0,enable_changes=0,pre_ready,amplitude,plot_y,col,j;
 reg [23:0] expected_rgb;
 function automatic [23:0] pixel_pattern(input integer number);
  reg [7:0] r,g,b;
  begin r=number*43+11;g=number*73+29;b=number*151+97;pixel_pattern={r,g,b};end
 endfunction
 function automatic [23:0] pcm_pattern(input integer kind,input integer number);
  reg [7:0] high_byte;
  reg [15:0] lower_bits;
  begin
   // The selected high bytes (number=4*j+3) traverse all 256 amplitudes:
   // 151*j+111+53*kind mod256 has odd stride. Lower bits deliberately vary.
   high_byte=number*37+(number/4)*3+kind*53;
   lower_bits=number*197+kind*997;
   pcm_pattern={high_byte,lower_bits};
  end
 endfunction
 always @(posedge pix_clk)begin
  cycles=cycles+1;
  if(!rst_n)begin
   if(observations!=0 && !ready_snapshot)reset_partial=reset_partial+1;
   if(ready_snapshot)reset_pending=reset_pending+1;
   if(front_valid)reset_active=reset_active+1;
   observations=0;ready_snapshot=0;front_valid=0;enabled=0;last_vsync=1;
   #1;
   if(rgb_out!==24'd0)$fatal(1,"reset leaked RAM or bypass data cycle=%0d got=%h",cycles,rgb_out);
  end else begin
   expected_rgb=rgb_in;
   if(front_valid && enabled && de && x>=16 && x<=271 && y>=336 && y<=415)begin
    col=x-16;
    plot_y=410-front[col]/4;
    if(y==plot_y)begin expected_rgb=24'h00ff60;trace_checks=trace_checks+1;end
    else if(y==378)begin expected_rgb=24'h214438;center_checks=center_checks+1;end
    else begin expected_rgb=24'h081018;background_checks=background_checks+1;end
   end else bypass_checks=bypass_checks+1;

   pre_ready=ready_snapshot;
   if(last_vsync && !vsync)begin
    frame_edges=frame_edges+1;
    if(enabled!=wave_enable)enable_changes=enable_changes+1;
    enabled=wave_enable;
    if(pre_ready)begin
     for(j=0;j<256;j=j+1)front[j]=building[j];
     front_valid=1;ready_snapshot=0;observations=0;published=published+1;
    end
   end
   // Abstract stream count, division and modulo: independent of DUT bit
   // counter, bank layout, XOR sign conversion and read-address arithmetic.
   if(sample_valid)begin
    samples=samples+1;
    if(pre_ready)ignored=ignored+1;
    else begin
     observations=observations+1;
     if(observations%4==0)begin
      amplitude=$signed(sample_left) >>> 16;
      building[observations/4-1]=amplitude+128;
      seen_amplitude[amplitude+128]=1;
      stored=stored+1;
     end
     if(observations==1024)begin ready_snapshot=1;completed=completed+1;end
    end
   end
   last_vsync=vsync;
   #1;
   if(rgb_out!==expected_rgb)
    $fatal(1,"pixel cycle=%0d xy=%0d,%0d expected=%h got=%h front_valid=%0d enabled=%0d observations=%0d ready=%0d",
     cycles,x,y,expected_rgb,rgb_out,front_valid,enabled,observations,ready_snapshot);
   if($isunknown(rgb_out))$fatal(1,"uninitialized RAM leaked to RGB cycle=%0d",cycles);
   checked=checked+1;
  end
 end
 task automatic step(input integer sx,input integer sy,input integer active,
  input integer sync_level,input integer enable,input integer valid,input [23:0] pcm);
  reg [23:0] previous;
  begin
   @(negedge pix_clk);previous=rgb_out;
   x=sx;y=sy;de=active;vsync=sync_level;wave_enable=enable;
   sample_valid=valid;sample_left=pcm;rgb_in=pixel_pattern(cycles+17);
   #1;
   if(rgb_out!==previous)$fatal(1,"output changed before clock; missing one-pixel delay cycle=%0d",cycles);
   held=held+1;
   @(posedge pix_clk);#2;
  end
 endtask
 task automatic reset_dut;
  begin
   @(negedge pix_clk);rst_n=0;de=0;vsync=1;sample_valid=0;wave_enable=0;
   rgb_in=24'hbadef1;sample_left=24'hff0055;
   #1;if(rgb_out!==0)$fatal(1,"asynchronous reset did not mask RAM");
   repeat(2)@(posedge pix_clk);
   @(negedge pix_clk);rst_n=1;
   step(16,378,1,1,0,0,24'h808080);
   step(271,410,1,1,0,0,24'h7fffff);
  end
 endtask
 task automatic frame(input integer enable);
  begin
   step(16,378,1,1,enable,0,24'h123456);
   step(17,378,1,0,enable,0,24'habcdef);
   step(18,378,1,0,enable,0,24'h800001);
  end
 endtask
 task automatic feed(input integer kind,input integer first,input integer count,input integer last_fall);
  integer n,g;
  begin
   for(n=first;n<first+count;n=n+1)begin
    // Gaps before sample 4 are particularly sensitive to advancing on invalid.
    if(n%7==3)begin
     for(g=0;g<(n%3)+1;g=g+1)
      step(16+(n%256),378,1,1,1,0,pcm_pattern(kind+7,n+g+101));
    end
    step(16+(n%256),378,1,
     (last_fall && n==first+count-1)?0:1,1,1,pcm_pattern(kind,n));
   end
  end
 endtask
 task automatic scan_all(input integer sync_level,input integer requested_enable);
  integer sx,sy;
  begin
   for(sx=16;sx<=271;sx=sx+1)
    for(sy=336;sy<=415;sy=sy+1)
     step(sx,sy,1,sync_level,requested_enable,0,pcm_pattern(9,sx*80+sy));
  end
 endtask
 task automatic scan_selected(input integer sync_level,input integer requested_enable);
  integer sx;
  begin
   for(sx=16;sx<=271;sx=sx+1)begin
    step(sx,347+(sx%64),1,sync_level,requested_enable,0,pcm_pattern(8,sx));
    step(sx,378,1,sync_level,requested_enable,0,pcm_pattern(8,sx+1));
    step(sx,415,1,sync_level,requested_enable,0,pcm_pattern(8,sx+2));
   end
  end
 endtask
 task automatic boundaries(input integer requested_enable);
  integer sx,sy;
  begin
   for(sx=0;sx<4;sx=sx+1)
    for(sy=0;sy<4;sy=sy+1)
     step((sx==0)?15:(sx==1)?16:(sx==2)?271:272,
          (sy==0)?335:(sy==1)?336:(sy==2)?415:416,
          1,0,requested_enable,0,pcm_pattern(5,sx*4+sy));
   step(16,378,0,0,requested_enable,0,24'h800000);
   step(1023,511,1,0,requested_enable,0,24'h7fffff);
  end
 endtask
 integer n;
 initial begin
  for(n=0;n<256;n=n+1)seen_amplitude[n]=0;
  reset_dut();
  frame(1); // Enabled, but no complete snapshot: every pixel must bypass.
  feed(0,0,1024,1); // Final write coincides with VSYNC: cannot publish yet.
  if(completed!=1 || published!=0)$fatal(1,"test sequencing first snapshot");
  scan_selected(0,1); // Hold VSYNC low: no repeated edge/publication.
  boundaries(1);
  frame(1);
  if(published!=1)$fatal(1,"first snapshot did not publish");
  scan_all(0,1); // All 256 columns x all 80 rows; paused capture holds snapshot.
  boundaries(1);

  // Enable/disable changes inside a frame cannot alter that frame.
  scan_selected(0,0);
  frame(0);
  scan_selected(0,0);boundaries(0);
  scan_selected(0,1);
  frame(1);scan_selected(0,1);

  // Second pattern traverses every signed amplitude with a different order.
  // During partial capture, the previous full snapshot remains immutable.
  feed(1,0,768,0);
  scan_all(1,1);
  feed(1,768,256,0);
  if(completed!=2 || published!=1)$fatal(1,"test sequencing second snapshot");
  // Full pending snapshot ignores further audio; it cannot be overwritten.
  for(n=0;n<29;n=n+1)step(16+n,378,1,1,1,1,pcm_pattern(13,n));
  scan_selected(1,1);
  frame(1);
  if(published!=2)$fatal(1,"second snapshot did not publish");
  scan_all(0,1);boundaries(1);
  for(n=0;n<128;n=n+1)step(16+(n%256),378,1,0,1,0,pcm_pattern(12,n));

  // Reset a displayed snapshot, a partial capture, then a completed pending
  // snapshot. Old RAM survives physically but may never leak into the output.
  reset_dut();frame(1);scan_selected(0,1);
  feed(2,0,33,0);
  reset_dut();frame(1);scan_selected(0,1);
  feed(3,0,1024,0);
  reset_dut();frame(1);scan_selected(0,1);
  feed(4,0,1024,0);
  frame(1);scan_all(0,1);boundaries(1);

  if(completed!=4 || published!=3 || reset_partial<1 || reset_pending<1 || reset_active<1)
   $fatal(1,"coverage counts missing complete=%0d publish=%0d resets=%0d/%0d/%0d",
    completed,published,reset_partial,reset_pending,reset_active);
  for(n=0;n<256;n=n+1)if(!seen_amplitude[n])$fatal(1,"amplitude coverage missing %0d",n);
  if(trace_checks<768 || center_checks<768 || background_checks<768 || ignored<29 || enable_changes<4)
   $fatal(1,"pixel/control coverage incomplete");
  $display("PASS: independent waveform stream oracle; all 256 signed high-byte amplitudes, 4 completed snapshots, 3 published, 4 full-window scans");
  $display("SUMMARY cycles=%0d checked=%0d held=%0d observed_samples=%0d stored_points=%0d pending_ignored=%0d completed=%0d published=%0d reset_partial=%0d reset_pending=%0d reset_active=%0d trace=%0d center=%0d background=%0d bypass=%0d frame_edges=%0d enable_changes=%0d",
   cycles,checked,held,samples,stored,ignored,completed,published,reset_partial,reset_pending,reset_active,
   trace_checks,center_checks,background_checks,bypass_checks,frame_edges,enable_changes);
  $finish;
 end
 initial begin #20000000;$fatal(1,"waveform test timeout");end
endmodule
