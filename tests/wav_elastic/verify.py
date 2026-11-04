"""Independent directed acceptance of the one-byte WAV elastic boundary."""
from pathlib import Path
import argparse,hashlib,json,struct,subprocess,tempfile

ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent


def wav(bits,frames):
    data=b''.join(int(v&((1<<bits)-1)).to_bytes(bits//8,'little') for frame in frames for v in frame)
    fmt=struct.pack('<HHIIHH',1,2,48000,48000*2*bits//8,2*bits//8,bits)
    body=b'WAVEfmt '+struct.pack('<I',16)+fmt+b'data'+struct.pack('<I',len(data))+data
    return b'RIFF'+struct.pack('<I',len(body))+body


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--tool-dir',type=Path,required=True)
    args=parser.parse_args();logs=[];cases=[]
    sources=[ROOT/'rtl'/name for name in ['fat32_wav_player.v','fat32_file_reader.v','wav_pcm_decoder.v']]+[HERE/'tb_elastic.sv']
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    hashes={p.relative_to(ROOT).as_posix():sha(p) for p in sources}
    frames={16:[[(0x1234,-0x124),(1,-32768)],[(-0x3456,0x2345),(0x5678,-2)]],
            24:[[(0x332211,0x665544),(-8388608,-1)],[(-0x112233,0x224466),(0x123456,-0x654321)]]}
    labels=['EOF last byte held, then final sample stalled across valid loop',
            'same EOF/drain contract with a separate reset',
            'one-byte next file completed while old final sample held, error then clean replay',
            'zero-byte next file completed while old final sample held, error then clean replay',
            'truncated next RIFF rejected after old final sample, clean replay',
            'controlled stop inside sector, wait CRC boundary, replay different PCM',
            'controlled stop with prefetched R and pending old sample, discard and clean replay']
    with tempfile.TemporaryDirectory(prefix='wav_elastic_') as folder:
        tmp=Path(folder)
        for bits,banks in frames.items():
            expected=[]
            for name,pairs in zip('ab',banks):
                data=wav(bits,pairs);assert len(data)==44+bits//8*4
                (tmp/f'{name}{bits}.hex').write_text(''.join(f'{v:02x}\n' for v in data+bytes(512-len(data))),encoding='ascii')
                expected += [((left&((1<<bits)-1))<<(24-bits+24))|((right&((1<<bits)-1))<<(24-bits)) for left,right in pairs]
            (tmp/f'expected{bits}.hex').write_text(''.join(f'{v:012x}\n' for v in expected),encoding='ascii')
        for bits in [16,24]:
            for case in [0,2,3,4,5,6]:
                output=''
                for cmd in [[args.tool_dir/'iverilog.exe','-g2012','-s','tb_wav_elastic',
                             f'-Ptb_wav_elastic.CASE={case}',f'-Ptb_wav_elastic.WIDTH={bits}',
                             '-o',tmp/'check.vvp',*sources],[args.tool_dir/'vvp.exe',tmp/'check.vvp']]:
                    result=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,
                                          encoding='utf-8',errors='replace',timeout=60)
                    output+=result.stdout+result.stderr
                    if result.returncode or 'FATAL' in output:
                        (HERE/'regression.log').write_text(''.join(logs)+output,encoding='utf-8')
                        raise AssertionError(output)
                assert 'PASS WAV elastic' in output,output
                print(output,end='',flush=True);logs.append(output)
                cases.append(dict(bits=bits,case=case,description=labels[case],passed=True))
    assert all(sha(ROOT/n)==digest for n,digest in hashes.items()),'production changed during acceptance; rerun'
    (HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')
    result=dict(status='passed',cases=cases,source_sha256=hashes,real_file_reader=True,
                sector_crc_boundary=True,controlled_stop=True,hardware_tested=False)
    (HERE/'summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS independent WAV elastic boundary: 12 directed reader/decoder cases',flush=True)


if __name__=='__main__':main()
