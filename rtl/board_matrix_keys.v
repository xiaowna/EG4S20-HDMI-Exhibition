// DMZ core 4x4 keyboard. Logical row/column numbers follow the schematic,
// KEY1/2/3 = row0/col1/2/3; KEY4 = row1/col0.
// At 50 MHz, settle 50 us per row and publish one complete scan every 200 us.
module board_matrix_keys #(parameter integer SCAN_CYCLES=2500,parameter VIEW_KEYS=0,parameter HOME_KEY=0,parameter SCENE_KEYS=0)(
 input wire clk,rst_n,
 input wire [3:0] col_n,
 output wire [3:0] row_n,
 output reg [3:0] key_n,
 output reg ready,output reg [4:0] view_key_n,output reg home_key_n,output reg [2:0] scene_key_n);
 localparam integer COUNT_BITS=(SCAN_CYCLES>1)?$clog2(SCAN_CYCLES):1;
 reg [COUNT_BITS-1:0] count;
 reg [1:0] row;
 reg [11:0] scan_keys;
 reg blocked;
 (* async_reg="true" *) reg [3:0] col_meta,col_sync;
 wire [15:0] completed={~col_sync,scan_keys};
 genvar i;
 generate for(i=0;i<4;i=i+1)begin: drive_row
  // Never drive HIGH: simultaneous keys must not short opposing GPIO outputs.
  assign row_n[i]=(rst_n && row==i)?1'b0:1'bz;
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   count<=0;row<=0;scan_keys<=0;blocked<=0;
   col_meta<=4'hf;col_sync<=4'hf;key_n<=4'hf;view_key_n<=5'h1f;home_key_n<=1;scene_key_n<=3'h7;ready<=0;
  end else begin
   col_meta<=col_n;col_sync<=col_meta;
   if(count==SCAN_CYCLES-1)begin
    count<=0;row<=row+1'b1;
    case(row)
     0:scan_keys[3:0]<=~col_sync;
     1:scan_keys[7:4]<=~col_sync;
     2:scan_keys[11:8]<=~col_sync;
     3:begin
      ready<=1;
      // Reject other keys and possible ghost combinations. Rearm only after
      // a complete scan with ALL keys released, including unsupported keys.
      // Accept single supported keys only, including rejection of ghost paths.
      if(completed!=0 && completed!=16'h0002 && completed!=16'h0004 &&
         completed!=16'h0008 && completed!=16'h0010 && (!HOME_KEY || completed!=16'h0001) &&
         (!VIEW_KEYS || (completed!=16'h0200 && completed!=16'h0400 && completed!=16'h0800 &&
          completed!=16'h4000 && completed!=16'h0040))&&
         (!SCENE_KEYS || (completed!=16'h0020 && completed!=16'h0080 && completed!=16'h0100)))begin
       blocked<=1;key_n<=4'hf;view_key_n<=5'h1f;home_key_n<=1;scene_key_n<=3'h7;
      end
      else if(blocked)begin
       key_n<=4'hf;view_key_n<=5'h1f;home_key_n<=1;scene_key_n<=3'h7;
       if(completed==0)blocked<=0;
      end else begin
       key_n<=~completed[4:1];
       view_key_n<=VIEW_KEYS?~{completed[6],completed[14],completed[11],completed[10],completed[9]}:5'h1f;
       home_key_n<=HOME_KEY?~completed[0]:1'b1;
       scene_key_n<=SCENE_KEYS?~{completed[8],completed[7],completed[5]}:3'h7;
      end
     end
    endcase
   end else count<=count+1'b1;
  end
 end
endmodule
