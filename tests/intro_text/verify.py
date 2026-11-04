"""Independent PIL pixel oracle, ROM initialization contract and staged-media QA."""
from __future__ import annotations

import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import zipfile

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
H = ROOT / "reports/gallery_caption_20261024"
WEIGHTS = (0, 11, 21, 32)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def round_fraction(value):
    return (value.numerator * 2 + value.denominator) // (2 * value.denominator)


def check_geometry(manifest):
    checks = 0
    for page in manifest["pages"]:
        source, final = page["source_photo_xywh"], page["final_photo_xywh"]
        for phase, descriptor in enumerate(page["phases"]):
            t = Fraction(max(0, min(37, phase-23)), 37)
            ease = 10*t**3 - 15*t**4 + 6*t**5
            dest = [round_fraction(a+(b-a)*ease) for a, b in zip(source, final)]
            tt = Fraction(max(0, min(19, phase-44)), 19)
            text_ease = 1-(1-tt)**3
            alpha, offset = round_fraction(32*text_ease), round_fraction(64*(1-text_ease))
            assert dest == descriptor["destination_xywh"]
            qx, rx = divmod(source[2], dest[2]);qy, ry = divmod(source[3], dest[3])
            words = [*dest, qx*1024+rx, qy*512+ry, alpha*128+offset, 0]
            assert words == descriptor["words"]
            address = page["topic"]*512+phase*8
            assert manifest["geometry_words"][address:address+8] == words
            # Check each DDA source coordinate against division, including last pixels.
            for dimension, quotient, remainder in [(0, qx, rx), (1, qy, ry)]:
                accumulator = coordinate = 0
                for pixel in range(dest[2+dimension]):
                    assert coordinate == pixel*source[2+dimension]//dest[2+dimension]
                    coordinate += quotient;accumulator += remainder
                    if accumulator >= dest[2+dimension]:
                        accumulator -= dest[2+dimension];coordinate += 1
                    checks += 1
    return checks


