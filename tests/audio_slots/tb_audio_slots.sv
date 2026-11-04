`timescale 1ns/1ps
module tb_audio_slots;
 reg clk=0,rst_n=0,build=0,frame_start=0,fifo_empty=0;
 reg [47:0] fifo_data=0;
 always #5 clk=~clk;
 wire fifo_read,sample_request,packet_valid;
 wire [23:0] audio_header,aux_header;
 wire [223:0] audio_body,aux_body;
 hdmi_audio_packets dut(.clk(clk),.rst_n(rst_n),.build(build),.frame_start(frame_start),
  .fifo_empty(fifo_empty),.fifo_data(fifo_data),.fifo_read(fifo_read),
  .sample_request(sample_request),.packet_valid(packet_valid),
  .audio_header(audio_header),.aux_header(aux_header),.audio_body(audio_body),.aux_body(aux_body));
`ifdef COMPARE_BASELINE
 wire ref_read,ref_request,ref_valid;
 wire [23:0] ref_ah,ref_bh;
 wire [223:0] ref_ab,ref_bb;
 hdmi_audio_packets_baseline baseline(.clk(clk),.rst_n(rst_n),.build(build),.frame_start(frame_start),
  .fifo_empty(fifo_empty),.fifo_data(fifo_data),.fifo_read(ref_read),.sample_request(ref_request),
  .packet_valid(ref_valid),.audio_header(ref_ah),.aux_header(ref_bh),.audio_body(ref_ab),.aux_body(ref_bb));
