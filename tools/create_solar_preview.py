"""Create an offline exhibit preview; it is not a recording of a physical board."""
from pathlib import Path
import argparse, importlib.util, json, sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]

def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

def main():
    p=argparse.ArgumentParser();p.add_argument('output',type=Path)
    p.add_argument('--verify-vectors',type=Path,help='Write independent Python canvas vectors for the Node VM test')
    args=p.parse_args()
    dest=args.output;pre=dest/'效果预览';pre.mkdir(parents=True,exist_ok=True)
    sys.path.insert(0,str(ROOT/'tests/home'))
    home=load('home_preview',ROOT/'tests/home/verify.py')
    solar=load('solar_preview',ROOT/'tests/solar_scene/verify.py')
    asset=json.loads((ROOT/'assets/home_assets.json').read_text(encoding='utf-8'));bits=asset['bits']
    for index in range(5):
        im=Image.new('RGB',(640,480))
        im.putdata([tuple((c>>s)&255 for s in (16,8,0)) for y in range(480) for x in range(640)
                    for c in [home.reference(x,y,0x4000|(index<<1),bits,branding=True)[0]]])
        im.save(pre/f'首页_{index+1}.png')
    for elevation,name in [(10,'俯视'),(3,'侧视')]:
        canvas=solar.canvas(solar.START,elevation,12);im=Image.new('RGB',(640,480))
        im.putdata([tuple((c>>s)&255 for s in (16,8,0)) for y in range(480) for x in range(640)
                    for c in [solar.pixel(x,y,canvas)]])
        im.save(pre/f'太阳系_{name}.png')
    html=r'''<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>星穹视界 · 三维线框作品预览</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#080e18;color:#e3ebe8;font:15px "Microsoft YaHei",sans-serif}
main{max-width:1160px;margin:auto;padding:34px 24px}h1{font-size:30px;letter-spacing:4px;margin:10px 0}p{color:#9eb3bf;line-height:1.8}
.eyebrow{font:12px monospace;color:#9ed5c2;letter-spacing:4px}.layout{display:grid;grid-template-columns:minmax(0,760px) 280px;gap:26px;margin-top:24px}
.screen{aspect-ratio:4/3;position:relative;overflow:hidden;border:1px solid #314858;border-radius:12px;background:#070e20;box-shadow:0 25px 100px #0008}
.screen>img,.screen>canvas{position:absolute;width:100%;height:100%;object-fit:contain;image-rendering:pixelated}
#canvas{display:none}
button,a{font:inherit}button{border:1px solid #344e5c;background:#142532;color:#dbece5;border-radius:8px;padding:11px 14px;cursor:pointer;transition:.2s}button:hover{border-color:#93cfba;background:#203c43}button.active{background:#254b4a;border-color:#9ed5c2}
.nav{display:flex;flex-wrap:wrap;gap:8px;margin:18px 0}.side{padding:22px;background:#101e2a;border:1px solid #2a424f;border-radius:12px}.side h2{font-size:21px;margin-top:0}.side p{font-size:13px}
.pad{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;margin:18px 0}.pad button{padding:10px 0}.small{font-size:12px;color:#7894a1}.row{display:flex;gap:6px;margin-top:9px}.row>*{flex:1}.status{font:13px monospace;color:#9ed5c2;margin:12px 0}
#toast{position:absolute;left:3%;top:8%;background:#1d353ee8;border:1px solid #598b86;border-radius:10px;padding:10px 18px;opacity:0;transition:opacity 1s}#toast.show{opacity:1}#note{display:inline-block;animation:spin 3s linear infinite;margin-right:8px;color:#9ed5c2}@keyframes spin{to{transform:rotate(360deg)}}
footer{font-size:12px;color:#77909e;margin-top:22px;line-height:1.8}a{color:#9ed5c2}#image{transition:opacity .3s}
@media(max-width:900px){.layout{grid-template-columns:1fr}.side{max-width:none}}
</style><main><div class="eyebrow">EG4S20 / SOLAR EXHIBITION</div><h1>星穹视界</h1>
<p>从太阳出发，穿过岩石世界与巨行星，抵达边界，再回望地球。</p>
<div class="nav" id="nav"></div><div class="layout"><div><div class="screen">
<img id="image" src="效果预览/首页_1.png"><canvas id="canvas" width="640" height="480"></canvas>
<div id="toast"><span id="note">♪</span><span id="track">音乐1</span></div></div><div class="row"><button id="home">KEY0 · 首页</button><button id="prev">上一张</button><button id="auto">自动浏览</button><button id="next">下一张</button></div>
<div class="status" id="status">首页 · 四个图册与一台实时太阳系仪</div></div><aside class="side"><h2 id="heading">从这里入场</h2>
<p id="help">选择上方任一专题。每个专题六幅图，第六幅带专题总结。第五项可交互观察八颗行星的公转。</p>
<div class="pad"><span></span><button data-c="up">↑ KEY14</button><span></span><button data-c="left">← KEY11</button><button data-c="reset">KEY10<br>归位</button><button data-c="right">KEY9 →</button><span></span><button data-c="down">↓ KEY6</button><span></span></div>
<div class="row"><button data-c="slower">KEY3 减速</button><button data-c="faster">KEY1 加速</button></div><div class="row"><button data-c="view">KEY2 八种视角</button></div>
<p class="small">键盘方向键转视角，R 归位，+ / − 调速。线框可看透，采用正交投影；轨道间距、天体大小与起始位置均为展陈示意。</p>
<button id="sound">开启配乐</button><audio id="audio" loop></audio></aside></div>
<footer>这是电脑离线交互预览，不是开发板实拍；天体采用 50 个 XYZ 顶点、64 条经纬线边的三维球体，使用与 RTL 相同的相机变换、正交投影、整数 Bresenham 画线、颜色、轨道及周期参数。线框内部透出背景，不填面、不隐藏背线。最终 HDMI 字幕、RTC、频谱和真实按键响应仍以上板验收为准。<br>
<a href="打开素材预览.html">查看全部 24 张素材与配乐</a> · <a href="素材来源/逐图来源与署名.txt">图像来源与署名</a></footer></main>
<script>
const $=id=>document.getElementById(id),names=['太阳','岩石世界','巨行星','边界与回望','太阳系仪'];
const radii=[9,14,20,26,34,44,52,57],sizes=[6,7,8,6,11,10,9,7,13],codes=[3,2,4,5,6,6,4,4,2],palette=['#070e20','#1e3d4d','#ffcf69','#b4b7bc','#69cce8','#e38464','#d9c391','#f4f3df'];
const vertices=__SOLAR_VERTICES__;
const edges=__SOLAR_EDGES__;
const steps=[32040,12543,7715,4102,650,262,92,47],slow=[3204,1254,772,410,65,26,9,5],rates=[.1,.25,.5,1,2,4,8,10],sin=Array.from({length:128},(_,i)=>Math.round(127*Math.sin(2*Math.PI*i/128)));
let phases=[0x100000,0x380000,0x700000,0xa00000,0xd40000,0x5c0000,0x900000,0x180000],yaw=12,elev=10,rate=3,preset=0,section=-1,index=0,automatic=false,sound=false,interval,last=0,toastTimer;
const ctx=$('canvas').getContext('2d');const stars=[];for(let y=0;y<480;y++)for(let x=0;x<640;x++)if((((x^(((y&127)<<3)|(y>>7)))+(((y&31)<<5)|(y>>5)))&1023)===423&&(x&3)!==0)stars.push([x,y]);
function project(r,a){const z=Math.floor(r*sin[a&127]/128);return [64+Math.floor(r*sin[(a+32)&127]/128),64+Math.floor(z*sin[elev*2]/128),z]}
function dot(x,y,c){ctx.fillStyle=palette[c];ctx.fillRect(128+x*3,48+y*3,3,3)}
function renderCanvas(){const image=new Uint8Array(16384),q7=p=>Math.floor((p+64)/128),scale=p=>Math.floor((p+16)/32);
 const write=(x,y,c)=>{if(x>=0&&x<128&&y>=0&&y<128)image[y*128+x]=c};
 const line=(a,b,c)=>{let [x,y]=a,[tx,ty]=b,dx=Math.abs(tx-x),dy=Math.abs(ty-y),sx=x<tx?1:-1,sy=y<ty?1:-1,error=dx-dy;
  for(;;){write(x,y,c);if(x===tx&&y===ty)break;const twice=2*error;if(twice>-dy){error-=dy;x+=sx}if(twice<dx){error+=dx;y+=sy}}};
 for(const r of radii)for(let a=0;a<128;a++){const [x,y]=project(r,a);write(x,y,1)}
 const bodies=phases.map((p,n)=>({...Object.fromEntries(['x','y','z'].map((k,i)=>[k,project(radii[n],(Math.floor(p/131072)+yaw)&127)[i]])),n}));bodies.push({x:64,y:64,z:0,n:8});bodies.sort((a,b)=>a.z-b.z||a.n-b.n);
 for(const b of bodies){function ring(start){for(let a=start;a<start+64;a+=2){const [x,y]=project(14,a);write(b.x+x-64,b.y+y-64,6)}}if(b.n===5)ring(64);
  const r=sizes[b.n],points=vertices.map(([x,y,z])=>{const rx=q7(x*sin[(yaw+32)&127])-q7(z*sin[yaw]),rz=q7(z*sin[(yaw+32)&127])+q7(x*sin[yaw]),ry=q7(y*sin[(elev*2+32)&127])+q7(rz*sin[elev*2]);return[b.x+scale(rx*r),b.y+scale(ry*r)]});
  for(const [a,c]of edges)line(points[a],points[c],codes[b.n]);
  if(b.n===5)ring(0)
 }return image}
function draw(dt){ctx.fillStyle='#070e20';ctx.fillRect(0,0,640,480);ctx.fillStyle='#8aa5b3';for(const [x,y]of stars)ctx.fillRect(x,y,1,1);ctx.strokeStyle='#24424f';ctx.strokeRect(124.5,44.5,391,391);
 for(let n=0;n<8;n++){const inc=[slow[n],steps[n]>>2,steps[n]>>1,steps[n],steps[n]*2,steps[n]*4,steps[n]*8,steps[n]*10][rate];phases[n]=(phases[n]+inc*dt*(25000000/420000))%16777216}
 const image=renderCanvas();for(let y=0;y<128;y++)for(let x=0;x<128;x++){const c=image[y*128+x];if(c)dot(x,y,c)}
 $('status').textContent=`实时太阳系仪 · ${rates[rate]}× · 方位 ${(yaw*360/128).toFixed(1)}° · 俯仰 ${(elev*360/64).toFixed(1)}°`;}
function animate(t){let dt=last?Math.min((t-last)/1000,.05):0;last=t;if(section===4)draw(dt);requestAnimationFrame(animate)}requestAnimationFrame(animate);
function notice(n){$('track').textContent='音乐'+n;$('toast').classList.add('show');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').classList.remove('show'),4000)}
function music(n){$('audio').src='TF卡内容/MUSIC'+n+'.WAV';$('audio').volume=.25;if(sound)$('audio').play().catch(()=>{});notice(n)}
function showImage(){let n=section*6+index+1;$('image').src='';$('image').src='效果预览/'+String(n).padStart(2,'0')+'_entrance.gif';$('status').textContent=names[section]+' · '+(index+1)+' / 6 · 全部图片 '+n+' / 24'}
function enter(n){section=n;index=0;automatic=false;clearInterval(interval);$('auto').textContent='自动浏览';$('canvas').style.display=n===4?'block':'none';$('image').style.display=n===4?'none':'block';$('heading').textContent=names[n];$('help').textContent=n===4?'四个方向键改变三维线框观察角度，八颗行星继续独立公转。上下5.625°—84.375°，左右环绕，速度与视角互不干扰。':'每组六幅官方来源图像，第六幅为左图右文介绍。可前后翻阅，也可自动浏览。';[...$('nav').children].forEach((b,i)=>b.classList.toggle('active',i===n));if(n===4){yaw=12;elev=10;rate=3;preset=0}else showImage();music(n<4?n+1:1)}
for(let i=0;i<5;i++){let b=document.createElement('button');b.textContent=names[i];b.onclick=()=>enter(i);$('nav').append(b)}
function command(c){if(section!==4)return;if(c==='left')yaw=(yaw+127)&127;if(c==='right')yaw=(yaw+1)&127;if(c==='up')elev=Math.min(15,elev+1);if(c==='down')elev=Math.max(1,elev-1);if(c==='reset'){yaw=12;elev=10;rate=3;preset=0}if(c==='faster')rate=Math.min(7,rate+1);if(c==='slower')rate=Math.max(0,rate-1);if(c==='view'){preset=(preset+1)&7;[yaw,elev]=[[12,10],[12,2],[0,8],[32,8],[64,8],[96,8],[12,15],[76,4]][preset]}}
document.querySelectorAll('[data-c]').forEach(b=>b.onclick=()=>command(b.dataset.c));$('prev').onclick=()=>{if(section>=0&&section<4){index=(index+5)%6;showImage()}};$('next').onclick=()=>{if(section>=0&&section<4){index=(index+1)%6;showImage()}};
$('auto').onclick=()=>{if(section<0||section===4)return;automatic=!automatic;$('auto').textContent=automatic?'暂停浏览':'自动浏览';clearInterval(interval);if(automatic)interval=setInterval(()=>$('next').click(),5000)};
$('home').onclick=()=>{section=-1;clearInterval(interval);$('audio').pause();$('canvas').style.display='none';$('image').style.display='block';$('image').src='效果预览/首页_1.png';$('status').textContent='首页 · 四个图册与一台实时太阳系仪';$('heading').textContent='从这里入场';[...$('nav').children].forEach(b=>b.classList.remove('active'))};
$('sound').onclick=()=>{sound=!sound;$('sound').textContent=sound?'关闭配乐':'开启配乐';if(sound&&section>=0)$('audio').play().catch(()=>{});else $('audio').pause()};
document.addEventListener('keydown',e=>{const map={ArrowLeft:'left',ArrowRight:'right',ArrowUp:'up',ArrowDown:'down',r:'reset',R:'reset','+':'faster','-':'slower',Enter:'view'};if(map[e.key]){e.preventDefault();command(map[e.key])}});
</script></html>'''
    html=html.replace('__SOLAR_VERTICES__',json.dumps(solar.VERTICES)).replace('__SOLAR_EDGES__',json.dumps(solar.DRAW_EDGES))
    (dest/'打开作品预览.html').write_text(html,encoding='utf-8')
    if args.verify_vectors:
        cases=[(elevation,azimuth,solar.START) for elevation in (1,3,10,15) for azimuth in (0,31,64,95)]
        cases.extend((elevation,12,solar.START) for elevation in (3,10))
        cases.extend((3,0,[angle<<17]*8) for angle in (0,32,64,96))
        vectors={'width':128,'height':128,'cases':[{'elevation':elevation,'azimuth':azimuth,'phases':phases,
                 'canvas':''.join(map(str,solar.canvas(phases,elevation,azimuth)))} for elevation,azimuth,phases in cases]}
        args.verify_vectors.parent.mkdir(parents=True,exist_ok=True)
        args.verify_vectors.write_text(json.dumps(vectors,separators=(',',':')),encoding='utf-8')
    print('Offline preview and module reference PNGs saved:',dest)

if __name__=='__main__':main()
