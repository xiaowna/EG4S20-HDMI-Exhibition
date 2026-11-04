"""文件扇区重试回归：使用当前板级 RTL，失败时返回非零退出码。"""
from pathlib import Path
import argparse
import subprocess

base = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--tool-dir', type=Path, required=True, help='iverilog 和 vvp 所在目录')
args = parser.parse_args()
tools = args.tool_dir.resolve()
work = Path(__file__).resolve().parent
logs = []

def run(command, cwd=work):
    result = subprocess.run([str(x) for x in command], cwd=cwd,
                            capture_output=True, text=True, timeout=120)
    output = result.stdout + result.stderr
    logs.append(output)
    print(output, end='', flush=True)
    if result.returncode or 'FATAL' in output:
        raise RuntimeError('回归测试失败')

try:
    for retries, modes in [(2, range(23)), (0, [0, 22]), (1, [22]), (8, [22])]:
        run([tools/'iverilog.exe', '-g2012', '-s', 'tb_file_retry',
             f'-Ptb_file_retry.RETRIES={retries}', '-o', work/'test.vvp',
             work/'tb_file_retry.sv', base/'rtl/fat32_file_reader.v'])
        for mode in modes:
            run([tools/'vvp.exe', work/'test.vvp', f'+MODE={mode}'])
    rtl = sorted(p for p in (base/'rtl').glob('*.v') if p.name != 'board_pll.v')
    tests = base/'tests'
    run([tools/'iverilog.exe', '-g2012', '-s', 'tb_pipeline', '-o', work/'pipeline.vvp',
         *rtl, tests/'clock_buffer_model.v', tests/'em638325_model.sv', tests/'tb_pipeline.sv'])
    for mode in range(8):
        run([tools/'vvp.exe', work/'pipeline.vvp', f'+MODE={mode}'], cwd=tests)
    print('全部 27 项文件读取测试和 8 项视频链路测试通过。')
finally:
    (base/'reports/file_retry_regression.txt').write_text(''.join(logs), encoding='utf-8')
