#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
/usr/bin/python3 - <<'PY'
import pathlib,plistlib,re,subprocess
root=pathlib.Path.cwd()
for name in ['App.entitlements','Worker.entitlements']:
    data=plistlib.loads((root/'Resources'/name).read_bytes())
    assert data.get('com.apple.security.app-sandbox') is True
    assert not data.get('com.apple.security.network.client')
    assert not data.get('com.apple.security.network.server')
for folder in ['Sources','Native']:
    for path in (root/folder).rglob('*'):
        if path.suffix in ['.swift','.cpp','.h']:
            text=path.read_text()
            assert not re.search(r'URLSession|WebSocket|NWConnection|curl_easy|\bsocket\s*\(|\bconnect\s*\(',text),str(path)
for name in ['text-worker', 'asr-worker']:
    binary=root/'build/native/bin'/name
    if binary.exists():
        symbols=subprocess.check_output(['nm','-u',str(binary)],text=True)
        assert not re.search(r'_(socket|connect|curl_easy_init|SSL_connect)\s*$',symbols,re.M)
app=root/'build/Speech Wingman.app'
if app.exists():
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    for target in [app,app/'Contents/Resources/text-worker',app/'Contents/Resources/asr-worker']:
        result=subprocess.run(['codesign','-d','--entitlements',':-',str(target)],capture_output=True,check=True)
        combined=result.stdout+result.stderr
        start=combined.find(b'<?xml')
        end=combined.find(b'</plist>',start)
        assert start>=0 and end>=0
        entitlements=plistlib.loads(combined[start:end+8])
        assert entitlements.get('com.apple.security.app-sandbox') is True
        assert not entitlements.get('com.apple.security.network.client')
        assert not entitlements.get('com.apple.security.network.server')
print('PASS: runtime source, native network symbols, sandbox entitlements, packaged signatures')
print('This is a scoped audit, not proof that all OS services make no network requests. Use evaluate-streaming.py for network-denied inference.')
PY
