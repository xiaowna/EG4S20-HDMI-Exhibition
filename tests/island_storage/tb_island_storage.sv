`timescale 1ns/1ps
module tb_island_storage;
 reg clk=0,rst_n=0,packet_valid=0,send_start=0,hsync=0,vsync=0,control_d3=0;
 reg [23:0] packet_header=0;
 reg [223:0] packet_body=0;
 always #5 clk=~clk;
 wire packet_ready,prepared,symbol_valid,symbol_last;
 wire [4:0] symbol_index;
 wire [9:0] channel0,channel1,channel2;
 wire [38:0] observed={packet_ready,prepared,symbol_valid,symbol_last,
                      symbol_index,channel0,channel1,channel2};
 hdmi_data_island_encoder dut(.clk(clk),.rst_n(rst_n),.packet_valid(packet_valid),
  .packet_ready(packet_ready),.packet_header(packet_header),.packet_body(packet_body),
  .send_start(send_start),.hsync(hsync),.vsync(vsync),.control_d3(control_d3),
  .prepared(prepared),.symbol_valid(symbol_valid),.symbol_last(symbol_last),
  .symbol_index(symbol_index),.channel0(channel0),.channel1(channel1),.channel2(channel2));
`ifdef COMPARE_BASELINE
 wire reference_ready,reference_prepared,reference_valid,reference_last;
 wire [4:0] reference_index;
 wire [9:0] reference_channel0,reference_channel1,reference_channel2;
 wire [38:0] reference={reference_ready,reference_prepared,reference_valid,reference_last,
                       reference_index,reference_channel0,reference_channel1,reference_channel2};
 hdmi_data_island_encoder_baseline baseline(.clk(clk),.rst_n(rst_n),
  .packet_valid(packet_valid),.packet_ready(reference_ready),.packet_header(packet_header),
  .packet_body(packet_body),.send_start(send_start),.hsync(hsync),.vsync(vsync),
  .control_d3(control_d3),.prepared(reference_prepared),.symbol_valid(reference_valid),
  .symbol_last(reference_last),.symbol_index(reference_index),
  .channel0(reference_channel0),.channel1(reference_channel1),.channel2(reference_channel2));
`endif

 // A packet-level BCH oracle is independent of the sequential RTL checker.
 // It implements the specified LSB-first polynomial, with no DUT internals.
 function [7:0] parity;
  input [55:0] data;
  input integer count;
  integer bit_number;
  reg [7:0] remainder;
  reg feedback;
  begin
   remainder=0;
   for(bit_number=0;bit_number<count;bit_number=bit_number+1)begin
    feedback=remainder[0]^data[bit_number];
    remainder={1'b0,remainder[7:1]};
    if(feedback)remainder=remainder^8'h83;
   end
   parity=remainder;
  end
 endfunction
 function [287:0] encode;
  input [247:0] data;
  integer subpacket;
  reg [287:0] result;
  reg [55:0] fragment;
  begin
   result=0;
   result[31:0]={parity({32'd0,data[23:0]},24),data[23:0]};
   for(subpacket=0;subpacket<4;subpacket=subpacket+1)begin
    fragment=data[24+56*subpacket +: 56];
    result[32+64*subpacket +: 64]={parity(fragment,56),fragment};
   end
   encode=result;
  end
 endfunction
 function [9:0] terc4;
  input [3:0] nibble;
  begin
   case(nibble)
    0:terc4=10'h29c;1:terc4=10'h263;2:terc4=10'h2e4;3:terc4=10'h2e2;
    4:terc4=10'h171;5:terc4=10'h11e;6:terc4=10'h18e;7:terc4=10'h13c;
    8:terc4=10'h2cc;9:terc4=10'h139;10:terc4=10'h19c;11:terc4=10'h2c6;
    12:terc4=10'h28e;13:terc4=10'h271;14:terc4=10'h163;15:terc4=10'h2c3;
   endcase
  end
 endfunction

 localparam IDLE=0,CALCULATE=1,READY=2,SEND=3;
 integer model_state=IDLE,model_index=0,calculation_left=0;
 reg [287:0] pending_packet=0,shift_packet=0;
 integer cycles=0,checks=0,accepted=0,completed=0,resets=0;
 integer ignored_valid=0,ignored_send=0,ready_hold_cycles=0,idle_cycles=0;
 integer payload_changes=0,prepare_edges=0,calculate_send_boundary=0;
 reg [247:0] previous_input=0;
 reg [31:0] send_positions=0,reset_send_positions=0;
 reg [31:0] control_coverage=0;
 reg [57:0] reset_calculate_ages=0;
 reg [3:0] model_even,model_odd;
 reg [38:0] expected;
 integer j;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   model_state=IDLE;model_index=0;calculation_left=0;
   pending_packet=0;shift_packet=0;
  end else begin
   cycles=cycles+1;
   if(model_state!=IDLE && packet_valid)ignored_valid=ignored_valid+1;
   if((model_state==IDLE || model_state==CALCULATE || model_state==SEND) && send_start)
    ignored_send=ignored_send+1;
   if(model_state!=IDLE && previous_input!=={packet_body,packet_header})
    payload_changes=payload_changes+1;
   previous_input={packet_body,packet_header};
   case(model_state)
    IDLE:begin
     idle_cycles=idle_cycles+1;
     if(packet_valid)begin
      pending_packet=encode({packet_body,packet_header});
      // 56 body processing edges, followed by the registered done observation.
      calculation_left=57;model_state=CALCULATE;accepted=accepted+1;
     end
    end
    CALCULATE:begin
     if(calculation_left==1)begin
      if(send_start)calculate_send_boundary=calculate_send_boundary+1;
      shift_packet=pending_packet;model_state=READY;prepare_edges=prepare_edges+1;
     end else calculation_left=calculation_left-1;
    end
    READY:begin
     if(send_start)begin model_state=SEND;model_index=0;end
     else ready_hold_cycles=ready_hold_cycles+1;
    end
    SEND:begin
     shift_packet[31:0]=shift_packet[31:0]>>1;
     for(j=0;j<4;j=j+1)
      shift_packet[32+64*j +: 64]=shift_packet[32+64*j +: 64]>>2;
     if(model_index==31)begin model_state=IDLE;completed=completed+1;end
     else model_index=model_index+1;
    end
   endcase
   if(model_state==SEND)send_positions[model_index]=1;
  end
  #1;
  check_outputs();
 end

 task check_outputs;
  integer subpacket;
  begin
   for(subpacket=0;subpacket<4;subpacket=subpacket+1)begin
    model_even[subpacket]=shift_packet[32+64*subpacket];
    model_odd[subpacket]=shift_packet[33+64*subpacket];
   end
   expected={model_state==IDLE,model_state==READY,model_state==SEND,
             model_state==SEND && model_index==31,model_index[4:0],
             terc4({control_d3,shift_packet[0],vsync,hsync}),
             terc4(model_even),terc4(model_odd)};
   checks=checks+1;
   control_coverage[model_state*8+{control_d3,vsync,hsync}]=1;
   if(observed!==expected)
    $fatal(1,"public oracle cycle=%0d state=%0d index=%0d left=%0d observed=%010h expected=%010h",
           cycles,model_state,model_index,calculation_left,observed,expected);
`ifdef COMPARE_BASELINE
   if(observed!==reference)
    $fatal(1,"all-39-bit equivalence cycle=%0d state=%0d observed=%010h reference=%010h",
           cycles,model_state,observed,reference);
