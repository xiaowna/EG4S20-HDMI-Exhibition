// Raw timing. Frame arm pulse is one clock BEFORE active pixel (0,0).
module video_raster_timing #(
 parameter H_ACTIVE=640,H_FP=16,H_SYNC=96,H_BP=48,
 parameter V_ACTIVE=480,V_FP=10,V_SYNC=2,V_BP=33)(
 input wire clk,rst_n,output wire de,hsync,vsync,blank_start,raster_start);
 localparam HT=H_ACTIVE+H_FP+H_SYNC+H_BP,VT=V_ACTIVE+V_FP+V_SYNC+V_BP;
 localparam integer X_BITS=(HT>1)?$clog2(HT):1;
 localparam integer Y_BITS=(VT>1)?$clog2(VT):1;
 reg [X_BITS-1:0] x;
 reg [Y_BITS-1:0] y;
 assign de=x<H_ACTIVE && y<V_ACTIVE;
 assign hsync=!(x>=H_ACTIVE+H_FP && x<H_ACTIVE+H_FP+H_SYNC);
 assign vsync=!(y>=V_ACTIVE+V_FP && y<V_ACTIVE+V_FP+V_SYNC);
 assign blank_start=x==0 && y==V_ACTIVE;
 assign raster_start=x==HT-1 && y==VT-1;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin x<=0;y<=V_ACTIVE;end
  else if(x==HT-1)begin x<=0;if(y==VT-1)y<=0;else y<=y+1'b1;end
  else x<=x+1'b1;
 end
endmodule
