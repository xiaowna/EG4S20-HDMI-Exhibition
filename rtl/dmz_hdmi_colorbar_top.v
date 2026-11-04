// DMZ-EG4S20 HDMI expansion: video-only bring-up, no TF/SDRAM/audio.
// SW0: low resets, high runs. LEDs are active high on the DMZ core board.
// The ADC differential standard allocates the physical negative pads.
module dmz_hdmi_colorbar_top(
 input wire clk50,rst_n,
 output wire hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p,
 output wire [1:0] led);
 wire sys_clk,pix_clk,ser_clk,locked;
 board_pll u_pll(.refclk(clk50),.reset(!rst_n),.extlock(locked),
  .clk0_out(pix_clk),.clk1_out(ser_clk),.clk2_out(sys_clk));
 wire reset_ok=rst_n&&locked;
 // Same release phase as the existing board top; assertion is asynchronous.
 reg [3:0] release_pipe;
 always @(negedge pix_clk or negedge reset_ok)
  if(!reset_ok)release_pipe<=0;else release_pipe<={release_pipe[2:0],1'b1};
 wire core_rst_n=release_pipe[3];
 reg [24:0] heartbeat_count;
 reg heartbeat_led;
 always @(posedge sys_clk or negedge core_rst_n)begin
  if(!core_rst_n)begin heartbeat_count<=0;heartbeat_led<=0;end
  else if(heartbeat_count==25'd24999999)begin
   heartbeat_count<=0;heartbeat_led<=!heartbeat_led;
  end else heartbeat_count<=heartbeat_count+1'b1;
 end
 assign led={locked,heartbeat_led};
 wire de,hs,vs;
 wire [23:0] rgb;
 wire [9:0] tr,tg,tb;
 dmz_colorbar_video video(.pix_clk(pix_clk),.rst_n(core_rst_n),
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb));
 tmds_channels enc(.pix_clk(pix_clk),.rst_n(core_rst_n),
  .de(de),.hsync(hs),.vsync(vs),
  .red(rgb[23:16]),.green(rgb[15:8]),.blue(rgb[7:0]),
  .tmds_red(tr),.tmds_green(tg),.tmds_blue(tb));
 tmds_ddr_tx tx(.pix_clk(pix_clk),.ser_clk(ser_clk),.rst_n(core_rst_n),
  .red(tr),.green(tg),.blue(tb),.clk_p(hdmi_clk_p),
  .d0_p(hdmi_d0_p),.d1_p(hdmi_d1_p),.d2_p(hdmi_d2_p));
endmodule
