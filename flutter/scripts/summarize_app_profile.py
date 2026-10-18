"""Full-app/control measurements; diagnostic traces never enter timing tables.

Smoothness uses Flutter's discrete |p[n-1]+p[n+1]-2p[n]| metric, in physical
pixels. Retain all samples and also report the upstream 40ms / 16ms input-delay
filter. Trim touch slop/startup and pointer-up/ballistic edges consistently.
"""
import argparse
import collections
import json
import math
from pathlib import Path
import statistics


def mean(values):
    return statistics.mean(values) if values else None


def percentile(values, fraction):
    if not values:
        return None
    values = sorted(values)
    return values[min(len(values) - 1, math.ceil(len(values) * fraction) - 1)]


def drag_metrics(sample, dpr):
    inputs = sample['input']
    if not inputs:
        return {}
    speed = sample.get('interaction', '').rsplit('-', 1)[-1]
    moves = [i for i in inputs if i.get('event') == 'PointerMoveEvent']
    release = next((i['timeUs'] for i in inputs if i.get('event') == 'PointerUpEvent'), None)
    if speed == 'fling' and release is not None:
        # A fling is deliberately decelerating. Measure its released ballistic
        # segment separately; never call that constant-velocity drag evenness.
        start = release + 60_000
        moving = [b for a, b in zip(sample['offsets'], sample['offsets'][1:])
                  if abs(b['offset'] - a['offset']) > 1e-6]
        end = moving[-1]['systemUs'] if moving else start
    elif speed == 'fast' and moves:
        start, end = inputs[0]['timeUs'] + 100_000, moves[-1]['timeUs'] - 30_000
    else:
        # Preserve the previous slow/medium trims; use final movement rather
        # than the new held-release pause when event types are available.
        start = inputs[0]['timeUs'] + 800_000
        end = (moves[-1]['timeUs'] if moves else inputs[-1]['timeUs']) - 100_000
    offsets = [o for o in sample['offsets'] if start <= o['systemUs'] <= end]
    jerks, filtered = [], []
    excluded = 0
    for prev, cur, nxt in zip(offsets, offsets[1:], offsets[2:]):
        jerk = abs(prev['offset'] + nxt['offset'] - 2 * cur['offset']) * dpr
        jerks.append(jerk)
        delay = max((i['delayUs'] for i in inputs
                     if prev['systemUs'] < i['timeUs'] <= nxt['systemUs']), default=0)
        if nxt['systemUs'] - prev['systemUs'] > 40_000 or delay > 16_000:
            excluded += 1
        else:
            filtered.append(jerk)
    # Pixel alignment is required throughout the entire recorded gesture,
    # including startup. Only the velocity/jerk statistic trims its edges.
    residuals = [abs(o['offset'] * dpr - round(o['offset'] * dpr))
                 for o in sample['offsets']]
    deltas = [(b['offset'] - a['offset']) * dpr for a, b in zip(offsets, offsets[1:])]
    return {
        'offsetFrames': len(sample['offsets']), 'jerkPxMean': mean(jerks),
        'filteredJerkPxMean': mean(filtered), 'excludedTriples': excluded,
        'jerkPxP99': percentile(jerks, .99),
        'stepPxMean': mean(deltas), 'stepPxStdev': statistics.pstdev(deltas) if deltas else None,
        'fractionalFrames': sum(r > 1e-6 for r in residuals),
        'maxPixelResidual': max(residuals, default=0),
        'maxInputDelayUs': max(i['delayUs'] for i in inputs),
        'smoothnessSamples': len(jerks),
        'segment': 'released-ballistic' if speed == 'fling' else 'held-drag',
        'keyboardVisibleAll': all(o.get('keyboardPx', 0) > 0 for o in sample['offsets']),
        'distanceDp': max((o['offset'] for o in sample['offsets']), default=0) -
                      min((o['offset'] for o in sample['offsets']), default=0),
        'boundaryLimited': sample.get('motion', {}).get('boundaryLimited'),
        'velocityDpPerSecond': sample.get('motion', {}).get('velocityDpPerSecond'),
        'requestedDistanceDp': sample.get('motion', {}).get('requestedDistanceDp'),
    }


