#!/usr/bin/env python3
"""Check published replay evidence without replacing or normalizing ASR output."""
import json,pathlib,re,hashlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
ASSETS=ROOT/'docs/assets'
report=json.loads((ASSETS/'multilingual-report.json').read_text())
source=json.loads((ASSETS/'multilingual-input.json').read_text())
assert report['audio_sha256']==source['audio_sha256']
assert report['response_language']=='en' and not report['errors']
finals=[e for e in report['events'] if e['final']]
assert len(finals)==10, f'Expected 10 finalized utterances, found {len(finals)}'
patterns=[r'banana',r'香蕉',r'バナナ',r'바나\s*나',r'香蕉']*2
for event,pattern in zip(finals,patterns):
    assert re.search(pattern,event['text'],re.I),event
alerts=report['alerts']
assert len(alerts)==10, f'Expected 10 alerts, found {len(alerts)}'
for alert in alerts:
    assert any(alert['quote'] in event['text'] for event in report['events']),alert
    assert not re.search(r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]',alert['suggestion']),alert
for name in ['multilingual-five-languages.gif','multilingual-mixed.gif','multilingual-continuous.mp4']:
    assert (ASSETS/name).stat().st_size>1000
summary={'synthetic_audio':True,'live_microphone_test':False,'audio_seconds':source['duration'],'languages':['English','Mandarin Chinese','Japanese','Korean','Cantonese'],'recognition_language':'auto; unchanged throughout','response_language':'English','finalized_utterances':len(finals),'alerts':len(alerts),'pipeline_errors':report['errors'],'checks':['banana meaning retained in each of ten finalized utterances','each alert quote occurs verbatim in an actual ASR event','all ten reminders use English'],'transcription_limitations':['Korean spacing/repeated syllables and Cantonese orthography are retained verbatim.','250 ms language switches in a single ASR segment lost words; see multilingual-rapid-stress.json.'],'method':report['source'],'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'Sources').rglob('*')) if p.is_file()},'packaged_worker_sha256':{name:hashlib.sha256((ROOT/'build/Speech Wingman.app/Contents/Resources'/name).read_bytes()).hexdigest() for name in ['asr-worker','text-worker']},'media_sha256':{name:hashlib.sha256((ASSETS/name).read_bytes()).hexdigest() for name in ['multilingual-five-languages.gif','multilingual-mixed.gif','multilingual-continuous.mp4']}}
(ASSETS/'multilingual-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print('PASS: 10 real ASR utterances, 10 matching alerts, five languages twice, English reminders, verbatim evidence; no pipeline errors.')
