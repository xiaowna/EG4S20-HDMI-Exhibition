"""Verify released files against the packaged SHA256 manifest (read only)."""
from pathlib import Path
import hashlib
import json
import sys

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'PACKAGE_MANIFEST.json').read_text(encoding='utf-8'))
errors = []
for relative, record in manifest['files'].items():
    path = (root / relative).resolve()
    if not path.is_relative_to(root) or not path.is_file():
        errors.append(relative + ': missing or outside package')
    elif hashlib.sha256(path.read_bytes()).hexdigest() != record['sha256']:
        errors.append(relative + ': changed')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
print(f"PASS: {len(manifest['files'])} packaged files match SHA256")
print('Run this before project initialization; relocation intentionally changes the .al file.')
