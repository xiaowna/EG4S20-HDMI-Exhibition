// EG4 9K block ROM. INIT holds 32 consecutive 256-bit blocks.
// SP8K reads two bits per address with no additional output register.
module anlogic_initialized_rom #(
 parameter [8191:0] DATA=0
)(input wire clk,input wire [11:0] address,output wire [1:0] pixel);
 wire [8:0] data;
 EG_PHY_BRAM #(
  .MODE("SP8K"),.DATA_WIDTH_A("2"),.DATA_WIDTH_B("2"),
  .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.RESETMODE("ASYNC"),
  .CEAMUX("1"),.CEBMUX("0"),.OCEAMUX("1"),.OCEBMUX("0"),
  .CSA0("1"),.CSA1("1"),.CSA2("1"),.CSB0("1"),.CSB1("1"),.CSB2("1"),
  .RSTAMUX("0"),.RSTBMUX("0"),.WEAMUX("0"),.WEBMUX("0"),
  .INIT_00(DATA[0+:256]), .INIT_01(DATA[256+:256]), .INIT_02(DATA[512+:256]), .INIT_03(DATA[768+:256]),
  .INIT_04(DATA[1024+:256]), .INIT_05(DATA[1280+:256]), .INIT_06(DATA[1536+:256]), .INIT_07(DATA[1792+:256]),
  .INIT_08(DATA[2048+:256]), .INIT_09(DATA[2304+:256]), .INIT_0A(DATA[2560+:256]), .INIT_0B(DATA[2816+:256]),
  .INIT_0C(DATA[3072+:256]), .INIT_0D(DATA[3328+:256]), .INIT_0E(DATA[3584+:256]), .INIT_0F(DATA[3840+:256]),
  .INIT_10(DATA[4096+:256]), .INIT_11(DATA[4352+:256]), .INIT_12(DATA[4608+:256]), .INIT_13(DATA[4864+:256]),
  .INIT_14(DATA[5120+:256]), .INIT_15(DATA[5376+:256]), .INIT_16(DATA[5632+:256]), .INIT_17(DATA[5888+:256]),
  .INIT_18(DATA[6144+:256]), .INIT_19(DATA[6400+:256]), .INIT_1A(DATA[6656+:256]), .INIT_1B(DATA[6912+:256]),
  .INIT_1C(DATA[7168+:256]), .INIT_1D(DATA[7424+:256]), .INIT_1E(DATA[7680+:256]), .INIT_1F(DATA[7936+:256])
 ) storage(
  .clka(clk),.addra({address,1'b1}),.dia(9'd0),.doa(data),
  .csa(3'b111),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.rsta(1'b0),
  .clkb(1'b0),.addrb(13'd0),.dib(9'd0),.dob(),
  .csb(3'b111),.ceb(1'b0),.oceb(1'b0),.web(1'b0),.rstb(1'b0));
 assign pixel=data[1:0];
endmodule

// In PDPW8K mode the ninth bit of each byte is in the separate parity INIT.
module anlogic_initialized_rom18 #(
 parameter WORDS=512,
 parameter WIDTH=16,
 parameter OFFSET=0,
 parameter [8191:0] DATA=0
)(input wire clk,input wire [8:0] address,output wire [17:0] word);
 function [9215:0] pack;
  input [8191:0] values;
  reg [31:0] source_word;
  reg [17:0] chunk;
  integer i;
  begin
   pack=0;
   for(i=0;i<WORDS;i=i+1)begin
    source_word=0;
    source_word[WIDTH-1:0]=values[i*WIDTH+:WIDTH];
    chunk=source_word>>OFFSET;
    pack[i*16+:16]={chunk[16:9],chunk[7:0]};
    pack[8192+i*2+:2]={chunk[17],chunk[8]};
   end
  end
 endfunction
 localparam [9215:0] INITIAL=pack(DATA);
 wire [12:0] physical_address={address,4'b1111};
 EG_PHY_BRAM #(
  .MODE("PDPW8K"),.DATA_WIDTH_A("18"),.DATA_WIDTH_B("18"),
  .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.RESETMODE("ASYNC"),
  .CEAMUX("0"),.CEBMUX("1"),.OCEAMUX("1"),.OCEBMUX("1"),
  .CSA0("1"),.CSA1("1"),.CSA2("1"),.CSB0("1"),.CSB1("1"),.CSB2("1"),
  .RSTAMUX("0"),.RSTBMUX("0"),.WEAMUX("1"),.WEBMUX("0"),
  .INITP_00(INITIAL[8192+:256]),.INITP_01(INITIAL[8448+:256]),
  .INITP_02(INITIAL[8704+:256]),.INITP_03(INITIAL[8960+:256]),
  .INIT_00(INITIAL[0+:256]), .INIT_01(INITIAL[256+:256]), .INIT_02(INITIAL[512+:256]), .INIT_03(INITIAL[768+:256]),
  .INIT_04(INITIAL[1024+:256]), .INIT_05(INITIAL[1280+:256]), .INIT_06(INITIAL[1536+:256]), .INIT_07(INITIAL[1792+:256]),
  .INIT_08(INITIAL[2048+:256]), .INIT_09(INITIAL[2304+:256]), .INIT_0A(INITIAL[2560+:256]), .INIT_0B(INITIAL[2816+:256]),
  .INIT_0C(INITIAL[3072+:256]), .INIT_0D(INITIAL[3328+:256]), .INIT_0E(INITIAL[3584+:256]), .INIT_0F(INITIAL[3840+:256]),
  .INIT_10(INITIAL[4096+:256]), .INIT_11(INITIAL[4352+:256]), .INIT_12(INITIAL[4608+:256]), .INIT_13(INITIAL[4864+:256]),
  .INIT_14(INITIAL[5120+:256]), .INIT_15(INITIAL[5376+:256]), .INIT_16(INITIAL[5632+:256]), .INIT_17(INITIAL[5888+:256]),
  .INIT_18(INITIAL[6144+:256]), .INIT_19(INITIAL[6400+:256]), .INIT_1A(INITIAL[6656+:256]), .INIT_1B(INITIAL[6912+:256]),
  .INIT_1C(INITIAL[7168+:256]), .INIT_1D(INITIAL[7424+:256]), .INIT_1E(INITIAL[7680+:256]), .INIT_1F(INITIAL[7936+:256])
 ) storage(
  .clka(clk),.addra(physical_address),.dia(9'd0),.doa(word[8:0]),
  .csa(3'b111),.cea(1'b0),.ocea(1'b1),.wea(1'b1),.rsta(1'b0),
  .clkb(clk),.addrb(physical_address),.dib(9'd0),.dob(word[17:9]),
  .csb(3'b111),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.rstb(1'b0));
endmodule
