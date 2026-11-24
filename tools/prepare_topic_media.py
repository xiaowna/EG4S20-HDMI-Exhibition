"""Prepare/check four TOPIC image folders with a shared root WAV playlist.

Copies only; never formats a drive or removes existing files. The original
flat media bundle remains the source of truth for generated font/intro assets.
"""
from pathlib import Path
import argparse,hashlib,json,shutil,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from check_demo_media import check_bmp,check_wav,check_directory,SHORT_NAME

DEFAULT=Path('media_source')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def check_topics(root):
    if not root.is_dir():raise ValueError(f'目录不存在：{root}')
    groups={p.name.upper():p for p in root.iterdir() if p.is_dir() and p.name.upper() in [f'TOPIC{i}' for i in range(1,5)]}
    if not groups:return check_directory(root,24,4)
    errors=[];total=0
    for g in range(1,5):
        folder=groups.get(f'TOPIC{g}')
        photos=sorted([p for p in folder.iterdir() if p.is_file() and p.suffix.upper()=='.BMP'],key=lambda p:p.name.upper()) if folder else []
        if len(photos)>6:errors.append(f'TOPIC{g} 有{len(photos)}张BMP；硬件最多读取前6张，请保留至多6张')
        total+=min(len(photos),6)
        print(f'TOPIC{g}：{len(photos)}张图片'+('（未建立，首页该专题不可进入）' if not folder else ''))
        for p in photos:
            try:
                if not SHORT_NAME.fullmatch(p.name.upper()):raise ValueError('请使用英文/数字短文件名，例如01.BMP')
                print(f'  {p.name}：{check_bmp(p)}')
            except (OSError,ValueError) as exc:errors.append(f'{p}: {exc}')
    music=sorted([p for p in root.iterdir() if p.is_file() and p.suffix.upper()=='.WAV'],key=lambda p:p.name.upper())
    if not 1<=len(music)<=4:errors.append('根目录需有1～4首48kHz双声道PCM WAV')
    for p in music:
        try:
            if not SHORT_NAME.fullmatch(p.name.upper()):raise ValueError('音乐请使用短文件名，例如MUSIC1.WAV')
            print(f'{p.name}：{check_wav(p)}')
        except (OSError,ValueError) as exc:errors.append(f'{p}: {exc}')
    for e in errors:print('错误：'+e)
    if not errors:print(f'通过：{total}/24张图片、{len(music)}/4首共用音乐。实际顺序按FAT目录顺序；建议按01～06顺序复制。')
    return int(bool(errors))

def prepare(source,output):
    source=source.resolve();output=output.resolve()
    if source==output or source in output.parents or output in source.parents:raise ValueError('源目录和目标目录必须彼此独立')
    pairs=[]
    for g in range(1,5):
        for n in range(1,7):pairs.append((source/f'{(g-1)*6+n:02}.BMP',output/f'TOPIC{g}'/f'{n:02}.BMP'))
    pairs += [(source/f'MUSIC{i}.WAV',output/f'MUSIC{i}.WAV') for i in range(1,5)]
    pairs += [(source/'CREDITS.TXT',output/'CREDITS.TXT')]
    # Validate every source and collision before writing any file.
    for src,dst in pairs:
        if not src.is_file():raise ValueError(f'缺少源素材：{src}')
        if src.suffix=='.BMP':check_bmp(src)
        elif src.suffix=='.WAV':check_wav(src)
        if dst.exists() and (not dst.is_file() or sha(dst)!=sha(src)):raise ValueError(f'目标已有不同内容，未覆盖：{dst}')
    records=[]
    for src,dst in pairs:
        dst.parent.mkdir(parents=True,exist_ok=True)
        if not dst.exists():shutil.copy2(src,dst)
        digest=sha(src)
        if sha(dst)!=digest:raise RuntimeError(f'复制校验失败：{dst}')
        records.append(dict(source=src.relative_to(source).as_posix(),target=dst.relative_to(output).as_posix(),bytes=src.stat().st_size,sha256=digest))
    if check_topics(output):raise RuntimeError('目标素材预检失败')
    manifest=output.parent/(output.name+'_校验清单.json')
    manifest.write_text(json.dumps(dict(status='passed',source=str(source),output=str(output),files=records,ordering='FAT directory order; copy 01..06 sequentially',image_cap=24,per_folder_cap=6,shared_root_wavs=4,card_written=False),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'已生成：{output}\n逐字节哈希相同：{len(records)}个文件；未写入任何其他磁盘。')
    return records

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,default=DEFAULT/'TF卡内容');p.add_argument('--output',type=Path,default=DEFAULT/'TF卡目录版')
    p.add_argument('--check',type=Path,help='只检查目录或TF卡，不写入')
    a=p.parse_args()
    try:
        if a.check is not None:return check_topics(a.check)
        prepare(a.source,a.output);return 0
    except (OSError,ValueError,RuntimeError) as exc:print('错误：'+str(exc),file=sys.stderr);return 1
if __name__=='__main__':raise SystemExit(main())
