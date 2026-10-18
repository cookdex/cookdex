"""Summarize physical profile samples; refuse incomplete or mismatched runs.

Usage: python flutter/scripts/summarize_editor_profile.py BEFORE_JSON [AFTER_JSON]
Frame work = max(UI build, raster), because these stages pipeline. Janky means
either stage exceeds one display interval. Total span is also retained separately.
Percentiles use the nearest-rank definition. Warm-up and diagnostic passes are
excluded, and all twelve independent interaction repetitions must be present.
"""
import json
import math
import sys
from pathlib import Path


def percentiles(values):
    values = sorted(values)
    if not values:
        raise ValueError('No frame samples')
    return {f'p{p}': round(values[max(0, math.ceil(len(values)*p/100)-1)]/1000, 3)
            for p in (50, 80, 90, 99)}


def summarize(path):
    data = json.loads(Path(path).read_text(encoding='utf-8-sig'))
    if not data.get('complete'):
        raise ValueError(f'Incomplete run: {path}')
    if data['device'] != 'Pixel 7 Pro' or data['mode'] != 'profile':
        raise ValueError('Physical Pixel 7 Pro profile evidence required')
    budget = 1_000_000 / data['targetHz']
    groups = {}
    for sample in data['results']:
        if sample['warmup'] or sample['diagnostic']:
            continue
        groups.setdefault(sample['interaction'], []).append(sample)
    summary = {'source': str(path), 'device': data['device'],
               'refreshRate': data['refreshRate'], 'targetHz': data['targetHz'],
               'budgetMs': budget/1000,
               'ingredients': data['ingredients'], 'steps': data['steps'],
               'interactions': {}}
    for name, runs in groups.items():
        if len(runs) != data['repetitions'] or {r['run'] for r in runs} != set(range(1, data['repetitions']+1)):
            raise ValueError(f'{name}: missing/repeated repetitions')
        frames = [f for r in runs for f in r['frames']]
        if any(not r['frames'] for r in runs):
            raise ValueError(f'{name}: empty repetition')
        stage = [max(f['buildUs'], f['rasterUs']) for f in frames]
        summary['interactions'][name] = {
            'frames': len(frames), 'runs': len(runs),
            'workMs': percentiles(stage),
            'maxWorkMs': round(max(stage)/1000, 3),
            'maxBuildMs': round(max(f['buildUs'] for f in frames)/1000, 3),
            'maxRasterMs': round(max(f['rasterUs'] for f in frames)/1000, 3),
            'buildMs': percentiles([f['buildUs'] for f in frames]),
            'rasterMs': percentiles([f['rasterUs'] for f in frames]),
            'totalSpanMs': percentiles([f['totalUs'] for f in frames]),
            'vsyncOverheadMs': percentiles([f['vsyncUs'] for f in frames]),
            'janky': sum(v > budget for v in stage),
            'buildJanky': sum(f['buildUs'] > budget for f in frames),
            'rasterJanky': sum(f['rasterUs'] > budget for f in frames),
            'buildOver16_7ms': sum(f['buildUs'] > 16700 for f in frames),
            'rasterOver16_7ms': sum(f['rasterUs'] > 16700 for f in frames),
            'jankyPercent': round(100*sum(v > budget for v in stage)/len(stage), 3),
            'runWorkP99Ms': [percentiles([max(f['buildUs'], f['rasterUs'])
                                         for f in r['frames']])['p99'] for r in runs],
            'liveFields': [r['afterFields'] for r in runs],
            'durationMs': percentiles([r['endUs']-r['startUs'] for r in runs]),
        }
    if len(groups) not in (6, 7):
        raise ValueError('Expected baseline and editor interactions, optionally separate keyboard close')
    return summary


if __name__ == '__main__':
    results = [summarize(path) for path in sys.argv[1:]]
    if not results:
        raise SystemExit(__doc__)
    if any((r['refreshRate'], r['targetHz'], r['ingredients'], r['steps']) !=
           (results[0]['refreshRate'], results[0]['targetHz'], results[0]['ingredients'], results[0]['steps'])
           for r in results):
        raise ValueError('Before/after display or fixture mismatch')
    print(json.dumps(results, indent=2))
