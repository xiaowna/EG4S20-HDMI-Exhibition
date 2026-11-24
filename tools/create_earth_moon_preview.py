"""Render exact integer-oracle frames; these are not recordings of the board."""
from pathlib import Path
import argparse, importlib.util, json
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('output',type=Path);args=parser.parse_args()
    spec=importlib.util.spec_from_file_location('earth_moon',ROOT/'tests/earth_moon/verify.py')
    model=importlib.util.module_from_spec(spec);spec.loader.exec_module(model)
    dest=args.output;dest.mkdir(parents=True,exist_ok=True)
    def render(mode,zoom,elevation,azimuth,phases):
        canvas=model.canvas(phases,elevation,azimuth,zoom) if mode else model.solar.canvas(phases[:8],elevation,azimuth)
        im=Image.new('RGB',(640,480))
        im.putdata([tuple((c>>n)&255 for n in (16,8,0)) for y in range(480) for x in range(640)
                    for c in [model.solar.pixel(x,y,canvas,mode,zoom)]])
        return im
    render(0,1,10,12,model.START).save(dest/'太阳系_公转周期.png')
    for zoom in range(3):render(1,zoom,3,0,model.START).save(dest/f'地月模型_缩放{zoom+1}.png')
    frames=[]
    for n in range(36):
        phases=model.START.copy();phases[8]=(phases[8]+n*4*131072)&0xffffff
        frames.append(render(1,n//12,[10,3,15][n//12],(12+n*2)%128,phases))
    frames[0].save(dest/'地月模型_旋转与缩放_软件参考.gif',save_all=True,append_images=frames[1:],duration=100,loop=0,optimize=False,disposal=2)
    (dest/'说明.txt').write_text('软件逐像素参考，不是开发板录像。GIF依次展示三档缩放、不同观察角度；实际球体转动由按键控制，月球自动公转。\n',encoding='utf-8')
    (dest/'地月与周期预览.html').write_text('''<!doctype html><meta charset="utf-8"><title>星穹视界 · 地月与周期</title>
<style>body{margin:32px;background:#070e20;color:#d6e5e8;font:16px Microsoft YaHei,sans-serif}main{max-width:1320px;margin:auto}img{width:min(100%,640px);border:1px solid #24424f}p{line-height:1.8;color:#9cb8c4}a{color:#8bd4c4}</style>
<main><h1>星穹视界 · 三维球体与随动星名</h1><p>软件逐像素参考，实板效果请下载新版主程序验证。KEY5切换太阳系/地月；KEY14上、KEY6下、KEY11左、KEY9右；KEY7缩小、KEY8放大，KEY1加速、KEY3减速，KEY10归位。红外0040上、0019下、0007左、0009右也可旋转两种模型。首页仍为五项。</p>
<img src="地月模型_旋转与缩放_软件参考.gif" alt="地月球体旋转与缩放"><img src="太阳系_公转周期.png" alt="太阳系与八大行星周期">
<p>太阳系、地球和月球都用实心球体与分层明暗呈现。中文星名使用清晰12px字形，随投影位置移动，贴近画框时钳位；默认九个标签互不重叠，极端观察角度可能相互遮挡并按固定优先级显示。正交投影，天体大小与间距为展陈示意，初始位置不代表当前星历。公转周期为平均恒星周期；月球27.3217天与朔望月29.53天不同。</p>
<p>数据：<a href="https://ssd.jpl.nasa.gov/planets/phys_par.html">NASA/JPL行星物理参数</a> · <a href="https://nssdc.gsfc.nasa.gov/planetary/factsheet/moonfact.html">NASA月球事实表</a></p></main>''',encoding='utf-8')
    print('Saved exact-oracle previews:',dest)

if __name__=='__main__':main()
