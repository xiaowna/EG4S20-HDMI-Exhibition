// FFT snapshot memories use two native 32K blocks, preserving synchronous reads.
// RAM contents and output data are deliberately not reset; the core masks them
// with capture/state metadata and gates writes during reset.
module audio_fft_capture_ram #(
`ifdef FFT_NATIVE_RAM_TEST
 parameter USE_NATIVE=1
`elsif __ICARUS__
 parameter USE_NATIVE=0
`else
 parameter USE_NATIVE=1
`endif
)(input wire clk,input wire [8:0] write_address,input wire write_enable,
 input wire [15:0] write_data,input wire [8:0] read_address,output wire [15:0] read_data);
 generate if(USE_NATIVE)begin:native
  // Separate 16-bit ports keep capture writes independent of load reads.
  EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),
   .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL")) storage(
   .doa(),.dia(write_data),.addra({2'd0,write_address}),
   .bytea(1'b0),.bytewea(1'b0),.csa(1'b1),.wea(write_enable),.clka(clk),.rsta(1'b0),.ocea(1'b1),
   .dob(read_data),.dib(16'd0),.addrb({2'd0,read_address}),
   .byteb(1'b0),.byteweb(1'b0),.csb(1'b1),.web(1'b0),.clkb(clk),.rstb(1'b0),.oceb(1'b1));
 end else begin:behavioral
  reg [15:0] memory[0:511];reg [15:0] q;
  always @(posedge clk)begin
   q<=memory[read_address];
   if(write_enable)memory[write_address]<=write_data;
  end
  assign read_data=q;
 end endgenerate
endmodule

module audio_fft_work_ram #(
`ifdef FFT_NATIVE_RAM_TEST
 parameter USE_NATIVE=1
`elsif __ICARUS__
 parameter USE_NATIVE=0
`else
 parameter USE_NATIVE=1
`endif
)(input wire clk,input wire [8:0] address,input wire write_enable,
 input wire [31:0] write_data,output wire [31:0] read_data);
 generate if(USE_NATIVE)begin:native
  wire [15:0] low_word,high_word;
  // One complex word occupies adjacent 16-bit addresses. Both ports update
  // together, so a 32-bit word still takes exactly one read or write edge.
  EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),
   .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL")) storage(
   .doa(low_word),.dia(write_data[15:0]),.addra({1'b0,address,1'b0}),
   .bytea(1'b0),.bytewea(1'b0),.csa(1'b1),.wea(write_enable),.clka(clk),.rsta(1'b0),.ocea(1'b1),
   .dob(high_word),.dib(write_data[31:16]),.addrb({1'b0,address,1'b1}),
   .byteb(1'b0),.byteweb(1'b0),.csb(1'b1),.web(write_enable),.clkb(clk),.rstb(1'b0),.oceb(1'b1));
  assign read_data={high_word,low_word};
 end else begin:behavioral
  reg [31:0] memory[0:511];reg [31:0] q;
  always @(posedge clk)begin
   q<=memory[address];
   if(write_enable)memory[address]<=write_data;
  end
  assign read_data=q;
 end endgenerate
endmodule
