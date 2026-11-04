"""Generate embedded Q15 periodic Hann and 512-point FFT coefficients."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def q15(value):
    return max(-32768, min(32767, round(value * 32768)))


def main():
    window = [q15((1-math.cos(2*math.pi*n/512))/2) for n in range(512)]
    twiddle = [(q15(math.cos(2*math.pi*k/512)), q15(-math.sin(2*math.pi*k/512))) for k in range(256)]
    packed_window = ',\n'.join(f"  16'h{x & 65535:04x}" for x in reversed(window))
    packed_twiddle = ',\n'.join(f"  32'h{r & 65535:04x}{i & 65535:04x}" for r, i in reversed(twiddle))
    rtl = '''// Generated Q15 constants. No external file is needed at configuration time.
module audio_fft_coeff_rom(input wire clk,input wire [8:0] window_address,
 input wire [7:0] twiddle_address,output reg signed [15:0] window_value,
 output reg signed [15:0] twiddle_real,twiddle_imag);
 localparam [8191:0] WINDOW={
''' + packed_window + '''};
 localparam [8191:0] TWIDDLE={
''' + packed_twiddle + '''};
 reg [15:0] window_mem[0:511];
 reg [31:0] twiddle_mem[0:255];integer n;
 initial begin
  for(n=0;n<512;n=n+1)window_mem[n]=WINDOW[n*16+:16];
  for(n=0;n<256;n=n+1)twiddle_mem[n]=TWIDDLE[n*32+:32];
 end
 always @(posedge clk)begin
  window_value<=window_mem[window_address];
  {twiddle_real,twiddle_imag}<=twiddle_mem[twiddle_address];
 end
endmodule
'''
    (ROOT/'rtl/audio_fft_coeff_rom.v').write_text(rtl, encoding='utf-8')
    (ROOT/'assets/fft512_q15.json').write_text(json.dumps(
        {'points':512,'sample_rate':48000,'window':window,'twiddle':twiddle}, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
