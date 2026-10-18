"""Summarize instrumented new-row frames, never acceptance frame timings.

Pipeline phase time per newly materialized row includes the rest of that frame;
the steady-frame median is also reported so attribution is not overstated.
"""
import argparse
import collections
import json
from pathlib import Path
import statistics


def spans(events):
    stacks = collections.defaultdict(list)
    out = []
    for e in events:
        phase = e.get('ph')
        key = (e.get('pid'), e.get('tid'))
        if phase == 'B':
            stacks[key].append(e)
        elif phase == 'E' and stacks[key]:
            start = stacks[key].pop()
            out.append((start['name'], start['ts'], e['ts'], key))
        elif phase == 'X':
            out.append((e['name'], e['ts'], e['ts'] + e.get('dur', 0), key))
    return out


def diagnose(folder):
    root = Path(folder)
    data = json.loads((root / 'frames.json').read_text(encoding='utf-8-sig'))
    output = {}
    for sample in data['results']:
        if not sample['diagnostic'] or sample['warmup'] or not sample['offsets']:
            continue
        name = sample['interaction']
        trace = root / f"trace-{name}-{sample['run']}.json"
        events = spans(json.loads(trace.read_text(encoding='utf-8-sig'))['traceEvents'])
        counters = collections.defaultdict(list)
        steady = collections.defaultdict(list)
        row_count = 0
        rows = []
        for previous, offset in zip([None] + sample['offsets'], sample['offsets']):
            low = previous['wallUs'] if previous else sample['startUs']
            high = offset['wallUs']
            count = len(offset.get('newRows', []))
            bucket = counters if count else steady
            costs = {}
            for stage in ['BUILD', 'LAYOUT', 'PAINT', 'SEMANTICS']:
                phase_spans = [(start, end, thread) for n, start, end, thread in events
                               if n == stage and low <= start < high]
                cost_us = sum(end - start for start, end, _ in phase_spans)
                if stage == 'LAYOUT':
                    # Sliver child creation calls buildScope inside layout.
                    # Attribute nested BUILD to build, not to both columns.
                    cost_us -= sum(max(0, min(end, b_end) - max(start, b_start))
                                   for start, end, thread in phase_spans
                                   for n, b_start, b_end, b_thread in events
                                   if n == 'BUILD' and b_thread == thread and
                                   start <= b_start < end)
                cost = cost_us / 1000
                costs[stage] = cost
                bucket[stage].append(cost)
            if count:
                row_count += count
                rows.append(dict(rows=offset['newRows'], newElements=offset.get('newElements'), **costs))
        output[name] = {
            'newRows': row_count, 'newRowFrames': len(rows),
            'phaseMsPerNewRow': {k: sum(v) / row_count if row_count else None for k, v in counters.items()},
            'steadyFrameMedianMs': {k: statistics.median(v) if v else None for k, v in steady.items()},
            'newRowFramesDetail': rows,
            'keyboardVisibleAll': all(o.get('keyboardPx', 0) > 0 for o in sample['offsets']),
        }
    return {'semanticsEnabled': data['semanticsEnabled'], 'rows': output}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('data')
    parser.add_argument('--output')
    args = parser.parse_args()
    result = diagnose(args.data)
    if args.output:
        Path(args.output).write_text(json.dumps(result, indent=2), encoding='utf-8')
    for name, row in result['rows'].items():
        print(name, row['newRows'], row['phaseMsPerNewRow'], 'steady', row['steadyFrameMedianMs'])