def font_oracle(manifest):
    text = manifest["text"]
    paths = manifest["input_sha256"]
    regular = next(path for path in paths if path.lower().endswith("/msyh.ttc") or path.lower().endswith("\\msyh.ttc"))
    bold = next(path for path in paths if path.lower().endswith("/msyhbd.ttc") or path.lower().endswith("\\msyhbd.ttc"))
    body_font, heading_font = ImageFont.truetype(regular, 16), ImageFont.truetype(bold, 20)
    expected_font_pixels = []
    for item in text["glyphs"]:
        char = item["character"]
        roomy = Image.new("L", (48, 48));d = ImageDraw.Draw(roomy)
        d.text((16, 12), char, font=body_font, fill=255)
        allowed = roomy.crop((16, 12, 32, 32))
        outside = roomy.copy();ImageDraw.Draw(outside).rectangle((16, 12, 31, 31), fill=0)
        assert outside.getbbox() is None, f"clipped glyph {char}"
        expected_font_pixels.extend((value*3+127)//255 for value in allowed.get_flattened_data())
    heading = Image.new("L", (128, 24))
    ImageDraw.Draw(heading).text((0, -1), "回望这一程", font=heading_font, fill=255)
    expected_font_pixels.extend((value*3+127)//255 for value in heading.get_flattened_data())
    expected_font_pixels += [0] * (8192*8-len(expected_font_pixels))
    expected_words = [sum(expected_font_pixels[start+k] << (k*2) for k in range(8))
                      for start in range(0, 8192*8, 8)]
    assert manifest["glyph_words"] == expected_words
    assert text["heading"]["word_base"] == 7680
    character_words = []
    dictionary = {item["character"]: item["index"] for item in text["glyphs"]}
    masks = []
    for topic in text["topics"]:
        summary = topic["text"]
        lines = [summary[start:start+15] for start in range(0, len(summary), 15)]
        cells = [dictionary.get(ch, 0) for line in lines+([""]*(6-len(lines))) for ch in line.ljust(15)]
        assert topic["characters"] == cells
        character_words.extend(cells+[0]*38)
        mask = Image.new("L", (240, 174));draw = ImageDraw.Draw(mask)
        draw.text((0, -1), "回望这一程", font=heading_font, fill=255)
        draw.rectangle((0, 26, 99, 27), fill=255)
        for line, value in enumerate(lines):
            draw.text((0, 36+line*23), value, font=body_font, fill=255)
        masks.append(mask.point(lambda value: (value*3+127)//255))
    assert character_words == manifest["character_words"]
    return masks


def check_media(manifest):
    assert len(list((H / "media").glob("*.BMP"))) == 24
    bg = tuple(manifest["clear_rgb"])
    for record, page in zip(manifest["media"], manifest["gallery"]):
        path = H / "media" / record["file"]
        data = path.read_bytes()
        assert data[:2] == b"BM" and len(data) == 921654
        assert struct.unpack_from("<IiiHHI", data, 14) == (40, 640, 480, 1, 24, 0)
        assert struct.unpack_from("<I", data, 10)[0] == 54
        assert digest(path) == record["sha256"]
        originals = [Image.open(x["path"]).convert("RGB") for x in page["original_files"]]
        if len(originals) == 1:
            photo = originals[0]
        else:
            photo = Image.new("RGB", (1100,550), "black")
            for i, original in enumerate(originals):
                tile=ImageOps.contain(original,(490,490),Image.Resampling.LANCZOS)
                photo.paste(tile,(30+i*550+(490-tile.width)//2,30+(490-tile.height)//2))
        scaled=ImageOps.contain(photo,(604,308),Image.Resampling.LANCZOS)
        expected=Image.new("RGB",(640,480),bg)
        x=18+(604-scaled.width)//2;y=36+(308-scaled.height)//2
        expected.paste(scaled,(x,y))
        assert page["source_photo_xywh"]==[x,y,scaled.width,scaled.height]
        actual=Image.open(path).convert("RGB")
        assert ImageChops.difference(actual.crop((0,0,640,384)),expected.crop((0,0,640,384))).getbbox() is None
        assert ImageChops.difference(actual.crop((0,448,640,480)),expected.crop((0,448,640,480))).getbbox() is None
        assert actual.crop((18,384,622,448)).getbbox() is not None
    for path, expected in manifest["input_sha256"].items():
        if digest(path) == expected:
            continue
        # Publishing replaces these specifically authorized media files.
        # Keep checking their old bytes in the verified rollback archive,
        # and require the live replacement to match the new atlas manifest.
        source=Path(path)
        replacement=next((x for x in manifest['media'] if x['file']==source.name),None)
        assert source.parent.name=='TF卡内容' and replacement and digest(path)==replacement['sha256'],f"read-only input changed: {path}"
        backup=source.parent.parent/'回退_线框版全部24图_动效图册前_20261024.zip'
        with zipfile.ZipFile(backup) as archive:
            assert hashlib.sha256(archive.read('TF卡内容/'+source.name)).hexdigest()==expected
    return {"bmp_headers":24,"pure_photo_regions":24,"separate_caption_strips":24,
            "read_only_inputs":len(manifest["input_sha256"])}


def write_vectors(path, manifest, masks):
    count = 0
    def emit(stream, topic, x, y, alpha, offset, valid=1):
        nonlocal count
        if not (0 <= x < 640 and 0 <= y < 480):
            return
        bg = (count*0x9e3779+0x320f1c) & 0xffffff
        if count % 11 == 0:bg = 0
        elif count % 11 == 1:bg = 0xffffff
        lx, ly = x-352-offset, y-101
        coverage = masks[topic].getpixel((lx, ly)) if 0 <= lx < 240 and 0 <= ly < 174 else 0
        effective = (WEIGHTS[coverage]*alpha+16)//32
        fg = manifest["pages"][topic]["accent"] if ly < 28 else [218, 227, 233]
        channels = [(bg >> shift) & 255 for shift in (16, 8, 0)]
        channels = [b+((f-b)*effective+16)//32 for b, f in zip(channels, fg)]
        rgb = (channels[0] << 16) | (channels[1] << 8) | channels[2]
        tag = (count*193+7) % 307200
        vector = (x | (y << 10) | (bg << 19) | (topic << 43) | (offset << 45) |
                  (alpha << 52) | (tag << 58) | (valid << 77) | (rgb << 78))
        stream.write(f"{vector:026x}\n");count += 1
    with path.open("w", encoding="ascii") as stream:
        for topic in range(4):
            # Full text footprint covers every row, column, packed word and font bank.
            for ly in range(174):
                for lx in range(240):
                    emit(stream, topic, 352+lx, 101+ly, 32, 0)
            points = {(col*16+gx, 36+row*23+gy)
                      for row in range(6) for col in range(15)
                      for gx, gy in [(0, 3), (7, 8), (8, 14), (15, 19)]}
            points.update((x, y) for x in (-1, 0, 1, 7, 8, 15, 16, 99, 100, 127, 128, 239, 240)
                          for y in (-1, 0, 4, 23, 24, 25, 26, 27, 28, 35, 36, 55, 56, 58, 59, 170, 171, 173, 174))
            for alpha in (0, 1, 16, 31, 32):
                for offset in (0, 1, 64):
                    for lx, ly in sorted(points):
                        emit(stream, topic, 352+offset+lx, 101+ly, alpha, offset)
                    for x, y in [(0, 0), (639, 479), (351, 101), (352, 100), (31, 49), (27, 435)]:
                        emit(stream, topic, x, y, alpha, offset)
                    # Validity bubbles are distinct from CE stalls and must retain tags.
                    for n in range(7):emit(stream, topic, 360+n, 110+n, alpha, offset, 0)
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool-dir", type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads((ROOT / "assets/intro_assets.json").read_text(encoding="utf-8"))
    media = check_media(manifest)
    dda_checks = check_geometry(manifest)
    masks = font_oracle(manifest)
    runs = []
    with tempfile.TemporaryDirectory(prefix="intro_text_") as temporary:
        temp = Path(temporary)
        vectors = write_vectors(temp / "vectors.hex", manifest, masks)
        for key, filename in [("geometry_words", "geometry.hex"), ("character_words", "characters.hex"), ("glyph_words", "glyphs.hex")]:
            (temp / filename).write_text("".join(f"{word:04x}\n" for word in manifest[key]), encoding="ascii")
        for native in (False, True):
            for top, bench in [("tb_intro_roms", "tb_roms.sv"), ("tb_intro_text", "tb_text.sv")]:
                output = temp / f"{top}_{native}.vvp"
                command = [str(args.tool_dir / "iverilog.exe"), "-g2012", "-s", top, "-o", str(output)]
                if native:command += ["-DTEST_NATIVE"]
                if top == "tb_intro_text":command += [f"-P{top}.N={vectors}"]
                command += [str(HERE / bench), str(HERE / "native_bram32k_contract.v"),
                            str(ROOT / "rtl/intro_assets_rom.v"), str(ROOT / "rtl/intro_text_layer.v")]
                result = subprocess.run(command, cwd=temp, text=True, capture_output=True)
                assert result.returncode == 0, result.stdout+result.stderr
                result = subprocess.run([str(args.tool_dir / "vvp.exe"), str(output)], cwd=temp,
                                        text=True, capture_output=True)
                log = result.stdout+result.stderr
                assert result.returncode == 0 and "PASS" in log, log
                print(("native " if native else "behavior ")+log.strip())
                runs.append({"top": top, "native_contract": native, "output": log.strip()})
    inputs = [ROOT / "rtl/intro_assets_rom.v", ROOT / "rtl/intro_text_layer.v", ROOT / "assets/intro_assets.json",
              HERE / "tb_text.sv", HERE / "tb_roms.sv", HERE / "native_bram32k_contract.v", Path(__file__)]
    summary = {"passed": True, "vectors_per_shader_run": vectors, "dda_coordinate_checks": dda_checks,
               "media_qa": media, "runs": runs, "inputs_sha256": {str(path): digest(path) for path in inputs},
               "hardware_tested": False}
    (HERE / "summary.json").write_text(json.dumps(summary, indent=2)+"\n", encoding="utf-8")
    print("PASS independent PIL text pixels, ROM payload/CE/native INIT contract and staged media QA")


if __name__ == "__main__":
    main()
