"""唯一总回归入口：全部子测试使用本工程 RTL，失败返回非零。"""
import argparse
import hashlib
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.check_project import check_logic_project, check_project
from verify import find_tool

STORAGE = [
    'tests/verify_storage_bounds.py',
    'tests/mbr_stream/verify.py',
    'tests/bpb_width/verify.py',
    'tests/bpb_share/verify.py',
    'tests/reader_width/verify.py',
    'tests/dir_bram/verify.py',
    'tests/file_read_verify/run_tests.py',
    'tests/file_read_verify/verify_cluster_limit.py',
    'tests/gallery_caption/verify_file_equivalence.py',
    'tests/file_retry/verify.py',
    'tests/wav_playback/verify.py',
    'tests/wav_playback/verify_stall.py',
]
OTHER = [
    'verify.py',
    'tests/bmp_header/verify.py',
    'tests/bmp_counters/verify.py',
    'tests/image_scale/verify.py',
    'tests/intro_text/verify.py',
    'tests/intro_animation/verify_producer.py',
    'tests/gallery_caption/verify.py',
    'tests/gallery_caption/verify_slide_raster.py',
    'tests/intro_raster/verify.py',
    'tests/fft_ram32k/verify.py',
    'tests/gallery32/verify.py',
    'tests/gallery24/verify.py',
    'tests/topic_folders/verify.py',
    'tests/slide/verify.py',
    'tests/music_select/verify.py',
    'tests/infrared/verify.py',
    'tests/resource_o18/verify.py',
    'tests/wav_common/verify.py',
    'tests/rtc/verify.py',
    'tests/rtc_ds1302/verify.py',
    'tests/rtc_setting/verify.py',
    'tests/home/verify.py',
    'tests/solar_scene/verify.py',
    'tests/earth_moon/verify.py',
    'tests/solar_integration/verify.py',
    'tests/fine_adjust/verify.py',
    'tests/fine_adjust/verify_pixel_path.py',
    'tests/font_banks/verify.py',
    'tests/prepare_bar/verify.py',
    'tests/spi_divider/verify.py',
    'tests/sd_fast_read/verify.py',
    'tests/safety_counters/verify.py',
    'tests/dmz_media/verify.py',
    'tests/control_events/verify.py',
    'tests/mode_switch/verify.py',
    'tests/four_key/verify.py',
    'tests/next_prefetch/verify.py',
    'tests/pixel_fifo/verify.py',
    'tests/audio_fifo/verify.py',
    'tests/audio_source/verify.py',
    'tests/audio_source/verify_tone_bank.py',
    'tests/data_island/verify.py',
    'tests/island_storage/verify.py',
    'tests/tmds_ddr/verify.py',
    'tests/hdmi_audio/verify.py',
    'tests/audio_slots/verify.py',
    'tests/osd/verify.py',
    'tests/osd_lookup/verify.py',
    'tests/chinese_subtitle/verify.py',
    'tests/chinese_settings/verify.py',
    'tests/video_adjust/verify.py',
    'tests/video_adjust/verify_control.py',
    'tests/video_adjust/verify_av.py',
    'tests/audio_waveform/verify.py',
    'tests/audio_spectrum/verify.py',
    'tests/verify_frame_address.py',
    'tests/verify_sdram_refresh.py',
    'tests/verify_review_fixes.py',
]
TOOL_TESTS = ['tests/test_project_tools.py', 'tests/test_td_gui_profile.py',
              'tests/test_td_project_prepare.py', 'tests/test_td_multiseed_paths.py', 'tests/test_ir_fixed_config.py']


def source_digest():
    digest = hashlib.sha256()
    for path in sorted((ROOT / 'rtl').glob('*.v')):
        digest.update(path.name.encode('utf-8'))
        digest.update(path.read_bytes())
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True, help='Icarus Verilog bin 目录')
    parser.add_argument('--suite', choices=['all', 'storage'], default='all')
    parser.add_argument('--full', action='store_true', help='额外验证三个完整显示帧')
    parser.add_argument('--logic-only', action='store_true', help='逻辑回归预检只允许 TF 四线映射待确认')
    args = parser.parse_args()
    logs = []
    try:
        checker = check_logic_project if args.logic_only else check_project
        project_check = checker(ROOT)
        logs.append(f'工程检查：{project_check}\n')
        tools = args.tool_dir.resolve()
        find_tool('iverilog', tools)
        find_tool('vvp', tools)
        initial_digest = source_digest()
        header = f'ROOT: {ROOT}\nRTL: {ROOT / "rtl"}\nRTL SHA256: {initial_digest}\n'
        print(header, end='', flush=True)
        logs.append(header)
        scripts = STORAGE + (OTHER if args.suite == 'all' else [])
        for script in scripts + (TOOL_TESTS if args.suite == 'all' else []):
            print(f'RUN: {script}', flush=True)
            command = [sys.executable, str(ROOT / script)]
            if script not in TOOL_TESTS:
                command.extend(['--tool-dir', str(tools)])
            if args.full and script == 'verify.py':
                command.append('--full')
            if args.logic_only and script == 'verify.py':
                command.append('--logic-only')
            result = subprocess.run(command, cwd=ROOT, capture_output=True,
                                    text=True, encoding='utf-8', errors='replace', timeout=1800)
            output = result.stdout + result.stderr
            print(output, end='', flush=True)
            logs.append(f'RUN: {script}\n{output}')
            if result.returncode or 'FATAL' in output or source_digest() != initial_digest:
                raise RuntimeError(f'{script} 失败或测试期间 RTL 被修改；不接受本轮结果')
        logs.append(f'PASS: 总回归通过，{len(scripts)} 个 RTL 回归入口\n')
        print(logs[-1], end='')
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        logs.append(f'FAIL: {exc}\n')
        print(logs[-1], file=sys.stderr, end='')
        return 1
    finally:
        (ROOT / 'reports').mkdir(exist_ok=True)
        (ROOT / 'reports/regression_latest.log').write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    raise SystemExit(main())
