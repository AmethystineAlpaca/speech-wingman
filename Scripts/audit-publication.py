#!/usr/bin/env python3
"""Check the exact Git index for accidental private artifacts and common secrets.

This is a scoped guardrail, not a replacement for reviewing the staged diff.
Only relative paths and finding categories are printed, never matching secrets.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
patterns = {
    'home directory path': re.compile(rb'/(?:Users|home)/[A-Za-z0-9_.-]+'),
    'private key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'GitHub token': re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})'),
    'service key': re.compile(rb'(?:sk-(?:proj-)?[A-Za-z0-9_-]{32,}|AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{20,})'),
    'credential in URL': re.compile(rb'https?://[^\s/<>]+:[^\s/<>]+@'),
}
forbidden_parts = {'.env', '.ssh', '.tools', '.build', 'build', 'Vendor', 'local-evaluation', 'Recordings', '__pycache__'}
forbidden_suffixes = {'.wav', '.aiff', '.aif', '.mp3', '.m4a', '.flac', '.pcm', '.log', '.gguf', '.onnx', '.dylib', '.pem', '.key', '.p12', '.part'}
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
failures, total, size = [], 0, 0
for name in filter(None, paths):
    path = pathlib.PurePosixPath(name)
    if set(path.parts) & forbidden_parts or path.suffix in forbidden_suffixes or path.name.startswith('.env.'):
        failures.append((name, 'private/generated artifact'))
    mode = subprocess.check_output(['git', 'ls-files', '-s', '--', name], cwd=ROOT).decode().split()[0]
    if mode not in ('100644', '100755'):
        failures.append((name, 'unexpected symlink/submodule'))
    data = subprocess.check_output(['git', 'show', ':' + name], cwd=ROOT)
    total += 1; size += len(data)
    if len(data) > 5 * 1024 * 1024:
        failures.append((name, 'unexpected large file'))
    if path.suffix == '.png':
        # Reject textual metadata chunks; README images are newly rendered synthetic views.
        cursor = 8
        while cursor + 12 <= len(data):
            length = int.from_bytes(data[cursor:cursor+4], 'big')
            kind = data[cursor+4:cursor+8]
            if kind in (b'tEXt', b'zTXt', b'iTXt', b'eXIf'):
                failures.append((name, 'image text/EXIF metadata'))
            cursor += length + 12
    else:
        for category, pattern in patterns.items():
            if pattern.search(data): failures.append((name, category))
if not total:
    failures.append(('(index)', 'no staged files'))
for path, category in failures:
    print('FAIL: ' + path + ' — ' + category)
if failures:
    sys.exit(1)
print(f'PASS: {total} staged files; {size:,} bytes; no blocked paths, large files, common secret patterns, home paths, or image text metadata.')
print('Review license attributions, document content, screenshots, and commit identity separately before publishing.')
