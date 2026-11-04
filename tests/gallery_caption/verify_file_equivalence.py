"""Cycle-by-cycle I/O equivalence of the shortened FAT address path."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
def main():
 p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
 original=HERE/'fat32_file_reader_reference.v';source=ROOT/'rtl/fat32_file_reader.v'
 before=original.read_text(encoding='utf-8');after=source.read_text(encoding='utf-8')
 hs={x.relative_to(ROOT).as_posix():hashlib.sha256(x.read_bytes()).hexdigest() for x in [source,original,Path(__file__)]};logs=[];cases=[]
 header=after[:after.index(' localparam IDLE=')].replace('output reg','output wire')
 outputs={'rd_start':'','rd_lba':'[31:0]','out_valid':'','out_data':'[7:0]','out_offset':'[31:0]','busy':'','done':'','error':'','error_code':'[3:0]'}
 params='#(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.MAX_FILE_CLUSTERS(MAX_FILE_CLUSTERS),.MAX_SECTOR_RETRIES(MAX_SECTOR_RETRIES))'
 wrapper=header+'\n'+''.join(f' wire {width} reference_{name};\n' for name,width in outputs.items())
 wrapper+=' fat32_file_reader_optimized '+params+' optimized(.*);\n'
 wrapper+=' fat32_file_reader_reference '+params+' reference('+','.join('.'+name+'(reference_'+name+')' for name in outputs)+',.*);\n'
 wrapper+=' wire [3:0] state=optimized.state;wire validating=optimized.validating;wire [23:0] cluster_limit=optimized.cluster_limit;\n'
 wrapper+=' integer equivalent_cycles=0;always @(negedge clk)if(rst_n)begin\n'
 wrapper+=' if({'+','.join(outputs)+'}!=={'+','.join('reference_'+name for name in outputs)+'})$fatal(1,"FAT address optimization changed external cycle behavior");\n equivalent_cycles=equivalent_cycles+1;end\n'
 wrapper+=' final $display("PASS FAT cycle equivalence: %0d clocks",equivalent_cycles);\nendmodule\n'
 try:
  with tempfile.TemporaryDirectory(prefix='fat_equivalence_') as t:
   t=Path(t);impl=t/'comparison.sv'
   impl.write_text(wrapper+after.replace('module fat32_file_reader #','module fat32_file_reader_optimized #',1)+before,encoding='utf-8')
   for top,modes in [('tb_file',range(18)),('tb_chain_cycles',range(19)),('tb_cluster_limit',range(3))]:
    bench=ROOT/'tests/file_read_verify'/(top+'.sv')
    hs[bench.relative_to(ROOT).as_posix()]=hashlib.sha256(bench.read_bytes()).hexdigest()
    commands=[[a.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',t/'check.vvp',impl,bench]]
    commands += [[a.tool_dir/'vvp.exe',t/'check.vvp',f'+MODE={mode}'] for mode in modes]
    for cmd in commands:
     r=subprocess.run(list(map(str,cmd)),cwd=bench.parent,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
     logs.append(r.stdout+r.stderr);print(logs[-1],end='',flush=True)
     assert r.returncode==0 and 'FATAL' not in logs[-1],logs[-1]
    cases.append(dict(top=top,modes=len(modes)))
  assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==d for n,d in hs.items())
  (HERE/'file_equivalence_summary.json').write_text(json.dumps(dict(status='passed',cases=cases,compares_every_output_every_cycle=True,no_added_cycles=True,input_sha256=hs),indent=2),encoding='utf-8')
 finally:(HERE/'file_equivalence.log').write_text(''.join(logs),encoding='utf-8')
if __name__=='__main__':main()