`else
 wire ref_read=fifo_read,ref_request=sample_request,ref_valid=packet_valid;
 wire [23:0] ref_ah=audio_header,ref_bh=aux_header;
 wire [223:0] ref_ab=audio_body,ref_bb=aux_body;
`endif
 function [47:0] pcm;
  input integer n;
  reg [23:0] l,r;
  begin l=24'h13579b^(n*24'h010103);r=24'hfedcba^(n*24'h050107);pcm={l,r};end
 endfunction
 // Channel status bytes: consumer PCM, channel 1/2, 48 kHz, 24 bit.
 // This byte-oriented oracle deliberately does not index the RTL status constants.
 function status;
  input integer sample_number,channel;
  integer byte_number,bit_number;
  reg [7:0] value;
  begin
   byte_number=(sample_number%192)/8;bit_number=sample_number%8;value=0;
   case(byte_number)
    0:value=8'h04;
    2:if(channel==1)value=8'h10;else value=8'h20;
    3:value=8'h02;
    4:value=8'h0b;
   endcase
   status=value[bit_number];
  end
 endfunction
 integer cycles=0,segment_cycle=0,reads=0,requests=0,packets=0;
 integer single_packets=0,double_packets=0,silent_samples=0,iec_wraps=0;
 integer ignored_builds=0,reset_count=0,acr_packets=0,avi_packets=0,info_packets=0;
 integer line_number=0,sample_number=0,next_request=0,valid_cycle=-1;
 integer expected_samples=0,collected=0,request_count=0,read_number=0;
 integer acr_clock=0,accepted_cycle=0,reset_age;
 integer reset_age_coverage=0,empty_transition_coverage=0,boundary_accepts=0;
 integer frame_with_acr=0,frame_with_avi=0,frame_with_info=0;
 reg model_busy=0,acr_wait=1,avi_wait=1,info_wait=1;
 reg old_acr,old_avi,old_info,accept_now,request_now,valid_now;
 reg previous_empty=0,previous_request=0;
 reg [23:0] expected_header=0,expected_aux_header=0;
 reg [223:0] expected_body=0,expected_aux_body=0;
 reg [47:0] expected_pcm;
 reg [7:0] expected_status;
 reg sl,sr;
 // Clocked FIFO: a successful read supplies its new sample for the following CAPTURE.
 always @(posedge clk)begin
  if(!rst_n)begin fifo_data<=0;read_number<=0;end
  else if(fifo_read)begin fifo_data<=pcm(read_number);read_number<=read_number+1;end
 end
 always @(posedge clk)begin
  cycles=cycles+1;
  if(!rst_n)begin
   segment_cycle=0;model_busy=0;line_number=0;sample_number=0;
   next_request=0;valid_cycle=-1;collected=0;expected_samples=0;request_count=0;
   expected_header=0;expected_body=0;expected_aux_header=0;expected_aux_body=0;
   acr_clock=0;acr_wait=1;avi_wait=1;info_wait=1;previous_request=0;previous_empty=0;
  end else begin
   accept_now=!model_busy&&build;
   request_now=model_busy&&(collected<expected_samples)&&(segment_cycle==next_request);
   if(sample_request!==request_now)$fatal(1,"sample_request timing cycle=%0d",cycles);
   if(fifo_read!==(request_now&&!fifo_empty))$fatal(1,"FIFO read handshake cycle=%0d",cycles);
   if(previous_request && previous_empty!=fifo_empty)empty_transition_coverage=empty_transition_coverage+1;
   previous_request=sample_request;previous_empty=fifo_empty;
   if(build&&model_busy)ignored_builds=ignored_builds+1;
   if(request_now)begin
    if(fifo_empty)begin expected_pcm=0;silent_samples=silent_samples+1;end
    else begin expected_pcm=pcm(read_number);reads=reads+1;end
    sl=status(sample_number,1);sr=status(sample_number,2);
    expected_status={(^expected_pcm[23:0])^sr,sr,2'b00,(^expected_pcm[47:24])^sl,sl,2'b00};
    expected_body[collected*56 +: 56]={expected_status,expected_pcm[23:0],expected_pcm[47:24]};
    expected_header[8+collected]=1;
    expected_header[20+collected]=(sample_number%192==0);
    expected_header[7:0]=8'h02;
    sample_number=sample_number+1;
    if(sample_number%192==0)iec_wraps=iec_wraps+1;
    collected=collected+1;request_count=request_count+1;requests=requests+1;next_request=next_request+2;
   end
   old_acr=acr_wait;old_avi=avi_wait;old_info=info_wait;
   if(acr_clock==24999)acr_wait=1;
   if(frame_start)begin avi_wait=1;info_wait=1;end
   if(accept_now)begin
    // floor(N*192/125) is the independent exact rational sample schedule.
    expected_samples=((line_number+1)*192)/125-(line_number*192)/125;
    line_number=line_number+1;collected=0;
    expected_header=0;expected_body=0;expected_aux_header=0;expected_aux_body=0;
    if(old_acr)begin
     expected_aux_header=24'h000001;
     expected_aux_body=224'h001800a8610000001800a8610000001800a8610000001800a8610000;
     acr_wait=(acr_clock==24999);
     if(frame_start)frame_with_acr=frame_with_acr+1;
    end else if(old_avi)begin
     expected_aux_header=24'h0d0282;expected_aux_body=224'h10005f;avi_wait=frame_start;
     if(frame_start)frame_with_avi=frame_with_avi+1;
    end else if(old_info)begin
     expected_aux_header=24'h0a0184;expected_aux_body=224'h170;info_wait=frame_start;
     if(frame_start)frame_with_info=frame_with_info+1;
    end
    if(acr_clock==24999&&frame_start)boundary_accepts=boundary_accepts+1;
    model_busy=1;accepted_cycle=segment_cycle;
    next_request=segment_cycle+1;valid_cycle=segment_cycle+2*expected_samples+1;
   end
   if(acr_clock==24999)acr_clock=0;else acr_clock=acr_clock+1;
   valid_now=model_busy&&(segment_cycle==valid_cycle);
   #1;
   if(packet_valid!==valid_now)$fatal(1,"packet_valid timing cycle=%0d expected=%0d",cycles,valid_now);
   if(valid_now)begin
    if(audio_header!==expected_header||audio_body!==expected_body)
     $fatal(1,"PCM/IEC oracle mismatch cycle=%0d actual=%h/%h expected=%h/%h",cycles,audio_header,audio_body,expected_header,expected_body);
    if(aux_header!==expected_aux_header||aux_body!==expected_aux_body)
     $fatal(1,"auxiliary oracle mismatch cycle=%0d actual=%h/%h expected=%h/%h",cycles,aux_header,aux_body,expected_aux_header,expected_aux_body);
    if(audio_header[11:10]!==0||audio_header[23:22]!==0||audio_body[223:112]!==0)
     $fatal(1,"unused audio slot became nonzero");
    packets=packets+1;
    if(expected_samples==1)single_packets=single_packets+1;else double_packets=double_packets+1;
    case(aux_header[7:0])
     1:acr_packets=acr_packets+1;
     8'h82:avi_packets=avi_packets+1;
     8'h84:info_packets=info_packets+1;
    endcase
    model_busy=0;
   end
   segment_cycle=segment_cycle+1;
  end
  #1;
  // Compare even invalid and reset cycles: payload persistence is part of equivalence.
  if({fifo_read,sample_request,packet_valid,audio_header,aux_header,audio_body,aux_body}!==
     {ref_read,ref_request,ref_valid,ref_ah,ref_bh,ref_ab,ref_bb})
   $fatal(1,"public output cycle equivalence mismatch at cycle=%0d",cycles);
 end

 // Encode a subset of both audio and auxiliary packets and check all 32 symbols.
 reg enc_valid=0,enc_send=0,enc_hs=0,enc_vs=0,enc_d3=0;
 reg [23:0] enc_ah=0,enc_ref_ah=0;
 reg [223:0] enc_ab=0,enc_ref_ab=0;
 wire enc_ready,enc_prepared,enc_symbol,enc_last;
 wire [4:0] enc_index;
 wire [9:0] enc_c0,enc_c1,enc_c2;
 wire enc_ref_ready,enc_ref_prepared,enc_ref_symbol,enc_ref_last;
 wire [4:0] enc_ref_index;
 wire [9:0] enc_ref_c0,enc_ref_c1,enc_ref_c2;
 hdmi_data_island_encoder encoder(.clk(clk),.rst_n(rst_n),.packet_valid(enc_valid),.packet_ready(enc_ready),
  .packet_header(enc_ah),.packet_body(enc_ab),.send_start(enc_send),.hsync(enc_hs),.vsync(enc_vs),.control_d3(enc_d3),
  .prepared(enc_prepared),.symbol_valid(enc_symbol),.symbol_last(enc_last),.symbol_index(enc_index),
  .channel0(enc_c0),.channel1(enc_c1),.channel2(enc_c2));
 hdmi_data_island_encoder ref_encoder(.clk(clk),.rst_n(rst_n),.packet_valid(enc_valid),.packet_ready(enc_ref_ready),
  .packet_header(enc_ref_ah),.packet_body(enc_ref_ab),.send_start(enc_send),.hsync(enc_hs),.vsync(enc_vs),.control_d3(enc_d3),
  .prepared(enc_ref_prepared),.symbol_valid(enc_ref_symbol),.symbol_last(enc_ref_last),.symbol_index(enc_ref_index),
  .channel0(enc_ref_c0),.channel1(enc_ref_c1),.channel2(enc_ref_c2));
 function [7:0] bch;
  input [55:0] data;
  input integer bits;
  reg [7:0] value;
  reg feedback;
  integer n;
  begin
   value=0;
   for(n=0;n<bits;n=n+1)begin
    feedback=value[0]^data[n];value=value>>1;
    if(feedback)value=value^8'h83;
   end
   bch=value;
  end
 endfunction
 function [9:0] terc;
  input [3:0] nibble;
  begin
   case(nibble)
    0:terc=10'h29c;1:terc=10'h263;2:terc=10'h2e4;3:terc=10'h2e2;
    4:terc=10'h171;5:terc=10'h11e;6:terc=10'h18e;7:terc=10'h13c;
    8:terc=10'h2cc;9:terc=10'h139;10:terc=10'h19c;11:terc=10'h2c6;
    12:terc=10'h28e;13:terc=10'h271;14:terc=10'h163;15:terc=10'h2c3;
   endcase
  end
 endfunction
 reg [31:0] golden_encoded_header;
 reg [63:0] golden_encoded_body[0:3];
 integer encoded_packets=0,encoded_symbols=0,encoded_audio=0,encoded_aux=0,k;
 integer symbols_in_packet=0,aborted_encoder_packets=0;
 integer send_count=0;
 reg selecting_aux=0;
 always @(posedge clk)begin
  if(!rst_n)begin
   enc_valid<=0;enc_send<=0;send_count=0;
   if(symbols_in_packet!=0)aborted_encoder_packets=aborted_encoder_packets+1;
   symbols_in_packet=0;
  end
  else begin
   enc_valid<=0;enc_send<=enc_prepared;
   if(packet_valid&&enc_ready&&!enc_valid)begin
    selecting_aux=(send_count%2!=0);send_count=send_count+1;
    if(selecting_aux)begin
     enc_ah<=aux_header;enc_ab<=aux_body;enc_ref_ah<=ref_bh;enc_ref_ab<=ref_bb;
    end else begin
     enc_ah<=audio_header;enc_ab<=audio_body;enc_ref_ah<=ref_ah;enc_ref_ab<=ref_ab;
    end
    enc_valid<=1;
   end
   if(enc_valid&&enc_ready)begin
    golden_encoded_header={bch({32'd0,enc_ah},24),enc_ah};
    for(k=0;k<4;k=k+1)golden_encoded_body[k]={bch(enc_ab[k*56+:56],56),enc_ab[k*56+:56]};
    if(enc_ah[7:0]==2)encoded_audio=encoded_audio+1;else encoded_aux=encoded_aux+1;
   end
   if(enc_symbol)begin
    if(enc_index!==symbols_in_packet)$fatal(1,"encoder skipped or repeated a symbol");
    symbols_in_packet=symbols_in_packet+1;
    if(enc_last!==(enc_index==31))$fatal(1,"encoder last/index mismatch");
    if(enc_c0!==terc({enc_d3,golden_encoded_header[enc_index],enc_vs,enc_hs}))
     $fatal(1,"encoded header symbol mismatch index=%0d",enc_index);
    if(enc_c1!==terc({golden_encoded_body[3][2*enc_index],golden_encoded_body[2][2*enc_index],
                     golden_encoded_body[1][2*enc_index],golden_encoded_body[0][2*enc_index]}))
     $fatal(1,"encoded even body symbol mismatch index=%0d",enc_index);
    if(enc_c2!==terc({golden_encoded_body[3][2*enc_index+1],golden_encoded_body[2][2*enc_index+1],
                     golden_encoded_body[1][2*enc_index+1],golden_encoded_body[0][2*enc_index+1]}))
     $fatal(1,"encoded odd body symbol mismatch index=%0d",enc_index);
    encoded_symbols=encoded_symbols+1;
    if(enc_last)begin
     if(symbols_in_packet!=32)$fatal(1,"incomplete encoded packet");
     encoded_packets=encoded_packets+1;symbols_in_packet=0;
    end
   end
  end
  #2;
  if({enc_ready,enc_prepared,enc_symbol,enc_last,enc_index,enc_c0,enc_c1,enc_c2}!==
     {enc_ref_ready,enc_ref_prepared,enc_ref_symbol,enc_ref_last,enc_ref_index,enc_ref_c0,enc_ref_c1,enc_ref_c2})
   $fatal(1,"encoder cycle equivalence mismatch");
 end
 reg [31:0] rng=32'h2167ba39;
 task tick;
  input do_build,do_empty,do_frame;
  begin
   @(negedge clk);build=do_build;fifo_empty=do_empty;frame_start=do_frame;
   rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   enc_hs=rng[7];enc_vs=rng[17];enc_d3=rng[27];
  end
 endtask
 task reset_now;
  begin
   @(negedge clk);
   if(model_busy)begin reset_age=segment_cycle-accepted_cycle-1;reset_age_coverage=reset_age_coverage|(1<<reset_age);end
   rst_n=0;build=0;frame_start=0;fifo_empty=0;reset_count=reset_count+1;
   repeat(2)@(negedge clk);
   rst_n=1;
  end
 endtask
 integer i,j,start_packets,start_requests;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  start_packets=packets;start_requests=requests;
  for(i=0;i<100000;i=i+1)tick(i%800==0,0,i==24000||i==49999);
  repeat(10)tick(0,0,0);
  if(packets-start_packets!=125||requests-start_requests!=192)
   $fatal(1,"125-line rational pacing mismatch packets=%0d requests=%0d",packets-start_packets,requests-start_requests);
  $display("PASS normal pacing: 125 lines, 192 sample requests");
  for(i=0;i<15000;i=i+1)tick(1,rng[0]&&rng[4],i%131==0);
  for(i=0;i<40000;i=i+1)tick(rng[1]||rng[6],rng[4]||rng[11],rng[19]&&rng[25]);
  // The second accepted packet has two samples: reset each in-flight phase.
  for(j=0;j<5;j=j+1)begin
   reset_now();tick(1,0,0);repeat(10)tick(0,0,0);
   tick(1,0,0);for(i=0;i<j;i=i+1)tick(0,1,i==1);
   reset_now();repeat(10)tick(0,0,0);
  end
  // ACR wrap and frame request coincide with an accepted build, first with
  // ACR still pending from reset, then with it already serviced.
  reset_now();
  while(segment_cycle<24998)tick(0,rng[3],0);
  tick(1,0,1);repeat(8)tick(0,0,0);tick(1,0,0);repeat(8)tick(0,0,0);
  reset_now();tick(1,0,0);repeat(8)tick(0,0,0);tick(1,0,0);
  repeat(8)tick(0,0,0);tick(1,0,0);
  while(segment_cycle<24998)tick(0,rng[3],0);
  tick(1,0,1);repeat(8)tick(0,0,0);tick(1,0,0);repeat(8)tick(0,0,0);
  repeat(150)tick(0,0,0);
  if(single_packets<100||double_packets<100||silent_samples<100||iec_wraps<10||ignored_builds<100||
     acr_packets<5||avi_packets<5||info_packets<5||encoded_packets<100||encoded_audio<20||encoded_aux<20||
     empty_transition_coverage<100||boundary_accepts!=2||(reset_age_coverage&31)!=31||
     frame_with_acr<1||frame_with_avi<1||frame_with_info<1)
   $fatal(1,"missing scenario coverage single=%0d double=%0d silence=%0d wraps=%0d ignored=%0d enc=%0d boundary=%0d reset_mask=%h",single_packets,double_packets,silent_samples,iec_wraps,ignored_builds,encoded_packets,boundary_accepts,reset_age_coverage);
  $display("PASS audio slots: cycles=%0d packets=%0d requests=%0d reads=%0d single=%0d double=%0d silence=%0d IEC_wraps=%0d ignored_busy_builds=%0d resets=%0d reset_phase_mask=%h READ_empty_changes=%0d ACR_frame_boundary=%0d ACR=%0d AVI=%0d AudioInfo=%0d encoded_packets=%0d encoded_symbols=%0d encoded_audio=%0d encoded_aux=%0d",cycles,packets,requests,reads,single_packets,double_packets,silent_samples,iec_wraps,ignored_builds,reset_count,reset_age_coverage,empty_transition_coverage,boundary_accepts,acr_packets,avi_packets,info_packets,encoded_packets,encoded_symbols,encoded_audio,encoded_aux);
  $display("PASS overlap coverage: frame_with_ACR=%0d frame_with_AVI=%0d frame_with_AudioInfo=%0d encoder_partial_reset_aborts=%0d",frame_with_acr,frame_with_avi,frame_with_info,aborted_encoder_packets);
  $finish;
 end
 initial begin #5000000;$fatal(1,"audio slot timeout");end
endmodule
