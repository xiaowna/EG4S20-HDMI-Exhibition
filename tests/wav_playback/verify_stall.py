"""Run the long-pause SD CMD17 regression separately from routine tests.

Examples:
  python verify_stall.py --tool-dir C:/path/to/iverilog/bin
  python verify_stall.py --tool-dir C:/path/to/iverilog/bin \
      --fifo-samples 256 --prebuffer 128 --urgent 192 \
      --stall-ms 3 --expect-underflow

An UNDERFLOW result is reported explicitly. Use --expect-underflow when
characterizing an intentionally excessive pause; it never masks HDL FATALs.
"""
from argparse import ArgumentParser
from pathlib import Path
import re
import subprocess
import sys


def main() -> int:
    parser = ArgumentParser()
    parser.add_argument("--tool-dir", type=Path, required=True)
    parser.add_argument("--fifo-samples", type=int, default=2048)
    parser.add_argument("--prebuffer", type=int, default=1024)
    parser.add_argument("--urgent", type=int, default=1536)
    parser.add_argument("--stall-ms", type=float, default=20.0)
    parser.add_argument("--expect-underflow", action="store_true")
    args = parser.parse_args()
    if args.fifo_samples < 4 or args.fifo_samples & (args.fifo_samples - 1):
        parser.error("--fifo-samples must be a power of two >= 4")
    if not 0 < args.prebuffer <= args.fifo_samples:
        parser.error("--prebuffer must be within the FIFO")
    if not 0 < args.urgent <= args.fifo_samples:
        parser.error("--urgent must be within the FIFO")
    if args.stall_ms < 0:
        parser.error("--stall-ms must be nonnegative")
    stall_cycles = round(args.stall_ms * 50_000)
    here = Path(__file__).resolve().parent
    root = here.parents[1]
    tool_dir = args.tool_dir.resolve()
    vvp_path = here / "tb_sd_audio_stall_probe.vvp"
    rtl = ["sd_sector_arbiter.v", "fat32_wav_player.v", "wav_pcm_decoder.v",
           "fat32_file_reader.v", "audio_async_fifo.v"]
    compile_cmd = [
        tool_dir / "iverilog.exe", "-g2012", "-s", "tb_sd_audio_stall",
        f"-DTEST_FIFO_ADDR_BITS={args.fifo_samples.bit_length() - 1}",
        f"-DTEST_PREBUF={args.prebuffer}",
        f"-DTEST_URGENT_THRESHOLD={args.urgent}",
        "-o", vvp_path,
        *(root / "rtl" / name for name in rtl),
        here / "tb_sd_audio_stall.sv",
    ]
    try:
        subprocess.run([str(x) for x in compile_cmd], cwd=here, check=True,
                       timeout=30)
        result = subprocess.run(
            [str(tool_dir / "vvp.exe"), str(vvp_path),
             f"+STALL_CYCLES={stall_cycles}"],
            cwd=here, text=True, capture_output=True, timeout=180,
        )
    finally:
        vvp_path.unlink(missing_ok=True)
    output = result.stdout + result.stderr
    print(output, end="")
    (root / "reports" / "sd_audio_stall_regression.txt").write_text(
        f"FIFO={args.fifo_samples}, prebuffer={args.prebuffer}, "
        f"urgent={args.urgent}, stall={args.stall_ms} ms\n" + output,
        encoding="utf-8",
    )
    if result.returncode or "FATAL" in output or "STALL begin" not in output:
        return 1
    underflow = "UNDERFLOW cycles=" in output
    if underflow == args.expect_underflow:
        if underflow:
            return 0
        match = re.search(
            r"PASS stall .*image sectors=(\d+) .*loops=(\d+) consumed=(\d+)",
            output,
        )
        if match and int(match.group(1)) >= 8 and int(match.group(2)) >= 2 \
                and int(match.group(3)) >= 1500:
            return 0
    print("unexpected " + ("underflow" if underflow else "continuous playback"),
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
