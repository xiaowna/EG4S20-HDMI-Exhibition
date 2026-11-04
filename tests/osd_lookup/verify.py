"""Cycle-exact OSD comparison against the frozen four-key version."""
import argparse,hashlib,json,re,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tool-dir',type=Path,required=True);p.add_argument('--candidate',type=Path);p.add_argument('--log-name',default='regression.log')
 args=p.parse_args();candidate=(args.candidate or ROOT/'rtl/video_scroll_osd.v').resolve();before=ROOT/'reports/osd_lookup_20261018/before/worktree/rtl/video_scroll_osd.v';tools=args.tool_dir.resolve()
 hashes={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in [candidate,before]};logs=[];runs=[]
 try:
  with tempfile.TemporaryDirectory(prefix='osd_lookup_') as temp:
   temp=Path(temp);old=before.read_text(encoding='utf-8-sig');old=re.sub(r'\bvideo_scroll_osd\b','video_scroll_osd_reference',old)
   # Palette is intentionally revised; preserve the frozen reference logic.
   palette={'ffffff': 'e7efec', 'ffe040': 'f0b877', '184058': '203f47', '101820': '162737', '80e8ff': 'b6e7d7'}
   old=re.sub(r"24'h([0-9a-fA-F]{6})",lambda m:"24'h"+palette.get(m[1].lower(),m[1]),old)
   reference=temp/'reference.v';reference.write_text(old,encoding='utf-8')
   ports=['clk','rst_n','de','vsync','rgb','image_count','image_index','paused','wav_found','catalog_ready','image_valid','settings_word']
   extra="\n wire [23:0] __old_rgb;wire [9:0] __old_x,__old_y;\n video_scroll_osd_reference #(.SETTINGS_UI(SETTINGS_UI)) __old("+','.join('.'+n+'('+n+')' for n in ports)+',.rgb_out(__old_rgb),.pixel_x(__old_x),.pixel_y(__old_y));\n'
   extra+="integer __checks=0;always @(posedge clk or negedge clk)begin #2;if(rst_n===1'b1)begin __checks=__checks+1;if({rgb_out,pixel_x,pixel_y}!=={__old_rgb,__old_x,__old_y})$fatal(1,\"OSD public-output mismatch %m xy=%0d,%0d expected=%h actual=%h\",pixel_x,pixel_y,__old_rgb,rgb_out);end end\n"
   extra+='final $display("EQUIV OSD %m checks=%0d",__checks);\n'
   if 'function font_pixel;' in candidate.read_text(encoding='utf-8-sig'):
    extra+="integer __g,__r,__c;reg [7:0] __row;initial begin for(__g=0;__g<32;__g=__g+1)for(__r=0;__r<8;__r=__r+1)begin __row=__old.font_row(__g,__r);for(__c=0;__c<8;__c=__c+1)if(font_pixel(__g,__r,__c)!==__row[7-__c])$fatal(1,\"font bitmap mismatch %m glyph=%0d row=%0d col=%0d\",__g,__r,__c);end $display(\"PASS all 2048 font bits %m\");end\n"

   source=temp/'candidate.v';source.write_text('`timescale 1ns/1ps\n'+candidate.read_text(encoding='utf-8-sig').replace('endmodule',extra+'endmodule'),encoding='utf-8')
   cases=[('tb_video_scroll_osd',ROOT/'tests/osd/tb_video_scroll_osd.sv'),('tb_settings_osd',ROOT/'tests/four_key/tb_settings_osd.sv'),('tb_osd_edges',HERE/'tb_osd_edges.sv')]
   for top,bench in cases:
    if top=='tb_video_scroll_osd':
     # This legacy test places the raster registers directly. Mirror the same
     # test stimulus into the frozen instance, without changing its oracle.
     text=bench.read_text(encoding='utf-8-sig')
     for coord in ['x','y']:
      statement='dut.active_'+coord+' = '+coord+';'
      assert text.count(statement)==1
      text=text.replace(statement,statement+' dut.__old.active_'+coord+' = '+coord+';')
     bench=temp/'legacy.sv';bench.write_text(text,encoding='utf-8')
    print('RUN '+top,flush=True);logs.append('RUN '+top+'\n');image=temp/'check.vvp'
    for i,cmd in enumerate([[tools/'iverilog.exe','-g2012','-s',top,'-o',image,source,reference,bench],[tools/'vvp.exe',image]]):
     result=subprocess.run(list(map(str,cmd)),cwd=temp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
     out=result.stdout+result.stderr;logs.append(out);print(out,end='',flush=True)
     assert result.returncode==0 and 'FATAL' not in out,top
     if i==1:
      checks=[int(n) for n in re.findall(r'EQUIV OSD .* checks=(\d+)',out)];assert checks and min(checks)>0 and 'PASS' in out
      runs.append({'top':top,'comparisons':sum(checks)})
  for f,d in hashes.items():assert hashlib.sha256(Path(f).read_bytes()).hexdigest()==d,f
  summary={'passed':True,'source_sha256':hashes,'runs':runs,'comparisons':sum(n['comparisons'] for n in runs)}
  (HERE/('summary.json' if args.log_name=='regression.log' else Path(args.log_name).stem+'_summary.json')).write_text(json.dumps(summary,indent=2),encoding='utf-8');print('PASS OSD lookup equivalence: '+str(summary['comparisons'])+' public output comparisons',flush=True)
 finally:(HERE/args.log_name).write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
