"""Independent closed-sphere geometry, shared RAM, canvas and raster checks."""
from pathlib import Path
import functools
import argparse, hashlib, importlib.util, json, math, random, subprocess, tempfile
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('solar',ROOT/'tests/solar_scene/verify.py')
solar=importlib.util.module_from_spec(spec);spec.loader.exec_module(solar)
VERTICES=[tuple(round(v) for v in (32*math.cos(math.radians(lat))*math.cos(a*math.pi/16),32*math.sin(math.radians(lat)),32*math.cos(math.radians(lat))*math.sin(a*math.pi/16))) for lat in [67.5,45,22.5,0,-22.5,-45,-67.5] for a in range(32)]+[(0,32,0),(0,-32,0)]

@functools.lru_cache(maxsize=2)
def topology(stride):
    faces=[]
    for a in range(0,32,stride):
        arc=[(a+k)%32 for k in range(stride+1)]
        faces += [(224,*arc),(*(192+n for n in arc),225)]
        for ring in range(6):faces.append(tuple(ring*32+n for n in arc)+tuple((ring+1)*32+n for n in reversed(arc)))
    edges=sorted({tuple(sorted((a,b))) for f in faces for a,b in zip(f,f[1:]+f[:1])})
    draw=[(b,a) if b==224 or (a//32==b//32 and b-a==31) else (a,b) for a,b in edges]
    return faces,edges,draw

START=solar.START+[0x200000]

def vertices(radius,elevation,azimuth):
    cy,sy=solar.SINE[(azimuth+32)%128],solar.SINE[azimuth]
    ce,se=solar.SINE[(elevation*2+32)%128],solar.SINE[elevation*2]
    points=[]
    for x,y,z in VERTICES:
        rx=(x*cy+64)//128-(z*sy+64)//128
        rz=(z*cy+64)//128+(x*sy+64)//128
        ry=(y*ce+64)//128+(rz*se+64)//128
        depth=(rz*ce+64)//128-(y*se+64)//128
        points.append(((rx*radius+16)//32,(ry*radius+16)//32,depth))
    return points

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
        points=vertices(([18,22,26] if n==0 else [8,10,12])[zoom],elevation,azimuth)
        for front in [False,True]:
            for a,b in topology(2 if n==0 else 4)[2]:
                if (points[a][2]+points[b][2]>=0)!=front:continue
                for dx,dy in solar.line(points[a][:2],points[b][:2]):
                    x,y=cx+dx,cy+dy
                    assert 0<=x<128 and 0<=y<128
                    image[y*128+x]=(4 if n==0 else 7) if front else 3
    return image

def geometry():
    from collections import Counter
    for orbit in [32,40,48]:
        assert 64-orbit>=4 and 64+(orbit*127)//128-4+8<=128,'Moon name X would require clipping'
    for stride,expected in [(2,352),(4,288)]:
        faces,edges,draw=topology(stride)
        counts=Counter(tuple(sorted((a,b))) for f in faces for a,b in zip(f,f[1:]+f[:1]))
        assert len(VERTICES)==226 and len(edges)==expected
        assert len(VERTICES)-len(edges)+len(faces)==2 and set(counts.values())=={2}
    worst=(0,None)
    for e in range(1,16):
        for a in range(128):
            for z in range(3):
                samples=0
                for r,stride in [([18,22,26][z],2),([8,10,12][z],4)]:
                    v=vertices(r,e,a)
                    assert all(-32<=c<32 for p in v for c in p[:2]),'signed-six-bit vertex overflow'
                    for u,w in topology(stride)[1]:samples+=max(abs(v[w][0]-v[u][0]),abs(v[w][1]-v[u][1]))+1
                if samples>worst[0]:worst=(samples,(e,a,z))
    return {'vertices':226,'earth_edges':352,'moon_edges':288,'closed_manifold':True,
            'moon_name_horizontal_clamp_proven_unnecessary':True,
            'longitude_samples':32,'latitude_rings':7,'legal_camera_zoom_combinations':15*128*3,
            'worst_line_samples':worst[0],'worst_pose':worst[1]}

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
    e,a,z=proof['worst_pose'];cases.append((1,z,3,e,a,START))
    cases += [(0,1,3,10,12,START),(1,0,2,10,12,START),(0,1,7,1,95,START)]
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
        images=[canvas(ph,e,a,z) if m else solar.canvas(ph[:8],e,a) for (m,z,s,e,a,_),ph in zip(cases,after)]
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
