"""F4/F3 AV oracle with frozen staging inputs and streamed real-raster progress."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
from threading import Thread
import tempfile


SUCCESS = 'PASS: isolated F4 HDMI waveform integration'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--lut', type=Path)
    parser.add_argument('--reference-lut', type=Path)
    parser.add_argument('--wave', type=Path)
    parser.add_argument('--osd', type=Path)
    parser.add_argument('--log-name', default='av_regression.log')
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = next(p for p in here.parents if (p / 'rtl/audio_async_fifo.v').is_file())
    isolated = (here.parent / 'hdmi_av_output_candidate.v').is_file()
    candidate = (args.candidate or (here.parent / 'hdmi_av_output_candidate.v'
                 if isolated else root / 'rtl/hdmi_av_output.v')).resolve()
    default_baseline = root / 'reports/waveform_20261018/before/worktree/rtl/hdmi_av_output.v'
    if args.baseline is None and not default_baseline.is_file():
        parser.error('Provide --baseline pointing to the preserved F3 AV source')
    baseline = (args.baseline or default_baseline).resolve()
    lut = (args.lut or (here.parent / 'video_brightness_lut.v' if isolated
                       else root / 'rtl/video_brightness_lut.v')).resolve()
    reference_lut = (args.reference_lut or baseline.parent / 'video_brightness_lut.v').resolve()
    wave = (args.wave or (here.parent.parent / 'audio_waveform/video_audio_waveform.v'
                         if isolated else root / 'rtl/video_audio_waveform.v')).resolve()
    osd = (args.osd or (here.parent / 'video_scroll_osd_candidate.v' if isolated
                       else root / 'rtl/video_scroll_osd.v')).resolve()
    bench = here / 'tb_video_adjust_av.sv'
    shared = ['audio_tone_bank.v', 'audio_async_fifo.v', 'hdmi_audio_packets.v',
              'hdmi_bch8.v', 'hdmi_terc4.v', 'hdmi_data_island_encoder.v',
              'tmds_encoder.v', 'tmds_channels.v']
    common = [root / 'rtl' / name for name in shared]
    sources = [candidate, baseline, lut, reference_lut, wave, osd, bench, *common]
    hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    iverilog = args.tool_dir / 'iverilog.exe' if args.tool_dir else shutil.which('iverilog')
    vvp = args.tool_dir / 'vvp.exe' if args.tool_dir else shutil.which('vvp')
    if not iverilog or not vvp:
        parser.error('Icarus not found; provide --tool-dir')
    summary = {'sources': hashes, 'pass': False}
    with (here / args.log_name).open('w', encoding='utf-8') as log:
        def emit(value):
            print(value, end='', flush=True)
            log.write(value)
            log.flush()

        for path, value in hashes.items():
            emit(f'Source: {path}\nSHA256: {value}\n')
        try:
            old, count = re.subn(r'\bmodule\s+hdmi_av_output\s*\(',
                                 'module hdmi_av_output_reference(',
                                 baseline.read_text(encoding='utf-8-sig'), count=1)
            if count != 1:
                raise RuntimeError('F3 reference AV module not found')
            old = re.sub(r'\bvideo_brightness_lut\b', 'video_brightness_lut_reference', old)
            old_lut, count = re.subn(r'\bmodule\s+video_brightness_lut\s*\(',
                                     'module video_brightness_lut_reference(',
                                     reference_lut.read_text(encoding='utf-8-sig'), count=1)
            if count != 1:
                raise RuntimeError('F3 reference LUT module not found')
            with tempfile.TemporaryDirectory(prefix='wave_av_') as temporary:
                directory = Path(temporary)
                reference = directory / 'reference.v'
                reference.write_text(old, encoding='utf-8')
                old_table = directory / 'reference_lut.v'
                old_table.write_text(old_lut, encoding='utf-8')
                simulation = directory / 'wave_av.vvp'
                result = subprocess.run(list(map(str, [
                    iverilog, '-g2012', '-s', 'tb_video_wave_av', '-o', simulation,
                    candidate, reference, lut, old_table, wave, osd, bench, *common,
                ])), capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
                emit(result.stdout + result.stderr)
                if result.returncode:
                    raise RuntimeError('F4 AV compilation failed')
                emit('PROGRESS: compiled F4/F3 frozen AV; starting real 800x525 raster\n')
                with subprocess.Popen([str(vvp), '-i', str(simulation)], stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT, text=True, encoding='utf-8',
                                      errors='replace', bufsize=1) as process:
                    output = []
                    def read_output():
                        for line in process.stdout:
                            output.append(line)
                            emit(line)
                    reader = Thread(target=read_output)
                    reader.start()
                    try:
                        code = process.wait(timeout=1800)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                        reader.join()
                        raise RuntimeError('F4 AV simulation exceeded 1800 seconds')
                    reader.join()
                    if code or any('FATAL' in line for line in output):
                        raise RuntimeError('F4 AV simulation failed')
                    success_line = next((line for line in output if SUCCESS in line), '')
                    if not success_line:
                        raise RuntimeError('F4 AV success marker missing')
                    summary['coverage'] = {key: int(value) for key, value in
                                           re.findall(r'(\w+)=(\d+)', success_line)}
            for path, value in hashes.items():
                if hashlib.sha256(Path(path).read_bytes()).hexdigest() != value:
                    raise RuntimeError(f'Source changed during F4 AV test: {path}')
            summary['pass'] = True
            emit('PASS: all frozen F4/F3 source hashes unchanged\n')
        finally:
            (here / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2),
                                             encoding='utf-8')


if __name__ == '__main__':
    main()
