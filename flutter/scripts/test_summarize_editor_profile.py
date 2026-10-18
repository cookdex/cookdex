"""Regression checks for statistics/coverage used by the physical benchmark."""
import json
from pathlib import Path
import tempfile
import unittest

from summarize_editor_profile import percentiles, summarize
from assess_editor_profile import assess


class ProfileSummaryTests(unittest.TestCase):
    def bounded_fixture(self):
        data = self.fixture()
        data.update(ingredients=30, steps=20, repetitions=1)
        data['results'] = []
        for name in ('baseline-recipe-scroll', 'editor-open', 'editor-scroll',
                     'editor-keyboard', 'editor-keyboard-close', 'editor-typing', 'editor-save-return'):
            data['results'].append({'interaction': name, 'run': 1, 'warmup': False, 'diagnostic': False,
                                    'frames': [{'buildUs': 8300, 'rasterUs': 4000} for _ in range(100)]})
        return data

    def test_finish_line_uses_exact_percentiles_and_maximum(self):
        data = self.bounded_fixture()
        scrolling = data['results'][2]['frames']
        for i in range(80, 99):
            scrolling[i]['buildUs'] = 16700
        scrolling[99]['buildUs'] = 16701  # exactly 1% exceeds 60Hz threshold
        self.assertTrue(assess(data)['editor-scroll']['pass'])
        scrolling[98]['buildUs'] = 16701
        self.assertFalse(assess(data)['editor-scroll']['pass'])
        data['results'][1]['frames'][0]['buildUs'] = 33001
        self.assertFalse(assess(data)['editor-open']['pass'])

    def test_baseline_fallback_is_explicit_and_stage_specific(self):
        data = self.bounded_fixture()
        for f in data['results'][0]['frames']:
            f['buildUs'] = 9000
        for f in data['results'][2]['frames']:
            f['buildUs'] = 9000
            f['rasterUs'] = 8500
        result = assess(data)['editor-scroll']
        self.assertFalse(result['pass'])  # a slow UI baseline cannot excuse raster
        self.assertTrue(result['checks'][0]['baselineFallback'])

    def test_nearest_rank_percentiles(self):
        self.assertEqual(percentiles(list(range(1000, 101000, 1000))),
                         {'p50': 50.0, 'p80': 80.0, 'p90': 90.0, 'p99': 99.0})

    def fixture(self):
        samples = []
        for name in ('baseline-recipe-scroll', 'editor-open', 'editor-scroll',
                     'editor-keyboard', 'editor-typing', 'editor-save-return'):
            for run in range(4):
                samples.append({'interaction': name, 'run': run,
                                'warmup': run == 0, 'diagnostic': run == 3,
                                'startUs': 1, 'endUs': 100001,
                                'afterFields': {}, 'frames': [
                                    {'buildUs': 2000, 'rasterUs': 9000,
                                     'totalUs': 15000, 'vsyncUs': 1000},
                                    {'buildUs': 4000, 'rasterUs': 3000,
                                     'totalUs': 15000, 'vsyncUs': 2000}]})
        return {'complete': True, 'device': 'Pixel 7 Pro', 'mode': 'profile',
                'targetHz': 120, 'refreshRate': 120, 'ingredients': 80,
                'steps': 50, 'repetitions': 2, 'results': samples}

    def read(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'frames.json'
            path.write_text(json.dumps(data), encoding='utf-8')
            return summarize(path)

    def test_exclusions_and_pipeline_budget(self):
        result = self.read(self.fixture())['interactions']['editor-open']
        self.assertEqual(result['frames'], 4)  # neither warm-up nor diagnosis
        self.assertEqual(result['janky'], 2)  # not all four total spans
        self.assertEqual(result['jankyPercent'], 50)

    def test_rejects_duplicates_missing_and_incomplete(self):
        for change in ('duplicate', 'missing', 'incomplete'):
            data = self.fixture()
            if change == 'duplicate':
                data['results'].append(data['results'][1])
            elif change == 'missing':
                data['results'].pop(1)
            else:
                data['complete'] = False
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.read(data)


if __name__ == '__main__':
    unittest.main()
