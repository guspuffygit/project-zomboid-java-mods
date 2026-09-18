"""Apply one reviewed vendor patch set into a NEW output version folder.

The installed source is read-only. SHA-256 checks reject a different mod release.
Requires Python 3 and git. Does not deploy, modify game profiles or publish mods.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent

def sha(data):
    return hashlib.sha256(data).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--module', required=True, choices=['atf-core', 'lifestyle', 'error-magnifier', 'true-music-radio'])
    parser.add_argument('--source', required=True, type=Path, help='Original version folder containing media/')
    parser.add_argument('--output', required=True, type=Path, help='New folder for changed files only')
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if output.exists():
        raise SystemExit('Output must not exist; use a new folder to preserve previous copies.')
    manifest = json.loads((HERE / 'manifest.json').read_text())
    selected = [entry for entry in manifest if entry['module'] == args.module]
    originals = {}
    for entry in selected:
        path = Path(*Path(entry['path']).parts[2:])
        if path.is_absolute() or '..' in path.parts:
            raise SystemExit('Invalid patch path')
        data = (source / path).read_bytes()
        if sha(data) != entry['before']:
            raise SystemExit(f'Unsupported source version: {path}. No output written.')
        originals[path] = data.decode('utf-8-sig').replace('\r\n', '\n').encode('utf-8')
    output.parent.mkdir(parents=True, exist_ok=True)
    # Construct in a private temporary tree; publish the output only after all checks.
    with tempfile.TemporaryDirectory(prefix='vendor-fix-', dir=output.parent) as temporary:
        stage = Path(temporary) / 'version'
        for path, data in originals.items():
            target = stage / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        for entry in selected:
            patch = HERE / (Path(entry['path']).stem + '.patch')
            patch_data = patch.read_text(encoding='utf-8-sig').encode('utf-8')
            subprocess.run(['git', '-c', 'core.autocrlf=false', 'apply', '--check', '-p3'], input=patch_data, cwd=stage, check=True)
            subprocess.run(['git', '-c', 'core.autocrlf=false', 'apply', '-p3'], input=patch_data, cwd=stage, check=True)
            target = stage / Path(*Path(entry['path']).parts[2:])
            if sha(target.read_bytes()) != entry['after']:
                raise SystemExit(f'Patched content verification failed: {target.name}')
        stage.rename(output)
    print(f'Wrote {len(selected)} verified changed files to {output}')

if __name__ == '__main__':
    main()
