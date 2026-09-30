#!/usr/bin/env python3
"""Replay synthetic speech through the bundled pipeline with all network access denied.

--realtime feeds audio at microphone speed and starts classification on ASR final events.
This is a regression/smoke benchmark, not a real-speaker accuracy claim.
"""
import argparse
import array
import base64
import json
import os
import pathlib
import queue
import shutil
import socket
import subprocess
import sys
import threading
import time
import wave

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--realtime', action='store_true')
parser.add_argument('--inside-sandbox', action='store_true')
parser.add_argument('--cases', default='Tests/Evaluation/cases.json')
args = parser.parse_args()
if not args.inside_sandbox:
    os.execv('/usr/bin/sandbox-exec', ['sandbox-exec', '-p', '(version 1)(allow default)(deny network*)',
             sys.executable, str(pathlib.Path(__file__).resolve()), '--inside-sandbox', *sys.argv[1:]])
try:
    s = socket.socket(); s.connect(('127.0.0.1', 9))
except PermissionError:
    network_blocked = True
except OSError as error:
    raise RuntimeError('Network denial not verified: ' + str(error))
else:
    raise RuntimeError('Network unexpectedly permitted')

resources = ROOT / 'build/Speech Wingman.app/Contents/Resources'
models = resources / 'Models'
# The shipped helpers require an App Sandbox parent (inherit entitlement).
# A sandbox-exec CLI is not such a parent. Re-sign disposable copies without
# inherit, keeping the original code, models and dylibs, then apply deny network*.
workers = ROOT / 'local-evaluation/offline-workers'
workers.mkdir(exist_ok=True)
for name in ['text-worker', 'asr-worker']:
    shutil.copy2(resources / name, workers / name)
    subprocess.run(['codesign', '--remove-signature', str(workers / name)], check=True, capture_output=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(workers / name)], check=True, capture_output=True)
if not (workers / 'lib').exists(): (workers / 'lib').symlink_to(resources / 'lib')
model = json.loads((models / 'manifest-text.json').read_text())['files'][0]['file']
system = (ROOT / 'Sources/WingmanCore/PromptBuilder.swift').read_text().split('"""')[1].strip()
policy_cases = json.loads((ROOT / args.cases).read_text())
log = (ROOT / 'local-evaluation/streaming-workers.log').open('w')
text_worker = subprocess.Popen([str(workers / 'text-worker'), str(models / model)],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True)
assert json.loads(text_worker.stdout.readline())['type'] == 'ready'
records = []
try:
    for case in policy_cases:
        wav_path = ROOT / 'local-evaluation' / (case.get('audio', case['id']) + '.wav')
        if not wav_path.exists():
            raise RuntimeError('Missing synthetic fixture: ' + str(wav_path))
        with wave.open(str(wav_path)) as wav:
            assert wav.getnchannels() == 1 and wav.getsampwidth() == 2 and wav.getframerate() == 16000
            pcm = array.array('h', wav.readframes(wav.getnframes()))
        audio_seconds = len(pcm) / 16000
        samples = array.array('f', [x / 32768 for x in pcm] + [0.] * 24000)
        asr = subprocess.Popen([str(workers / 'asr-worker'), str(models)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True)
        assert json.loads(asr.stdout.readline())['type'] == 'ready'
        events, judgments, errors = [], [], []
        jobs = queue.Queue()
        began = time.monotonic()
        def receive():
            try:
                for line in asr.stdout:
                    event = json.loads(line)
                    if event['type'] == 'error': raise RuntimeError(event)
                    if event['type'] != 'transcript': continue
                    event['wall_seconds'] = time.monotonic() - began
                    events.append(event)
                    if event['final']: jobs.put(event)
            except Exception as error:
                errors.append(str(error))
            finally:
                jobs.put(None)
        def classify():
            try:
                while True:
                    event = jobs.get()
                    if event is None: return
                    time.sleep(.18)  # same final-text debounce as the UI
                    user = '提醒规则：' + case['policy'].replace('<', '\\u003c') + '\n当前发言：' + json.dumps(event['text'], ensure_ascii=False).replace('<', '\\u003c')
                    request = {'type':'evaluate', 'id':case['id'], 'system':system, 'user':user}
                    text_worker.stdin.write(json.dumps(request) + '\n'); text_worker.stdin.flush()
                    reply = json.loads(text_worker.stdout.readline())
                    if reply['type'] != 'result': raise RuntimeError(reply)
                    result = json.loads(reply['output'])
                    if result['decision'] == 'alert':
                        assert result['quote'] in event['text'] and result['quote'] and result['suggestion']
                    judgments.append({'result':result, 'inference_seconds':reply['elapsed_seconds'],
                        'wall_seconds':time.monotonic()-began})
            except Exception as error:
                errors.append(str(error))
        reader = threading.Thread(target=receive, daemon=True)
        judge = threading.Thread(target=classify, daemon=True)
        reader.start(); judge.start()
        for offset in range(0, len(samples), 1600):
            chunk = samples[offset:offset+1600]
            request = {'type':'audio', 'pcm_f32_base64':base64.b64encode(chunk.tobytes()).decode()}
            asr.stdin.write(json.dumps(request)+'\n'); asr.stdin.flush()
            if args.realtime:
                # Fixed playback clock, avoiding cumulative inference/scheduling drift.
                delay = began + min(offset+1600,len(samples))/16000 - time.monotonic()
                if delay > 0: time.sleep(delay)
        asr.stdin.write('{"type":"finish"}\n'); asr.stdin.flush()
        asr.wait(timeout=30); reader.join(timeout=30); judge.join(timeout=30)
        if reader.is_alive() or judge.is_alive(): raise RuntimeError('Worker test timed out')
        if errors: raise RuntimeError(errors)
        finals = [e for e in events if e['final']]
        actual = judgments[-1]['result']['decision'] if judgments else 'missing'
        record = {'id':case['id'], 'expected':case['expected'], 'actual':actual, 'passed':actual==case['expected'],
            'audio_seconds':audio_seconds, 'transcript':'\n'.join(e['text'] for e in finals),
            'first_text_seconds':events[0]['wall_seconds'] if events else None,
            'final_text_after_audio_seconds':finals[-1]['wall_seconds']-audio_seconds if finals and args.realtime else None,
            'decision_after_audio_seconds':judgments[-1]['wall_seconds']-audio_seconds if judgments and args.realtime else None,
            'judgments':judgments}
        records.append(record)
        print(json.dumps(record, ensure_ascii=False), flush=True)
finally:
    text_worker.stdin.close()
    text_worker.wait(timeout=10)
    log.close()
report = {'network_blocked':network_blocked,'realtime':args.realtime,'synthetic_audio':True,'records':records}
path = ROOT / 'local-evaluation' / ('streaming-realtime.json' if args.realtime else 'streaming-smoke.json')
path.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print(f'{sum(r["passed"] for r in records)}/{len(records)} decisions matched; {path}', flush=True)
if not all(r['passed'] for r in records): sys.exit(1)
