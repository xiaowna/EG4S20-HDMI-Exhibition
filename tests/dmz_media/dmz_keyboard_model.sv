// Passive switch network, including ghost paths; no FPGA-internal signals used.
module dmz_keyboard_model(input wire [15:0] pressed,
 inout wire [3:0] row_n,col_n);
 genvar r,c;
 generate
  for(c=0;c<4;c=c+1)begin: columns
   pullup(col_n[c]);
  end
  for(r=0;r<4;r=r+1)begin: rows
   for(c=0;c<4;c=c+1)begin: keys
    tranif1 contact(row_n[r],col_n[c],pressed[r*4+c]);
   end
  end
 endgenerate
endmodule
