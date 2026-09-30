#!/usr/bin/env python3
"""Development-only installer for pinned native ASR libraries and notices."""
import hashlib
import io
import json
import pathlib
import tarfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEST = ROOT / 'Vendor' / 'sherpa-onnx'
MANIFEST = ROOT / 'Resources' / 'asr-runtime.json'

def fetch(url, sha256):
    data = urllib.request.urlopen(url, timeout=120).read()
    if hashlib.sha256(data).hexdigest() != sha256:
        raise RuntimeError('SHA-256 mismatch: ' + url)
    return data

if __name__ == '__main__':
    manifest = json.loads(MANIFEST.read_text())
    DEST.mkdir(parents=True, exist_ok=True)
    needed = [item for item in manifest['files'] if not (DEST / item['file']).is_file()
              or hashlib.sha256((DEST / item['file']).read_bytes()).hexdigest() != item['sha256']]
    if any(item['file'].startswith('lib/') for item in needed):
        blob = fetch(manifest['archive_url'], manifest['archive_sha256'])
        with tarfile.open(fileobj=io.BytesIO(blob), mode='r:bz2') as archive:
            for item in needed:
                if not item['file'].startswith('lib/'):
                    continue
                members = [m for m in archive.getmembers() if m.name.endswith('/' + item['file']) and m.isfile()]
                if len(members) != 1:
                    raise RuntimeError('Missing runtime file: ' + item['file'])
                data = archive.extractfile(members[0]).read()
                if hashlib.sha256(data).hexdigest() != item['sha256']:
                    raise RuntimeError('Runtime file mismatch')
                path = DEST / item['file']; path.parent.mkdir(exist_ok=True)
                path.write_bytes(data)
    for item in needed:
        if 'url' in item:
            (DEST / item['file']).write_bytes(fetch(item['url'], item['sha256']))
    print('Verified sherpa-onnx ' + manifest['version'] + ' and ONNX Runtime ' + manifest['onnxruntime'])
