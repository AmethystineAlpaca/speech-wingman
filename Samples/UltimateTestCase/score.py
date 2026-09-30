#!/usr/bin/env python3
"""Score frozen labels; no model-as-judge, no relabeling, no missing-as-pass."""
import argparse,collections,hashlib,json,pathlib,statistics,math
HERE=pathlib.Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--run-dir',type=pathlib.Path,required=True);p.add_argument('--tag',required=True);p.add_argument('--labels',type=pathlib.Path,default=HERE/'window-labels.json');p.add_argument('--append',action='store_true');a=p.parse_args()
labels=json.loads(a.labels.read_text())['windows'];out=HERE/'results'/a.tag
if pathlib.Path(a.tag).name != a.tag: raise SystemExit('Use a simple unique run tag')
if out.exists(): raise SystemExit('Run tag already exists; choose a new tag to preserve history')
out.mkdir(parents=True)
summary={};rows=[]
run_ids={json.loads(p.read_text()).get("runID") for p in (a.run_dir/(level+".json") for level in ["low","medium","high"]) if p.exists()}
if len(run_ids)>1: raise SystemExit("Mixed run IDs; refusing to combine results from different runs")
def percentile(values,q):
 return sorted(values)[max(0,math.ceil(len(values)*q)-1)] if values else None
for level in ['low','medium','high']:
 path=a.run_dir/(level+'.json')
 if not path.exists():continue
 data=json.loads(path.read_text());windows=data['windows'];assert len(windows)==len(labels)
 evaluated=[w for w in windows if w['status']=='evaluated'];scored=[];tp=fp=fn=tn=correct=presented_tp=presented_fp=0
 for w,g in zip(windows,labels):
  assert w['index']==g['index'] and hashlib.sha256(w['text'].encode()).hexdigest()==g['text_sha256'], 'Window/label mismatch; do not silently reassign labels'
  expected=g['expected_rules'][level];decision=w.get('decision');matched=w.get('matchedRuleID');finished=w['status']=='evaluated';valid_alert=finished and decision=='alert';right_alert=valid_alert and matched in expected
  presented_fp+=int(valid_alert and not right_alert and w['presented'])
  if expected:
   passed=right_alert;tp+=int(right_alert);fn+=int(not right_alert);fp+=int(valid_alert and not right_alert);presented_tp+=int(right_alert and w['presented'])
  else:
   passed=finished and decision in g['acceptable_quiet_decisions'];tn+=int(passed);fp+=int(valid_alert)
  correct+=int(passed)
  scored.append({'window':w['index'],'expected':expected or ['quiet'],'actual':decision or w['status'],'matched_rule':matched,'presented':w['presented'],'correct':passed,'note':g['note']})
 completed=[w for w in windows if w.get('completedAt') is not None]
 durations=[w['completedAt']-w['startedAt'] for w in completed];latencies=[w['completedAt']-w['finalTime'] for w in completed if w['presented']]
 expected_positive=sum(bool(g['expected_rules'][level]) for g in labels)
 s={'windows':len(windows),'completed':len(completed),'correct':correct,'accuracy':correct/len(windows),'tp':tp,'fp':fp,'fn':fn,'tn':tn,'precision':tp/(tp+fp) if tp+fp else None,'recall':tp/expected_positive if expected_positive else None,'presented_true_positives':presented_tp,'presentation_recall':presented_tp/expected_positive if expected_positive else None,'statuses':dict(collections.Counter(w['status'] for w in windows)),'decisions':dict(collections.Counter(w.get('decision') for w in evaluated)),'inference_wall_p50':statistics.median(durations) if durations else None,'inference_wall_p95':percentile(durations,.95),'presented_after_final_p50':statistics.median(latencies) if latencies else None,'presented_after_final_p95':percentile(latencies,.95),'validation_diagnostics':sum(bool(w['errors']) for w in windows),'continuations':sum(w.get('continuedFrom') is not None for w in windows),'failures':[x for x in scored if not x['correct']]}
 summary[level]=s
 s['presented_false_positives']=presented_fp
 s['presented_precision']=presented_tp/(presented_tp+presented_fp) if presented_tp+presented_fp else None
 (out/(level+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');(out/(level+'-scored.json')).write_text(json.dumps(scored,ensure_ascii=False,indent=2)+'\n')
 def pct(x):return '—' if x is None else f'{x*100:.1f}%'
 rows.append(f"| {level} | {len(completed)}/{len(windows)} | {correct}/{len(windows)} ({pct(s['accuracy'])}) | {tp}/{fp}/{fn} | {pct(s['precision'])} | {pct(s['recall'])} | {pct(s['presentation_recall'])} | {s['inference_wall_p50']:.2f}/{s['inference_wall_p95']:.2f}s |")
if (a.run_dir/'metadata.json').exists():
 (out/'metadata.json').write_text((a.run_dir/'metadata.json').read_text())
(out/'labels.json').write_text(a.labels.read_text())
(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
section=['',f'### {a.tag} — 自动计分 / Frozen-label scoring','','| Sensitivity | Returned | Correct windows | TP/FP/FN | Precision | Recall | Presented recall | Inference p50/p95 |','|---|---:|---:|---:|---:|---:|---:|---:|',*rows,'','分母包含未完成、错误、过期及丢弃窗口。TP 必须命中预期规则身份；一个错误规则提醒同时计 FP，并使应有提醒计 FN。这里的延迟是实测文本推理加音频时钟模拟，不含真实实时 ASR 计算等待。 / Missing work never counts as quiet success. Wrong-rule alerts are not true positives.','']
for level,s in summary.items():
 section += [f'**{level}** — statuses `{s["statuses"]}`; decisions `{s["decisions"]}`; continuations {s["continuations"]}; validation diagnostics {s["validation_diagnostics"]}.','']
 if s['presented_after_final_p50'] is not None:
  section += [f'实际呈现的提醒距窗口最后一次 ASR final 的模拟延迟 / Presented alert delay from the last ASR final, audio-clock simulation: p50 **{s["presented_after_final_p50"]:.2f}s**, p95 **{s["presented_after_final_p95"]:.2f}s**. This includes grouping/queue wait and inference, not live ASR computation.','']
  section += [f'实际呈现 / Presented: {s["presented_true_positives"]} true positives, {s["presented_false_positives"]} false positives.','']
 if s['failures']:
  section+=['| Window | Expected | Actual | Rule | Presented |','|---|---|---|---|---|']
  section += [f"| W{x['window']} | {', '.join(x['expected'])} | {x['actual']} | {x['matched_rule'] or '—'} | {x['presented']} |" for x in s['failures']]
  section+=['']
 section += [f'[Raw results](results/{a.tag}/{level}.json) · [Per-window scores](results/{a.tag}/{level}-scored.json)','']
if a.append:
 with (HERE/'EVALUATION.md').open('a') as f:f.write('\n'.join(section)+'\n')
print(json.dumps(summary,ensure_ascii=False,indent=2))
