// TMDS encoder: DVI/HDMI 8-bit symbol to 10-bit symbol.
module tmds_encoder(input wire pix_clk,input wire rst_n,input wire [7:0] din,
 input wire de,input wire c0,input wire c1,output reg [9:0] tmds);
 reg [8:0] q_m; integer i; integer ones_d; integer ones_q; integer balance;
 reg signed [7:0] disparity;
 always @* begin
   ones_d=0; for(i=0;i<8;i=i+1) ones_d=ones_d+din[i];
   q_m=0; q_m[0]=din[0];
   if ((ones_d>4) || ((ones_d==4) && (din[0]==1'b0))) begin
     q_m[8]=1'b0; for(i=1;i<8;i=i+1) q_m[i]=q_m[i-1]^~din[i];
   end else begin
     q_m[8]=1'b1; for(i=1;i<8;i=i+1) q_m[i]=q_m[i-1]^din[i];
   end
   ones_q=0; for(i=0;i<8;i=i+1) ones_q=ones_q+q_m[i];
   balance=(ones_q*2)-8;
 end
 always @(posedge pix_clk or negedge rst_n) begin
  if(!rst_n) begin tmds<=10'b1101010100; disparity<=0; end
  else if(!de) begin
   disparity<=0;
   case({c1,c0})
    2'b00:tmds<=10'b1101010100; 2'b01:tmds<=10'b0010101011;
    2'b10:tmds<=10'b0101010100; default:tmds<=10'b1010101011;
   endcase
  end else if((disparity==0)||(balance==0)) begin
   tmds[9]<=~q_m[8]; tmds[8]<=q_m[8]; tmds[7:0]<=q_m[8]?q_m[7:0]:~q_m[7:0];
   disparity<=q_m[8] ? disparity+balance : disparity-balance;
  end else if ((disparity>0 && balance>0)||(disparity<0 && balance<0)) begin
   tmds[9]<=1'b1; tmds[8]<=q_m[8]; tmds[7:0]<=~q_m[7:0];
   // For same-sign disparity, invert q_m data and subtract its balance.
   disparity<=disparity-balance+(q_m[8]?2:0);
  end else begin
   tmds[9]<=1'b0; tmds[8]<=q_m[8]; tmds[7:0]<=q_m[7:0];
   // For opposite-sign disparity, keep q_m data and add its balance.
   disparity<=disparity+balance-(q_m[8]?0:2);
  end
 end
endmodule

