// DMZ-EG4S20 core board: fixed left-to-right display "1234".
// Common cathode: segments high-active, digit selects low-active.
// seg_led[7:0] = {DP,G,F,E,D,C,B,A}; DIG0 is the rightmost digit.
module dmz_seg_test_top(
 input wire clk50,rst_n,
 output reg [7:0] seg_led,
 output reg [3:0] seg_sel);
 reg [15:0] scan_count;
 reg [1:0] scan_digit;
 // 50000 clocks per digit at 50 MHz: 1 ms/slot, 250 Hz/full frame.
 // Blank before changing segments to avoid lighting the previous digit.
 always @(posedge clk50 or negedge rst_n)begin
  if(!rst_n)begin
   scan_count<=0;
   scan_digit<=0;
   seg_led<=8'h00;
   seg_sel<=4'b1111;
  end else begin
   if(scan_count==16'd49999)begin
    scan_count<=0;
    scan_digit<=scan_digit+1'b1;
    seg_sel<=4'b1111;
   end else begin
    scan_count<=scan_count+1'b1;
    if(scan_count==0)begin
     case(scan_digit)
      2'd0:seg_led<=8'h66; // Rightmost: 4.
      2'd1:seg_led<=8'h4f; // 3.
      2'd2:seg_led<=8'h5b; // 2.
      2'd3:seg_led<=8'h06; // Leftmost: 1.
     endcase
    end else if(scan_count==1)begin
     case(scan_digit)
      2'd0:seg_sel<=4'b1110;
      2'd1:seg_sel<=4'b1101;
      2'd2:seg_sel<=4'b1011;
      2'd3:seg_sel<=4'b0111;
     endcase
    end
   end
  end
 end
endmodule
