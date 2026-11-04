"""Restore known options omitted by TD's GUI save, then run strict checks."""
from pathlib import Path,PureWindowsPath
import argparse,datetime,re,xml.etree.ElementTree as ET
from xml.sax.saxutils import escape
if __package__:
    from .check_project import PROJECT,TOP,check_project,check_logic_project
else:
    from check_project import PROJECT,TOP,check_project,check_logic_project

EXPECTED={
 'syn_1':[('gate','eram_init','on'),('gate','opt_area','high'),('gate','pack_effort','high')],
 'phy_1':[('place','pr_strategy','5'),('route','effort','routability')],
}

def restored_text(text,root):
    xml=ET.fromstring(re.sub(r'&(?!amp;|lt;|gt;|quot;|apos;|#\d+;|#x[0-9A-Fa-f]+;)','&amp;',text))
    if (xml.findtext('HardWare/Device')!='EG4S20BG256' or xml.findtext('TOP_MODULE/MODULE')!=TOP
        or Path(xml.attrib.get('Path','')).resolve()!=Path(root).resolve()):
        raise ValueError('Refusing to repair an unrelated device, top or project path')
    newline='\r\n' if '\r\n' in text else '\n';added=[]
    for run,options in EXPECTED.items():
        node=xml.find(f"Runs/Run[@Name='{run}']")
        if node is None:raise ValueError('Missing TD run '+run)
        params=[' '.join((p.text or '').split()) for p in node.findall('UserParams/param')]
        missing=[]
        for stage,key,value in options:
            command=f'set_param {stage} {key} {value}'
            matching=[p for p in params if re.search(r'\b'+re.escape(stage)+r'\s+'+re.escape(key)+r'\b',p)]
            # Never silently change an explicit conflicting/duplicate option.
            if matching and matching!=[command]:raise ValueError('Conflicting TD option: '+stage+' '+key)
            if not matching:missing.append(command)
        if not missing:continue
        expression=r'(<Run\b[^>]*\bName="'+re.escape(run)+r'"[^>]*>)(.*?)(</Run>)'
        matches=list(re.finditer(expression,text,re.S))
        if len(matches)!=1:raise ValueError('Ambiguous TD run '+run)
        match=matches[0];body=match[2]
        lines=''.join('                <param>'+p+'</param>'+newline for p in missing)
        if '</UserParams>' in body:
            body=body.replace('            </UserParams>',lines+'            </UserParams>',1)
        elif re.search(r'<UserParams\s*/>',body):
            body=re.sub(r'<UserParams\s*/>','<UserParams>'+newline+lines+'            </UserParams>',body,count=1)
        else:
            body+=('            <UserParams>'+newline+lines+'            </UserParams>'+newline)
        # Validate the insertion too, rather than assuming GUI indentation.
        for command in missing:
            if '<param>'+command+'</param>' not in body:raise ValueError('Unsupported UserParams layout')
        text=text[:match.start()]+match[1]+body+match[3]+text[match.end():]
        added.extend(missing)
    return text,added

def relocated_text(text,root):
    """Rebase this packaged project only after validating every local input."""
    root=Path(root).resolve()
    xml=ET.fromstring(re.sub(r'&(?!amp;|lt;|gt;|quot;|apos;|#\d+;|#x[0-9A-Fa-f]+;)','&amp;',text))
    if (xml.tag!='Project' or xml.findtext('Name')!=Path(PROJECT).stem
        or xml.findtext('HardWare/Device')!='EG4S20BG256' or xml.findtext('TOP_MODULE/MODULE')!=TOP):
        raise ValueError('Refusing to relocate an unrelated project, device or top')
    entries=xml.findall('Source_Files/*/File')
    if not entries:raise ValueError('Refusing to relocate a project without source files')
    for entry in entries:
        name=entry.attrib.get('Path','')
        if not name or Path(name).is_absolute() or PureWindowsPath(name).drive or name.startswith(('\\','/')):
            raise ValueError('Relocation requires relative project files: '+name)
        path=(root/name).resolve()
        if not path.is_relative_to(root):raise ValueError('Relocation source escapes project directory: '+name)
        if not path.is_file():raise ValueError('Relocation source file is missing: '+name)
    if Path(xml.attrib.get('Path','')).is_absolute() and Path(xml.attrib.get('Path','')).resolve()==root:return text,False
    matches=list(re.finditer(r'(<Project\b[^>]*\bPath=")([^"]*)(")',text))
    if len(matches)!=1:raise ValueError('Ambiguous TD project path')
    match=matches[0]
    value=escape(root.as_posix(),{'"':'&quot;'})
    return text[:match.start(2)]+value+text[match.end(2):],True


def prepare(root,*,logic_only=False,relocate=False):
    root=Path(root).resolve();path=root/PROJECT;original=path.read_bytes()
    text=original.decode('utf-8-sig');relocated=False
    if relocate:text,relocated=relocated_text(text,root)
    text,added=restored_text(text,root)
    checker=check_logic_project if logic_only else check_project
    if not added and not relocated:
        result=dict(checker(root),restored_options=[])
        if relocate:result['relocated']=False
        return result
    backup=root/'reports/td_gui_reopen_backups'/datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')/PROJECT
    backup.parent.mkdir(parents=True,exist_ok=True);backup.write_bytes(original)
    try:
        path.write_bytes(text.encode('utf-8'))
        result=checker(root)
    except BaseException:
        path.write_bytes(original)
        raise
    result=dict(result,restored_options=added,backup=str(backup))
    if relocate:result['relocated']=relocated
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--logic-only',action='store_true')
    p.add_argument('--relocate',action='store_true',help='Validate packaged inputs and update only this project root after extraction')
    a=p.parse_args();print('PASS prepared TD project:',prepare(a.root,logic_only=a.logic_only,relocate=a.relocate))

if __name__=='__main__':main()
