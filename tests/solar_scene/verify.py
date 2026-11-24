"""Independent solid sphere, orbit projection, canvas and full-raster oracle."""
from pathlib import Path
import argparse, json, math, random, subprocess, tempfile, re, hashlib
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
SINE=[round(127*math.sin(2*math.pi*n/128)) for n in range(128)]
RADII=[14,19,23,29,35,41,46,50]
BODY=[4,5,6,4,8,7,6,5,8]
ZOOM_RADII=[[11,16,20,24,30,36,41,45], RADII, [16,21,25,31,38,44,49,52]]
ZOOM_BODY=[[r-1 for r in BODY], BODY, [r+2 for r in BODY[:7]]+[9]+[BODY[8]+2]]
RING_RADII=[10,12,15]
EARTH_RADII=[14,18,22]
MOON_RADII=[6,8,10]
SIDEBAR=json.loads((ROOT/'assets/scene_sidebar.json').read_text(encoding='utf-8'))['bits']
STEPS=[32040,12543,7715,4102,650,262,92,47]
SLOW=[3204,1254,772,410,65,26,9,5]
PALETTE=[
    None,0x244456,0x515961,0x8e9394,0xc9c8bf,0x88603b,0xc89754,0xeacb86,
    0x243d66,0x417db0,0x70bfe3,0x733c39,0xbc684e,0xe99068,0x795645,0xb58969,
    0xe3c39e,0x8a704c,0xc49c64,0xe5ca93,0x417a89,0x77a89a,0xb4dce0,0x283a72,
    0x4e73b7,0x84a9e2,0xdf8d3e,0xffbb61,0xffe2a0,0x5c6269,0x9ea4a6,0xdfdfd5,
]
START=[0x680000,0xd80000,0x080000,0xba0000,0x3c0000,0x8c0000,0xf00000,0x6a0000]
def sphere_pixels(index, radius, cx, cy):
    """Direct circle equation and palette selection, independent of RTL stepping."""
    r2=radius**2
    half=radius//2
    for dy in range(-radius,radius+1):
        for dx in range(-radius,radius+1):
            d2=dx**2+dy**2
            if d2>r2:
                continue
            illumination=(-dx if cx>=64 else dx)+(-dy if cy>=64 else dy)
            shade=1
            if illumination< -half or (d2>r2-r2//4 and illumination<0):
                shade=0
            elif illumination>half and not (index==4 and dy in (-2,2,3)):
                shade=2
            coast=dx+dy//2
            land=index==2 and ((dy<0 and -half-3<=coast<=-2) or
                               (0<=dy<half and 2<=coast<=half+2))
            yield dx,dy,21 if land and shade else 2+index*3+shade

def check_geometry_contract():
    pixels=[]
    # Orthographic disk silhouettes are view-independent. Exhaust the orbit
    # projections used by each zoom, including Saturn's ring and the outer labels.
    for level,radii in enumerate(ZOOM_RADII):
        for elevation in range(1,16):
            for index,orbit in enumerate(radii):
                radius=RING_RADII[level] if index==5 else ZOOM_BODY[level][index]
                for angle in range(128):
                    x,y,_=project(orbit,angle,elevation)
                    assert radius<=x<128-radius and radius<=y<128-radius
                    assert (6 if index>=6 else 4)<=x<=(122 if index>=6 else 124)
        for index,radius in enumerate(ZOOM_BODY[level]):
            samples=list(sphere_pixels(index,radius,64,64))
            assert len(samples)==sum(2*math.isqrt(radius**2-y**2)+1 for y in range(-radius,radius+1))
            assert len({color for _,_,color in samples})>=3
            pixels.append(len(samples))
    return {'projected_orbit_positions':3*15*128*8,'smallest_solid_body_pixels':min(pixels),
            'all_zoom_silhouettes_closed':True,'ring_and_body_bounds':True}

def increment(n,speed):
    base=STEPS[n]
    return [SLOW[n],base//4,base//2,base,base*2,base*4,base*8,base*10][speed]

def project(radius,angle,elevation):
    px=radius*SINE[(angle+32)%128]//128
    z=radius*SINE[angle]//128
    py=z*SINE[elevation*2]//128
    return 64+px,64+py,z

def labels(phases,elevation,azimuth,mode=0,zoom=1):
    """Independent screen layout from projected physical body centers."""
    centers={i:project(r,((p>>17)+azimuth)%128,elevation) for i,(r,p) in enumerate(zip(ZOOM_RADII[zoom],phases))}
    centers[8]=(64,64,0)
    if mode:centers={2:(64,64,0),9:project([32,40,48][zoom],((phases[8]>>17)+azimuth)%128,elevation)}
    result=[]
    for i in sorted(centers):
        cx,cy,_=centers[i];width=12 if i in [6,7] else 8
        radius=(EARTH_RADII[zoom] if i==2 else MOON_RADII[zoom]) if mode else ZOOM_BODY[zoom][i]
        above=cy<64 or i==(2 if mode else 8)
        nx=max(0,min(128-width,cx-width//2))
        ny=max(0,min(124,cy-radius-5 if above else cy+radius+2))
        result.append(dict(index=i,native_x=nx,native_y=ny,x=16+3*nx,y=48+3*ny,width=width*3,
                           font_y=0 if i==8 else (192 if i==9 else 24+20*i)))
    return result

class Frame(list):
    def __init__(self,pixels,names):super().__init__(pixels);self.names=names

def canvas(phases,elevation,azimuth=12,zoom=1):
    radii=ZOOM_RADII[zoom]
    image=Frame([0]*16384,labels(phases,elevation,azimuth,zoom=zoom))
    for radius in radii:
        for angle in range(128):
            x,y,_=project(radius,angle,elevation)
            image[y*128+x]=1
    points=[project(r,((p>>17)+azimuth)%128,elevation) for r,p in zip(radii,phases)]+[(64,64,0)]
    # Stable depth ordering: ties are resolved in physical body index order.
    for n in sorted(range(9),key=lambda n:(points[n][2],n)):
        cx,cy,z=points[n]
        def ring(start):
            for angle in range(start,start+64,2):
                x=cx+RING_RADII[zoom]*SINE[(angle+32)%128]//128
                ring_z=RING_RADII[zoom]*SINE[angle%128]//128
                y=cy+ring_z*SINE[elevation*2]//128
                if 0<=x<128 and 0<=y<128:image[y*128+x]=19 if start==0 else 17
        if n==5:ring(64)
        for dx,dy,shade in sphere_pixels(n,ZOOM_BODY[zoom][n],cx,cy):
            x,y=cx+dx,cy+dy
            assert 0<=x<128 and 0<=y<128
            image[y*128+x]=shade
        if n==5:ring(0)
    return image

def pixel(x,y,image,mode=0,zoom=1,speed=3):
    edge=((x in (12,403)) and 44<=y<436) or ((y in (44,435)) and 12<=x<404)
    star_hash=((x^(((y&127)<<3)|(y>>7)))+(((y&31)<<5)|(y>>5)))&1023
    star=star_hash==423 and (x&3)!=0
    rgb=0x3b5363 if edge else (0x93a9b4 if star else 0x0b1420)
    if 16<=x<400 and 48<=y<432:
        code=image[((y-48)//3)*128+(x-16)//3]
        if code:rgb=PALETTE[code]
    if 432<=x<624 and (104<=y<(232 if mode else 344) or 440<=y<464):rgb=0x162737
    if 464<=x<592 and 128<=y<(192 if mode else 320):
        row=y-128+(192 if mode else 0)
        hidden=(row<12 or 192<=row<204) and x-464<32
        is_speed_atlas=any(16+20*i<=row<24+20*i for i in range(8))
        if not hidden and not is_speed_atlas and SIDEBAR[row*128+x-464]:rgb=0xe7efec
    if 464<=x<592 and 448<=y<456 and SIDEBAR[(16+20*speed+y-448)*128+x-464]:rgb=0xe7efec
    if mode and 208<=y<212 and 480<=x<560 and x%32<16:
        rgb=0x70d6bc if (x-480)//32==zoom else 0x3b5363
    for name in getattr(image,'names',[]):
        dx=x-name['x'];dy=y-name['y']
        if 0<=dx<name['width'] and 0<=dy<12:
            rgb=0xe7efec if SIDEBAR[(name['font_y']+dy)*128+4+dx] else 0x0b1420
    return rgb

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--tool-dir',type=Path,required=True)
    args=parser.parse_args()
    inputs=[ROOT/'rtl'/name for name in ('video_scene3d.v','scene_sidebar_rom.v','scene_sphere_rom.v','media_3d_control.v','audio_tone_bank.v')]
    inputs+=list(HERE.glob('*.sv'))+[Path(__file__).resolve(),ROOT/'assets/scene_sidebar.json',ROOT/'assets/scene_periods.json']
    source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    assert all(ZOOM_RADII[2][n]>ZOOM_RADII[1][n] and ZOOM_BODY[2][n]>ZOOM_BODY[1][n]
               for n in range(8)), 'zoom must enlarge every planet and its orbit'
    geometry=check_geometry_contract()
    rng=random.Random(45830)
    cases=[]
    for elevation in (10,3):
        for speed in range(8):
            phases=START if speed==3 and elevation==10 else [rng.randrange(1<<24) for _ in range(8)]
            cases.append((speed,elevation,12,phases))
    for elevation in (10,3):
        for angle in (0,32,64,96):
            cases.append((3,elevation,0,[angle<<17]*8))
    for elevation in (1,15):
        for azimuth in (0,32,64,96):
            cases.append((3,elevation,azimuth,START))
    # Grazing angles, aligned orbits, and outermost positions exercise overlap
    # and every edge of the shared 128-pixel canvas.
    for elevation in (1,3,10,15):
        for azimuth in (0,31,64,95):
            phases=[((n*7+azimuth)*131072)&0xffffff for n in range(8)]
            cases.append((3,elevation,azimuth,phases))
    zoom_levels=[1]*len(cases)
    for level in (0,2):
        for elevation,azimuth in [(1,0),(10,31),(15,0)]:
            for angle in (0,64):
                phases=START[:]
                phases[7]=((angle-azimuth)%128)<<17
                cases.append((3,elevation,azimuth,phases))
                zoom_levels.append(level)
    after=[[((p+increment(n,speed))&0xffffff) for n,p in enumerate(phases)] for speed,elevation,azimuth,phases in cases]
    assert all(increment(n,speed)>0 for n in range(8) for speed in range(8))
    logs=[]
    with tempfile.TemporaryDirectory(prefix='solar_oracle_') as folder:
        tmp=Path(folder)
        (tmp/'phase_before.hex').write_text(''.join(f'{p:06x}\n' for _,_,_,ph in cases for p in ph),encoding='ascii')
        (tmp/'phase_after.hex').write_text(''.join(f'{p:06x}\n' for ph in after for p in ph),encoding='ascii')
        (tmp/'modes.hex').write_text(''.join(f'{(z<<14)|(azimuth<<7)|(elevation<<3)|speed:x}\n'
            for (speed,elevation,azimuth,_),z in zip(cases,zoom_levels)),encoding='ascii')
        (tmp/'canvas.hex').write_text(''.join(f'{c:x}\n' for (_,elevation,azimuth,_),ph,z in zip(cases,after,zoom_levels)
            for c in canvas(ph,elevation,azimuth,zoom=z)),encoding='ascii')
        anchors=[]
        for (_,e,a,_),ph,z in zip(cases,after,zoom_levels):
            names={n['index']:n for n in labels(ph,e,a,zoom=z)}
            anchors += [(names[i]['native_y']<<7)|names[i]['native_x'] if i in names else 0 for i in range(10)]
        (tmp/'labels.hex').write_text(''.join(f'{a:04x}\n' for a in anchors),encoding='ascii')
        preview=canvas(after[3],10,12)
        (tmp/'pixels.hex').write_text(''.join(f'{pixel(x,y,preview):06x}\n' for y in range(480) for x in range(640)),encoding='ascii')
        for top,rtl,bench in [('tb_solar_scene',['video_scene3d.v','scene_sidebar_rom.v','scene_sphere_rom.v'],'tb_scene.sv'),('tb_solar_control',['media_3d_control.v'],'tb_control.sv')]:
            exe=tmp/f'{top}.vvp'
            parameters=[f'-P{top}.CASES={len(cases)}'] if top=='tb_solar_scene' else []
            cmds=[[args.tool_dir/'iverilog.exe','-g2012','-s',top,*parameters,'-o',exe,*[ROOT/'rtl'/name for name in rtl],HERE/bench],
                  [args.tool_dir/'vvp.exe',exe]]
            output=''
            for cmd in cmds:
                result=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
                output+=result.stdout+result.stderr
                if result.returncode or 'FATAL' in output:raise AssertionError(output)
            assert 'PASS ' in output,output
            print(output,end='',flush=True);logs.append(output)
        # Compile the actual FPGA branch against the public dual-port contract.
        native=(HERE/'tb_scene.sv').read_text(encoding='utf-8')
        native=native.replace('dut.phases.memory[j]', '{dut.phases.storage.memory[j*2+1][7:0],dut.phases.storage.memory[j*2]}')
        native_file=tmp/'tb_native.sv';native_file.write_text('`undef __ICARUS__\n'+native,encoding='utf-8')
        jobs=[('native_phase_binding',[args.tool_dir/'iverilog.exe','-g2012','-s','tb_solar_scene',f'-Ptb_solar_scene.CASES={len(cases)}','-o',tmp/'native.vvp',native_file,HERE/'bram32k_contract.sv',ROOT/'rtl/video_scene3d.v',ROOT/'rtl/scene_sidebar_rom.v',ROOT/'rtl/scene_sphere_rom.v'],tmp/'native.vvp')]
        jobs.append(('solid_sphere_smoke',[args.tool_dir/'iverilog.exe','-g2012','-s','tb_solar_smoke','-o',tmp/'smoke.vvp',ROOT/'rtl/video_scene3d.v',ROOT/'rtl/scene_sidebar_rom.v',ROOT/'rtl/scene_sphere_rom.v',HERE/'tb_smoke.sv'],tmp/'smoke.vvp'))
        jobs.append(('name_line_cache',[args.tool_dir/'iverilog.exe','-g2012','-s','tb_scene_label_lines','-o',tmp/'names.vvp',ROOT/'rtl/video_scene3d.v',HERE/'tb_scene_label_lines.sv'],tmp/'names.vvp'))
        (tmp/'tone48.hex').write_text(''.join(f'{round(4096*math.sin(2*math.pi*n/48))&65535:04x}\n' for n in range(48)),encoding='ascii')
        for rate in [480000,50000000]:
            exe=tmp/f'tone{rate}.vvp'
            jobs.append((f'fixed_tone_{rate}',[args.tool_dir/'iverilog.exe','-g2012','-s','tb_fixed_tone',f'-Ptb_fixed_tone.CLK_HZ={rate}','-o',exe,ROOT/'rtl/audio_tone_bank.v',HERE/'tb_fixed_tone.sv'],exe))
        for label,compile_cmd,exe in jobs:
            output=''
            for cmd in [compile_cmd,[args.tool_dir/'vvp.exe',exe]]:
                result=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
                output+=result.stdout+result.stderr
                if result.returncode or 'FATAL' in output:raise AssertionError(label+'\n'+output)
            assert 'PASS ' in output,output
            print(output,end='',flush=True);logs.append(output)
        for side in range(2):
            image=canvas(after[3],3 if side else 10,12)
            im=Image.new('RGB',(640,480))
            im.putdata([((c>>16)&255,(c>>8)&255,c&255) for y in range(480) for x in range(640) for c in [pixel(x,y,image)]])
            im.save(HERE/f'solar_{"side" if side else "top"}_preview.png')
    assert all(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest
               for name,digest in source_hashes.items()),'verification inputs changed during run; rerun on frozen sources'
    summary={'status':'passed','rendering':'Filled shaded spheres, stable occlusion, Saturn ring and orbital paths','cases':len(cases),'geometry':geometry,'canvas_pixels_checked':len(cases)*16384,
             'raster_pixels_checked':640*480,'speed_settings':[.1,.25,.5,1,2,4,8,10],
             'all_eight_orbits_move_at_every_speed':True,'four_direction_camera':True,'native_32k_port_contract_passed':True,'fixed_1khz_sample_rom_passed':True,'camera_elevation_steps':15,'camera_azimuth_steps':128,'render_sys_clocks':int(re.search(r'draw_budget=(\d+)', ''.join(logs))[1]),
             'guard_sys_clocks':45000,'blanking_sys_clocks':56000,'hardware_tested':False,'source_sha256':source_hashes}
    summary['name_labels']=dict(language='Chinese',solar=9,earth_moon=2,pixel_font_height=12,
        anchor_cases=len(cases)*9,shared_existing_sidebar_rom=True,new_ram_blocks=1,new_dsp=0,
        line_cache_exact_pixels=442368,font_busy_clocks_per_line=128,partial_line_hidden=True,
        one_pixel_clock_latency_preserved=True,extreme_pose_collision_policy='stable last-index priority')
    (HERE/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    (HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
