"""Real SDRAM/VGA intro integration plus fast production phase-control FSM."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True)
    parser.add_argument('--smoke', action='store_true')
    args = parser.parse_args()
    oracle_path = ROOT/'tests/intro_animation/verify_producer.py'
    spec = importlib.util.spec_from_file_location('intro_pixel_oracle', oracle_path)
    oracle = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(oracle)
    metadata = json.loads((ROOT/'assets/intro_assets.json').read_text(encoding='utf-8'))
    names = ['frame_stream_display.v', 'frame_burst_prefetch.v', 'frame_intro_prefetch.v',
             'intro_line_store.v', 'intro_text_layer.v', 'intro_assets_rom.v',
             'pixel_async_fifo.v', 'video_pixel_sink.v', 'video_raster_timing.v',
             'eg4s20_stream_memory.v', 'em638325_stream_controller.v']
    sources = [ROOT/'rtl'/name for name in names]
    sources += [ROOT/'tests/clock_buffer_model.v', ROOT/'tests/em638325_model.sv']
    inputs = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in sources+[HERE/'tb_raster.sv', HERE/'tb_control.sv',
                                   oracle_path, ROOT/'assets/intro_assets.json', Path(__file__)]}
    logs = []
    def run(command, cwd):
        result = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=1800)
        output = result.stdout+result.stderr
        logs.append(output)
        print(output, end='', flush=True)
        if result.returncode or 'FATAL' in output:
            raise RuntimeError('intro raster regression failed')
    try:
        with tempfile.TemporaryDirectory(prefix='intro_raster_') as temporary:
            temporary = Path(temporary)
            phases = [0] if args.smoke else [0, 49, 63]
            for topic in range(1 if args.smoke else 4):
                for phase in phases:
                    for bank in range(2):
                        pixels = oracle.expected_frame(metadata, topic, phase, bank, captions=True)
                        (temporary/f'golden_{topic}_{phase}_{bank}.hex').write_text(
                            ''.join(f'{int(pixel):06x}\n' for pixel in pixels), encoding='ascii')
            for phase in [0,9,18]:
                for bank in range(2):
                    pixels=oracle.expected_frame(metadata,0,phase,bank,captions=True,intro=False)
                    (temporary/f'normal_{phase}_{bank}.hex').write_text(''.join(f'{int(x):06x}\n' for x in pixels),encoding='ascii')
            run([args.tool_dir/'iverilog.exe', '-g2012', '-s', 'tb_intro_phase_control',
                 '-o', temporary/'control.vvp', *sources, HERE/'tb_control.sv'], temporary)
            run([args.tool_dir/'vvp.exe', temporary/'control.vvp'], temporary)
            run([args.tool_dir/'iverilog.exe', '-g2012', '-s', 'tb_intro_raster',
                 f'-Ptb_intro_raster.SMOKE={int(args.smoke)}', '-o', temporary/'raster.vvp',
                 *sources, HERE/'tb_raster.sv'], temporary)
            run([args.tool_dir/'vvp.exe', temporary/'raster.vvp'], temporary)
            for filename, original in inputs.items():
                assert hashlib.sha256((ROOT/filename).read_bytes()).hexdigest() == original, filename+' changed during test'
        summary = {'status': 'passed', 'smoke_only': args.smoke,
                   'actual_vga_640x480_sys50MHz_pix25MHz': True,
                   'actual_sdram_controller_model_refresh_and_competing_back_writes': True,
                   'selected_raster_phases_forced_in_test_only': phases,
                   'phase_fsm_all64_control_only': True,
                   'control_test_mocking': ['mailbox request', 'prefetch readiness/completion', 'prefetch start held disabled'],
                   'hardware_tested': False, 'input_sha256': inputs}
        (HERE/('smoke_summary.json' if args.smoke else 'summary.json')).write_text(
            json.dumps(summary, indent=2)+'\n', encoding='utf-8')
    finally:
        (HERE/('smoke.log' if args.smoke else 'regression.log')).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