def summarize(path):
    data = json.loads(Path(path).read_text(encoding='utf-8-sig'))
    hz = data['refreshHz']
    budget = 1_000_000 / hz
    groups = collections.defaultdict(list)
    for sample in data['results']:
        if not sample['diagnostic'] and not sample['warmup']:
            groups[sample['interaction']].append(sample)
    rows = {}
    for name, samples in groups.items():
        frames = [f for s in samples for f in s['frames']]
        builds = [f['buildUs'] for f in frames]
        rasters = [f['rasterUs'] for f in frames]
        late = sum(max(f['buildUs'], f['rasterUs']) > budget for f in frames)
        drags = [drag_metrics(s, data['dpr']) for s in samples if s['input']]
        row = {'runs': len(samples), 'frames': len(frames), 'late': late,
               'latePct': late / len(frames) * 100 if frames else None,
               'buildP99Ms': (percentile(builds, .99) or 0) / 1000,
               'rasterP99Ms': (percentile(rasters, .99) or 0) / 1000,
               'maxBuildMs': max(builds, default=0) / 1000,
               'maxRasterMs': max(rasters, default=0) / 1000}
        if drags:
            row.update({'dragRuns': drags,
                        'jerkPxMean': mean([d['jerkPxMean'] for d in drags if d['jerkPxMean'] is not None]),
                        'filteredJerkPxMean': mean([d['filteredJerkPxMean'] for d in drags if d['filteredJerkPxMean'] is not None]),
                        'fractionalFrames': sum(d['fractionalFrames'] for d in drags),
                        'offsetFrames': sum(d['offsetFrames'] for d in drags)})
        rows[name] = row
    return {'complete': data.get('complete'), 'error': data.get('error'),
            'control': data['control'], 'refreshHz': hz, 'dpr': data['dpr'], 'rows': rows}


def diagnostic(path):
    events = json.loads(Path(path).read_text(encoding='utf-8-sig'))['traceEvents']
    # Framework build profile events use widget class names. Counts include
    # initial materialization; a no-new-rows run must establish that separately.
    names = ['CookdexApp', 'RecipesScreen', 'RecipeDetail', 'RecipeEditor',
             'ShoppingScreen', 'SettingsScreen', '_EditorField', 'EditableText',
             'ListenableBuilder', 'LayoutBuilder', 'SliverList']
    counts = collections.Counter(e.get('name') for e in events if e.get('ph') in ('B', 'X'))
    return {name: counts[name] for name in names}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('frames')
    parser.add_argument('--output')
    args = parser.parse_args()
    summary = summarize(args.frames)
    if args.output:
        Path(args.output).write_text(json.dumps(summary, indent=2), encoding='utf-8')
    print('complete=%s hz=%.2f dpr=%.3f' % (summary['complete'], summary['refreshHz'], summary['dpr']))
    print('| Interaction | Runs | Late / frames (%) | Build/raster p99 ms | Jerk px | Fractional offsets |')
    print('| --- | ---: | ---: | ---: | ---: | ---: |')
    for name, r in summary['rows'].items():
        jerk = '—' if r.get('jerkPxMean') is None else '%.4f' % r['jerkPxMean']
        frac = '—' if 'offsetFrames' not in r else f"{r['fractionalFrames']}/{r['offsetFrames']}"
        print(f"| {name} | {r['runs']} | {r['late']}/{r['frames']} ({r['latePct']:.2f}) | "
              f"{r['buildP99Ms']:.3f}/{r['rasterP99Ms']:.3f} | {jerk} | {frac} |")
    if summary['error']:
        print(summary['error'])
