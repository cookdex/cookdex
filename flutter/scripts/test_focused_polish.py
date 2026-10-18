import copy
import json
from pathlib import Path
import tempfile
import unittest

from compare_focused_polish import compare
from test_performance_polish import sample, offset


class FocusedComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cookdex-focused-unit-')
        self.addCleanup(self.temp.cleanup)
        self.paths = [Path(self.temp.name) / f'{stage}.json' for stage in ('before', 'after')]
        data = dict(complete=True, control=False, refreshHz=120, dpr=2,
                    widthPx=1080, heightPx=2340, libraryCount=60,
                    config=dict(screens=['library-cards'], speeds=['fast', 'fling'],
                                samplingOffsetMs=-16, realLibrary=True, paddingCount=45), results=[])
        for speed in ('fast', 'fling'):
            for run in range(1, 6):
                row = sample(f'library-cards-{speed}')
                row['run'] = run
                if speed == 'fling':
                    row['offsets'] = [offset(t, i * 4) for i, t in enumerate(range(0, 600001, 10000))]
                    row['motion']['velocityDpPerSecond'] = 2000
                data['results'].append(row)
        self.data = [copy.deepcopy(data), copy.deepcopy(data)]

    def compare(self):
        for path, data in zip(self.paths, self.data):
            path.write_text(json.dumps(data), encoding='utf-8')
        return compare(*self.paths)

    def test_matched_five_repeats_and_boundary_limit_are_reported(self):
        self.assertEqual(self.compare()['library-cards-fast']['status'], 'Measured')
        self.data[1]['results'][-1]['motion']['boundaryLimited'] = True
        self.assertEqual(self.compare()['library-cards-fling']['status'], 'Boundary-limited')

    def test_failed_or_instrumented_job_is_rejected(self):
        self.data[1]['complete'] = False
        with self.assertRaises(ValueError): self.compare()
        self.data[1]['complete'] = True
        self.data[1]['config']['diagnostic'] = True
        with self.assertRaises(ValueError): self.compare()

    def test_one_duplicated_repeat_is_rejected(self):
        self.data[1]['results'][0]['run'] = 2
        with self.assertRaises(ValueError): self.compare()

    def test_changed_offset_or_input_is_rejected(self):
        self.data[1]['config']['samplingOffsetMs'] = -38
        with self.assertRaises(ValueError): self.compare()
        self.data[1]['config']['samplingOffsetMs'] = -16
        self.data[1]['results'][0]['motion']['requestedDistanceDp'] = 25
        with self.assertRaises(ValueError): self.compare()

    def test_missing_motion_metadata_is_rejected(self):
        self.data[1]['results'][0].pop('motion')
        with self.assertRaises(ValueError): self.compare()

    def test_missing_workload_is_explicit(self):
        self.data[1]['results'] = self.data[1]['results'][:5]
        self.assertTrue(self.compare()['library-cards-fling']['status'].startswith('Not measured'))


if __name__ == '__main__':
    unittest.main()
