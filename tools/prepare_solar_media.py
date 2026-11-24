"""Prepare the 24-image solar exhibition from cached official image sources.

This is an offline media authoring tool. It does not access a removable drive,
change RTL, or change the source photos. Requires Pillow and NumPy.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps


DEFAULT = Path("media_source")
FONT = Path("C:/Windows/Fonts/msyh.ttc")
FONT_BOLD = Path("C:/Windows/Fonts/msyhbd.ttc")
SIZE = (640, 480)
TOPICS = [
    {"title": "太阳", "en": "01 / OUR STAR", "color": (237, 187, 110),
     "summary": "太阳的光与热来自核心的核聚变。光离开太阳表面后，约八分二十秒抵达地球。金色日冕、暗色黑子与极地的光带，记录着同一颗恒星的活动；一亿五千万公里之外，它仍在影响我们的日常。"},
    {"title": "岩石世界", "en": "02 / ROCKY WORLDS", "color": (218, 161, 133),
     "summary": "水星遍布撞击坑，金星藏在厚厚的云层之下，火星的峡谷刻下漫长的地质历史。月球背面的高地与我们熟悉的正面很不一样。相似的岩石起点，演化出不同的世界；回望地球，温和的环境值得珍惜。"},
    {"title": "巨行星", "en": "03 / GIANT WORLDS", "color": (136, 200, 224),
     "summary": "木星与土星是气态巨行星，天王星与海王星属于冰巨行星。它们的结构不能用地球式地面来理解。风暴、冰环、冰壳与地下海洋，让巨行星及其卫星成为一座复杂的自然实验室。"},
    {"title": "边界与回望", "en": "04 / FARTHER, THEN HOME", "color": (182, 173, 226),
     "summary": "一九九〇年，旅行者一号从遥远的外太阳系回望。地球在光束里只是一点微光。探测器继续飞向更远处，金唱片带着地球的声音同行。看完这段旅程，回到首页，亲手转动太阳系仪。"},
]

# The source IDs resolve to downloaded, unmodified official source files.
# ESA_67P has an explicitly stated CC BY-SA 3.0 IGO license; this adaptation
# carries the same license. Other credits are preserved per source metadata.
ENTRIES = [
    ("SDO_171_20260927", "金色日冕", "171 埃极紫外影像，以假色显现日冕结构。", "NASA / SDO", "171 Å · FALSE COLOR"),
    ("PIA22661", "扭转的日珥", "炽热等离子体沿磁场舒展，勾勒太阳边缘。", "NASA / SDO", "PROMINENCES · EUV"),
    ("GSFC_20171208_Archive_e000923", "黑子与磁场", "黑子相对周围更冷、更暗，也是强磁场活动的标记。", "NASA / SDO", "SUNSPOTS · VISIBLE LIGHT"),
    ("GSFC_20171208_Archive_e001210", "同一场耀斑", "同一时刻的不同波段，显示不同温度的太阳大气。", "NASA / SDO", "SOLAR FLARE · MULTI-WAVELENGTH"),
    ("AFRC2017-0233-009", "日全食 · 钻石环", "月球遮住太阳时，一点阳光点亮日冕的轮廓。", "NASA / Carla Thomas", "TOTAL SOLAR ECLIPSE · 2017"),
    ("iss039e009160", "来自太阳的回响", "极光越过地球边缘，太阳与家园在此相连。", "NASA / Rick Mastracchio", "AURORA · INTERNATIONAL SPACE STATION"),
    ("GSFC_20171208_Archive_e001545", "水星 · 岩石的颜色", "增强色显示岩石性质差异，并非肉眼所见的颜色。", "NASA / MESSENGER", "MERCURY · ENHANCED COLOR"),
    ("PIA00008", "金星 · 穿过云层", "麦哲伦号的雷达穿透浓云，拼出地表的模样。", "NASA / JPL / USGS", "VENUS · RADAR FALSE COLOR"),
    ("as17-148-22727", "地球 · 蓝色弹珠", "阿波罗十七号从奔月途中，回望我们共同的家园。", "NASA / Apollo 17", "EARTH · APOLLO 17 · 1972"),
    ("GSFC_20171208_Archive_e001939", "月球 · 另一面", "背面高地密布撞击坑，海洋般的月海较少。", "NASA / Goddard / ASU", "LUNAR FARSIDE · LRO MOSAIC"),
    ("PIA00199", "火星 · 峡谷的层次", "水手号峡谷的层状地形，留下古老地质过程的线索。", "NASA / JPL / USGS", "MARS · CANDOR CHASM"),
    ("PIA10369", "火卫一 · 不规则世界", "撞击坑与沟槽，写在这颗小卫星的表面。", "NASA / JPL-Caltech / UArizona", "PHOBOS · MARS RECONNAISSANCE ORBITER"),
    ("PIA21395", "木星 · 大红斑", "朱诺号近看巨大的风暴；增强色帮助辨认云层。", "NASA / Juno · Kevin M. Gill", "JUPITER · ENHANCED COLOR · CC BY"),
    ("PIA14934", "土星 · 逆光的环", "卡西尼号藏进土星的阴影，看见被阳光照亮的冰环。", "NASA / JPL-Caltech / SSI", "SATURN · CASSINI"),
    ("PIA00275", "木卫二 · 冰的裂纹", "增强色揭示冰面交错的脊线与不同的表面物质。", "NASA / JPL / UArizona", "EUROPA · ENHANCED COLOR"),
    ("PIA07759", "土卫二 · 冰粒喷泉", "增强并着色的影像，显现南极羽流的细节与范围。", "NASA / JPL-Caltech / SSI", "ENCELADUS · ENHANCED PLUME"),
    ("PIA08630", "土卫六 · 陌生的湖", "雷达图中的暗色区域，为碳氢化合物湖泊提供证据。", "NASA / JPL-Caltech / ASI", "TITAN · RADAR IMAGE"),
    ("PIA18182+PIA02210", "远方的蓝色巨人", "旅行者二号所见的天王星与海王星，冰巨行星家族。", "NASA / JPL-Caltech · NASA / JPL", "URANUS + NEPTUNE · VOYAGER 2"),
    ("PIA19952", "冥王星 · 心形平原", "新视野号揭开矮行星的丰富地貌；本图为增强色。", "NASA / JHUAPL / SwRI", "PLUTO · ENHANCED COLOR"),
    ("ARROKOTH", "阿罗科斯 · 双瓣相连", "两个相连的天体，保留着太阳系早期形成的线索。", "NASA / JHUAPL / SwRI / R. Tkachenko", "ARROKOTH · NEW HORIZONS"),
    ("ESA_67P", "彗星 · 太阳系的档案", "罗塞塔号近看 67P；这不是光滑的冰球，而是崎岖的世界。", "ESA / Rosetta / NAVCAM · CC BY-SA 3.0 IGO", "67P / CHURYUMOV-GERASIMENKO"),
    ("PIA21895", "卡西尼号 · 最后一眼", "最后的相机影像望向土星，随后探测器进入它的大气。", "NASA / JPL-Caltech / SSI", "CASSINI · FINAL CAMERA IMAGE · 2017"),
    ("PIA23645", "地球 · 暗淡蓝点", "一束散射的阳光中，那一点微光，就是地球。", "NASA / JPL-Caltech", "PALE BLUE DOT · VOYAGER 1 · REPROCESSED"),
    ("PIA14113", "把地球的声音带走", "两艘旅行者探测器，带着镀金唱片飞向远方。", "NASA / JPL-Caltech", "VOYAGER · THE GOLDEN RECORD"),
]


def font(size: int, bold: bool = False):
    return ImageFont.truetype(str(FONT_BOLD if bold else FONT), size)


def wrapped(draw, text, xy, width, f, fill, line_height=22):
    """Wrap by measured glyph width, with an explicit overflow check."""
    x, y = xy
    lines, line = [], ""
    for ch in text:
        if ch == "\n" or (line and draw.textlength(line + ch, font=f) > width):
            lines.append(line)
            line = "" if ch == "\n" else ch
        else:
            line += ch
    if line:
        lines.append(line)
    for i, line in enumerate(lines):
        draw.text((x, y + line_height * i), line, font=f, fill=fill)
    return y + line_height * len(lines)


def background(seed=1):
    im = Image.new("RGB", SIZE)
    d = ImageDraw.Draw(im)
    for y in range(480):
        k = math.exp(-((y - 180) / 240) ** 2)
        d.line((0, y, 639, y), fill=(7 + int(k * 3), 13 + int(k * 8), 23 + int(k * 12)))
    r = random.Random(seed)
    for _ in range(100):
        x, y = r.randrange(640), r.randrange(32, 475)
        v = r.randrange(30, 85)
        d.point((x, y), (v, v + 8, min(255, v + 15)))
    return im


def photo_path(sources, n):
    candidates = list((sources / "原图").glob(n + ".*"))
    if len(candidates) != 1:
        raise ValueError(f"Missing/ambiguous source image: {n}: {candidates}")
    return candidates[0]


def source_photo(sources, n):
    if "+" in n:
        montage = Image.new("RGB", (1100, 650), "black")
        d = ImageDraw.Draw(montage)
        for i, part in enumerate(n.split("+")):
            pic = Image.open(photo_path(sources, part)).convert("RGB")
            pic = ImageOps.contain(pic, (490, 490), Image.Resampling.LANCZOS)
            montage.paste(pic, (30 + i * 550 + (490-pic.width)//2, 45+(490-pic.height)//2))
            d.text((180 + i*550, 560), ["天王星", "海王星"][i], font=font(25), fill=(168, 193, 209))
        return montage
    return Image.open(photo_path(sources, n)).convert("RGB")


def paste_contain(im, pic, box):
    x, y, w, h = box
    pic = ImageOps.contain(pic, (w, h), Image.Resampling.LANCZOS)
    px, py = x + (w - pic.width)//2, y + (h - pic.height)//2
    im.paste(pic, (px, py))
    return (px, py, pic.width, pic.height)


def render(sources, index, entry):
    sid, title, caption, credit, descriptor = entry
    group, within = divmod(index, 6)
    topic = TOPICS[group]
    accent = topic["color"]
    im = background(group + 17)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((16, 40, 623, 448), radius=6, fill=(6, 12, 20), outline=(40, 62, 78))
    pic = source_photo(sources, sid)
    if within == 5:
        # Four topic conclusions reuse the sixth image; no extra BMP slot.
        photo_box = paste_contain(im, pic, (24, 90, 290, 254))
        d = ImageDraw.Draw(im)
        d.line((332, 108, 332, 331), fill=(46, 68, 83))
        d.text((352, 101), "回望这一程", font=font(20, True), fill=accent)
        end_y = wrapped(d, topic["summary"], (352, 139), 246, font(16), (218, 227, 233), 23)
        if end_y > 341:
            raise ValueError(f"Summary overflow: {topic['title']}: {end_y}")
        d.text((31, 350), title, font=font(17, True), fill=(208, 220, 230))
        d.text((31, 377), "06 / 06  ·  本专题小结", font=font(12), fill=(133, 155, 173))
        d.text((352, 371), "左右翻页  ·  KEY0 返回首页", font=font(12), fill=(133, 155, 173))
        if group == 3:
            d.text((352, 395), "下一站：第五项「太阳系仪」", font=font(13), fill=accent)
    else:
        photo_box = paste_contain(im, pic, (18, 42, 604, 404))
        # Vignette only outside the photo subject, plus a readable annotation band.
        overlay = Image.new("RGBA", SIZE, (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        od.rounded_rectangle((20, 300, 619, 343), radius=4, fill=(6, 14, 24, 225))
        for y in range(345, 448):
            od.line((18, y, 621, y), fill=(5, 10, 18, int((y-345)/103*160)))
        im = Image.alpha_composite(im.convert("RGBA"), overlay).convert("RGB")
        d = ImageDraw.Draw(im)
        d.text((31, 302), title, font=font(18, True), fill=(228, 235, 239))
        if d.textlength(caption, font=font(13)) > 576:
            raise ValueError(f"Caption overflow: {title}")
        d.text((31, 326), caption, font=font(13), fill=(162, 186, 201))
        if sid == "PIA23645":
            # Pointer marks the actual Earth speck in NASA's 1280x1266 image.
            px, py, pw, ph = photo_box
            ex, ey = px + 761/1280*pw, py + 658/1266*ph
            d.ellipse((ex-6, ey-6, ex+6, ey+6), outline=accent, width=1)
            d.line((ex+7, ey, ex+60, ey-18), fill=accent, width=1)
            d.text((ex+63, ey-29), "地球", font=font(14), fill=accent)
    # The top 30 rows are reserved for the hardware subtitle and RTC.
    # Music toast temporarily covers x=16..175, y=40..87. Main title avoids it.
    strip = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    sd = ImageDraw.Draw(strip)
    sd.rounded_rectangle((22, 46, 617, 87), radius=4, fill=(8, 16, 27, 220))
    im = Image.alpha_composite(im.convert("RGBA"), strip).convert("RGB")
    d = ImageDraw.Draw(im)
    d.text((31, 49), f"{index+1:02d} / 24", font=font(17, True), fill=accent)
    d.text((200, 46), topic["title"], font=font(20, True), fill=(228, 235, 239))
    d.text((200, 72), descriptor, font=font(9), fill=(151, 177, 197))
    # Complete author attribution remains on the image and in CREDITS.TXT.
    credit_font = font(9)
    if d.textlength(credit, font=credit_font) > 580:
        raise ValueError(f"Credit overflow: {credit}")
    d.text((27, 432), credit, font=credit_font, fill=(131, 154, 171))
    d.line((26, 455, 614, 455), fill=(35, 54, 70))
    for i in range(6):
        x = 280 + i*14
        d.rounded_rectangle((x, 461, x+7, 464), radius=1,
                            fill=accent if i == within else (44, 62, 76))
    return im


def create_music(path, group):
    rate, seconds = 48000, 24
    n = rate * seconds
    t = np.arange(n, dtype=np.float64) / rate
    roots = [[48, 53, 57, 55], [50, 46, 53, 48], [53, 55, 60, 58], [45, 53, 48, 52]][group]
    offsets = [[0,4,7,11], [0,3,7,10], [0,4,7,14], [0,3,7,14]][group]
    left = np.zeros(n, dtype=np.float64)
    right = np.zeros(n, dtype=np.float64)
    # Original six-second harmonic pads and quiet one-second glass notes.
    for chord, root in enumerate(roots):
        start = chord * 6
        local = t-start
        envelope = np.where((local>=0)&(local<6), np.sin(np.pi*np.clip(local/6,0,1))**1.2, 0)
        for voice, interval in enumerate(offsets):
            hz = 440 * 2**((root+interval-69)/12)
            phase = 2*np.pi*hz*t + 0.15*np.sin(2*np.pi*(voice+1)*t/24)
            pad = (np.sin(phase) + .18*np.sin(2*phase) + .08*np.sin(3*phase))*envelope
            pan = (voice-1.5)/6
            left += pad*.034*(.5-pan)
            right += pad*.034*(.5+pan)
    scale = [0,7,12,16,19,24,19,16]
    for beat in range(24):
        local = t-beat
        envelope = np.where((local>=0)&(local<2.2), np.exp(-np.clip(local,0,None)*3)*(1-np.exp(-np.clip(local,0,None)*40)),0)
        midi = roots[beat//6] + 12 + scale[(beat+group*2)%len(scale)]
        hz = 440*2**((midi-69)/12)
        bell = (np.sin(2*np.pi*hz*t)+.35*np.sin(2*np.pi*hz*2*t)+.1*np.sin(2*np.pi*hz*4*t))*envelope*.035
        p = .5+.3*math.sin(beat*1.2)
        left += bell*p
        right += bell*(1-p)
    master = np.minimum(1, t/.4)*np.minimum(1, (seconds-t)/.8)
    stereo = np.column_stack((left*master,right*master))
    peak = float(np.max(np.abs(stereo)))
    stereo *= .24/max(peak,.24)
    pcm = np.clip(np.rint(stereo*32767),-32768,32767).astype('<i2')
    with wave.open(str(path),'wb') as w:
        w.setparams((2,2,rate,0,'NONE','not compressed'))
        w.writeframes(pcm.tobytes())
    return {"rate":rate,"channels":2,"bits":16,"seconds":seconds,
            "peak_dbfs":round(20*math.log10(float(np.max(np.abs(pcm.astype(np.int32))))/32768),2),
            "rms_dbfs":round(20*math.log10(float(np.sqrt(np.mean(pcm.astype(np.float64)**2)))/32768),2),
            "description":"本次工具生成的原创合成氛围配乐，无人声，不是兰花草录音"}


def metadata(sources, sid):
    extras = json.loads((sources/'extra_sources.json').read_text(encoding='utf-8'))
    if sid == 'SDO_171_20260927':
        return {"id":sid,"page":"https://sdo.gsfc.nasa.gov/data/",
                "download":extras[sid],"credit":"NASA/SDO/AIA",
                "license":"SDO data use policy", "license_url":"https://sdo.gsfc.nasa.gov/data/rules.php"}
    if sid == 'ARROKOTH':
        return {"id":sid,"page":"https://science.nasa.gov/missions/new-horizons/nasas-new-horizons-mission-reveals-entirely-new-kind-of-world/",
                "download":extras[sid],"credit":"NASA/Johns Hopkins University Applied Physics Laboratory/Southwest Research Institute/Roman Tkachenko",
                "license":"NASA media guidelines; preserve listed image credit", "license_url":"https://www.nasa.gov/nasa-brand-center/images-and-media/"}
    if sid == 'ESA_67P':
        return {"id":sid,"page":"https://sci.esa.int/rosetta/54704-comet-67p-on-24-september-2014-navcam-mosaic/",
                "download":extras[sid],"credit":"ESA/Rosetta/NAVCAM",
                "license":"CC BY-SA 3.0 IGO", "license_url":"https://creativecommons.org/licenses/by-sa/3.0/igo/",
                "adaptation_license":"CC BY-SA 3.0 IGO"}
    item = json.loads((sources/'metadata'/f'{sid}.json').read_text(encoding='utf-8'))
    d = item['data'][0]
    download = extras.get(sid) or next(x['href'] for x in item['links'] if x.get('rel')=='preview')
    download = download.replace('~small.','~medium.').replace('~thumb.','~medium.') if sid not in extras else download
    credit = d.get('secondary_creator') or d.get('photographer') or 'NASA'
    if sid.startswith('GSFC_'):
        credit = {'GSFC_20171208_Archive_e001545':'NASA/Johns Hopkins University Applied Physics Laboratory/Carnegie Institution of Washington',
                  'GSFC_20171208_Archive_e001939':'NASA/Goddard/Arizona State University'}.get(sid,'NASA/SDO')
    if sid=='iss039e009160':credit='NASA/Rick Mastracchio'
    if sid=='PIA21395':credit='NASA/JPL-Caltech/SwRI/MSSS/Kevin M. Gill (CC BY)'
    return {"id":sid,"page":'https://images.nasa.gov/details/'+sid,
            "api":'https://images-api.nasa.gov/search?nasa_id='+sid+'&media_type=image',
            "download":download,"credit":credit,"title":d['title'],
            "license":"CC BY (version not specified in NASA item)" if sid=='PIA21395' else "NASA media guidelines; preserve listed image credit",
            "license_url":"https://www.nasa.gov/nasa-brand-center/images-and-media/"}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', type=Path, default=DEFAULT)
    ap.add_argument('--skip-music',action='store_true')
    args = ap.parse_args()
    root = args.output
    sources, media, previews = root/'素材来源', root/'TF卡内容', root/'效果预览'
    media.mkdir(parents=True, exist_ok=True)
    previews.mkdir(parents=True, exist_ok=True)
    all_sources = {sid:metadata(sources,sid) for e in ENTRIES for sid in e[0].split('+')}
    manifest = {"profile":"SOLAR24","image_count":24,"image_size":[640,480],
                "bmp":"RGB24 BI_RGB BITMAPINFOHEADER40, bottom-up",
                "runtime_layout":"FAT32 root directory, 01.BMP..24.BMP in creation order",
                "ui_reserved_regions":{"header":[0,0,639,29],"music_toast":[16,40,175,87],"fft":[0,345,639,479]},
                "topics":TOPICS,"sources":all_sources,"images":[],"music":[]}
    thumbs = []
    for i,entry in enumerate(ENTRIES):
        im = render(sources,i,entry)
        dest = media/f'{i+1:02d}.BMP'
        im.save(dest,format='BMP')
        h = dest.read_bytes()[:54]
        assert struct.unpack_from('<IiiHHI',h,14)==(40,640,480,1,24,0)
        assert dest.stat().st_size==921654
        im.save(previews/f'{i+1:02d}.png')
        ids=entry[0].split('+')
        manifest['images'].append({"file":dest.name,"title":entry[1],"caption":entry[2],
            "topic":i//6+1,"position":i%6+1,"summary_page":i%6==5,"source_ids":ids,
            "sha256":hashlib.sha256(dest.read_bytes()).hexdigest(),
            "changes":"等比缩放、展陈边框、文字图注；原照片内容不锐化、不生成补画。"+
                ("双图并置。" if len(ids)>1 else "")+("添加指向地球光点的标记。" if entry[0]=='PIA23645' else ""),
            "adaptation_license":"CC BY-SA 3.0 IGO" if entry[0]=='ESA_67P' else None})
        tile = im.resize((320,240),Image.Resampling.LANCZOS)
        tile_canvas=Image.new('RGB',(320,264),(7,13,23));tile_canvas.paste(tile,(0,0))
        ImageDraw.Draw(tile_canvas).text((8,242),f'{i+1:02d}  {entry[1]}',font=font(12),fill=(194,213,225))
        thumbs.append(tile_canvas)
    for group in range(4):
        sheet=Image.new('RGB',(960,528),(7,13,23))
        for k in range(6):sheet.paste(thumbs[group*6+k],((k%3)*320,(k//3)*264))
        sheet.save(previews/f'{group+1:02d}_{TOPICS[group]["title"]}_六图预览.jpg',quality=94)
    sheet=Image.new('RGB',(1280,1584),(7,13,23))
    for i,tile in enumerate(thumbs):sheet.paste(tile,((i%4)*320,(i//4)*264))
    sheet.save(root/'24张展陈图片总览.jpg',quality=93)
    for group in range(4):
        path=media/f'MUSIC{group+1}.WAV'
        if not args.skip_music:
            info=create_music(path,group)
        else:
            with wave.open(str(path),'rb') as w:
                pcm=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float64)
                info={"rate":w.getframerate(),"channels":w.getnchannels(),"bits":w.getsampwidth()*8,
                      "seconds":w.getnframes()/w.getframerate(),
                      "peak_dbfs":round(20*math.log10(float(np.max(np.abs(pcm)))/32768),2),
                      "rms_dbfs":round(20*math.log10(float(np.sqrt(np.mean(pcm**2)))/32768),2),
                      "description":"本次工具生成的原创合成氛围配乐，无人声，不是兰花草录音"}
        info.update(file=path.name,title=['日光回声','岩石漫步','冰环漂流','回望家园'][group],
                    sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        manifest['music'].append(info)
    credits=['太阳系特展 / SOLAR24 — 图像署名与来源','',
             '这是离线排版的展陈图，不是 FPGA 实时中文排版。四个专题各六张，第六张含专题说明。',
             '所有图均保持宽高比；未用 AI 生成照片。未声明 NASA/ESA 对本设备背书。',
             'NASA 图像不一概标为公有领域；保留单项署名并遵守 NASA 媒体使用指南。',
             '21.BMP 是 ESA 67P NAVCAM 图像的版式改编，按 CC BY-SA 3.0 IGO 共享；图像做等比缩放并叠加中文标题与边框。',
             '13.BMP 保留 Kevin M. Gill 的 CC BY 署名，NASA 条目没有说明 CC BY 的版本。','']
    for item in manifest['images']:
        credits.append(f'{item["file"]} — {item["title"]}')
        for sid in item['source_ids']:
            s=all_sources[sid]
            credits += ['  Credit: '+s['credit'],'  Source: '+s['page'],'  Use/license: '+s['license'],
                        '  Terms: '+s['license_url']]
        credits.append('  Changes: '+item['changes'])
        credits.append('')
    credits += ['音乐：MUSIC1.WAV～MUSIC4.WAV 均由本工具原创合成，无人声，无第三方录音采样。',
                '每首 24 秒，48kHz、双声道、PCM16；音量刻意较低，可循环。',
                '文案事实校订：太阳能量来自核聚变，不是化学燃烧；月背不是从未被人类目视；',
                '气态巨行星和冰巨行星应区分，不能把各层内部概括为没有尽头的大气。',
                'https://science.nasa.gov/sun/facts/',
                'https://www.nasa.gov/missions/apollo/apollo-8-mission-details/',
                'https://science.nasa.gov/jupiter/jupiter-facts/',
                'https://science.nasa.gov/uranus/facts/',
                'https://science.nasa.gov/mission/voyager/voyager-1s-pale-blue-dot/']
    (media/'CREDITS.TXT').write_text('\n'.join(credits)+'\n',encoding='utf-8-sig')
    (sources/'逐图来源与署名.txt').write_text('\n'.join(credits)+'\n',encoding='utf-8-sig')
    for sid, item in all_sources.items():
        src=photo_path(sources,sid)
        item['source_file']='素材来源/原图/'+src.name
        item['source_sha256']=hashlib.sha256(src.read_bytes()).hexdigest()
    (root/'素材清单.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (root/'素材说明.txt').write_text(
        '素材已准备在电脑桌面，尚未写入 TF 卡。\n\n'
        'TF卡内容：24张 640×480、24位未压缩 BMP；4首原创24秒氛围WAV；CREDITS.TXT。\n'
        '01～06 太阳；07～12 岩石世界；13～18 巨行星；19～24 边界与回望。\n'
        '每专题第六张自带左图右文总结；简介文字已经排入BMP，因此无需额外FPGA字库、无需第25张图。\n'
        '普通图保留主体，完整等比缩放，不拉伸。主图延伸到底部，频谱开启时只由柱子覆盖。\n'
        '上方前30行预留实时字幕/RTC；音乐提示临时占左上角，不遮主标题。\n\n'
        '重要：当前FPGA按FAT目录实际顺序分配编号，不会按文件名排序。\n'
        '请在TF卡备份完成后，按01.BMP到24.BMP的顺序逐个新建复制，之后再按顺序复制MUSIC1.WAV到MUSIC4.WAV。\n'
        '直接覆盖旧文件可能保留旧目录位置；在有其他BMP/WAV的旧卡上随意拖入会造成分组错乱。\n'
        '不要把图片放入专题子文件夹，当前主工程仅扫描根目录。不要复制原图/预览图到TF根目录。\n\n'
        '替换内容：替换同编号BMP并保持640×480 RGB24未压缩；歌曲保持48kHz双声道PCM16/24 WAV。\n'
        '改文案：编辑 tools/prepare_solar_media.py 内 TOPICS/ENTRIES，然后运行脚本重新生成素材；不需重烧FPGA。\n'
        '音乐是本次原创氛围合成音，不是《兰花草》。原有歌曲可在符合格式时替换。\n'
        '源码工具不访问TF卡；本次未格式化或写入任何移动盘。\n',encoding='utf-8-sig')
    print(json.dumps({"images":len(manifest['images']),"wavs":len(manifest['music']),
                      "bmp_bytes":24*921654,"output":str(root),"ok":True},ensure_ascii=False))


if __name__=='__main__':
    main()
