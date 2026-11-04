// Four-phase level handshake. Stop FIFO reads immediately on the synchronized
// request, but leave packet builders/encoders running. Clear pointers only
// after the caller proves every old audio packet has finished transmission.
module audio_source_flush(
 input wire sys_clk,pix_clk,rst_n,request,safe_to_flush,
 output wire flush_done,fifo_rst_n,block_reads,
 output wire flush_hold_pix);
 (* async_reg="true" *) reg [1:0] request_pix,ack_sys;
 reg ack_pix,hold_request;
 reg hold_negedge;
 reg [1:0] state,release_count;
 localparam IDLE=0,ASSERT=1,WAIT_RELEASE=2,RELEASE=3;
 assign flush_done=ack_sys[1];
 assign block_reads=request_pix[1]||hold_negedge||ack_pix;
 assign flush_hold_pix=hold_negedge;
 assign fifo_rst_n=rst_n&&!hold_negedge;
 always @(posedge sys_clk or negedge rst_n)
  if(!rst_n)ack_sys<=0;else ack_sys<={ack_sys[0],ack_pix};
 always @(negedge pix_clk or negedge rst_n)
  if(!rst_n)hold_negedge<=1;else hold_negedge<=hold_request;
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin request_pix<=0;ack_pix<=0;hold_request<=0;state<=IDLE;release_count<=0;end
  else begin
   request_pix<={request_pix[0],request};
   case(state)
    IDLE:if(request_pix[1]&&safe_to_flush)begin hold_request<=1;state<=ASSERT;end
    ASSERT:begin ack_pix<=1;state<=WAIT_RELEASE;end
    WAIT_RELEASE:if(!request_pix[1])begin hold_request<=0;release_count<=0;state<=RELEASE;end
    // Four pixel edges cover falling-edge reset release and FIFO synchronizers.
    RELEASE:if(release_count==3)begin ack_pix<=0;state<=IDLE;end
            else release_count<=release_count+1'b1;
    default:begin state<=IDLE;ack_pix<=0;hold_request<=0;end
   endcase
  end
 end
endmodule
