import json
from pathlib import Path
import tempfile
import unittest

from summarize_app_profile import drag_metrics, summarize
from compare_app_profile import compare


class AppProfileStatisticsTests(unittest.TestCase):
    def sample(self, offsets):
        return {'input': [{'timeUs': 0, 'delayUs': 0}, {'timeUs': 2_000_000, 'delayUs': 0}],
                'offsets': [{'systemUs': 900_000 + i * 10_000, 'offset': x}
                            for i, x in enumerate(offsets)]}

    def test_constant_velocity_and_fractional_pixels_are_separate(self):
        result = drag_metrics(self.sample([.1, 1.1, 2.1, 3.1]), 2)
        self.assertAlmostEqual(result['jerkPxMean'], 0)
        self.assertEqual(result['fractionalFrames'], 4)

    def test_stutter_and_whole_pixels_are_separate(self):
        result = drag_metrics(self.sample([0, 0, 2, 2]), 2)
        self.assertEqual(result['jerkPxMean'], 4)
        self.assertEqual(result['fractionalFrames'], 0)

    def test_alignment_checks_startup_even_when_jerk_trims_it(self):
        sample = self.sample([0, 1, 2, 3])
        sample['offsets'].insert(0, {'systemUs': 100_000, 'offset': .1})
        result = drag_metrics(sample, 2)
        self.assertEqual(result['fractionalFrames'], 1)
        self.assertEqual(result['offsetFrames'], 5)
        self.assertAlmostEqual(result['jerkPxMean'], 0)

    def test_timing_excludes_warmups_diagnostics_and_counts_either_stage_once(self):
        frame = lambda b, r: {'buildUs': b, 'rasterUs': r}
        samples = [
            {'interaction': 'scroll', 'diagnostic': False, 'warmup': False,
             'frames': [frame(8000, 8500), frame(9000, 9500), frame(1000, 1000)], 'input': []},
            {'interaction': 'scroll', 'diagnostic': True, 'warmup': False,
             'frames': [frame(99000, 99000)], 'input': []},
            {'interaction': 'scroll', 'diagnostic': False, 'warmup': True,
             'frames': [frame(99000, 99000)], 'input': []},
        ]
        scratch = Path(__file__).resolve().parents[2] / 'artifacts/app-performance/statistics-tests'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            path = Path(directory) / 'frames.json'
            path.write_text(json.dumps({'refreshHz': 120, 'dpr': 2,
                'control': False, 'complete': True, 'results': samples}), encoding='utf-8')
            row = summarize(path)['rows']['scroll']
        self.assertEqual(row['frames'], 3)
        self.assertEqual(row['late'], 2)
        self.assertEqual(row['runs'], 1)


class FinalComparisonEvidenceTests(unittest.TestCase):
    def make_runs(self, directory):
        root = Path(directory)
        for display in ('phone', 'tablet'):
            for stage in ('before', 'control', 'after'):
                names = (['text-slow', 'text-medium'] if stage == 'control'
                         else ['recipe-slow', 'recipe-medium', 'sync-slow'])
                samples = []
                for name in names:
                    for run in range(1, 13):
                        sample = AppProfileStatisticsTests().sample([0, 1, 2, 3])
                        samples.append(dict(sample, interaction=name, run=run,
                            diagnostic=False, warmup=False,
                            frames=[{'buildUs': 1000, 'rasterUs': 1000}]))
                data = {'complete': True, 'control': stage == 'control',
                        'refreshHz': 120 if display == 'phone' else 60,
                        'dpr': 2, 'widthPx': 1000, 'heightPx': 2000,
                        'config': {'diagnostic': False, 'resampling': stage == 'after',
                                   'screens': ['text'] if stage == 'control' else
                                              ['recipe', 'recipe-directions', 'sync', 'import']},
                        'results': samples,
                        'nonScrollable': [{'screen': 'sync', 'speed': 'medium'},
                                          {'screen': 'import', 'speed': 'slow'},
                                          {'screen': 'import', 'speed': 'medium'}]}
                path = root / f'final-{stage}-{display}' / 'data' / 'frames.json'
                path.parent.mkdir(parents=True)
                path.write_text(json.dumps(data), encoding='utf-8')
        return root

    def scratch(self):
        parent = Path(__file__).resolve().parents[2] / 'artifacts/app-performance/statistics-tests'
        parent.mkdir(parents=True, exist_ok=True)
        return tempfile.TemporaryDirectory(dir=parent)

    def test_short_content_is_partial_never_a_full_pass(self):
        with self.scratch() as directory:
            root = self.make_runs(directory)
            result, text = compare(root)
            self.assertTrue(result['phone']['screens']['recipe']['pass'])
            self.assertFalse(result['tablet']['screens']['sync']['pass'])
            self.assertFalse(result['tablet']['screens']['sync']['speeds']['medium']['measured'])
            self.assertIn('Partial', text)
            self.assertIn('N/A', text)

    def test_wholly_unmeasured_and_inapplicable_surfaces_stay_visible(self):
        with self.scratch() as directory:
            root = self.make_runs(directory)
            result, text = compare(root)
            self.assertEqual(result['phone']['screens']['import']['result'], 'Unmeasured')
            self.assertFalse(result['phone']['screens']['import']['pass'])
            self.assertIn('| import | N/A / N/A |', text)
            self.assertFalse(result['phone']['screens']['recipe-directions']['applicable'])
            self.assertIn('Not applicable (single pane)', text)

    def test_partial_surface_exposes_a_measured_failure(self):
        with self.scratch() as directory:
            root = self.make_runs(directory)
            path = root / 'final-after-tablet/data/frames.json'
            data = json.loads(path.read_text())
            for sample in data['results']:
                if sample['interaction'] == 'sync-slow':
                    sample['frames'][0]['buildUs'] = 99999
            path.write_text(json.dumps(data), encoding='utf-8')
            result, text = compare(root)
            sync = result['tablet']['screens']['sync']
            self.assertTrue(sync['measuredMiss'])
            self.assertEqual(sync['result'], 'Partial - measured miss')
            self.assertIn('Partial - measured miss', text)

    def test_configured_surface_missing_from_both_runs_is_rejected(self):
        with self.scratch() as directory:
            root = self.make_runs(directory)
            for stage in ('before', 'after'):
                path = root / f'final-{stage}-phone/data/frames.json'
                data = json.loads(path.read_text())
                data['results'] = [r for r in data['results'] if not r['interaction'].startswith('recipe-')]
                path.write_text(json.dumps(data), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'Unexpected missing measurement'):
                compare(root)

    def test_missing_repetition_or_unexplained_missing_speed_is_rejected(self):
        for missing in ('repetition', 'speed', 'screen'):
            with self.subTest(missing=missing), self.scratch() as directory:
                root = self.make_runs(directory)
                path = root / 'final-after-phone/data/frames.json'
                data = json.loads(path.read_text())
                if missing == 'screen':
                    data['results'] = [r for r in data['results'] if not r['interaction'].startswith('recipe-')]
                elif missing == 'speed':
                    data['results'] = [r for r in data['results'] if r['interaction'] != 'recipe-medium']
                else:
                    data['results'].pop(0)
                path.write_text(json.dumps(data), encoding='utf-8')
                with self.assertRaises(ValueError):
                    compare(root)


if __name__ == '__main__':
    unittest.main()
