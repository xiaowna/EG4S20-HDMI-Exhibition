"""User-run exhaustive font comparison against a frozen RTL and bitmap oracle."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bitmap(manifest):
    bits = []
    for glyph in manifest['glyphs']:
        assert len(glyph['rows']) == 16
        for row in glyph['rows']:
            assert len(row) == 16 and set(row) <= {'0', '1'}
            bits.extend(row)
    assert len(bits) <= 32768
    return bits + ['0']*(32768-len(bits))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True)
    args = parser.parse_args()
    files = [ROOT/'rtl/settings_font_rom.v', ROOT/'assets/settings_v04.json',
             HERE/'reference_settings_font_rom.v', HERE/'tb_settings_font_banks.sv',
             Path(__file__), HERE/'reference_settings_v04.json']
    inputs = {p.relative_to(ROOT).as_posix(): sha(p) for p in files}
    summary = {'status': 'running', 'inputs_sha256': inputs,
               'hardware_tested': False}
    summary_path = HERE/'summary.json'
    summary_path.write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
    output = ''
    try:
        manifest = json.loads(files[1].read_text(encoding='utf-8'))
        historical = json.loads(files[5].read_text(encoding='utf-8'))
        # O20 predates M02's rotating music note. Keep that frozen RTL and its
        # independent bitmap unchanged; only the eight newly allocated slots
        # may differ from the historical design.
        assert sha(files[2]) == '8d6417b26175b55dddd0842004687f27400534d5371fcbdb99134eb325939c05'
        assert sha(files[5]) == 'dbeeda4b1e22585afbed4a847d15a0f5038c1e147ba347f9ea1e0c556b465e1b'
        assert len(historical['glyphs']) == 74
        assert manifest['glyphs'][:74] == historical['glyphs']
        assert manifest['music_note_first'] == 74 and manifest['music_note_frames'] == 8
        assert len(manifest['glyphs']) == 82
        assert [g['character'] for g in manifest['glyphs'][74:82]] == [chr(0xe100+i) for i in range(8)]
        bits, old_bits = bitmap(manifest), bitmap(historical)
        changed = [i for i,(a,b) in enumerate(zip(bits,old_bits)) if a != b]
        assert changed and all(74*256 <= i < 82*256 for i in changed)
        assert all(value == '0' for value in old_bits[74*256:])
        # Also prove the copied historical bitmap belongs to the frozen ROM.
        value = 0
        words = re.findall(r"256'h([0-9a-fA-F]+)", files[2].read_text(encoding='utf-8'))
        assert len(words) == 128
        for word in words:
            value = (value << 256) | int(word,16)
        assert all(str((value >> i) & 1) == bit for i,bit in enumerate(old_bits))
        with tempfile.TemporaryDirectory(prefix='font_banks_') as folder:
            tmp = Path(folder)
            (tmp/'font_bits.hex').write_text('\n'.join(bits)+'\n', encoding='ascii')
            (tmp/'reference_font_bits.hex').write_text('\n'.join(old_bits)+'\n', encoding='ascii')
            commands = [
                [args.tool_dir/'iverilog.exe', '-g2012', '-s', 'tb_settings_font_banks',
                 '-o', tmp/'test.vvp', files[0], files[2], files[3]],
                [args.tool_dir/'vvp.exe', tmp/'test.vvp'],
            ]
            for command in commands:
                result = subprocess.run(list(map(str, command)), cwd=tmp,
                                        capture_output=True, text=True,
                                        encoding='utf-8', errors='replace', timeout=180)
                output += result.stdout+result.stderr
                assert result.returncode == 0 and 'FATAL' not in output, output
        assert 'PASS banked settings font:' in output, output
        assert all(sha(ROOT/n) == value for n, value in inputs.items())
        summary.update(status='passed', public_addresses_per_mode=32768,
                       modes=[0, 1], golden_bits=len(bits),
                       frozen_reference_and_independent_bitmap=True,
                       historical_glyphs_preserved=74, added_music_note_slots=[74,81],
                       changed_bits_confined_to_added_slots=len(changed),
                       both_historical_and_current_exhaustive_bitmaps=True)
        print(output, end='', flush=True)
    except Exception as exc:
        summary.update(status='failed', error=str(exc))
        raise
    finally:
        (HERE/'regression.log').write_text(output, encoding='utf-8')
        summary_path.write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
