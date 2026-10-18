"""Summarize separate instrumented traces; never mix these into frame timing."""
import argparse
import collections
import json
import re
from pathlib import Path


ROOTS = ('CookdexApp', 'RecipesScreen', 'RecipeDetail', 'RecipeEditor',
         'ShoppingScreen', 'SettingsScreen', 'SyncScreen',
         'SyncDeviceDetailsScreen', 'ConflictsScreen', 'PairingScreen', 'ImportScreen',
         'SmartSettingsScreen', 'HowCookdexWorksScreen', '_EditorField',
         'EditableText', 'RetainedScreen', 'VisibleListenableBuilder')


def summarize(folder):
    folder = Path(folder)
    data = json.loads((folder / 'frames.json').read_text(encoding='utf-8-sig'))
    result = {}
    for sample in data['results']:
        if not sample['diagnostic'] or sample['warmup']:
            continue
        name, run = sample['interaction'], sample['run']
        trace = json.loads((folder / f'trace-{name}-{run}.json').read_text())
        # Build profiling names are widget runtime types. Layout profiling names
        # start Render; scheduler phases are uppercase. Count only build spans.
        builds = [e for e in trace['traceEvents']
                  if e.get('cat') == 'Dart' and e.get('ph') in ('B', 'X')
                  and re.fullmatch(r'_?[A-Z][A-Za-z0-9_]*(?:<.*>)?', e.get('name', ''))
                  and not e['name'].isupper() and not e['name'].lstrip('_').startswith('Render')
                  and e['name'] != 'Frame']
        counts = collections.Counter(e['name'] for e in builds)
        row = {'roots': {n: counts[n] for n in ROOTS},
               'allBuildSpans': dict(counts),
               'mountedBefore': sample['mountedBefore'],
               'mountedAfter': sample['mountedAfter']}
        frames = sample['offsets']
        no_new = []
        for previous, frame in zip(frames, frames[1:]):
            if frame['newElements'] == 0:
                no_new.append(sum(previous['wallUs'] < e['ts'] <= frame['wallUs']
                                  for e in builds))
        if no_new:
            row['noNewElementFrames'] = len(no_new)
            row['buildsPerNoNewElementFrameMean'] = sum(no_new) / len(no_new)
            row['buildsPerNoNewElementFrameMax'] = max(no_new)
            row['zeroBuildFrames'] = no_new.count(0)
        result[name] = row
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    parser.add_argument('--output')
    args = parser.parse_args()
    result = summarize(args.directory)
    text = json.dumps(result, indent=2)
    if args.output:
        Path(args.output).write_text(text, encoding='utf-8')
    print(text)
