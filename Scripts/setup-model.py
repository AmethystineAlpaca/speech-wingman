#!/usr/bin/env python3
"""Development-only downloader. Never included in the application runtime."""
import argparse
import concurrent.futures
import hashlib
import json
import pathlib
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFESTS = {'text': 'manifest-text.json', 'asr': 'manifest-asr.json', 'vad': 'manifest-vad.json'}

def hash_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()

def download_attempt(manifest, item):
    name = item['file']
    expected = item['sha256']
    size = item['size']
    output = ROOT / 'Models' / name
    output.parent.mkdir(exist_ok=True)
    if output.exists() and output.stat().st_size == size:
        digest = hash_file(output)
        if digest == expected:
            return {'file': name, 'size': size, 'sha256': digest}
    partial = output.with_suffix('.part')
    offset = partial.stat().st_size if partial.exists() else 0
    # Different offsets must not reuse a cached redirect for an earlier Range request.
    url = item.get("url") or f"https://huggingface.co/{manifest['source']}/resolve/{manifest['revision']}/{name}?download=true&offset={offset}"
    request = urllib.request.Request(url, headers={'Range': f'bytes={offset}-'} if offset else {})
    with urllib.request.urlopen(request, timeout=120) as response:
        if response.status == 206 and not response.headers.get('Content-Range', '').startswith(f'bytes {offset}-'):
            raise RuntimeError(f'{name}: incorrect resume range')
        if response.status != 206:
            offset = 0
        with partial.open('ab' if offset else 'wb') as stream:
            count = offset
            last = time.monotonic()
            while chunk := response.read(1024 * 1024):
                stream.write(chunk)
                count += len(chunk)
                if time.monotonic() - last > 20:
                    print(f'{name}: {count / size:.0%} ({count // 1048576} MiB)', flush=True)
                    last = time.monotonic()
    if partial.stat().st_size != size:
        raise RuntimeError(f'{name}: incomplete download')
    digest = hash_file(partial)
    if digest != expected:
        raise RuntimeError(f'{name}: SHA-256 mismatch')
    partial.replace(output)
    print(f'{name}: verified', flush=True)
    return {'file': name, 'size': size, 'sha256': digest}

def download(manifest, item):
    for attempt in range(5):
        try:
            return download_attempt(manifest, item)
        except (OSError, RuntimeError, urllib.error.URLError) as error:
            if attempt == 4:
                raise
            print(f"{item['file']}: {error}; retrying from saved partial download", flush=True)
            time.sleep(2)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Download and verify pinned offline models.')
    parser.add_argument('--model', choices=['all', *MANIFESTS], default='all')
    args = parser.parse_args()
    for key in MANIFESTS if args.model == 'all' else [args.model]:
        manifest = json.loads((ROOT / 'Models' / MANIFESTS[key]).read_text())
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            list(executor.map(lambda item: download(manifest, item), manifest['files']))
        if key == 'text':
            license_url = f"https://huggingface.co/Qwen/{manifest['model']}/resolve/{manifest['original_revision']}/LICENSE"
            with urllib.request.urlopen(license_url, timeout=60) as response:
                (ROOT / 'Models' / f"LICENSE-{manifest['model']}.txt").write_bytes(response.read())
        print(f"{manifest['model']}: all pinned resources verified", flush=True)
