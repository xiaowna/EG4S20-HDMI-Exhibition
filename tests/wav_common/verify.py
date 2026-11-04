"""WAV common-field compression: O18 cycle equivalence and independent samples."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tool-dir',type=Path,required=True)
 args=p.parse_args();logs=[];cases=[]
 source=ROOT/'rtl/wav_pcm_decoder.v';frozen=ROOT/'reports/o19_wav_common_20261021/before/worktree/rtl/wav_pcm_decoder.v'
 files=[source,frozen,HERE/'verify.py',HERE/'wrapper.sv',HERE/'tb_wav_fields.sv',
        ROOT/'tests/wav_playback/tb_wav_pcm_decoder.sv',ROOT/'tests/wav_playback/tb_wav_bounds.sv']
 hashes={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
 try:
  with tempfile.TemporaryDirectory(prefix='wav_common_') as directory:
   tmp=Path(directory);new=tmp/'candidate.v';old=tmp/'reference.v'
   new.write_text(re.sub(r'\bwav_pcm_decoder\b','wav_pcm_decoder_candidate',source.read_text(encoding='utf-8-sig')),encoding='utf-8')
   old.write_text(re.sub(r'\bwav_pcm_decoder\b','wav_pcm_decoder_o18',frozen.read_text(encoding='utf-8-sig')),encoding='utf-8')
   for top,bench,modes in [('tb_wav_fields',HERE/'tb_wav_fields.sv',[None]),
      ('tb_wav_pcm_decoder',ROOT/'tests/wav_playback/tb_wav_pcm_decoder.sv',[None]),
      ('tb_wav_bounds',ROOT/'tests/wav_playback/tb_wav_bounds.sv',range(11))]:
    image=tmp/'check.vvp';cmd=[args.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',image,new,old,HERE/'wrapper.sv',bench]
    r=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
    out=r.stdout+r.stderr;logs.append(out);print(out,end='',flush=True);assert not r.returncode and 'FATAL' not in out,out
    for mode in modes:
     cmd=[args.tool_dir/'vvp.exe',image,*([] if mode is None else [f'+MODE={mode}'])]
     r=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
     out=r.stdout+r.stderr;logs.append(out);print(out,end='',flush=True)
     coverage=re.findall(r'PASS WAV public-port equivalence: (\d+) cycles, 53 bits',out)
     assert not r.returncode and 'FATAL' not in out and len(coverage)==1 and int(coverage[0])>0,out
     assert re.search(r'PASS.*(?:WAV|RIFF)',out),out
     cases.append({'top':top,'mode':mode,'compared_cycles':int(coverage[0]),'passed':True})
  assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in hashes.items())
  (HERE/'summary.json').write_text(json.dumps({'status':'passed','cases':cases,'inputs_sha256':hashes,
     'oracle':'Every public bit including invalid sample_data compared every clock; independent common-field rejection, valid PCM samples and eleven RIFF bounds scenarios retained'},indent=2)+'\n',encoding='utf-8')
 finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
