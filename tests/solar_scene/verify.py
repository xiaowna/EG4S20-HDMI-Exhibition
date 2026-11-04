"""Independent XYZ wire-mesh, line, canvas and full-raster oracle."""
from pathlib import Path
import argparse, json, math, random, subprocess, tempfile, re, hashlib
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
SINE=[round(127*math.sin(2*math.pi*n/128)) for n in range(128)]
RADII=[9,14,20,26,34,44,52,57]
BODY=[6,7,8,6,11,10,9,7,13]
COLORS=[3,2,4,5,6,6,4,4,2]
SIDEBAR=json.loads((ROOT/'assets/scene_sidebar.json').read_text(encoding='utf-8'))['bits']
STEPS=[32040,12543,7715,4102,650,262,92,47]
SLOW=[3204,1254,772,410,65,26,9,5]
PALETTE=[None,0x1e3d4d,0xffcf69,0xb4b7bc,0x69cce8,0xe38464,0xd9c391,0xf4f3df]
START=[0x100000,0x380000,0x700000,0xa00000,0xd40000,0x5c0000,0x900000,0x180000]
# Independent XYZ sphere samples, never extracted from the RTL or its ROM.
# Three 16-segment latitude circles and four meridian halves form 64 edges.
VERTICES=[tuple(round(v) for v in (32*math.cos(math.radians(lat))*math.cos(a*math.pi/8),
          32*math.sin(math.radians(lat)),32*math.cos(math.radians(lat))*math.sin(a*math.pi/8)))
          for lat in [45,0,-45] for a in range(16)]+[(0,32,0),(0,-32,0)]
FACES=[]
for a in range(0,16,4):
    arc=[(a+k)%16 for k in range(5)]
    FACES += [(48,*arc),(*(32+n for n in arc),49)]
    for ring in range(2):FACES.append(tuple(ring*16+n for n in arc)+tuple((ring+1)*16+n for n in reversed(arc)))