`endif
  end
 endtask

 reg [31:0] random_state=32'h9273a6d5;
 function [31:0] next_random;
  input [31:0] value;
  reg [31:0] x;
  begin x=value^(value<<13);x=x^(x>>17);x=x^(x<<5);next_random=x;end
 endfunction
 task change_inputs;
  integer word_number;
  begin
   random_state=next_random(random_state);packet_header=random_state[23:0];
   for(word_number=0;word_number<7;word_number=word_number+1)begin
    random_state=next_random(random_state);packet_body[32*word_number +: 32]=random_state;
   end
   random_state=next_random(random_state);
   {control_d3,vsync,hsync}=random_state[2:0];
  end
 endtask
 // Every driven cycle changes the input payload and control bits, even while
 // busy or invalid. This catches accidental dependence on unlatched inputs.
 task step;
  input pv,send,rst;
  begin
   @(negedge clk);change_inputs();packet_valid=pv;send_start=send;rst_n=rst;
   #2;check_outputs();
   @(posedge clk);#2;
  end
 endtask
 task reset_core;
  begin
   step(0,0,0);step(0,0,0);step(0,0,1);resets=resets+1;
  end
 endtask
 task accept_packet;
  input [247:0] payload;
  begin
   if(!packet_ready)$fatal(1,"test attempted an acceptance while busy");
   @(negedge clk);change_inputs();{packet_body,packet_header}=payload;
   packet_valid=1;send_start=1;
   #2;check_outputs();@(posedge clk);#2;
   if(packet_ready || prepared || symbol_valid)$fatal(1,"acceptance did not enter calculation");
  end
 endtask
 task wait_prepared;
  integer elapsed;
  begin
   elapsed=0;
   while(!prepared && elapsed<58)begin
    // Keep send asserted through the final calculation edge: it must not
    // start SEND until a subsequent edge in the READY state.
    step(1,1,1);elapsed=elapsed+1;
   end
   if(elapsed!=57 || symbol_valid || packet_ready || !prepared)
    $fatal(1,"preparation handshake/latency %0d",elapsed);
  end
 endtask
 task finish_packet;
  integer position;
  begin
   if(!prepared)$fatal(1,"test expected prepared packet");
   step(1,1,1);
   for(position=0;position<32;position=position+1)begin
    if(!symbol_valid || symbol_index!==position[4:0] || symbol_last!==(position==31))
     $fatal(1,"32-symbol length/index position=%0d",position);
    step(1,1,1);
   end
   if(symbol_valid || !packet_ready || prepared)$fatal(1,"packet termination");
  end
 endtask

 reg [247:0] golden_inputs[0:7];
 reg [287:0] golden_outputs[0:7];
 reg [247:0] one_hot;
 integer p,k,age,position,completed_target,random_cycle;
 reg noise_valid,noise_send,noise_reset;
 initial begin
  $readmemh("../data_island/input.hex",golden_inputs);
  $readmemh("../data_island/golden.hex",golden_outputs);
  for(p=0;p<8;p=p+1)
   if(encode(golden_inputs[p])!==golden_outputs[p])
    $fatal(1,"independent BCH oracle disagrees with existing golden packet %0d",p);
  reset_core();
  repeat(1024)step(0,1,1);
  for(p=0;p<8;p=p+1)begin
   accept_packet(golden_inputs[p]);wait_prepared();
   repeat(7)step(1,0,1);
   finish_packet();
  end
  // Every bit of the full 24+224-bit payload is separately exercised through
  // the real checker and all 32 TERC4 output symbols.
  for(p=0;p<248;p=p+1)begin
   one_hot=0;one_hot[p]=1;
   accept_packet(one_hot);wait_prepared();finish_packet();
  end
  accept_packet(golden_inputs[3]);wait_prepared();
  repeat(256)step(1,0,1);
  finish_packet();
  // Continuous valid and send requests force all handshaking boundaries,
  // including immediate re-acceptance after the final symbol.
  completed_target=completed+128;
  while(completed<completed_target)step(1,1,1);
  step(0,0,1);
  reset_core();

  // Reset at every calculation age, including 24-bit header completion and
  // 56-bit body completion, and the edge that first exposes READY.
  for(age=0;age<=57;age=age+1)begin
   accept_packet(golden_inputs[age%8]);
   for(k=0;k<age;k=k+1)step(1,1,1);
   if(age<57 && prepared)$fatal(1,"early prepared before calculation reset");
   if(age==57 && !prepared)$fatal(1,"missing READY reset boundary");
   reset_calculate_ages[age]=1;
   reset_core();
  end
  // All 32 in-flight symbol positions are reset, and the same test then
  // re-enters a fresh full packet to check that stale data cannot survive.
  for(position=0;position<32;position=position+1)begin
   accept_packet(golden_inputs[position%8]);wait_prepared();
   step(1,1,1);
   for(k=0;k<position;k=k+1)step(1,1,1);
   if(!symbol_valid || symbol_index!==position[4:0])$fatal(1,"send reset position");
   reset_send_positions[position]=1;reset_core();
   accept_packet(golden_inputs[(position+1)%8]);wait_prepared();finish_packet();
  end
  // Deterministic random traffic includes idle gaps, sustained stalls, busy
  // requests, control changes, input changes, and asynchronous reset pulses.
  for(random_cycle=0;random_cycle<200000;random_cycle=random_cycle+1)begin
   random_state=next_random(random_state);
   noise_valid=random_state[0] || random_state[4];
   noise_send=random_state[1] && random_state[5];
   noise_reset=(random_state[17:6]!=12'd0);
   if(!noise_reset)resets=resets+1;
   step(noise_valid,noise_send,noise_reset);
  end
  reset_core();
  accept_packet(golden_inputs[7]);wait_prepared();finish_packet();
  repeat(1024)step(0,0,1);
  if(send_positions!==32'hffffffff || reset_send_positions!==32'hffffffff ||
     reset_calculate_ages!=={58{1'b1}} || control_coverage!==32'hffffffff)
   $fatal(1,"reset/symbol coverage incomplete");
  if(completed<1500 || ignored_valid<100000 || ignored_send<30000 ||
     ready_hold_cycles<1000 || payload_changes<150000 || calculate_send_boundary<500)
   $fatal(1,"random/boundary coverage insufficient");
  $display("PASS: all 39 public bits including invalid cycles; 8 golden BCH packets; 248 one-hot payloads");
  $display("PASS: 58 calculation reset ages, 32 send reset positions, 4 states x 8 sync/control combinations, long idle/READY holds, sustained and random handshakes");
  $display("SUMMARY cycles=%0d checks=%0d accepted=%0d completed=%0d resets=%0d ignored_valid=%0d ignored_send=%0d ready_hold=%0d payload_changes=%0d prepared=%0d calculate_send_boundary=%0d",
           cycles,checks,accepted,completed,resets,ignored_valid,ignored_send,
           ready_hold_cycles,payload_changes,prepare_edges,calculate_send_boundary);
  $finish;
 end
 initial begin #5000000;$fatal(1,"deadline");end
endmodule
