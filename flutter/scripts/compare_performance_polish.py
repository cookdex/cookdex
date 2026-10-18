"""Matched performance/polish tables, preserving gaps and failed samples.

Input: JSON list of {profile, before, after, control, screens, repetitions}.
Each directory contains data/frames.json. Diagnostic data cannot pass a gate.
"""
import argparse
import json
from pathlib import Path
from summarize_app_profile import summarize

SPEEDS = ('slow', 'medium', 'fast', 'fling')


def compare(jobs):
    report, rows = [], []
    offsets = {}
    for job in jobs:
        raw, summaries = {}, {}
        for stage in ('before', 'control', 'after'):
            path = Path(job[stage]) / 'data/frames.json'
            raw[stage] = json.loads(path.read_text(encoding='utf-8-sig'))
            summaries[stage] = summarize(path)
            if not raw[stage].get('complete') or raw[stage].get('error'):
                raise ValueError(f'Incomplete {stage}: {path}')
            if raw[stage]['config'].get('diagnostic'):
                raise ValueError(f'Instrumented {stage}: {path}')
        for field in ('refreshHz', 'dpr', 'widthPx', 'heightPx'):
            if len({d[field] for d in raw.values()}) != 1:
                raise ValueError(f'Unmatched {field}: {job["profile"]}')
        if not raw['control']['control'] or raw['before']['control'] or raw['after']['control']:
            raise ValueError('App/control identities reversed')
        for field in ('resampling', 'samplingOffsetMs'):
            if raw['before']['config'].get(field) != raw['after']['config'].get(field):
                raise ValueError(f'Unmatched {field}: {job["profile"]}')
        if raw['control']['config'].get('resampling'):
            raise ValueError('Acceptance requires the retained normal-default bare control (resampling off)')
        offsets.setdefault(job['profile'], set()).add(raw['after']['config'].get('samplingOffsetMs'))
        for screen in job['screens']:
            for speed in job.get('speeds', SPEEDS):
                if screen in ('recipe-directions', 'cook-directions') and raw['after']['widthPx'] / raw['after']['dpr'] < 840:
                    continue
                reference = ('fields-keyboard' if screen == 'editor-keyboard' else
                             'fields' if screen.startswith('editor-') or screen == 'import-text' else 'text')
                values = {stage: summaries[stage]['rows'].get(f'{reference if stage == "control" else screen}-{speed}')
                          for stage in summaries}
                for stage, value in values.items():
                    if value is None:
                        if not any(v['screen'] == screen and v['speed'] == speed
                                   for v in raw[stage].get('nonScrollable', [])):
                            raise ValueError(f'Missing {stage}/{screen}/{speed}')
                    else:
                        required = job.get('controlRepetitions', job['repetitions']) if stage == 'control' else job['repetitions']
                        interaction = f'{reference if stage == "control" else screen}-{speed}'
                        samples = [s for s in raw[stage]['results']
                                   if s['interaction'] == interaction and not s['warmup'] and not s['diagnostic']]
                        if any(not s['frames'] or not s['input'] for s in samples):
                            raise ValueError(f'Invalid individual repeat {stage}/{screen}/{speed}')
                        if len(value.get('dragRuns', [])) != value['runs']:
                            raise ValueError(f'Missing individual motion {stage}/{screen}/{speed}')
                        if value['runs'] < required or not value['frames']:
                            raise ValueError(f'Insufficient repetitions {stage}/{screen}/{speed}')
                        if value.get('jerkPxMean') is None or any(d['smoothnessSamples'] < 3 for d in value.get('dragRuns', [])):
                            raise ValueError(f'Insufficient motion samples {stage}/{screen}/{speed}')
                        if not value.get('dragRuns') or any(d['distanceDp'] < 20 for d in value['dragRuns']):
                            raise ValueError(f'Insufficient scroll distance {stage}/{screen}/{speed}')
                        if any(d['boundaryLimited'] is None for d in value['dragRuns']):
                            raise ValueError(f'Missing boundary evidence {stage}/{screen}/{speed}')
                        if screen == 'editor-keyboard' and not all(d['keyboardVisibleAll'] for d in value['dragRuns']):
                            raise ValueError('Keyboard-open sample dismissed its keyboard')
                before, control, after = (values[s] for s in ('before', 'control', 'after'))
                if all(values.values()):
                    for field in ('requestedDistanceDp', 'velocityDpPerSecond'):
                        recorded = [d[field] for value in values.values() for d in value['dragRuns']]
                        if any(v is None for v in recorded) or max(recorded) - min(recorded) > 1e-6:
                            raise ValueError(f'Unmatched gesture {field}: {screen}/{speed}')
                if before is None or after is None:
                    verdict = 'Unmeasured (short content)'
                elif any(d['boundaryLimited'] for value in values.values() for d in value['dragRuns']):
                    verdict = 'Unmeasured (boundary-limited motion)'
                else:
                    late_pass = after['latePct'] <= control['latePct'] + 1
                    smooth_pass = after['jerkPxMean'] <= control['jerkPxMean']
                    aligned = after['fractionalFrames'] == 0
                    verdict = 'Pass' if late_pass and smooth_pass and aligned else 'Miss: ' + ', '.join(
                        n for n, ok in [('late', late_pass), ('smoothness', smooth_pass), ('pixels', aligned)] if not ok)
                rows.append(dict(profile=job['profile'], screen=screen, speed=speed, result=verdict, values=values))
    # A manifest may select different controls per gesture. Keep those checks
    # independent while presenting one continuous table per display profile.
    for profile, sampling in offsets.items():
        offset_label = ', '.join(str(n) for n in sorted(sampling, key=str))
        report += [f'## {profile}', '',
                   'Late frames are percentages; smoothness is physical pixels (lower is better). '
                   'Fling smoothness covers only released ballistic motion, including natural deceleration.', '',
                   f'App sampling: {offset_label}ms; '
                   'bare control uses its retained normal default (resampling off).', '',
                   '| Screen / speed | Late before / control / after | Smoothness before / control / after | Runs B/C/A | Result |',
                   '| --- | ---: | ---: | --- | --- |']
        for row in (r for r in rows if r['profile'] == profile):
            values = row['values']
            cells = [' / '.join('N/A' if values[s] is None else
                                format(values[s][metric], '.2f' if metric == 'latePct' else '.3f')
                                for s in ('before', 'control', 'after')) for metric in ('latePct', 'jerkPxMean')]
            counts = '/'.join(str(values[s]['runs']) if values[s] else '—' for s in ('before', 'control', 'after'))
            report.append(f'| {row["screen"]} / {row["speed"]} | {cells[0]} | {cells[1]} | {counts} | {row["result"]} |')
        report.append('')
    return rows, '\n'.join(report)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    result, markdown = compare(json.loads(Path(args.manifest).read_text(encoding='utf-8-sig')))
    Path(args.output).with_suffix('.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    Path(args.output).with_suffix('.md').write_text(markdown, encoding='utf-8')
    print(f'{len(result)} groups; {sum(r["result"] == "Pass" for r in result)} pass; '
          f'{sum(r["result"].startswith("Miss") for r in result)} miss; '
          f'{sum(r["result"].startswith("Unmeasured") for r in result)} unmeasured')
