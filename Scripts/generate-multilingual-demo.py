#!/usr/bin/env python3
"""Generate explicit, fictional macOS-TTS inputs; never supply transcript/model output."""
import argparse,json,pathlib,subprocess,wave,hashlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'local-evaluation/multilingual-demo';OUT.mkdir(parents=True,exist_ok=True)
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--scenario',default='Tests/MultilingualDemo/scenario.json')
args=parser.parse_args()
scenario=json.loads((ROOT/args.scenario).read_text())
pcm=bytearray(bytes(32000));timeline=[]
for index,segment in enumerate(scenario['segments']):
    start=len(pcm)/32000
    parts=segment.get('parts',[segment])
    for part_index,part in enumerate(parts):
        aiff=OUT/f'{index}-{part_index}.aiff';wav=OUT/f'{index}-{part_index}.wav'
        subprocess.run(['/usr/bin/say','-v',part['voice'],'-r','155','-o',str(aiff),part['text']],check=True)
        subprocess.run(['/usr/bin/afconvert','-f','WAVE','-d','LEI16@16000','-c','1',str(aiff),str(wav)],check=True)
        with wave.open(str(wav)) as audio: pcm.extend(audio.readframes(audio.getnframes()))
        if part_index+1<len(parts): pcm.extend(bytes(int(32000*segment.get("part_pause",.25))))
    end=len(pcm)/32000
    pcm.extend(bytes(int(32000*segment['pause'])))
    timeline.append(dict(segment,start=start,end=end))
with wave.open(str(OUT/'continuous.wav'),'wb') as audio:
    audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(16000);audio.writeframes(pcm)
# Raw floats make the realtime Swift harness independent of WAV container details.
import array
floats=array.array('f',(v/32768 for v in array.array('h',pcm)))
(OUT/'continuous.f32').write_bytes(floats.tobytes())
scenario.update(timeline=timeline,duration=len(pcm)/32000,audio_sha256=hashlib.sha256((OUT/'continuous.wav').read_bytes()).hexdigest())
(OUT/'input.json').write_text(json.dumps(scenario,ensure_ascii=False,indent=2)+'\n')
print(f'Generated {scenario["duration"]:.2f}s continuous audio with five languages plus rapid alternation.')
