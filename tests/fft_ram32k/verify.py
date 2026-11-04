"""Native FFT RAM wiring, fixed-point bins, reset retention, and baseline timing."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path,
                        default=ROOT/'reports/intro_animation_20261024/fft_ram_migration')
    parser.add_argument('--vendor-macro', type=Path,
                        default=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/arch/eagle_macro.v'))
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    sources = [ROOT/'rtl'/name for name in ('audio_fft_coeff_rom.v', 'audio_fft_memory.v', 'audio_fft512.v')]
    fixtures = [HERE/name for name in ('bram32k_contract.sv', 'tb_memory.sv', 'tb_core.sv', 'reference_audio_fft512.v')]
    inputs = sources+fixtures+[Path(__file__), ROOT/'tests/audio_spectrum/verify.py', ROOT/'assets/fft512_q15.json']
    hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    spec = importlib.util.spec_from_file_location('fft_oracle', ROOT/'tests/audio_spectrum/verify.py')
    oracle = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(oracle)
    asset = json.loads((ROOT/'assets/fft512_q15.json').read_text(encoding='utf-8'))
    assert asset['window'] == oracle.WINDOW and asset['twiddle'] == list(map(list, oracle.TWIDDLE))
    # Restrict the core change to the declarations and memory binding only.
    reference = (HERE/'reference_audio_fft512.v').read_text(encoding='utf-8').replace('module audio_fft512_reference(', 'module audio_fft512(')
    original = ROOT/'reports/intro_animation_20261024/before/rtl/audio_fft512.v'
    if original.is_file():
        assert original.read_text(encoding='utf-8').rstrip() == reference.rstrip(), 'reference differs from frozen original'
    expected = reference.replace(
        ' reg [15:0] capture_mem[0:511];reg signed [15:0] capture_read;\n reg [31:0] fft_mem[0:511],fft_read;',
        ' wire signed [15:0] capture_read;\n wire [31:0] fft_read;')
    before = ''' always @(posedge clk)begin
  capture_read<=capture_mem[load_index];
  if(rst_n&&state==CAPTURE&&capture_enable&&sample_valid)
   capture_mem[capture_index]<=sample_left[23:8];
  fft_read<=fft_mem[ram_address];
  if(rst_n&&ram_write)fft_mem[ram_address]<=ram_data;
 end'''
    after = ''' audio_fft_capture_ram capture_storage(.clk(clk),.write_address(capture_index),
  .write_enable(rst_n&&state==CAPTURE&&capture_enable&&sample_valid),
  .write_data(sample_left[23:8]),.read_address(load_index),.read_data(capture_read));
 audio_fft_work_ram fft_storage(.clk(clk),.address(ram_address),
  .write_enable(rst_n&&ram_write),.write_data(ram_data),.read_data(fft_read));'''
    assert before in expected
    expected = expected.replace(before, after)
    assert (ROOT/'rtl/audio_fft512.v').read_text(encoding='utf-8').rstrip() == expected.rstrip(), 'FFT logic changed outside RAM substitution'
    structural = 'PASS structural freeze: FFT math, states, coefficients, normalization, and control logic unchanged\n'
    print(structural, end='')
    cases = oracle.vectors()
    oracle.numerical_checks(cases)
    logs = [structural]
    vendor_api = None

    def run(command, cwd):
        result = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True, text=True,
                                encoding='utf-8', errors='replace', timeout=600)
        output = result.stdout+result.stderr
        logs.append(output)
        print(output, end='', flush=True)
        if result.returncode or 'FATAL' in output:
            raise RuntimeError('FFT RAM migration regression failed')

    try:
        with tempfile.TemporaryDirectory(prefix='fft_ram32k_') as directory:
            directory = Path(directory)
            if args.vendor_macro.is_file():
                # Other macros contain names reserved by SystemVerilog. Compile
                # the exact official BRAM32K declaration without those modules.
                macro_bytes = args.vendor_macro.read_bytes()
                declaration = re.search(r'module\s+EG_PHY_BRAM32K\b.*?endmodule', macro_bytes.decode('utf-8'), re.S)
                assert declaration, 'official BRAM32K declaration missing'
                api_file = directory/'vendor_bram32k.v'
                api_file.write_text(declaration[0]+'\n', encoding='utf-8')
                run([args.tool_dir/'iverilog.exe', '-g2012', '-DFFT_NATIVE_RAM_TEST', '-s', 'audio_fft512',
                     '-tnull', *sources, api_file], directory)
                vendor_api = {'path': str(args.vendor_macro), 'sha256': hashlib.sha256(macro_bytes).hexdigest()}
                logs.append('PASS exact official EG_PHY_BRAM32K API elaboration\n')
                print(logs[-1], end='')
            (directory/'samples.hex').write_text(''.join(f'{s & 65535:04x}\n' for case in cases for s in case), encoding='ascii')
            (directory/'bins.hex').write_text(''.join(f'{r & 65535:04x}{i & 65535:04x}\n' for case in cases for r, i in oracle.transform(case)), encoding='ascii')
            executable = directory/'memory.vvp'
            run([args.tool_dir/'iverilog.exe', '-g2012', '-s', 'tb_fft_memory', '-o', executable,
                 sources[1], HERE/'bram32k_contract.sv', HERE/'tb_memory.sv'], directory)
            run([args.tool_dir/'vvp.exe', executable], directory)
            for native in (False, True):
                executable = directory/f'core_{int(native)}.vvp'
                command = [args.tool_dir/'iverilog.exe', '-g2012', '-s', 'tb_fft_ram_core', '-o', executable]
                if native:
                    command += ['-DFFT_NATIVE_RAM_TEST', HERE/'bram32k_contract.sv']
                run(command+sources+[HERE/'reference_audio_fft512.v', HERE/'tb_core.sv'], directory)
                run([args.tool_dir/'vvp.exe', executable], directory)
        for filename, expected_hash in hashes.items():
            assert hashlib.sha256((ROOT/filename).read_bytes()).hexdigest() == expected_hash, filename+' changed during regression'
        summary = {
            'status': 'passed',
            'rtl_native_32k_instances': 2,
            'behavioral_and_native_complex_bins_each': 2048,
            'cycle_equivalence_reference': 'tests/fft_ram32k/reference_audio_fft512.v',
            'reference_origin': 'reports/intro_animation_20261024/before/rtl/audio_fft512.v',
            'reference_origin_sha256': hashlib.sha256(original.read_bytes()).hexdigest() if original.is_file() else None,
            'official_primitive_api_elaboration': vendor_api,
            'all_capture_and_complex_addresses': 512,
            'randomized_simultaneous_memory_operations': 4096,
            'reset_cases_each_branch': ['partial_capture', 'processing', 'valid_output'],
            'reset_retained_words_each_case': 1024,
            'primitive_model_scope': 'Public true-dual-port synchronous RAM contract; encrypted vendor timing and physical resource mapping require TD build.',
            'input_sha256': hashes,
        }
        (args.output_dir/'summary.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
        (HERE/'summary.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
    finally:
        (args.output_dir/'regression.log').write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
