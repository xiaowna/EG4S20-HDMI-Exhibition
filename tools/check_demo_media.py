"""检查准备复制到 TF 卡根目录的 BMP/WAV 演示素材。只使用 Python 标准库。"""

import argparse
import re
import struct
from pathlib import Path


WIDTH, HEIGHT = 640, 480
SHORT_NAME = re.compile(r"[A-Z0-9_]{1,8}\.(?:BMP|WAV)")
PCM_SUBFORMAT = bytes.fromhex("0100000000001000800000aa00389b71")


def check_bmp(path: Path) -> str:
    size = path.stat().st_size
    with path.open("rb") as file:
        header = file.read(54)
    if len(header) < 54 or header[:2] != b"BM":
        raise ValueError("不是完整的 BMP 文件头")
    bmp_size = struct.unpack_from("<I", header, 2)[0]
    pixel_offset = struct.unpack_from("<I", header, 10)[0]
    dib_size = struct.unpack_from("<I", header, 14)[0]
    width, height = struct.unpack_from("<ii", header, 18)
    planes, bits = struct.unpack_from("<HH", header, 26)
    compression = struct.unpack_from("<I", header, 30)[0]
    stride = (WIDTH * 3 + 3) & ~3
    pixel_end = pixel_offset + stride * HEIGHT
    if (dib_size != 40 or width != WIDTH or abs(height) != HEIGHT
            or planes != 1 or bits != 24 or compression != 0):
        raise ValueError("需要 640×480、24 位、未压缩、40 字节 BITMAPINFOHEADER")
    if pixel_offset < 54 or bmp_size > size or pixel_end > min(size, bmp_size):
        raise ValueError("像素偏移、BMP 声明长度或实际文件长度不匹配")
    return f"{WIDTH}×{HEIGHT}，24 位，{'自上而下' if height < 0 else '自下而上'}"


def check_wav(path: Path) -> str:
    size = path.stat().st_size
    with path.open("rb") as file:
        header = file.read(12)
        if len(header) != 12 or header[:4] != b"RIFF" or header[8:] != b"WAVE":
            raise ValueError("不是 RIFF/WAVE 文件")
        riff_end = struct.unpack_from("<I", header, 4)[0] + 8
        if riff_end > size or riff_end < 12:
            raise ValueError("RIFF 声明长度超过实际文件长度")
        fmt = None
        while file.tell() + 8 <= riff_end:
            chunk_header = file.read(8)
            chunk_id, chunk_size = struct.unpack("<4sI", chunk_header)
            chunk_end = file.tell() + chunk_size
            if chunk_end > riff_end or chunk_end > size:
                raise ValueError("WAV 数据块超出 RIFF 或实际文件长度")
            if chunk_id == b"fmt " and fmt is None:
                if chunk_size < 16:
                    raise ValueError("fmt 数据块不足 16 字节")
                fmt_data = file.read(min(chunk_size, 40))
                fmt = struct.unpack_from("<HHIIHH", fmt_data)
                encoding, channels, rate, byte_rate, align, bits = fmt
                if encoding == 0xFFFE:
                    if (len(fmt_data) < 40
                            or struct.unpack_from("<H", fmt_data, 16)[0] < 22
                            or struct.unpack_from("<H", fmt_data, 18)[0] != bits
                            or struct.unpack_from("<I", fmt_data, 20)[0] not in (0, 3)
                            or fmt_data[24:40] != PCM_SUBFORMAT):
                        raise ValueError("仅支持有效位宽等于容器位宽的双声道 PCM extensible")
            elif chunk_id == b"data":
                if fmt is None:
                    raise ValueError("data 数据块出现在 fmt 之前")
                encoding, channels, rate, byte_rate, align, bits = fmt
                if (encoding not in (1, 0xFFFE) or channels != 2 or rate != 48000
                        or bits not in (16, 24) or align != channels * bits // 8
                        or byte_rate != rate * align):
                    raise ValueError("需要 48 kHz、双声道、16/24 位整数 PCM")
                if chunk_size == 0 or chunk_size % align:
                    raise ValueError("data 长度必须是正数且为双声道采样帧的整数倍")
                return f"48 kHz，双声道，{bits} 位 PCM，{chunk_size / byte_rate:.1f} 秒"
            file.seek(chunk_end + (chunk_size & 1))
        raise ValueError("未找到可播放的 data 数据块")


def check_directory(folder: Path, max_images: int = 24, max_wavs: int = 4) -> int:
    if not folder.is_dir():
        print(f"错误：目录不存在：{folder}")
        return 1
    media = sorted((p for p in folder.iterdir()
                    if p.is_file() and p.suffix.upper() in (".BMP", ".WAV")),
                   key=lambda p: p.name.upper())
    bmps = [p for p in media if p.suffix.upper() == ".BMP"]
    wavs = [p for p in media if p.suffix.upper() == ".WAV"]
    errors = []
    if not 1 <= len(bmps) <= max_images:
        errors.append(f"需要 1～{max_images} 张 BMP，当前有 {len(bmps)} 张")
    if not 1 <= len(wavs) <= max_wavs:
        errors.append(f"需要 1～{max_wavs} 个 WAV，当前有 {len(wavs)} 个；歌曲编号按 FAT 目录扫描顺序分配")
    for path in media:
        if not SHORT_NAME.fullmatch(path.name.upper()):
            errors.append(f"{path.name}：文件名请使用最多 8 个英文字母/数字/下划线加 .BMP 或 .WAV")
            continue
        try:
            detail = check_bmp(path) if path.suffix.upper() == ".BMP" else check_wav(path)
            print(f"通过：{path.name} — {detail}")
        except (OSError, ValueError, struct.error) as exc:
            errors.append(f"{path.name}：{exc}")
    for error in errors:
        print(f"错误：{error}")
    if errors:
        return 1
    print("素材检查通过。复制到 FAT32 TF 卡根目录后，还需在开发板上验证。")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path, help="包含 BMP 和 WAV 文件的目录或 TF 卡根目录")
    parser.add_argument("--max-images", type=int, choices=range(1, 33), default=24,
                        help="位流支持的图片数上限；太阳系特展为24，旧C01请指定32")
    parser.add_argument("--max-wavs", type=int, choices=range(1, 5), default=4,
                        help="位流支持的音乐数上限；当前支持4，旧单曲版请指定1")
    args = parser.parse_args()
    raise SystemExit(check_directory(args.folder, args.max_images, args.max_wavs))
