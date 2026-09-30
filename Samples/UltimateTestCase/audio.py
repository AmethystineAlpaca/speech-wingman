#!/usr/bin/env python3
"""Generate and transcribe ONE uninterrupted, fictional bilingual recording offline."""
import argparse, array, base64, hashlib, json, os, pathlib, re, socket, subprocess, sys, tempfile, time, wave
HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parents[1]
p=argparse.ArgumentParser(); p.add_argument('--inside-sandbox',action='store_true'); p.add_argument('--output',type=pathlib.Path,default=ROOT/'local-evaluation/ultimate'); a=p.parse_args()
if not a.inside_sandbox:
    os.execv('/usr/bin/sandbox-exec',['sandbox-exec','-p','(version 1)(allow default)(deny network*)',sys.executable,str(__file__),'--inside-sandbox',*sys.argv[1:]])
try:
    with socket.socket() as s: s.connect(('127.0.0.1',9))
except PermissionError: pass
else: raise RuntimeError('Network denial not verified')
a.output.mkdir(parents=True,exist_ok=True)
scenario=json.loads((HERE/'scenario.json').read_text()); digest=hashlib.sha256((HERE/'scenario.json').read_bytes()).hexdigest()
wavefile=a.output/'ultimate.wav'; timingfile=a.output/'timing.json'
if not wavefile.exists() or not timingfile.exists() or json.loads(timingfile.read_text()).get('scenario_sha256')!=digest:
    pcm=bytearray(); spans=[]
    with tempfile.TemporaryDirectory() as tmp:
        tmp=pathlib.Path(tmp)
        for block in scenario['blocks']:
            start=len(pcm)/32000
            for part in block['parts']:
                # Keep code-switching inside a single TTS utterance when possible.
                voice='Tingting' if re.search(r'[\u4e00-\u9fff]',part['text']) else 'Samantha'
                subprocess.run(['/usr/bin/say','-v',voice,'-r','205','-o',str(tmp/'part.aiff'),part['text']],check=True)
                subprocess.run(['/usr/bin/afconvert','-f','WAVE','-d','LEI16@16000','-c','1',str(tmp/'part.aiff'),str(tmp/'part.wav')],check=True)
                with wave.open(str(tmp/'part.wav')) as w: raw=w.readframes(w.getnframes())
                samples=array.array('h',raw)
                # Remove TTS-generated edge silence so configured breaths are reproducible.
                voiced=[i for i,v in enumerate(samples) if abs(v)>180]
                if voiced: samples=samples[max(0,voiced[0]-320):min(len(samples),voiced[-1]+321)]
                pcm.extend(samples.tobytes()); pcm.extend(bytes(round(part['pause_after']*16000)*2))
            spans.append({'id':block['id'],'start':start,'end':len(pcm)/32000})
            print('Synthesized',block['id'],round(spans[-1]['end'],1),flush=True)
    with wave.open(str(wavefile),'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(pcm)
    timingfile.write_text(json.dumps({'scenario_sha256':digest,'audio_seconds':len(pcm)/32000,'spans':spans,'network_blocked':True},indent=2)+'\n')
with wave.open(str(wavefile)) as w: pcm=array.array('h',w.readframes(w.getnframes()))
samples=array.array('f',(v/32768 for v in pcm)); samples.extend([0.]*32000)
events=[]; began=time.monotonic()
with (a.output/'asr.stderr.log').open('w') as log:
    proc=subprocess.Popen([str(ROOT/'build/native/bin/asr-worker'),str(ROOT/'Models')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,text=True)
    assert json.loads(proc.stdout.readline())['type']=='ready'
    # Wait for each ack: bounded transport; preserve the audio clock, not wall-clock speed.
    for offset in range(0,len(samples),1600):
        proc.stdin.write(json.dumps({'type':'audio','pcm_f32_base64':base64.b64encode(samples[offset:offset+1600].tobytes()).decode()})+'\n'); proc.stdin.flush()
        while True:
            ev=json.loads(proc.stdout.readline())
            if ev['type']=='error': raise RuntimeError(ev)
            if ev['type']=='ack': break
            if ev['type']=='transcript':
                events.append(ev)
                if ev['final']: print('ASR',round(ev['audio_seconds'],1),ev['text'],flush=True)
    proc.stdin.write('{"type":"finish"}\n');proc.stdin.flush()
    for line in proc.stdout:
        ev=json.loads(line)
        if ev['type']=='error':raise RuntimeError(ev)
        if ev['type']=='transcript':events.append(ev)
    assert proc.wait(timeout=20)==0
(a.output/'events.json').write_text(json.dumps(events,ensure_ascii=False,indent=2)+'\n')
metadata={'network_blocked':True,'scenario_sha256':digest,'wav_sha256':hashlib.sha256(wavefile.read_bytes()).hexdigest(),'asr_worker_sha256':hashlib.sha256((ROOT/'build/native/bin/asr-worker').read_bytes()).hexdigest(),'asr_wall_seconds':time.monotonic()-began,'finals':sum(e['final'] for e in events),'partials':sum(not e['final'] for e in events),'mode':'continuous PCM / accelerated ASR / audio-clock trace'}
(a.output/'audio-metadata.json').write_text(json.dumps(metadata,indent=2)+'\n');print(metadata,flush=True)
