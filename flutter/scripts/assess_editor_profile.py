"""Apply the owner's bounded finish line to raw physical profile samples.

Usage: python flutter/scripts/assess_editor_profile.py FRAMES_JSON
Uses exact microseconds, independently for build and raster. A failing baseline
can relax only the corresponding metric/stage, and every fallback is named.
"""
import json
import math
import sys
from pathlib import Path


def rank(values, percentile):
    return sorted(values)[math.ceil(len(values) * percentile / 100) - 1]


def assess(data):
    if not data.get('complete') or data['ingredients'] != 30 or data['steps'] != 20:
        raise ValueError('Complete 30-ingredient/20-step physical run required')
    if data['mode'] != 'profile' or data['device'] != 'Pixel 7 Pro' or abs(data['refreshRate'] - 120) > .1:
        raise ValueError('Pixel 7 Pro at 120Hz in profile mode required')
    groups = {}
    for sample in data['results']:
        if not sample['warmup'] and not sample['diagnostic']:
            groups.setdefault(sample['interaction'], []).append(sample)
    expected = {'baseline-recipe-scroll', 'editor-open', 'editor-scroll', 'editor-keyboard',
                'editor-keyboard-close', 'editor-typing', 'editor-save-return'}
    if set(groups) != expected:
        raise ValueError('All seven interaction groups required')
    for runs in groups.values():
        if len(runs) != data['repetitions'] or {r['run'] for r in runs} != set(range(1, data['repetitions'] + 1)):
            raise ValueError('Missing or duplicate repetitions')
        if any(not r['frames'] for r in runs):
            raise ValueError('Empty measured repetition')
    frames = {name: [f for r in runs for f in r['frames']] for name, runs in groups.items()}
    baseline = frames['baseline-recipe-scroll']
    results = {}
    for name, samples in frames.items():
        checks = []
        metrics = [('max', 33000)] if name in ('editor-open', 'editor-save-return') else [('p80', 8300), ('p99', 16700)]
        for stage in ('buildUs', 'rasterUs'):
            values = [f[stage] for f in samples]
            base_values = [f[stage] for f in baseline]
            for metric, target in metrics:
                value = max(values) if metric == 'max' else rank(values, int(metric[1:]))
                base = max(base_values) if metric == 'max' else rank(base_values, int(metric[1:]))
                limit = max(target, base)
                checks.append({'stage': stage, 'metric': metric, 'valueUs': value,
                               'targetUs': target, 'baselineUs': base, 'limitUs': limit,
                               'pass': value <= limit,
                               'baselineFallback': target < value <= limit})
        results[name] = {'pass': all(c['pass'] for c in checks), 'checks': checks}
    return results


if __name__ == '__main__':
    print(json.dumps(assess(json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))), indent=2))
