// Mode 0, MSB first. Select the half-period at the start of each byte.
// start is a one-cycle request accepted while !busy. done follows the last falling edge.
module sd_spi_master #(parameter integer CLK_DIV=64,READ_CLK_DIV=4,
 parameter CAPTURE_FALLING=0)(
 input wire clk,input wire rst_n,input wire start,fast_mode,input wire [7:0] tx_data,
 output reg [7:0] rx_data,output reg busy,output reg done,
 output reg sd_sck,output reg sd_mosi,input wire sd_miso);
 reg [7:0] tx,rx;
 reg [2:0] bit_index;
 localparam integer MAX_HALF_PERIOD=(CLK_DIV>READ_CLK_DIV)?CLK_DIV:READ_CLK_DIV;
 localparam integer DIVIDER_BITS=(MAX_HALF_PERIOD<2)?1:$clog2(MAX_HALF_PERIOD);
 // Store the terminal count so a power-of-two half-period also fits.
 reg [DIVIDER_BITS-1:0] divider,half_last;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   rx_data<=0; busy<=0; done<=0; sd_sck<=0; sd_mosi<=1;
   tx<=0; rx<=0; bit_index<=0; divider<=0;half_last<=CLK_DIV-1;
  end else begin
   done<=0;
   if(!busy) begin
    sd_sck<=0;
    if(start) begin
     busy<=1; tx<=tx_data; rx<=0; bit_index<=0; divider<=0; sd_mosi<=tx_data[7];
     half_last<=(fast_mode===1'b1)?READ_CLK_DIV-1:CLK_DIV-1;
    end
   end else if(divider==half_last) begin
    divider<=0;
    if(!sd_sck) begin
     sd_sck<=1;
     if(!CAPTURE_FALLING)rx<={rx[6:0],sd_miso};
    end
    else begin
     sd_sck<=0;
     // The board's two input FFs delay the Mode-0 rising-edge sample.
     // Consume that stable sample half a bit later, before the card changes
     // its next output. Keep the last bit in rx_data on this same edge.
     if(CAPTURE_FALLING)rx<={rx[6:0],sd_miso};
     if(bit_index==7) begin
      rx_data<=CAPTURE_FALLING?{rx[6:0],sd_miso}:rx;
      busy<=0; done<=1; sd_mosi<=1;
     end
     else begin bit_index<=bit_index+1'b1; tx<={tx[6:0],1'b1}; sd_mosi<=tx[6]; end
    end
   end else divider<=divider+1;
  end
 end
endmodule
