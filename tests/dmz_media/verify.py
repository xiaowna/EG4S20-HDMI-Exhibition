"""Verify the original media top adapted to DMZ and the actual SPI/MISO boundary."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--tool-dir', type=Path, required=True)
tools = parser.parse_args().tool_dir.resolve()

with tempfile.TemporaryDirectory(prefix='dmz_media_') as temporary:
    for top, sources, marker in [
        ('tb_board_matrix_keys', ['board_matrix_keys.v'], 'PASS board_matrix_keys SCAN_CYCLES='),
        ('tb_hdmi_media_board_top', ['rtc_ds1302.v', 'rtc_set_control.v', 'hdmi_media_board_top.v', 'board_key.v', 'media_control_events.v', 'media_rotary_encoder.v', 'media_nec_receiver.v', 'media_infrared_control.v', 'media_mode_control.v', 'media_adjust_control.v', 'board_matrix_keys.v'], 'PASS KEY1234 board top COUNT='),
        ('tb_board_key_default', ['board_key.v'], 'PASS board_key default:'),
        ('tb_dmz_spi_miso', ['sd_spi_master.v'], 'PASS DMZ SPI MISO:'),
    ]:
        settings = ((32, 128) if top == 'tb_hdmi_media_board_top' else
                    (4, 17, 2500) if top == 'tb_board_matrix_keys' else (None,))
        for count in settings:
            parameter = 'SCAN_CYCLES' if top == 'tb_board_matrix_keys' else 'COUNT'
            image = Path(temporary) / (top + '.vvp')
            commands = [
                [tools / 'iverilog.exe', '-g2012', '-s', top,
                 *([f'-P{top}.{parameter}={count}'] if count is not None else []), '-o', image,
                 *[ROOT / 'rtl' / source for source in sources],
                 *([HERE / 'dmz_keyboard_model.sv'] if top in ('tb_hdmi_media_board_top', 'tb_board_matrix_keys') else []),
                 HERE / (top + '.sv')],
                [tools / 'vvp.exe', image],
            ]
            for index, command in enumerate(commands):
                result = subprocess.run(list(map(str, command)), capture_output=True,
                                        text=True, encoding='utf-8', errors='replace', timeout=120)
                output = result.stdout + result.stderr
                print(output, end='', flush=True)
                if result.returncode or 'FATAL' in output or (index == 1 and marker not in output):
                    raise SystemExit(1)
