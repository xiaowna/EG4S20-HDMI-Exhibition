"""Independent fixed-point cube/raster oracle and real board-control integration."""
from pathlib import Path
import argparse,json,math,random,subprocess,tempfile
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
EDGES=[(i,i^(1<<b)) for b in range(3) for i in range(8) if not i&(1<<b)]
SINE=[round(127*math.sin(2*math.pi*n/128)) for n in range(128)]
def vertices(yaw,pitch):
 sy,cy=SINE[yaw],SINE[(yaw+32)%128];sp,cp=SINE[pitch],SINE[(pitch+32)%128]
 result=[]
 for i in range(8):
  x,y,z=[28 if i&(1<<b) else -28 for b in range(3)]
  rx=(x*cy+z*sy)//128;rz=(z*cy-x*sy)//128
  ry=(y*cp-rz*sp)//128;depth=(y*sp+rz*cp)//128
  result.append((64+rx,64-ry,depth))
 return result
def canvas(yaw,pitch):
 points=vertices(yaw,pitch);image=[0]*16384
 for a,b in EDGES:
  x,y,z=points[a];ex,ey,ez=points[b];dx,dy=abs(ex-x),abs(ey-y)
  sx=1 if x<ex else -1;sy=1 if y<ey else -1;e=dx-dy;first=True
  while True:
   image[y*128+x]=3 if first or (x==ex and y==ey) else (1 if z+ez<0 else 2)
   first=False
   if (x,y)==(ex,ey):break
   twice=2*e
   if twice>=-dy:e-=dy;x+=sx
   if twice<=dx:e+=dx;y+=sy
 return image
def pixel(x,y,image,hue=1):
 ramp=(hue&63)*4;neon=[(ramp,255,255),(255,255-ramp,255),(255-ramp,ramp,255),(0,255,255)][hue//64]
 corner=(120<=x<124 or 516<=x<520) and (40<=y<64 or 416<=y<440)
 border=(40<=y<43 or 437<=y<440) and (120<=x<144 or 496<=x<520)
 grid=y>=336 and (x%64==0 or y%32==0)
 rgb=0x267b98 if corner or border else (0x102b40 if grid else (0x0d2339 if y%256==hue and y<432 else 0x070e20))
 if 128<=x<512 and 48<=y<432:
  u,v=(x-128)//3,(y-48)//3;code=image[v*128+u]
  if code==1:r,g,b=[n//4 for n in neon];rgb=r<<16|g<<8|b
  elif code==2:rgb=0xd5ffff if (x-128)%3==1 or (y-48)%3==1 else neon[0]<<16|neon[1]<<8|neon[2]
  elif code==3:rgb=0xffffff
 return rgb
def main():
 p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
 max_bound=0
 for yaw in range(128):
  for pitch in range(128):
   v=vertices(yaw,pitch);assert all(0<=x<128 and 0<=y<128 for x,y,z in v)
   bound=16384+64+12+sum(max(abs(v[i][0]-v[j][0]),abs(v[i][1]-v[j][1]))+1 for i,j in EDGES)
   max_bound=max(max_bound,bound)
 assert max_bound<22000<56000
 logs=[];cases=[]
 with tempfile.TemporaryDirectory(prefix='cube_') as folder:
  tmp=Path(folder);rng=random.Random(45830)
  poses=[(12,10)]+[(y,p) for y in (0,32,64,96) for p in (0,32,64,96)]+[(rng.randrange(128),rng.randrange(128)) for _ in range(15)]
  (tmp/'poses.hex').write_text(''.join(f'{y<<7|p:04x}\n' for y,p in poses),encoding='ascii')
  (tmp/'canvas.hex').write_text(''.join(f'{n:x}\n' for y,p in poses for n in canvas(y,p)),encoding='ascii')
  image=canvas(12,10)
  (tmp/'pixels.hex').write_text(''.join(f'{pixel(x,y,image):06x}\n' for y in range(480) for x in range(640)),encoding='ascii')
  jobs=[('tb_scene',['video_scene3d.v'],[HERE/'tb_scene.sv']),
   ('tb_cube_board',['rtc_ds1302.v','rtc_set_control.v','hdmi_media_board_top.v','board_key.v','media_control_events.v','media_rotary_encoder.v','media_nec_receiver.v','media_infrared_control.v','media_mode_control.v','media_adjust_control.v','board_matrix_keys.v','media_home_control.v','home_album_config.v','media_3d_control.v'],[HERE/'tb_board.sv',ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv'])]
  for top,params,files in [
   ('tb_3d_matrix',{'SCAN_CYCLES':4},['tb_matrix.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv']),
   ('tb_3d_matrix',{'SCAN_CYCLES':17},['tb_matrix.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv']),
   ('tb_3d_control',{},['tb_control.sv']),('tb_3d_keys_board',{},['tb_board.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv'])]:
   bench=[HERE/{'tb_control.sv':'tb_rotation.sv','tb_board.sv':'tb_matrix_control.sv'}.get(f,f) if isinstance(f,str) else f for f in files]
   jobs.append((top,['board_matrix_keys.v','media_3d_control.v','board_key.v'],bench,params))
  for job in jobs:
   top,names,benches=job[:3];params=job[3] if len(job)>3 else {};output=''
   for cmd in [[a.tool_dir/'iverilog.exe','-g2012','-s',top,*[f'-P{top}.{k}={v}' for k,v in params.items()],'-o',tmp/'test.vvp',*[ROOT/'rtl'/n for n in names],*benches],[a.tool_dir/'vvp.exe',tmp/'test.vvp']]:
    r=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
    output+=r.stdout+r.stderr
    assert r.returncode==0 and 'FATAL' not in output,output
   assert 'PASS ' in output;print(output,end='',flush=True);logs.append(output);cases.append(top)
  with Image.open(tmp/'cube.ppm') as im:im.save(HERE/'cube_preview.png')
 (HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')
 (HERE/'summary.json').write_text(json.dumps({'status':'passed','cases':cases,'all_angle_pairs_bounded':16384,'worst_render_bound_sys_clocks':max_bound,'deadline_sys_clocks':22000,'blanking_sys_clocks':56000,'canvas_pixels_checked':524288,'raster_pixels_checked':307200,'hardware_tested':False},indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
