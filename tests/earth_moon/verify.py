"""Independent solid Earth and Moon canvas, phase and raster checks."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, math, random, subprocess, tempfile
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('solar',ROOT/'tests/solar_scene/verify.py')
solar=importlib.util.module_from_spec(spec);spec.loader.exec_module(solar)
START=solar.START+[0x200000]

def increment(n,speed):
    if n<8:return solar.increment(n,speed)
    base=round(2**24/(27.3217*.1*(25_000_000/(800*525))))
    assert base==103162
    return [round(base/10),base//4,base//2,base,base*2,base*4,base*8,base*10][speed]

def canvas(phases,elevation,azimuth,zoom):
    image=solar.Frame([0]*16384,solar.labels(phases,elevation,azimuth,1,zoom))
    radius=[32,40,48][zoom]
    for angle in range(128):
        x,y,_=solar.project(radius,angle,elevation);image[y*128+x]=1
    centers=[(64,64,0),solar.project(radius,((phases[8]>>17)+azimuth)%128,elevation)]
    for n in sorted(range(2),key=lambda n:(centers[n][2],n)):
        cx,cy,_=centers[n]
        index,radius=(2,solar.EARTH_RADII[zoom]) if n==0 else (9,solar.MOON_RADII[zoom])
        for dx,dy,color in solar.sphere_pixels(index,radius,cx,cy):
            x,y=cx+dx,cy+dy
            assert 0<=x<128 and 0<=y<128
            image[y*128+x]=color
    return image

def geometry():
    for zoom,orbit in enumerate([32,40,48]):
        for elevation in range(1,16):
            for angle in range(128):
                x,y,_=solar.project(orbit,angle,elevation)
                radius=solar.MOON_RADII[zoom]
                assert radius<=x<128-radius and radius<=y<128-radius
    return {'projected_moon_positions':3*15*128,'earth_radii':solar.EARTH_RADII,
            'moon_radii':solar.MOON_RADII,'all_body_bounds':True}

def main():
    p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);args=p.parse_args()
    paths=[ROOT/'rtl'/n for n in ['video_scene3d.v','scene_sidebar_rom.v','scene_sphere_rom.v','media_3d_control.v','board_matrix_keys.v']]
    paths+=list(HERE.glob('*.sv'))+[Path(__file__).resolve(),ROOT/'assets/scene_sidebar.json',ROOT/'assets/scene_periods.json',ROOT/'tests/solar_scene/verify.py',ROOT/'tests/solar_scene/bram32k_contract.sv']
    digests={x.relative_to(ROOT).as_posix():hashlib.sha256(x.read_bytes()).hexdigest() for x in paths}
    proof=geometry();rng=random.Random(45830)
    cases=[(1,1,3,10,12,START)]
    cases += [(1,1,s,10,12,[0xfffff0]*9) for s in range(8)]
    cases += [(1,z,s,e,a,[rng.randrange(2**24) for _ in range(9)])
              for z in range(3) for e,a in [(1,0),(3,31),(10,64),(15,95)] for s in [0,3,7]]
    cases += [(1,2,3,e,a,[v if n!=8 else a<<17 for n,v in enumerate(START)])
              for e in [1,15] for a in [0,32,64,96]]
    cases.append((1,2,3,15,95,START))
    cases += [(0,1,3,10,12,START),(1,0,2,10,12,START),(0,1,7,1,95,START)]
    cases += [(0,z,s,e,a,[rng.randrange(2**24) for _ in range(9)])
              for z in [0,2] for e,a in [(1,0),(3,31),(10,64),(15,95)] for s in [0,3,7]]
    after=[[((v+increment(n,s))&0xffffff) for n,v in enumerate(ph)] for m,z,s,e,a,ph in cases]
    logs=[]
    def run(cmd,cwd):
        r=subprocess.run(list(map(str,cmd)),cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
        out=r.stdout+r.stderr;logs.append(out);print(out,end='',flush=True)
        assert r.returncode==0 and 'FATAL' not in out,out
    with tempfile.TemporaryDirectory(prefix='earth_moon_') as folder:
        tmp=Path(folder)
        (tmp/'phase_before.hex').write_text(''.join(f'{v:06x}\n' for *_,ph in cases for v in ph))
        (tmp/'phase_after.hex').write_text(''.join(f'{v:06x}\n' for ph in after for v in ph))
        (tmp/'modes.hex').write_text(''.join(f'{(m<<16)|(z<<14)|(a<<7)|(e<<3)|s:x}\n' for m,z,s,e,a,ph in cases))
        images=[canvas(ph,e,a,z) if m else solar.canvas(ph[:8],e,a,z) for (m,z,s,e,a,_),ph in zip(cases,after)]
        anchors=[]
        for im in images:
            names={n['index']:n for n in im.names}
            anchors += [(names[i]['native_y']<<7)|names[i]['native_x'] if i in names else 0 for i in range(10)]
        (tmp/'labels.hex').write_text(''.join(f'{a:04x}\n' for a in anchors))
        (tmp/'canvas.hex').write_text(''.join(f'{c:x}\n' for im in images for c in im))
        (tmp/'pixels.hex').write_text(''.join(f'{solar.pixel(x,y,images[0],1,1):06x}\n' for y in range(480) for x in range(640)))
        bench=(HERE/'tb_scene.sv').read_text()
        for native in [False,True]:
            text=bench
            if native:
                text='`undef __ICARUS__\n'+text
                text=text.replace('dut.phases.memory[j]','{dut.phases.storage.memory[j*2+1][7:0],dut.phases.storage.memory[j*2]}')
            tb=tmp/'bench.sv';tb.write_text(text)
            cmd=[args.tool_dir/'iverilog.exe','-g2012','-s','tb_earth_moon',f'-Ptb_earth_moon.CASES={len(cases)}','-o',tmp/'check.vvp',tb]
            if native:cmd.append(ROOT/'tests/solar_scene/bram32k_contract.sv')
            cmd += [ROOT/'rtl/video_scene3d.v',ROOT/'rtl/scene_sidebar_rom.v',ROOT/'rtl/scene_sphere_rom.v']
            run(cmd,tmp);run([args.tool_dir/'vvp.exe',tmp/'check.vvp'],tmp)
        for scan in [4,20]:
            run([args.tool_dir/'iverilog.exe','-g2012','-s','tb_earth_moon_matrix',
                 f'-Ptb_earth_moon_matrix.SCAN_CYCLES={scan}','-o',tmp/'matrix.vvp',
                 ROOT/'rtl/board_matrix_keys.v',HERE/'tb_matrix.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv'],tmp)
            run([args.tool_dir/'vvp.exe',tmp/'matrix.vvp'],tmp)
        for z in range(3):
            im=canvas(after[0],10,12,z)
            picture=Image.new('RGB',(640,480));picture.putdata([tuple(bytes.fromhex(f'{solar.pixel(x,y,im,1,z):06x}')) for y in range(480) for x in range(640)])
            picture.save(HERE/f'earth_moon_zoom{z}.png')
    assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in digests.items()),'inputs changed during run'
    result={'status':'passed','geometry':proof,'canvas_cases':len(cases),'canvas_pixels':len(cases)*16384,
            'raster_pixels':307200,'native_and_behavioral':True,'nine_phases_and_work_ram_partition':True,
            'source_sha256':digests,'hardware_tested':False}
    (HERE/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
    (HERE/'regression.log').write_text(''.join(logs))

if __name__=='__main__':main()
