#!/usr/bin/python3
import pathlib,json,hashlib,sys,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[2]
fixtures,run=map(pathlib.Path,sys.argv[1:])
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
paths=list((ROOT/'Sources/WingmanCore').glob('*.swift'))+[ROOT/'Sources/WingmanApp/SessionController.swift',ROOT/'Native/TextWorker/main.cpp',ROOT/'Samples/UltimateTestCase/main.swift']
scenario=sha(ROOT/'Samples/UltimateTestCase/scenario.json'); audio=json.loads((fixtures/'audio-metadata.json').read_text())
if audio['scenario_sha256']!=scenario:raise SystemExit('Scenario changed: regenerate audio before evaluating.')
meta={'scenario_sha256':scenario,'audio':audio,'sources':{str(p.relative_to(ROOT)):sha(p) for p in paths},'text_worker_sha256':sha(ROOT/'build/native/bin/text-worker'),'model_sha256':sha(ROOT/'Models/Qwen3-4B-Instruct-2507-Q4_K_M.gguf'),'events_sha256':sha(fixtures/'events.json'),'hardware':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),'os':subprocess.check_output(['sw_vers','-productVersion'],text=True).strip()}
(run/'metadata.json').write_text(json.dumps(meta,indent=2)+'\n')
