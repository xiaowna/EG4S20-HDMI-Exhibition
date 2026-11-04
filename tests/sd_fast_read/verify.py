"""Measure real SPI sector latency and verify the delayed MISO/CRC contract."""
from pathlib import Path
import argparse, hashlib, json, re, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True)
    args = parser.parse_args()
    sources = [ROOT/'rtl'/n for n in ('sd_spi_master.v', 'sd_subsystem.v',
               'sd_init_controller.v', 'sd_command_engine.v', 'sd_data_block_reader.v')]
    sources += [HERE/'tb_fast_card.sv', Path(__file__).resolve()]
    hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    logs = []
    with tempfile.TemporaryDirectory(prefix='sd_fast_read_') as name:
        image = Path(name)/'test.vvp'
        for cmd in [[args.tool_dir/'iverilog.exe', '-g2012', '-s', 'tb_fast_card',
                     '-o', image, *sources[:-1]], [args.tool_dir/'vvp.exe', image]]:
            r = subprocess.run(list(map(str, cmd)), capture_output=True, text=True,
                               encoding='utf-8', errors='replace', timeout=120)
            logs.append(r.stdout+r.stderr)
            assert r.returncode == 0 and 'FATAL' not in logs[-1], logs[-1]
    output = ''.join(logs)
    assert 'PASS sector benchmark:' in output, output
    old, new = map(int, re.search(r'old6.25MHz=(\d+) new12.5MHz=(\d+)', output).groups())
    assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest() == v for n,v in hashes.items())
    result = dict(status='passed', old_sector_clocks=old, new_sector_clocks=new,
                  sector_time_reduction_percent=round(100*(1-new/old), 2),
                  card_return_delays_ns=[14,25,39], crc_corruption_rejected=True,
                  hardware_tested=False, input_sha256=hashes)
    (HERE/'summary.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    (HERE/'regression.log').write_text(output, encoding='utf-8')
    print(output, end='')


if __name__ == '__main__':
    main()
