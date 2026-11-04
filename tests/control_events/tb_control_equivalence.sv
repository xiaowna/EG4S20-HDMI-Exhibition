`timescale 1ns/1ps
module tb_control_equivalence;
 reg clk=0,rst_n=0;
 reg [3:0] key_press=0,encoder_event=0,infrared_event=0;
 wire [3:0] control_event;
 wire [3:0] reference_input=!rst_n?4'b0:
  (key_press!=0?key_press:(encoder_event!=0?encoder_event:infrared_event));
 wire signed [8:0] value_new,value_old;
 wire [8:0] gain_new,gain_old;
 wire fade_new,fade_old,wave_new,wave_old,update_new,update_old;
 wire active_new,active_old,next_new,next_old,prev_new,prev_old,pause_new,pause_old;
 wire [1:0] page_new,page_old;
 wire [26:0] new_signature={value_new,gain_new,fade_new,wave_new,update_new,
  active_new,page_new,next_new,prev_new,pause_new};
 wire [26:0] old_signature={value_old,gain_old,fade_old,wave_old,update_old,
  active_old,page_old,next_old,prev_old,pause_old};
 integer b,g,f,w,s,mask,source,j,trials=0,checks=0,cycles=0;
 reg [31:0] random_state=32'h45830ace;
 reg [3:0] random_key,random_encoder,random_ir;
 always #5 clk=~clk;
 media_control_events events(.enable(rst_n),.key_press(key_press),
  .encoder_event(encoder_event),.infrared_event(infrared_event),.control_event(control_event));
 media_adjust_control candidate(.clk(clk),.rst_n(rst_n),.key_press(control_event),
  .cfg_value(value_new),.cfg_gain_q8(gain_new),.cfg_fade_enabled(fade_new),
  .cfg_wave_enabled(wave_new),.cfg_update(update_new),.setting_active(active_new),
  .setting_page(page_new),.next_event(next_new),.prev_event(prev_new),.pause_event(pause_new));
 media_adjust_control_o12 reference(.clk(clk),.rst_n(rst_n),.key_press(reference_input),
  .cfg_value(value_old),.cfg_gain_q8(gain_old),.cfg_fade_enabled(fade_old),
  .cfg_wave_enabled(wave_old),.cfg_update(update_old),.setting_active(active_old),
  .setting_page(page_old),.next_event(next_old),.prev_event(prev_old),.pause_event(pause_old));
 task compare;begin
  if(new_signature!==old_signature)$fatal(1,"control mismatch cycle=%0d mask=%h/%h/%h old=%h new=%h",cycles,key_press,encoder_event,infrared_event,old_signature,new_signature);
  checks=checks+1;
 end endtask
 task tick(input [3:0] k,e,i);begin
  @(negedge clk);key_press=k;encoder_event=e;infrared_event=i;#1;compare;
  @(posedge clk);#1;cycles=cycles+1;compare;
 end endtask
 task press(input [3:0] k);begin tick(k,0,0);tick(0,0,0);end endtask
 task reset_controls;begin
  @(negedge clk);key_press=0;encoder_event=0;infrared_event=0;rst_n=0;#1;compare;
  @(posedge clk);#1;compare;
  @(negedge clk);rst_n=1;#1;compare;
 end endtask
 // Reach every state through real events, never force internal registers.
 task prepare(input integer target_b,target_g,target_f,target_w,target_s);begin
  reset_controls;
  press(8);
  for(j=0;j<target_b;j=j+1)press(1);
  for(j=0;j>target_b;j=j-1)press(4);
  press(2);
  for(j=0;j<target_g;j=j+1)press(1);
  for(j=0;j>target_g;j=j-1)press(4);
  press(2);if(target_f)press(1);
  press(2);if(target_w)press(1);
  press(2);
  if(target_s!=0)begin press(8);for(j=1;j<target_s;j=j+1)press(2);end
  if($signed(value_new)!=target_b*32 || gain_new!=256+target_g*64 ||
     fade_new!==target_f[0] || wave_new!==target_w[0] || active_new!==(target_s!=0) ||
     (target_s!=0 && page_new!=target_s-1))$fatal(1,"reachable-state setup failed");
 end endtask
 task random_next;begin
  random_state=random_state^(random_state<<13);
  random_state=random_state^(random_state>>17);
  random_state=random_state^(random_state<<5);
 end endtask
 initial begin
  #1;rst_n=1;#1;rst_n=0;
  for(b=-2;b<=2;b=b+1)
   for(g=-2;g<=2;g=g+1)
    for(f=0;f<2;f=f+1)
     for(w=0;w<2;w=w+1)
      for(s=0;s<5;s=s+1)
       for(mask=0;mask<16;mask=mask+1)begin
        prepare(b,g,f,w,s);tick(mask,0,0);tick(0,0,0);trials=trials+1;
       end
  // Exercise each future source over long sequences, changing context freely.
  for(source=0;source<3;source=source+1)begin
   reset_controls;
   for(mask=0;mask<16;mask=mask+1)begin
    tick(source==0?mask:0,source==1?mask:0,source==2?mask:0);tick(0,0,0);
   end
  end
  for(mask=0;mask<20000;mask=mask+1)begin
   random_next;random_key=random_state[3:0];
   random_next;random_encoder=random_state[3:0];
   random_next;random_ir=random_state[3:0];
   tick(random_key,random_encoder,random_ir);
   if(mask%257==0)reset_controls;
  end
  reset_controls;
  $display("PASS control_equivalence: %0d exhaustive state/input trials (500 reachable configurations x 16 key masks), 20000 mixed-source cycles, %0d cycles/%0d public-output checks",trials,cycles,checks);
  $finish;
 end
 initial begin #20000000;$fatal(1,"control equivalence timeout");end
endmodule
