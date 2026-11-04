"""Frozen T04 equivalence: every BPB fixed-byte value and valid NEC frame data."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,re,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
BEFORE=ROOT/'reports/o18_resource_20261021/before/worktree/rtl'

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tool-dir',type=Path,required=True)
 args=p.parse_args();logs=[];cases=[]
 names=['fat32_boot_parser','media_nec_receiver']
 files=[*[ROOT/'rtl'/(n+'.v') for n in names],*[BEFORE/(n+'.v') for n in names],HERE/'verify.py',
        ROOT/'tests/bpb_width/tb_bpb_width.sv',ROOT/'tests/infrared/verify.py',ROOT/'tests/infrared/tb_receiver.sv']
 hashes={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
 def run(top,files,tmp,params):
  image=tmp/(top+'.vvp')
  commands=[[args.tool_dir/'iverilog.exe','-g2012','-DCOMPARE_BASELINE','-s',top,
             *[f'-P{top}.{k}={v}' for k,v in params.items()],'-o',image,*files],
            [args.tool_dir/'vvp.exe',image]]
  for i,cmd in enumerate(commands):
   r=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=300)
   out=r.stdout+r.stderr;logs.append(out);print(out,end='',flush=True)
   assert not r.returncode and 'FATAL' not in out and (i==0 or re.search(r'\bPASS[: ]',out)),out
   if i==1 and top=='tb_ir_receiver':
    coverage=re.findall(r'EQUIV NEC .* comparisons=(\d+) valid_frames=(\d+)',out)
    assert len(coverage)==1 and all(int(v)>0 for v in coverage[0]),'NEC comparison coverage missing'
  cases.append({'top':top,'parameters':params,'passed':True})
 try:
  with tempfile.TemporaryDirectory(prefix='o18_equivalence_') as tmp:
   tmp=Path(tmp)
   source=(BEFORE/'fat32_boot_parser.v').read_text(encoding='utf-8-sig')
   reference=re.sub(r'\bfat32_boot_parser\b','fat32_boot_parser_baseline',source)
   reference=re.sub(r'\bfat32_bpb_math\b','fat32_bpb_math_baseline',reference)
   old=tmp/'bpb_reference.v';old.write_text(reference,encoding='utf-8')
   bench=(ROOT/'tests/bpb_width/tb_bpb_width.sv').read_text(encoding='utf-8-sig')
   bench=bench.replace('parameter integer TIMEOUT_CYCLES=800;','parameter integer TIMEOUT_CYCLES=800,SHARED=0;')
   bench=bench.replace('fat32_boot_parser #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) dut(.bpb_fields(),.bpb_result(129\'d0),.*);',
    'wire [255:0] fields;wire [128:0] result;\n fat32_bpb_math math(.clk(clk),.bpb_fields(fields),.bpb_result(result));\n fat32_boot_parser #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.SHARED_BPB(SHARED)) dut(.bpb_fields(fields),.bpb_result(result),.*);')
   assert 'wire [255:0] fields;' in bench
   marker='  // Wide arithmetic extremes:';assert bench.count(marker)==1
   extra='''  // Every value in every replaced fixed byte; independent oracle is unchanged.
  for(i=0;i<10;i=i+1)for(j=0;j<256;j=j+1)begin
   make_bpb(70000,8,2,2);
   case(i)0:n=11;1:n=12;2:n=17;3:n=18;4:n=19;5:n=20;6:n=22;7:n=23;8:n=42;9:n=43;endcase
   sector[n]=j;run_sector($sformatf("fixed byte=%0d value=%0d",n,j),i%2);
  end
'''
   bench=bench.replace(marker,extra+marker);b=tmp/'bpb_test.sv';b.write_text(bench,encoding='utf-8')
   for shared in [0,1]:
    for timeout in [800,2048]:run('tb_bpb_width',[ROOT/'rtl/fat32_boot_parser.v',old,b],tmp,{'TIMEOUT_CYCLES':timeout,'SHARED':shared})
   spec=importlib.util.spec_from_file_location('vectors',ROOT/'tests/infrared/verify.py')
   module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
   old=tmp/'nec_reference.v';old.write_text((BEFORE/'media_nec_receiver.v').read_text(encoding='utf-8-sig').replace('module media_nec_receiver','module media_nec_receiver_reference'),encoding='utf-8')
   source=(ROOT/'rtl/media_nec_receiver.v').read_text(encoding='utf-8-sig')
   extra='''
 wire old_tick,old_valid,old_repeat;wire [7:0] old_address,old_command;
 media_nec_receiver_reference #(.SAMPLE_CYCLES(SAMPLE_CYCLES)) reference(
  .clk(clk),.rst_n(rst_n),.enable(enable),.infrared_n(infrared_n),.sample_tick(old_tick),
  .frame_valid(old_valid),.frame_repeat(old_repeat),.frame_address(old_address),.frame_command(old_command));
 integer comparisons=0,valid_comparisons=0;
 always @(posedge clk)begin #2;if(rst_n)begin
  comparisons=comparisons+1;
  if({sample_tick,frame_valid,frame_repeat}!=={old_tick,old_valid,old_repeat})$fatal(1,"NEC pulse equivalence");
  if(frame_valid)begin valid_comparisons=valid_comparisons+1;
   if({frame_address,frame_command}!=={old_address,old_command})$fatal(1,"NEC valid-data equivalence");end
 end end
 final $display("EQUIV NEC valid data and all timing pulses comparisons=%0d valid_frames=%0d",comparisons,valid_comparisons);
'''
   dut=tmp/'nec_candidate.v';dut.write_text('`timescale 1ns/1ps\n'+source.replace('endmodule',extra+'endmodule'),encoding='utf-8')
   for sample in [1,7]:
    module.vectors(True).write(tmp/'stimulus.txt')
    run('tb_ir_receiver',[dut,old,ROOT/'tests/infrared/tb_receiver.sv'],tmp,{'SAMPLE':sample})
  assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in hashes.items())
  (HERE/'summary.json').write_text(json.dumps({'status':'passed','cases':cases,'inputs_sha256':hashes,
   'bpb_oracle':'204 public bits every clock; all 256 values of each of ten fixed bytes, shared and local arithmetic, two timeout profiles; existing arithmetic/transport/reset cases retained',
   'nec_oracle':'all sampling/valid/repeat pulses every clock, address/command only when valid; intermediate uncommitted shift data intentionally private'},indent=2)+'\n',encoding='utf-8')
 finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
