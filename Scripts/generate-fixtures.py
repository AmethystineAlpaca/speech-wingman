#!/usr/bin/env python3
# coding: utf-8
"""Create fictional evaluation WAV files with installed macOS voices, without network access."""
import argparse
import json
import pathlib
import re
import subprocess
import tempfile
import wave

ROOT = pathlib.Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'local-evaluation')
    parser.add_argument('--voice-en', default='Samantha')
    parser.add_argument('--voice-zh', default='Tingting')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    cases = []
    for name in ['cases.json', 'heldout.json']:
        cases.extend(json.loads((ROOT / 'Tests/Evaluation' / name).read_text()))
    missing = [c for c in cases if not (args.output / (c['id'] + '.wav')).exists()]
    if not missing:
        print('All fictional fixtures already exist; no files changed.')
        return
    voices = subprocess.check_output(['/usr/bin/say', '-v', '?'], text=True)
    for voice in [args.voice_en, args.voice_zh]:
        if not re.search(r'^' + re.escape(voice) + r'\s', voices, re.M):
            raise SystemExit('Voice unavailable: ' + voice + '. Select an installed voice or install it in macOS settings first.')
    sandbox = ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)']
    with tempfile.TemporaryDirectory(prefix='wingman-fixtures-') as work:
        work = pathlib.Path(work)
        def synthesize(text, language):
            aiff, wav = work / 'speech.aiff', work / 'speech.wav'
            voice = args.voice_en if language == 'en' else args.voice_zh
            subprocess.run([*sandbox, '/usr/bin/say', '-v', voice, '-o', str(aiff), text], check=True)
            subprocess.run(['/usr/bin/afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', str(aiff), str(wav)], check=True)
            with wave.open(str(wav), 'rb') as audio:
                assert (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) == (1, 2, 16000)
                return audio.readframes(audio.getnframes())
        for case in missing:
            if case['id'] == 'H5':
                pcm = b''.join(synthesize(text, lang) for text, lang in [
                    ('这周我们使用', 'zh'), ('GitHub Actions', 'en'), ('自动部署项目。', 'zh')])
            elif case['id'] == 'H6':
                pcm = (synthesize('我不能保证周五之前完成。', 'zh') + bytes(16000 * 2 * 3 // 2)
                       + synthesize('Alex is a dog.', 'en') + bytes(16000 * 2 * 3 // 2))
            else:
                pcm = synthesize(case['speech'], case['language'])
            dest = args.output / (case['id'] + '.wav')
            with wave.open(str(dest), 'wb') as audio:
                audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(16000)
                audio.writeframes(pcm)
            print('Generated ' + case['id'] + ' (fictional speech)')
    print('Voice/OS versions can change the audio and evaluation results. No existing fixtures were overwritten.')

if __name__ == '__main__':
    main()
