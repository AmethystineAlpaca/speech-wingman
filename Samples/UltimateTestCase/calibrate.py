#!/usr/bin/env python3
"""Compare recall on identical positives; never pass relabeled outputs off as inference."""
import argparse
import collections
import json
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
p = argparse.ArgumentParser()
p.add_argument('--source', type=pathlib.Path, required=True)
p.add_argument('--profile-run', type=pathlib.Path, required=True)
p.add_argument('--short-log', type=pathlib.Path, required=True)
p.add_argument('--tag', required=True)
a = p.parse_args()
out = HERE / 'results' / a.tag
if pathlib.Path(a.tag).name != a.tag or out.exists():
    raise SystemExit('Choose a new simple tag; existing results are never overwritten')
profiles = json.loads((a.profile_run / 'sensitivity-profiles.json').read_text())
gold = json.loads((a.source / 'labels.json').read_text())['windows']
targets = [set().union(*g['expected_rules'].values()) for g in gold]
positive_count = sum(bool(t) for t in targets)
large = {}
for selected, profile in profiles.items():
    old = profile.removeprefix('legacy-')
    raw = json.loads((a.source / (old + '.json')).read_text())
    windows = raw['windows']
    assert len(windows) == len(gold)
    tp = fp = presented_tp = 0
    for w, g, expected in zip(windows, gold, targets):
        import hashlib
        assert w['index'] == g['index'] and hashlib.sha256(w['text'].encode()).hexdigest() == g['text_sha256']
        alert = w['status'] == 'evaluated' and w.get('decision') == 'alert'
        matched = alert and w.get('matchedRuleID') in expected
        tp += int(matched)
        fp += int(alert and not matched)
        presented_tp += int(matched and w['presented'])
    large[selected] = {'source_sensitivity': old, 'profile': profile,
        'source_run_id': raw['runID'], 'positive_windows': positive_count,
        'tp': tp, 'fp': fp, 'fn': positive_count-tp,
        'recall': tp/positive_count, 'precision': tp/(tp+fp) if tp+fp else None,
        'presented_tp': presented_tp}

short_log = a.short_log.read_text()
assert re.search(r'Policy check: \d+/73 passed', short_log), 'Wait for the full independent regression run'
decisions = {m.group(2): m.group(3) for m in re.finditer(r'^(PASS|FAIL) ([^:]+): ([^,\n]+)', short_log, re.M)}
groups = collections.defaultdict(list)
for case in json.loads((HERE.parents[1] / 'Tests/Evaluation/sensitivity.json').read_text()):
    groups[(case['speech'], case['policy'])].append(case)
positives = [group for group in groups.values() if any(c['expected'] == 'alert' for c in group)]
small = {}
for selected in ['low', 'medium', 'high']:
    cases = [next(c for c in g if c['sensitivity'] == selected) for g in positives]
    assert all(c['id'] in decisions for c in cases)
    tp = sum(decisions[c['id']] == 'alert' for c in cases)
    small[selected] = {'profile': 'legacy-' + selected, 'positive_cases': len(cases),
                       'tp': tp, 'recall': tp/len(cases)}

out.mkdir(parents=True)
result = {'mapping_version': 'routed-recall-v1',
    'method': 'Large-rule values reclassify recorded Iteration 11 outputs using the compiled production mapping; this is NOT a fresh continuous replay. Small-rule values come from a fresh regression run.',
    'positive_definition': 'Union of the frozen positive labels across sensitivities, identical for every strategy. No model outputs determine labels.',
    'large_rule_path': large, 'small_rule_path': small}
(out / 'calibration.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
for name in ['sensitivity-profiles.json', 'metadata.json']:
    (out / name).write_text((a.profile_run / name).read_text())
(out / 'regressions.txt').write_text(short_log)
print(json.dumps(result, ensure_ascii=False, indent=2))
