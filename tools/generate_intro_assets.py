"""Generate SOLAR24 intro ROMs and staged photo-only sixth-page media.

The desktop delivery and removable media are read-only inputs. Generated BMPs,
software-oracle stills and GIFs stay in the report directory until deployment.
Requires Pillow and the existing prepare_solar_media.py source-photo helpers.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct

from PIL import Image, ImageDraw, ImageOps


ROOT = Path(__file__).resolve().parents[1]
DELIVERY = (Path.home() / "Desktop" / "太阳系特展_交付包_20261023")
REPORT = ROOT / "reports/gallery_caption_20261024"
HERO = (18, 36, 604, 308)
BACKGROUND = (6, 12, 20)
BODY_COLOR = (218, 227, 233)
HEADING = "回望这一程"
AA_WEIGHTS = (0, 11, 21, 32)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def payload_hash(words):
    return hashlib.sha256(struct.pack("<" + "H" * len(words), *words)).hexdigest()


def load_author():
    path = ROOT / "tools/prepare_solar_media.py"
    spec = importlib.util.spec_from_file_location("solar_media_author", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rounded_fraction(numerator, denominator):
    return (numerator + denominator // 2) // denominator


def descriptor(source, target, phase):
    """Offline integer minimum-jerk geometry and cubic-out text motion."""
    n, d = max(0, min(37, phase - 23)), 37
    ease = 6*n**5 - 15*n**4*d + 10*n**3*d*d
    denominator = d**5
    dest = [rounded_fraction(a * (denominator-ease) + b * ease, denominator)
            for a, b in zip(source, target)]
    x, y, w, h = dest
    xq, xr = divmod(source[2], w)
    yq, yr = divmod(source[3], h)
    tn, td = max(0, min(19, phase - 44)), 19
    text_denominator = td**3
    text_ease = text_denominator - (td-tn)**3
    alpha = rounded_fraction(32 * text_ease, text_denominator)
    offset = rounded_fraction(64 * (text_denominator-text_ease), text_denominator)
    assert 0 <= xq <= 3 and 0 <= yq <= 3
    words = [x, y, w, h, (xq << 10) | xr, (yq << 9) | yr,
             (alpha << 7) | offset, 0]
    return {"phase": phase, "destination_xywh": dest, "x_quotient": xq,
            "x_remainder": xr, "y_quotient": yq, "y_remainder": yr,
            "text_alpha": alpha, "text_offset": offset, "words": words}


def aa_image(size, text, font, xy=(0, 0)):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).text(xy, text, font=font, fill=255)
    # Round the native font coverage to two bits, retaining partial edge pixels.
    mask = mask.point(lambda value: (value * 3 + 127) // 255)
    return mask


def pack_aa(mask):
    values = list(mask.get_flattened_data())
    assert len(values) % 8 == 0
    return [sum(value << (2*pixel) for pixel, value in enumerate(values[start:start+8]))
            for start in range(0, len(values), 8)]


def make_text_assets(author):
    summaries = [topic["summary"] for topic in author.TOPICS]
    glyphs = [""] + sorted(set("".join(summaries)), key=ord)
    assert len(glyphs) == 192, "Review glyph-ROM capacity after changing the summaries"
    glyph_index = {ch: index for index, ch in enumerate(glyphs)}
    body_font, title_font = author.font(16), author.font(20, True)
    glyph_words, glyph_metadata = [], []
    for index, char in enumerate(glyphs):
        bbox = body_font.getbbox(char) if char else (0, 0, 0, 0)
        assert bbox[0] >= 0 and bbox[1] >= 0 and bbox[2] <= 16 and bbox[3] <= 20
        mask = aa_image((16, 20), char, body_font)
        glyph_words.extend(pack_aa(mask))
        glyph_metadata.append({"index": index, "character": char,
                               "codepoint": ord(char) if char else None,
                               "word_base": index * 40,
                               "font_bbox": list(bbox), "ink_bbox": mask.getbbox()})
    heading_base = len(glyph_words)
    # YaHei bold 20 has bottom=25 at y=0. Shift by one to fit all ink in 24 rows.
    title_bbox = title_font.getbbox(HEADING)
    assert title_bbox[0] >= 0 and title_bbox[2] <= 128
    assert title_bbox[1] - 1 >= 0 and title_bbox[3] - 1 <= 24
    title_mask = aa_image((128, 24), HEADING, title_font, (0, -1))
    glyph_words.extend(pack_aa(title_mask))
    font_used = len(glyph_words)
    assert font_used <= 8192
    glyph_words += [0] * (8192-len(glyph_words))
    character_words, layouts = [], []
    for topic, summary in enumerate(summaries):
        lines = [summary[start:start+15] for start in range(0, len(summary), 15)]
        assert len(lines) <= 6
        # Existing TOPICS contain full-width Chinese; retain the measured author wrap.
        assert all(body_font.getlength(line) <= 246 for line in lines)
        padded = lines + [""] * (6-len(lines))
        cells = [glyph_index.get(ch, 0) for line in padded for ch in line.ljust(15)]
        assert len(cells) == 90
        character_words.extend(cells + [0] * 38)
        layouts.append({"topic": topic, "lines": lines, "characters": cells,
                        "text": summary, "first_word": topic * 128})
    metadata = {"format": "AA2; eight row-major pixels/word; leftmost pixel in bits 1:0",
                "glyph_cell": [16, 20], "glyph_words_per_cell": 40,
                "glyph_count": len(glyphs), "glyphs": glyph_metadata,
                "heading": {"text": HEADING, "size": [128, 24],
                            "draw_xy": [0, -1], "word_base": heading_base,
                            "word_count": 384, "font_bbox": list(title_bbox),
                            "ink_bbox": title_mask.getbbox()},
                "font_used_words": font_used,
                "layout": {"panel_x": 352, "panel_y": 101, "columns": 15,
                           "rows": 6, "body_y": 36, "line_height": 23,
                           "heading_underline_xywh": [0, 26, 100, 2],
                           "topic_stride_words": 128, "body_color": BODY_COLOR},
                "coverage_weights_q5": AA_WEIGHTS,
                "blend": "a=(coverage_weight*text_alpha+16)>>5; out=(bg*(32-a)+fg*a+16)>>5",
                "topics": layouts}
    return character_words, glyph_words, metadata


def rom_module(name, words, address_bits):
    """Emit six explicit native 32K blocks across the three public ROMs."""
    banks = (len(words)+2047)//2048
    padded = words + [0] * (banks*2048-len(words))
    lines = [f"module {name}(input wire clk,en,input wire [{address_bits-1}:0] address,",
             " output wire [15:0] data);"]
    if banks > 1:
        lines += [" reg [1:0] bank_q;", " always @(posedge clk)if(en)bank_q<=address[12:11];"]
    for bank in range(banks):
        bank_words = padded[bank*2048:(bank+1)*2048]
        # The exact same 32768-bit constant initializes simulation and hardware.
        chunks = [sum(word << (16*i) for i, word in enumerate(bank_words[start:start+16]))
                  for start in range(0, 2048, 16)]
        constants = ",\n".join(f"  256'h{value:064x}" for value in reversed(chunks))
        lines += [f" localparam [32767:0] BANK_{bank}={{", constants+"};",
                  f" wire [15:0] q_{bank};", "`ifdef __ICARUS__",
                  f" reg [15:0] memory_{bank}[0:2047];reg [15:0] sim_q_{bank};integer i_{bank};",
                  f" initial for(i_{bank}=0;i_{bank}<2048;i_{bank}=i_{bank}+1)",
                  f"  memory_{bank}[i_{bank}]=BANK_{bank}[i_{bank}*16+:16];",
                  f" always @(posedge clk)if(en)sim_q_{bank}<=memory_{bank}[" +
                  ("address[10:0]" if address_bits > 11 else
                   ("address" if address_bits == 11 else "{2'd0,address}")) + "];",
                  f" assign q_{bank}=sim_q_{bank};", "`else"]
        init = ",\n".join(f"  .INIT_{i:02X}(BANK_{bank}[{i*256}+:256])" for i in range(128))
        lines += [" EG_PHY_BRAM32K #(.MODE(\"DP16K\"),.DATA_WIDTH_A(\"16\"),.DATA_WIDTH_B(\"16\"),",
                  "  .REGMODE_A(\"NOREG\"),.REGMODE_B(\"NOREG\"),",
                  init + f") bank_{bank}(",
                  f"  .doa(q_{bank}),.dia(16'd0),.addra(" +
                  ("address[10:0]" if address_bits > 11 else
                   ("address" if address_bits == 11 else "{2'd0,address}")) + "),",
                  "  .bytea(1'b0),.bytewea(1'b0),.csa(en),.wea(1'b0),.clka(clk),.rsta(1'b0),.ocea(1'b1),",
                  "  .dob(),.dib(16'd0),.addrb(11'd0),.byteb(1'b0),.byteweb(1'b0),",
                  "  .csb(1'b0),.web(1'b0),.clkb(clk),.rstb(1'b0),.oceb(1'b0));",
                  "`endif"]
    lines += ([" assign data=q_0;"] if banks == 1 else
              [" assign data=bank_q==0?q_0:bank_q==1?q_1:bank_q==2?q_2:q_3;"])
    return "\n".join(lines + ["endmodule", ""])


def text_coverage(font_words, text, topic, x, y):
    layout = text["layout"]
    if 0 <= x < 128 and 0 <= y < 24:
        pixel = y*128+x
        word = font_words[text["heading"]["word_base"] + pixel//8]
        return (word >> ((pixel % 8)*2)) & 3, True
    if 0 <= x < 100 and 26 <= y < 28:
        return 3, True
    by = y-layout["body_y"]
    row, gy = divmod(by, layout["line_height"])
    col, gx = divmod(x, 16)
    if 0 <= col < 15 and 0 <= row < 6 and gy < 20:
        glyph = text["topics"][topic]["characters"][row*15+col]
        word = font_words[glyph*40+gy*2+gx//8]
        return (word >> ((gx % 8)*2)) & 3, False
    return 0, False


def oracle_frame(staged, source, geometry, topic, text, font_words, accent):
    """Reference address formula: floor(local*source_dimension/dest_dimension)."""
    frame = Image.new("RGB", (640, 480), BACKGROUND)
    sx, sy, sw, sh = source
    dx, dy, dw, dh = geometry["destination_xywh"]
    source_pixels, dest_pixels = staged.load(), frame.load()
    for vy in range(dh):
        source_y = sy + vy*sh//dh
        for vx in range(dw):
            dest_pixels[dx+vx, dy+vy] = source_pixels[sx+vx*sw//dw, source_y]
    alpha, offset = geometry["text_alpha"], geometry["text_offset"]
    if alpha:
        for ty in range(174):
            for tx in range(240):
                coverage, heading = text_coverage(font_words, text, topic, tx, ty)
                if not coverage:
                    continue
                effective = (AA_WEIGHTS[coverage]*alpha+16) >> 5
                if not effective:
                    continue
                px, py = 352+offset+tx, 101+ty
                if not 0 <= px < 640:
                    continue
                fg = accent if heading else BODY_COLOR
                bg = dest_pixels[px, py]
                dest_pixels[px, py] = tuple((b*(32-effective)+f*effective+16) >> 5
                                          for b, f in zip(bg, fg))
    return frame


def clean_photo(author, sources, source_id):
    if "+" not in source_id:
        return Image.open(author.photo_path(sources, source_id)).convert("RGB")
    # Presentation labels belong in the drawer, not on top of the photographs.
    montage = Image.new("RGB", (1100, 550), "black")
    for i, part in enumerate(source_id.split("+")):
        photo = Image.open(author.photo_path(sources, part)).convert("RGB")
        photo = ImageOps.contain(photo, (490, 490), Image.Resampling.LANCZOS)
        montage.paste(photo, (30+i*550+(490-photo.width)//2, 30+(490-photo.height)//2))
    return montage


def caption_fraction(phase):
    # Captions must be readable in the first committed frame, even paused.
    return 32


def caption_bitmap(author, index, entry):
    group, within = divmod(index, 6)
    _, title, caption, credit, _ = entry
    im = Image.new("RGB", (640, 64), BACKGROUND)
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle((18, 0, 621, 63), radius=6, fill=(12, 25, 37), outline=(35, 58, 72))
    draw.rounded_rectangle((23, 9, 26, 54), radius=1, fill=author.TOPICS[group]["color"])
    heading = f'{index+1:02d} / 24  ·  {author.TOPICS[group]["title"]}  /  {title}'
    assert draw.textlength(heading, font=author.font(16, True)) <= 576, heading
    draw.text((33, 1), heading, font=author.font(16, True), fill=(228, 235, 239))
    body_font = author.font(13)
    if draw.textlength(caption, font=body_font) > 576:
        body_font = author.font(12)
    assert draw.textlength(caption, font=body_font) <= 576, caption
    draw.text((33, 25), caption, font=body_font, fill=(166, 189, 202))
    credit_font = author.font(9)
    if draw.textlength(credit, font=credit_font) > 576:
        credit_font = author.font(8)
    assert draw.textlength(credit, font=credit_font) <= 576, credit
    draw.text((33, 47), credit, font=credit_font, fill=(119, 145, 164))
    return im


def add_caption(frame, staged, phase, slide_fraction=None):
    import numpy as np
    alpha = caption_fraction(phase) if slide_fraction is None else 32-min(32, slide_fraction//8)
    offset = 64-2*alpha if slide_fraction is None else 0
    top = 352+offset
    if alpha and top < 416:
        height = 416-top
        bg = np.asarray(frame.crop((0, top, 640, 416)), dtype=np.int32)
        fg = np.asarray(staged.crop((0, 384, 640, 384+height)), dtype=np.int32)
        out = ((bg*(32-alpha)+fg*alpha+16)//32).astype('uint8')
        frame.paste(Image.fromarray(out), (0, top))
    return frame


def gif_durations(count):
    # GIF stores centiseconds. Preserve the 16.8ms hardware frame period in total.
    ticks = [round(i*1.68) for i in range(count+1)]
    return [(ticks[i+1]-ticks[i])*10 for i in range(count)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--delivery", type=Path, default=DELIVERY)
    parser.add_argument("--report", type=Path, default=REPORT)
    parser.add_argument("--skip-previews", action="store_true")
    args = parser.parse_args()
    delivery, report = args.delivery.resolve(), args.report.resolve()
    assert delivery != report and delivery not in report.parents
    baseline = report / "baseline.json"
    assert baseline.is_file(), "Capture an accepted baseline before generating this stage"
    author = load_author()
    sources, old_media = delivery / "素材来源", delivery / "TF卡内容"
    media, previews = report / "media", report / "preview"
    media.mkdir(parents=True, exist_ok=True)
    previews.mkdir(parents=True, exist_ok=True)
    char_words, font_words, text = make_text_assets(author)
    pages, all_geometry, gallery, images = [], [], [], []
    input_hashes = {str(baseline): sha256(baseline),
                    str(ROOT / "tools/prepare_solar_media.py"): sha256(ROOT / "tools/prepare_solar_media.py"),
                    str(author.FONT): sha256(author.FONT), str(author.FONT_BOLD): sha256(author.FONT_BOLD)}
    for index, entry in enumerate(author.ENTRIES):
        page, topic = index+1, index//6
        input_hashes[str(old_media/f'{page:02d}.BMP')] = sha256(old_media/f'{page:02d}.BMP')
        photo = clean_photo(author, sources, entry[0])
        staged = Image.new('RGB', (640, 480), BACKGROUND)
        actual_source = author.paste_contain(staged, photo, HERO)
        staged.paste(caption_bitmap(author, index, entry), (0, 384))
        path = media/f'{page:02d}.BMP';staged.save(path, format='BMP')
        header = path.read_bytes()[:54]
        assert struct.unpack_from('<IiiHHI', header, 14) == (40, 640, 480, 1, 24, 0)
        assert path.stat().st_size == 921654
        originals=[]
        for sid in entry[0].split('+'):
            original=author.photo_path(sources,sid)
            input_hashes[str(original)] = sha256(original)
            originals.append({'id':sid,'path':str(original),'sha256':sha256(original)})
        item={'topic':topic,'page':page,'file':path.name,'title':entry[1],
              'caption':entry[2],'credit':entry[3],
              'source_photo_xywh':list(actual_source),'original_files':originals,
              'accent':list(author.TOPICS[topic]['color']),'staged_sha256':sha256(path)}
        gallery.append(item);images.append(staged)
        if page%6==0:
            target_image=Image.new('RGB',(640,480),BACKGROUND)
            target=author.paste_contain(target_image,photo,(24,90,290,254))
            geometry=[descriptor(actual_source,target,phase) for phase in range(64)]
            all_geometry.extend(word for desc in geometry for word in desc['words'])
            pages.append({**item,'final_photo_xywh':list(target),'phases':geometry})
    assert len(all_geometry)==2048 and len(char_words)==512 and len(font_words)==8192
    rtl='// Generated by tools/generate_intro_assets.py; payload oracle: assets/intro_assets.json\n'
    for name,words,width in [('intro_geometry_rom',all_geometry,11),('intro_character_rom',char_words,9),('intro_glyph_rom',font_words,13)]:
        rtl+=rom_module(name,words,width)
    rtl_path=ROOT/'rtl/intro_assets_rom.v';rtl_path.write_text(rtl,encoding='utf-8')
    manifest={'profile':'SOLAR24_GALLERY_CAPTION','version':3,
              'generator':'tools/generate_intro_assets.py','generator_sha256':sha256(__file__),
              'hero_xywh':list(HERO),'clear_rgb':list(BACKGROUND),
              'caption_source_xywh':[0,384,640,64],'caption_viewport_xywh':[0,352,640,64],
              'caption_fraction_q5':[caption_fraction(i) for i in range(19)],
              'spectrum_picture_viewport_xywh':[0,416,640,64],
              'image_format':'640x480 RGB24 BI_RGB bottom-up BITMAPINFOHEADER40; gallery atlas',
              'motion':{'phase_count':64,'phase_tick_frames':1,'phase_step_per_frame':2,
                        'image':'intro hold0..23; minimum-jerk through60; settle60..63',
                        'text':'intro cubic-out44..63, offset64..0 alpha0..32',
                        'caption':'visible in first committed frame, independent of playback pause; old caption fades during12frame slide',
                        'sampling':'floor(local*source/destination); independent exact quotient/remainder DDA'},
              'descriptor_words':['destination_x','destination_y','destination_width','destination_height',
                                  'x_quotient[11:10],x_remainder[9:0]','y_quotient[10:9],y_remainder[8:0]',
                                  'text_alpha[12:7],text_offset[6:0]','reserved=0'],
              'rom_contract':{'latency_clocks':1,'enable':'hold whenen=0','native_primitive':'EG_PHY_BRAM32K',
                              'native_blocks':6,'init':'INIT_00..7F;16little-endianwords/chunk'},
              'geometry_words':all_geometry,'character_words':char_words,'glyph_words':font_words,
              'payload_sha256_le16':{'geometry':payload_hash(all_geometry),'characters':payload_hash(char_words),'glyphs':payload_hash(font_words)},
              'text':text,'pages':pages,'gallery':gallery,'input_sha256':input_hashes,
              'generated_rtl_sha256':sha256(rtl_path),
              'media':[{'file':p.name,'sha256':sha256(p),'bytes':p.stat().st_size} for p in sorted(media.glob('*.BMP'))]}
    manifest_path=ROOT/'assets/intro_assets.json';manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if not args.skip_previews:
        preview_records=[]
        for i,(item,staged) in enumerate(zip(gallery,images)):
            if item['page']%6==0:
                page=pages[item['topic']]
                display_phases=list(range(0,64,2))+[63]
                frames=[add_caption(oracle_frame(staged,page['source_photo_xywh'],page['phases'][phase],item['topic'],text,font_words,tuple(item['accent'])),staged,phase) for phase in display_phases]
            else:
                frames=[]
                for phase in range(1):
                    frame=Image.new('RGB',(640,480),BACKGROUND)
                    frame.paste(staged.crop((0,0,640,352)),(0,0))
                    frames.append(add_caption(frame,staged,phase))
            final=previews/f"{item['page']:02d}.png";frames[-1].save(final)
            anim=previews/f"{item['page']:02d}_entrance.gif"
            frames[0].save(anim,save_all=True,append_images=frames[1:],duration=gif_durations(len(frames)),disposal=2,optimize=False)
            preview_records.extend({'file':p.name,'sha256':sha256(p)} for p in [final,anim])
            if item['page']%6==0:
                for phase in [0,24,44,52,63]:frames[display_phases.index(phase)].save(previews/f"{item['page']:02d}_phase{phase:02d}.png")
        (previews/'software_oracle.json').write_text(json.dumps({'notice':'Software oracle, not board capture','manifest_sha256':sha256(manifest_path),'files':preview_records,'frame_ms':16.8,'gif_one_shot':True},indent=2),encoding='utf-8')
    assert all(sha256(path)==digest for path,digest in input_hashes.items())
    print(json.dumps({'status':'staged','images':24,'rom_blocks':6,'gallery':str(media),'desktop_modified':False,'tf_modified':False},ensure_ascii=False))


if __name__ == '__main__':
    main()
