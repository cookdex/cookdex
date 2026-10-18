"""Generate the final matched control/before/after tables from retained raw data.

All six directories must contain complete, uninstrumented twelve-repeat runs.
An absent/short-content surface is unmeasured, never a passing result.
"""
import argparse
import json
from pathlib import Path

from summarize_app_profile import summarize


def compare(root, control_suffix=''):
    root = Path(root)
    tables, comparisons = [], {}
    for display in ('phone', 'tablet'):
        loaded = {}
        raw = {}
        for stage in ('before', 'control', 'after'):
            suffix = control_suffix if stage == 'control' else ''
            folder = root / f'final-{stage}-{display}{suffix}'
            path = folder / 'data' / 'frames.json'
            raw[stage] = json.loads(path.read_text(encoding='utf-8-sig'))
            loaded[stage] = summarize(path)
            if not loaded[stage]['complete'] or loaded[stage]['error']:
                raise ValueError(f'Incomplete measurement: {folder}')
            if raw[stage]['config'].get('diagnostic'):
                raise ValueError(f'Instrumented measurement: {folder}')
            (folder / 'summary.json').write_text(
                json.dumps(loaded[stage], indent=2), encoding='utf-8')
        if len({(s['refreshHz'], s['dpr']) for s in loaded.values()}) != 1:
            raise ValueError(f'Unmatched display settings: {display}')
        if len({(s['widthPx'], s['heightPx']) for s in raw.values()}) != 1:
            raise ValueError(f'Unmatched viewport dimensions: {display}')
        expected_hz = 120 if display == 'phone' else 60
        if abs(loaded['after']['refreshHz'] - expected_hz) > .01:
            raise ValueError(f'Unexpected refresh rate: {display}')
        if raw['control']['config'].get('resampling') or raw['before']['config'].get('resampling'):
            raise ValueError('Control and before must use the original resampling-off default')
        if not raw['after']['config'].get('resampling'):
            raise ValueError('After must use the proposed resampling-on default')
        table = [f'### {display.title()} ({expected_hz}Hz)', '',
                 'Each cell is slow / medium. Late rates are percentages; jerk is physical pixels (lower is smoother).', '',
                 '| Screen | Late before | Late control | Late after | Jerk before | Jerk control | Jerk after | Result |',
                 '| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |']
        # Include requested and explicitly unmeasured surfaces. Deriving this
        # only from after rows would silently hide a completely missing screen.
        inventory = []
        for stage in ('before', 'after'):
            inventory.extend(raw[stage]['config'].get('screens', []))
            inventory.extend(name.rsplit('-', 1)[0] for name in loaded[stage]['rows']
                             if name.endswith(('-slow', '-medium')))
            inventory.extend(item['screen'] for item in raw[stage].get('nonScrollable', []))
        screens = list(dict.fromkeys(inventory))
        if not screens or not loaded['control']['rows']:
            raise ValueError(f'No measured scrolling surfaces: {display}')
        entries = {}
        for screen in screens:
            # The narrow recipe layout has one combined pane; the runner only
            # requests a separate directions drag at the same 840dp breakpoint.
            if screen == 'recipe-directions' and raw['after']['widthPx'] / loaded['after']['dpr'] < 840:
                entries[screen] = {'pass': False, 'applicable': False,
                                   'reason': 'Single-pane layout', 'speeds': {}}
                table.append(f'| {screen} | N/A | N/A | N/A | N/A | N/A | N/A | Not applicable (single pane) |')
                continue
            control = 'fields' if screen in ('editor', 'import-text') else 'text'
            values = {'late': {}, 'jerk': {}}
            speeds = {}
            for speed in ('slow', 'medium'):
                rows = {stage: result['rows'].get(f'{control if stage == "control" else screen}-{speed}')
                        for stage, result in loaded.items()}
                for stage, row in rows.items():
                    if row is None and (stage == 'control' or not any(
                        item['screen'] == screen and item['speed'] == speed
                        for item in raw[stage].get('nonScrollable', [])
                    )):
                        raise ValueError(f'Unexpected missing measurement: {display}/{stage}/{screen}/{speed}')
                if any(r['runs'] != 12 or not r['frames'] for r in rows.values() if r is not None):
                    raise ValueError(f'Expected twelve repetitions: {display}/{screen}/{speed}')
                for metric, key in (('late', 'latePct'), ('jerk', 'jerkPxMean')):
                    for stage, row in rows.items():
                        values[metric].setdefault(stage, []).append(row[key] if row else None)
                after, reference = rows['after'], rows['control']
                if after is None:
                    speeds[speed] = {'measured': False, 'reason': 'Insufficient scroll extent'}
                    continue
                speeds[speed] = {
                    'measured': True,
                    'lateGapPercentagePoints': after['latePct'] - reference['latePct'],
                    'latePass': after['latePct'] <= reference['latePct'] + 1,
                    'jerkPass': after['jerkPxMean'] <= reference['jerkPxMean'],
                    'pixelPass': after['fractionalFrames'] == 0,
                    'afterFractionalFrames': after['fractionalFrames'],
                    'afterOffsetFrames': after['offsetFrames'],
                }
            complete = all(r['measured'] for r in speeds.values())
            measured = [r for r in speeds.values() if r['measured']]
            measured_miss = any(not r[key] for r in measured
                                for key in ('latePass', 'jerkPass', 'pixelPass'))
            passed = complete and not measured_miss
            verdict = ('Pass' if passed else 'Miss' if complete else
                       'Unmeasured' if not measured else
                       'Partial - measured miss' if measured_miss else 'Partial')
            entries[screen] = {'pass': passed, 'applicable': True,
                               'measuredMiss': measured_miss, 'result': verdict, 'speeds': speeds}
            cells = [' / '.join(f'{n:.2f}' if n is not None else 'N/A' for n in values[metric][stage])
                     for metric in ('late', 'jerk') for stage in ('before', 'control', 'after')]
            table.append(f'| {screen} | ' + ' | '.join(cells) + f' | {verdict} |')
        comparisons[display] = {'screens': entries,
                                'unmeasured': raw['after'].get('nonScrollable', [])}
        tables.extend(table + ['',
            'Control mapping: ordinary fields for editor/import text; plain text list for the other surfaces. A pass applies only to this measured workload.', ''])
        tables.extend(['| Editor interaction (one sample, not twelve) | Late before / after % | Max build before / after ms | Max raster before / after ms |',
                       '| --- | ---: | ---: | ---: |'])
        for name, after in loaded['after']['rows'].items():
            if 'jerkPxMean' in after:
                continue
            before = loaded['before']['rows'][name]
            cells = [f'{before[k]:.2f} / {after[k]:.2f}'
                     for k in ('latePct', 'maxBuildMs', 'maxRasterMs')]
            tables.append(f'| {name} | ' + ' | '.join(cells) + ' |')
        tables.append('')
    return comparisons, '\n'.join(tables)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    parser.add_argument('--control-suffix', default='')
    args = parser.parse_args()
    result, markdown = compare(args.directory, args.control_suffix)
    root = Path(args.directory)
    (root / 'final-comparison.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    (root / 'final-tables.md').write_text(markdown, encoding='utf-8')
    print(markdown)
