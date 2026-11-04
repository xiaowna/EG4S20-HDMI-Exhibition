"""当前 RTL 的 WAV 长度与 FAT 有限簇前缀回归。"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True)
    tools = parser.parse_args().tool_dir.resolve()
    logs = [f'RTL: {ROOT / "rtl"}\n']
    try:
        with tempfile.TemporaryDirectory(prefix='hdmi_storage_bounds_') as temporary:
            for top, source, bench, modes in [
                ('tb_wav_bounds', 'wav_pcm_decoder.v', 'wav_playback/tb_wav_bounds.sv', range(11)),
                ('tb_chain_cycles', 'fat32_file_reader.v', 'file_read_verify/tb_chain_cycles.sv', range(20)),
            ]:
                image = Path(temporary) / (top + '.vvp')
                commands = [[tools / 'iverilog.exe', '-g2012', '-s', top, '-o', image,
                             ROOT / 'rtl' / source, ROOT / 'tests' / bench]]
                commands.extend([tools / 'vvp.exe', image, f'+MODE={mode}'] for mode in modes)
                for command in commands:
                    result = subprocess.run(list(map(str, command)), capture_output=True,
                                            text=True, errors='replace', timeout=30)
                    output = result.stdout + result.stderr
                    logs.append(output)
                    print(output, end='', flush=True)
                    if result.returncode or 'FATAL' in output:
                        raise RuntimeError(f'{top} 失败')
        return 0
    finally:
        (ROOT / 'reports').mkdir(exist_ok=True)
        (ROOT / 'reports/storage_bounds_regression.txt').write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    raise SystemExit(main())