# Derive edges from closed faces rather than copying the hardware edge mapper.
EDGES=sorted({tuple(sorted((u,v))) for face in FACES for u,v in zip(face,face[1:]+face[:1])})
DRAW_EDGES=[(b,a) if b==48 or (a//16==b//16 and b-a==15) else (a,b) for a,b in EDGES]

def mesh_vertices(radius,elevation,azimuth):
    """Rotate local XYZ in Q7, then round model scale directly to pixels.

    Each Q7 product rounds to nearest separately (half toward +infinity).
    Integer pixel scale is (coordinate*radius+16)//32; it deliberately avoids
    double rounding through intermediate quarter-pixel coordinates.
    """
    cy,sy=SINE[(azimuth+32)%128],SINE[azimuth]
    ce,se=SINE[(elevation*2+32)%128],SINE[elevation*2]
    points=[]
    for x,y,z in VERTICES:
        rx=(x*cy+64)//128-(z*sy+64)//128
        rz=(z*cy+64)//128+(x*sy+64)//128
        ry=(y*ce+64)//128+(rz*se+64)//128
        points.append(((rx*radius+16)//32,(ry*radius+16)//32))
    return points

def line(a,b):
    """Inclusive all-octant integer Bresenham with strict decision ties."""
    x,y=a;end_x,end_y=b
    dx=abs(end_x-x);dy=abs(end_y-y)
    sx=1 if x<end_x else -1;sy=1 if y<end_y else -1
    error=dx-dy
    while True:
        yield x,y
        if (x,y)==(end_x,end_y):break
        doubled=2*error
        if doubled>-dy:
            error-=dy;x+=sx
        if doubled<dx:
            error+=dx;y+=sy

def mesh_pixels(radius,elevation,azimuth,color):
    points=mesh_vertices(radius,elevation,azimuth)
    for a,b in DRAW_EDGES:
        for x,y in line(points[a],points[b]):yield x,y,color

def check_line_contract():
    """Small explicit goldens establish strict ties and every octant."""
    base=[(0,0),(1,0),(2,1),(3,1),(4,2)]
    for swap in (False,True):
        for sx in (-1,1):
            for sy in (-1,1):
                expected=[(sy*y,sx*x) if swap else (sx*x,sy*y) for x,y in base]
                assert list(line(expected[0],expected[-1]))==expected
    assert list(line((2,-3),(2,-3)))==[(2,-3)]
    assert list(line((0,0),(0,-3)))==[(0,0),(0,-1),(0,-2),(0,-3)]
    assert list(line((0,0),(3,0)))==[(0,0),(1,0),(2,0),(3,0)]
    assert list(line((-1,2),(2,-1)))==[(-1,2),(0,1),(1,0),(2,-1)]
    return {'eight_octants':True,'horizontal_vertical_diagonal':True,
            'zero_length':True,'strict_error_ties':True,'both_endpoints':True}

def check_geometry_contract():
    """Inspect topology/all 1920 legal poses without taking data from the DUT."""
    from collections import Counter
    edge_counts=Counter()
    for face in FACES:
        for u,v in zip(face,face[1:]+face[:1]):edge_counts[tuple(sorted((u,v)))]+=1
    assert len(VERTICES)==50 and len(VERTICES)-len(edge_counts)+len(FACES)==2 and len(EDGES)==64
    assert all(abs(math.sqrt(sum(c*c for c in p))-32)<1 for p in VERTICES)
    assert set(edge_counts.values())=={2},'model is not a closed two-manifold'
    minimum_pixels=1<<30;maximum_samples=0;worst_pose=None;collapsed=0;octants=set();ties=0
    for elevation in range(1,16):
        for azimuth in range(128):
            tiny=set((x,y) for x,y,_ in mesh_pixels(BODY[0],elevation,azimuth,3))
            assert tiny,'smallest wire body disappeared at a valid camera pose'
            minimum_pixels=min(minimum_pixels,len(tiny))
            samples=0
            for body_index,radius in enumerate(BODY):
                points=mesh_vertices(radius,elevation,azimuth)
                assert all(-radius-1<=v<=radius+1 for p in points for v in p)
                centers=[project(RADII[body_index],phase,elevation) for phase in range(128)] if body_index<8 else [(64,64,0)]
                name_width=12 if body_index in [6,7] else 8
                assert min(c[0] for c in centers)>=name_width//2,'label X would require a lower clamp'
                assert max(c[0] for c in centers)-name_width//2+name_width<=128,'label X would require an upper clamp'
                for axis in [0,1]:
                    assert min(p[axis] for p in points)+min(c[axis] for c in centers)>=0,'sphere clips at minimum orbital phase'
                    assert max(p[axis] for p in points)+max(c[axis] for c in centers)<128,'sphere clips at maximum orbital phase'
                for first,last in EDGES:
                    a,b=points[first],points[last];pixels=list(line(a,b))
                    assert pixels[0]==a and pixels[-1]==b
                    dx=b[0]-a[0];dy=b[1]-a[1]
                    assert len(pixels)==max(abs(dx),abs(dy))+1
                    assert all(max(abs(x1-x0),abs(y1-y0))==1 for (x0,y0),(x1,y1) in zip(pixels,pixels[1:]))
                    if a==b:collapsed+=1
                    elif dx and dy:octants.add((dx>0,dy>0,abs(dx)>abs(dy)))
                    if dx and dy and max(abs(dx),abs(dy))%min(abs(dx),abs(dy))==0:ties+=1
                    samples+=len(pixels)
            if samples>maximum_samples:maximum_samples=samples;worst_pose=(elevation,azimuth)
    assert len(octants)==8
    return {'model_vertices':50,'model_faces':16,'model_edges':64,'draws_all_back_and_front_edges':True,
            'closed_spherical_mesh':True,'camera_poses_checked':15*128,'all_body_orbital_phase_bounds_checked':True,
            'name_horizontal_clamp_proven_unnecessary':True,
            'smallest_body_minimum_pixels':minimum_pixels,'collapsed_projected_edges_checked':collapsed,
            'projected_edge_octants_checked':len(octants),'integer_slope_edges_checked':ties,
            'maximum_line_samples':maximum_samples,'worst_raster_pose':worst_pose,
            'line_contract':check_line_contract()}

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
    centers={i:project(r,((p>>17)+azimuth)%128,elevation) for i,(r,p) in enumerate(zip(RADII,phases))}
    centers[8]=(64,64,0)
    if mode:centers={2:(64,64,0),9:project([32,40,48][zoom],((phases[8]>>17)+azimuth)%128,elevation)}
    result=[]
    for i in sorted(centers):
        cx,cy,_=centers[i];width=12 if i in [6,7] else 8
        radius=([18,22,26][zoom] if i==2 else [8,10,12][zoom]) if mode else BODY[i]
        above=cy<64 or i==(2 if mode else 8)
        nx=max(0,min(128-width,cx-width//2))
        ny=max(0,min(124,cy-radius-5 if above else cy+radius+2))
        result.append(dict(index=i,native_x=nx,native_y=ny,x=16+3*nx,y=48+3*ny,width=width*3,
                           font_y=0 if i==8 else (192 if i==9 else 24+20*i)))
    return result

class Frame(list):
    def __init__(self,pixels,names):super().__init__(pixels);self.names=names

def canvas(phases,elevation,azimuth=12):
    image=Frame([0]*16384,labels(phases,elevation,azimuth))
    for radius in RADII:
        for angle in range(128):
            x,y,_=project(radius,angle,elevation)
            image[y*128+x]=1
    points=[project(r,((p>>17)+azimuth)%128,elevation) for r,p in zip(RADII,phases)]+[(64,64,0)]
    # Stable depth ordering: ties are resolved in physical body index order.
    for n in sorted(range(9),key=lambda n:(points[n][2],n)):
        cx,cy,z=points[n]
        def ring(start):
            for angle in range(start,start+64,2):
                x=cx+14*SINE[(angle+32)%128]//128
                ring_z=14*SINE[angle%128]//128
                y=cy+ring_z*SINE[elevation*2]//128
                if 0<=x<128 and 0<=y<128:image[y*128+x]=6
        if n==5:ring(64)
        for dx,dy,shade in mesh_pixels(BODY[n],elevation,azimuth,COLORS[n]):
            x,y=cx+dx,cy+dy
            assert 0<=x<128 and 0<=y<128
            image[y*128+x]=shade
        if n==5:ring(0)
    return image

def pixel(x,y,image,mode=0,zoom=1):
    edge=((x in (12,403)) and 44<=y<436) or ((y in (44,435)) and 12<=x<404)
    star_hash=((x^(((y&127)<<3)|(y>>7)))+(((y&31)<<5)|(y>>5)))&1023
    star=star_hash==423 and (x&3)!=0
    rgb=0x3b5363 if edge else (0x93a9b4 if star else 0x0b1420)
    if 16<=x<400 and 48<=y<432:
        code=image[((y-48)//3)*128+(x-16)//3]
        if code:rgb=0x3b596b if mode and code==3 else PALETTE[code]
    if 432<=x<624 and 104<=y<(232 if mode else 344):rgb=0x162737
    if 464<=x<592 and 128<=y<(192 if mode else 320):
        row=y-128+(192 if mode else 0)
        hidden=(row<12 or 192<=row<204) and x-464<32
        if not hidden and SIDEBAR[row*128+x-464]:rgb=0xe7efec
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
    # Additional grazing and nearly edge-on poses exercise collapsed projected
    # edges, line crossings and near-horizontal/vertical raster decisions.
    for elevation in (1,3,10,15):
        for azimuth in (0,31,64,95):
            phases=[((n*7+azimuth)*131072)&0xffffff for n in range(8)]
            cases.append((3,elevation,azimuth,phases))
    # Exhaustively chosen maximum line-sample pose. Line raster timing is
    # independent of the orbital body centers and orbital phases.
    elevation,azimuth=geometry['worst_raster_pose']
    cases.append((3,elevation,azimuth,START))
    after=[[((p+increment(n,speed))&0xffffff) for n,p in enumerate(phases)] for speed,elevation,azimuth,phases in cases]
    assert all(increment(n,speed)>0 for n in range(8) for speed in range(8))
    logs=[]
    with tempfile.TemporaryDirectory(prefix='solar_oracle_') as folder:
        tmp=Path(folder)
        (tmp/'phase_before.hex').write_text(''.join(f'{p:06x}\n' for _,_,_,ph in cases for p in ph),encoding='ascii')
        (tmp/'phase_after.hex').write_text(''.join(f'{p:06x}\n' for ph in after for p in ph),encoding='ascii')
        (tmp/'modes.hex').write_text(''.join(f'{(azimuth<<7)|(elevation<<3)|speed:x}\n' for speed,elevation,azimuth,_ in cases),encoding='ascii')
        (tmp/'canvas.hex').write_text(''.join(f'{c:x}\n' for (_,elevation,azimuth,_),ph in zip(cases,after) for c in canvas(ph,elevation,azimuth)),encoding='ascii')
        anchors=[]
        for (_,e,a,_),ph in zip(cases,after):
            names={n['index']:n for n in labels(ph,e,a)}
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
        jobs.append(('wireframe_smoke',[args.tool_dir/'iverilog.exe','-g2012','-s','tb_solar_smoke','-o',tmp/'smoke.vvp',ROOT/'rtl/video_scene3d.v',ROOT/'rtl/scene_sidebar_rom.v',ROOT/'rtl/scene_sphere_rom.v',HERE/'tb_smoke.sv'],tmp/'smoke.vvp'))
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
    summary={'status':'passed','rendering':'XYZ sphere wireframe: all 64 unique model edges; no filled faces','cases':len(cases),'geometry':geometry,'canvas_pixels_checked':len(cases)*16384,
             'raster_pixels_checked':640*480,'speed_settings':[.1,.25,.5,1,2,4,8,10],
             'all_eight_orbits_move_at_every_speed':True,'four_direction_camera':True,'native_32k_port_contract_passed':True,'fixed_1khz_sample_rom_passed':True,'camera_elevation_steps':15,'camera_azimuth_steps':128,'render_sys_clocks':int(re.search(r'draw_budget=(\d+)', ''.join(logs))[1]),
             'guard_sys_clocks':45000,'blanking_sys_clocks':56000,'hardware_tested':False,'source_sha256':source_hashes}
    summary['name_labels']=dict(language='Chinese',solar=9,earth_moon=2,pixel_font_height=12,
        anchor_cases=len(cases)*9,shared_existing_sidebar_rom=True,new_ram_blocks=1,new_dsp=0,
        line_cache_exact_pixels=442368,font_busy_clocks_per_line=128,partial_line_hidden=True,
        one_pixel_clock_latency_preserved=True,extreme_pose_collision_policy='stable last-index priority')
    (HERE/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    (HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')
    evidence=ROOT/'reports/solar_wireframe_20261024'
    evidence.mkdir(parents=True,exist_ok=True)
    (evidence/'geometry_verification.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    (evidence/'geometry_regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
