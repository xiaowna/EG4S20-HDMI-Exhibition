// Serial BCH and payload transmission share a circular payload store.
// Complete 24/56 rotations restore the original data before READY.
module hdmi_data_island_encoder(
 input wire clk,rst_n,packet_valid,
 output wire packet_ready,
 input wire [23:0] packet_header,input wire [223:0] packet_body,
 input wire send_start,hsync,vsync,control_d3,
 output wire prepared,symbol_valid,symbol_last,
 output wire [4:0] symbol_index,
 output wire [9:0] channel0,channel1,channel2);
 localparam IDLE=0,CALCULATE=1,READY=2,SEND=3;
 reg [1:0] state;reg [4:0] index;reg [5:0] crc_index;
 reg [31:0] header_shift;
 reg [63:0] body0,body1,body2,body3;
 reg [7:0] header_crc,crc0,crc1,crc2,crc3;
 function [7:0] advance_crc;
  input [7:0] crc;input data_bit;
  begin advance_crc={1'b0,crc[7:1]}^((crc[0]^data_bit)?8'h83:8'h00);end
 endfunction
 wire accept=packet_valid&&packet_ready;
 wire payload_visible=state[1];
 wire [3:0] even_bits={body3[0],body2[0],body1[0],body0[0]}&{4{payload_visible}};
 wire [3:0] odd_bits={body3[1],body2[1],body1[1],body0[1]}&{4{payload_visible}};
 assign packet_ready=state==IDLE;assign prepared=state==READY;
 assign symbol_valid=state==SEND;assign symbol_last=symbol_valid&&index==31;
 assign symbol_index=index;
 hdmi_terc4 c0(.nibble({control_d3,header_shift[0]&payload_visible,vsync,hsync}),.symbol(channel0));
 hdmi_terc4 c1(.nibble(even_bits),.symbol(channel1));
 hdmi_terc4 c2(.nibble(odd_bits),.symbol(channel2));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;index<=0;crc_index<=0;
   header_shift<=0;body0<=0;body1<=0;body2<=0;body3<=0;
   header_crc<=0;crc0<=0;crc1<=0;crc2<=0;crc3<=0;
  end else case(state)
   IDLE:if(accept)begin
    header_shift<={8'd0,packet_header};
    body0<={8'd0,packet_body[55:0]};body1<={8'd0,packet_body[111:56]};
    body2<={8'd0,packet_body[167:112]};body3<={8'd0,packet_body[223:168]};
    header_crc<=0;crc0<=0;crc1<=0;crc2<=0;crc3<=0;
    crc_index<=0;state<=CALCULATE;
   end
   CALCULATE:begin
    if(crc_index<24)begin
     header_crc<=advance_crc(header_crc,header_shift[0]);
     header_shift[23:0]<={header_shift[0],header_shift[23:1]};
    end
    if(crc_index<56)begin
     crc0<=advance_crc(crc0,body0[0]);crc1<=advance_crc(crc1,body1[0]);
     crc2<=advance_crc(crc2,body2[0]);crc3<=advance_crc(crc3,body3[0]);
     body0[55:0]<={body0[0],body0[55:1]};body1[55:0]<={body1[0],body1[55:1]};
     body2[55:0]<={body2[0],body2[55:1]};body3[55:0]<={body3[0],body3[55:1]};
     crc_index<=crc_index+1'b1;
    end else begin
     header_shift[31:24]<=header_crc;
     body0[63:56]<=crc0;body1[63:56]<=crc1;
     body2[63:56]<=crc2;body3[63:56]<=crc3;
     state<=READY;
    end
   end
   READY:if(send_start)begin index<=0;state<=SEND;end
   SEND:begin
    header_shift<=header_shift>>1;
    body0<=body0>>2;body1<=body1>>2;body2<=body2>>2;body3<=body3>>2;
    if(index==31)state<=IDLE;else index<=index+1'b1;
   end
   default:state<=IDLE;
  endcase
 end
endmodule
