"""Clone established independent protocol oracles; add signature-specific coverage."""
from pathlib import Path
import hashlib,json
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
provenance={}

boot_path=ROOT/'tests/bpb_width/tb_bpb_width.sv'
s=boot_path.read_text(encoding='utf-8-sig');provenance[str(boot_path.relative_to(ROOT))]=hashlib.sha256(boot_path.read_bytes()).hexdigest()
s=s.replace('module tb_bpb_width;','module tb_signature_boot;\n parameter integer SHARED=0;')
s=s.replace('parameter integer TIMEOUT_CYCLES=800;','parameter integer TIMEOUT_CYCLES=800;\n wire [255:0] bpb_fields,old_bpb_fields;\n wire [128:0] bpb_result,old_bpb_result;\n fat32_bpb_math math_new(.clk(clk),.bpb_fields(bpb_fields),.bpb_result(bpb_result));\n fat32_bpb_math_baseline math_old(.clk(clk),.bpb_fields(old_bpb_fields),.bpb_result(old_bpb_result));')
s=s.replace('fat32_boot_parser #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) dut(.bpb_fields(),.bpb_result(129\'d0),.*);',
 'fat32_boot_parser #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.SHARED_BPB(SHARED)) dut(.*);')
s=s.replace('fat32_boot_parser_baseline #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) baseline(',
 'fat32_boot_parser_baseline #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.SHARED_BPB(SHARED)) baseline(\n  .bpb_fields(old_bpb_fields),.bpb_result(old_bpb_result),')
s=s.replace('if(public_outputs!==old_outputs) begin','if(bpb_fields!==old_bpb_fields)fail("all 256 bpb_fields bits differ from frozen RTL");\n  if(public_outputs!==old_outputs) begin')
anchor='  // All eight legal SPC powers, both FAT counts, and mirroring/active FAT modes.'
assert anchor in s
s=s.replace(anchor,'''  // Every encoded low/high signature byte, with independent good-sector oracle.
  for(i=0;i<2;i=i+1)for(j=0;j<256;j=j+1)begin
   make_bpb(70000,8,2,2);sector[510+i]=j;
   run_sector($sformatf("signature byte=%0d value=%0d",i,j),j%2);
  end
'''+anchor,1)
s=s.replace('PASS: BPB width timeout=%0d scenarios=', 'PASS signature boot SHARED=%0d timeout=%0d scenarios=')
s=s.replace('TIMEOUT_CYCLES,scenarios,accepted,completed,aborted,reset_pulses,success_count,failure_count,cycles);',
 'SHARED,TIMEOUT_CYCLES,scenarios,accepted,completed,aborted,reset_pulses,success_count,failure_count,cycles);')
s=s.replace('public_bits=204','public_bits=460 signature_mutations=512')
(HERE/'tb_signature_boot.sv').write_text(s,encoding='utf-8')

mbr_path=ROOT/'tests/mbr_stream/tb_mbr_stream.sv'
s=mbr_path.read_text(encoding='utf-8-sig');provenance[str(mbr_path.relative_to(ROOT))]=hashlib.sha256(mbr_path.read_bytes()).hexdigest()
s=s.replace('module tb_mbr_stream;','module tb_signature_locator;\n parameter integer SHARED=0;')
s=s.replace('parameter integer TIMEOUT_CYCLES=800;','parameter integer TIMEOUT_CYCLES=800;\n wire [255:0] bpb_fields,old_bpb_fields;\n wire [128:0] bpb_result,old_bpb_result;\n fat32_bpb_math math_new(.clk(clk),.bpb_fields(bpb_fields),.bpb_result(bpb_result));\n fat32_bpb_math_baseline math_old(.clk(clk),.bpb_fields(old_bpb_fields),.bpb_result(old_bpb_result));')
s=s.replace('fat32_volume_locator #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) dut(.bpb_fields(),.bpb_result(129\'d0),.*);',
 'fat32_volume_locator #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.SHARED_BPB(SHARED)) dut(.*);')
s=s.replace('fat32_volume_locator_baseline #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) baseline(',
 'fat32_volume_locator_baseline #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.SHARED_BPB(SHARED)) baseline(\n  .bpb_fields(old_bpb_fields),.bpb_result(old_bpb_result),')
s=s.replace('if(public_outputs!==old_outputs) begin','if(bpb_fields!==old_bpb_fields)fail("all 256 bpb_fields bits differ from frozen RTL");\n  if(public_outputs!==old_outputs) begin')
anchor='  // Every table position, both accepted kinds, both accepted statuses.'
assert anchor in s
s=s.replace(anchor,'''  // Both superfloppy and MBR: every possible byte at each signature position.
  for(i=0;i<2;i=i+1)for(j=0;j<2;j=j+1)for(n=0;n<256;n=n+1)begin
   if(i==0)make_mbr();else make_bpb(70000,8);
   sector[510+j]=n;
   run_sector($sformatf("signature format=%0d byte=%0d value=%0d",i,j,n),n%2,n%3==0);
  end
'''+anchor,1)
s=s.replace('PASS MBR timeout=%0d scenarios=', 'PASS signature locator SHARED=%0d timeout=%0d scenarios=')
s=s.replace('TIMEOUT_CYCLES,scenarios,completed,oracle_successes,oracle_failures,resets,cycles);',
 'SHARED,TIMEOUT_CYCLES,scenarios,completed,oracle_successes,oracle_failures,resets,cycles);')
s=s.replace('public_bits=101','public_bits=357 signature_mutations=1024')
(HERE/'tb_signature_locator.sv').write_text(s,encoding='utf-8')
(HERE/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n',encoding='utf-8')
print('Prepared standalone independent oracles + exhaustive signature mutations.')
