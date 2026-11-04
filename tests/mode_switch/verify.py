"""SW7 modes, graceful WAV stop and packet-boundary audio FIFO acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True)
    parser.add_argument('--only', help='Run one named testbench during development')
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[1]
    cases = [
        ('tb_mode_control', ['media_mode_control.v'], {'COUNT': count})
        for count in [1, 2, 7, 32, 1000000]
    ] + [
        ('tb_audio_flush', ['audio_source_flush.v', 'audio_async_fifo.v'], {}),
        ('tb_mode_menu', ['media_adjust_control.v'], {}),
    ]
    extra = [
        ('tb_wav_stop', ['fat32_wav_player.v', 'fat32_file_reader.v', 'wav_pcm_decoder.v'], {}),
        ('tb_mode_av', ['media_mode_control.v', 'audio_source_flush.v', 'hdmi_av_output.v',
         'audio_tone_bank.v', 'audio_async_fifo.v', 'video_scroll_osd.v', 'video_brightness_lut.v',
         'video_audio_waveform.v', 'hdmi_audio_packets.v', 'hdmi_data_island_encoder.v',
         'hdmi_bch8.v', 'hdmi_terc4.v', 'tmds_channels.v', 'tmds_encoder.v'], {}),
        ('tb_mode_osd', ['video_scroll_osd.v'], {}),
        ('tb_mode_prefetch', ['media_prefetch_control.v', 'frame_buffer_manager.v'], {}),
        ('tb_mode_player_fence', ['sd_media_player.v', 'sd_sector_arbiter.v', 'fat32_wav_player.v',
         'fat32_file_reader.v', 'wav_pcm_decoder.v', 'media_prefetch_control.v'], {}),
    ]
    cases += extra
    if args.only:
        cases = [case for case in cases if case[0] == args.only]
        if not cases:
            parser.error('Unknown testbench')
    sources = {path: hashlib.sha256(path.read_bytes()).hexdigest()
               for path in list((root / 'rtl').glob('*.v')) + list(here.glob('*.sv'))}
    logs = [json.dumps({str(p): value for p, value in sources.items()}, indent=2) + '\n']
    runs = []
    try:
        with tempfile.TemporaryDirectory(prefix='hdmi_mode_') as temporary:
            for top, names, parameters in cases:
                simulation = Path(temporary) / (top + '.vvp')
                command = [args.tool_dir / 'iverilog.exe', '-g2012', '-s', top,
                           *[f'-P{top}.{name}={value}' for name, value in parameters.items()],
                           '-o', simulation, *[root / 'rtl' / name for name in names],
                           here / 'wav_sector_model.sv', here / (top + '.sv')]
                for index, cmd in enumerate([command, [args.tool_dir / 'vvp.exe', simulation]]):
                    result = subprocess.run(list(map(str, cmd)), cwd=root, capture_output=True,
                        text=True, encoding='utf-8', errors='replace', timeout=240)
                    output = result.stdout + result.stderr
                    logs.append(output)
                    print(output, end='', flush=True)
                    if result.returncode or 'FATAL' in output or (index == 1 and 'PASS ' not in output):
                        raise RuntimeError(f'Mode acceptance failed: {top} {parameters}')
                runs.append({'top': top, 'parameters': parameters, 'passed': True})
        assert all(hashlib.sha256(path.read_bytes()).hexdigest() == value for path, value in sources.items())
        payload = {'passed': True, 'runs': runs, 'source_sha256': {str(p): value for p, value in sources.items()},
                   'hardware_tested': False}
        (here / 'summary.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
        logs.append(f'PASS mode-switch acceptance: {len(runs)} simulations; source hashes unchanged\n')
        print(logs[-1], end='', flush=True)
    finally:
        (here / 'regression.log').write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
