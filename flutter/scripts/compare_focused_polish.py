"""Compare the frozen real-library fast/fling workloads; never imply control parity."""
import argparse
import json
from pathlib import Path

from summarize_app_profile import summarize


def compare(before_path, after_path):
    paths = [Path(before_path), Path(after_path)]
    raw = [json.loads(p.read_text(encoding='utf-8-sig')) for p in paths]
    for data in raw:
        if not data.get('complete') or data.get('error') or data['config'].get('diagnostic'):
            raise ValueError('Only complete uninstrumented jobs are comparable')
    for field in ('refreshHz', 'dpr', 'widthPx', 'heightPx', 'libraryCount'):
        if raw[0][field] != raw[1][field]:
            raise ValueError(f'Unmatched {field}')
    for field in ('resampling', 'samplingOffsetMs', 'realLibrary', 'paddingCount',
                  'sectionedId', 'unsectionedId', 'speeds'):
        if raw[0]['config'].get(field) != raw[1]['config'].get(field):
            raise ValueError(f'Unmatched config {field}')
    summaries = [summarize(p) for p in paths]
    result = {}
    screens = raw[1]['config']['screens']
    if not screens or not set(screens).issubset(raw[0]['config']['screens']):
        raise ValueError('After workloads must have matching baselines')
    for screen in screens:
        for speed in ('fast', 'fling'):
            name = f'{screen}-{speed}'
            rows = [s['rows'].get(name) for s in summaries]
            if any(r is None for r in rows):
                result[name] = {'status': 'Not measured: insufficient extent or missing group'}
                continue
            for data in raw:
                samples = [s for s in data['results'] if s['interaction'] == name and not s['warmup']]
                if sorted(s.get('run', -1) for s in samples) != [1, 2, 3, 4, 5]:
                    raise ValueError(f'Missing or duplicated repetitions: {name}')
            for row in rows:
                if row['runs'] != 5 or not row['frames'] or len(row.get('dragRuns', [])) != 5:
                    raise ValueError(f'Expected five measured gestures: {name}')
                if any(not r.get('smoothnessSamples') for r in row['dragRuns']):
                    raise ValueError(f'Missing motion: {name}')
                if any(d.get('boundaryLimited') is None or d.get('requestedDistanceDp') is None
                       or d.get('velocityDpPerSecond') is None for d in row['dragRuns']):
                    raise ValueError(f'Missing input metadata: {name}')
            for a, b in zip(rows[0]['dragRuns'], rows[1]['dragRuns']):
                for field in ('requestedDistanceDp', 'velocityDpPerSecond'):
                    if a.get(field) != b.get(field):
                        raise ValueError(f'Unmatched input {name}/{field}')
            limited = any(d.get('boundaryLimited') for row in rows for d in row['dragRuns'])
            result[name] = {'status': 'Boundary-limited' if limited else 'Measured',
                            'before': rows[0], 'after': rows[1]}
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('before')
    parser.add_argument('after')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    rows = compare(args.before, args.after)
    Path(args.output).write_text(json.dumps(rows, indent=2), encoding='utf-8')
    print('| Workload | Late before / after % | Build p99 before / after ms | Raster p99 before / after ms | Jerk before / after px | Coverage |')
    print('| --- | ---: | ---: | ---: | ---: | --- |')
    for name, row in rows.items():
        cells = [' / '.join(f'{row[s][metric]:.2f}' for s in ('before', 'after'))
                 for metric in ('latePct', 'buildP99Ms', 'rasterP99Ms', 'jerkPxMean')] if 'before' in row else ['N/A'] * 4
        print(f'| {name} | ' + ' | '.join(cells) + f' | {row["status"]} |')
