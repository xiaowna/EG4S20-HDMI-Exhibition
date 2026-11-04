"""Black-box pixel FIFO regression, including capacity held outside its RAM."""
from pathlib import Path
import argparse
import hashlib
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True)
    parser.add_argument('--rtl', type=Path, help='Optional baseline RTL; defaults to this project')
    parser.add_argument('--log-name', default='regression.log')
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    rtl = (args.rtl or directory.parents[1] / 'rtl/pixel_async_fifo.v').resolve()
    tools = args.tool_dir.resolve()
    digest = hashlib.sha256(rtl.read_bytes()).hexdigest()
    logs = [f'RTL: {rtl}\nRTL SHA256: {digest}\n']
    print(logs[0], end='', flush=True)
    # Different widths, minimum depth, production depth, and both clock-rate orders.
    cases = [(1, 2, 3, 5, 1, 1), (13, 3, 7, 3, 1, 2),
             (57, 8, 5, 7, 1, 3), (57, 8, 7, 3, 1, 4),
             (57, 8, 3, 7, 1, 5), (72, 5, 5, 3, 1, 6),
             # Coincident rising edges: equal clocks and a 2:1 clock relation.
             (57, 8, 5, 5, 0, 7), (57, 8, 5, 10, 5, 8)]
    try:
        with tempfile.TemporaryDirectory(prefix='pixel_fifo_', dir=directory) as temporary:
            output_path = Path(temporary) / 'check.vvp'
            for width, bits, write_half, read_half, read_phase, seed in cases:
                compile_command = [tools / 'iverilog.exe', '-g2012', '-s', 'tb_pixel_fifo',
                                   f'-Ptb_pixel_fifo.WIDTH={width}', f'-Ptb_pixel_fifo.ADDR_BITS={bits}',
                                   f'-Ptb_pixel_fifo.W_HALF={write_half}', f'-Ptb_pixel_fifo.R_HALF={read_half}',
                                   f'-Ptb_pixel_fifo.R_PHASE={read_phase}',
                                   f'-Ptb_pixel_fifo.RANDOM_SEED={seed}', '-o', output_path,
                                   rtl, directory / 'tb_pixel_fifo.sv']
                for command in (compile_command, [tools / 'vvp.exe', output_path]):
                    result = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=90)
                    output = result.stdout + result.stderr
                    logs.append(output)
                    print(output, end='', flush=True)
                    if result.returncode or 'FATAL' in output:
                        raise RuntimeError('Pixel FIFO regression failed')
        if hashlib.sha256(rtl.read_bytes()).hexdigest() != digest:
            raise RuntimeError('RTL changed during the test; result rejected')
        logs.append(f'PASS: {len(cases)} pixel FIFO configurations\n')
        print(logs[-1], end='')
    finally:
        (directory / args.log_name).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
