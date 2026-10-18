"""Synthetic, host-only checks for performance measurement and acceptance gates."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from compare_performance_polish import compare
from summarize_app_profile import drag_metrics, summarize


def event(time, kind, delay=0):
    return {'timeUs': time, 'event': kind, 'delayUs': delay}


def offset(time, value, keyboard=300):
    return {'systemUs': time, 'offset': value, 'keyboardPx': keyboard}


def sample(name='shopping-fast'):
    return {
        'interaction': name, 'diagnostic': False, 'warmup': False,
        'motion': {'boundaryLimited': False, 'velocityDpPerSecond': 700,
                   'requestedDistanceDp': 40},
        'frames': [{'buildUs': 1000, 'rasterUs': 1000} for _ in range(100)],
        'input': [event(0, 'PointerDownEvent'),
                  event(230_000, 'PointerMoveEvent'),
                  event(300_000, 'PointerUpEvent')],
        'offsets': [offset(t, i * 4) for i, t in enumerate(range(100_000, 200_001, 10_000))],
    }


class DragMetricsTests(unittest.TestCase):
    def test_motion_evidence_is_preserved_without_inventing_missing_values(self):
        value = sample()
        measured = drag_metrics(value, 2)
        self.assertIs(measured['boundaryLimited'], False)
        self.assertEqual(measured['velocityDpPerSecond'], 700)
        self.assertEqual(measured['requestedDistanceDp'], 40)
        value.pop('motion')
        measured = drag_metrics(value, 2)
        for field in ('boundaryLimited', 'velocityDpPerSecond', 'requestedDistanceDp'):
            self.assertIsNone(measured[field])

    def test_fast_has_its_own_short_trim_and_slow_ignores_release_pause(self):
        value = sample()
        value['input'] = [event(0, 'PointerDownEvent'),
                          event(1_600_000, 'PointerMoveEvent'),
                          event(2_500_000, 'PointerUpEvent')]
        value['offsets'] = [offset(t, t / 10_000) for t in range(0, 2_500_001, 10_000)]
        fast = drag_metrics(value, 2)
        self.assertEqual(fast['smoothnessSamples'], 146)
        self.assertEqual(fast['segment'], 'held-drag')
        self.assertEqual(fast['jerkPxMean'], 0)
        self.assertEqual(fast['stepPxMean'], 2)
        for speed in ('slow', 'medium'):
            with self.subTest(speed=speed):
                value['interaction'] = f'shopping-{speed}'
                measured = drag_metrics(value, 2)
                self.assertEqual(measured['smoothnessSamples'], 69)
                self.assertEqual(measured['stepPxMean'], 2)

    def test_fling_uses_released_ballistic_motion_and_excludes_stationary_tail(self):
        value = sample('shopping-fling')
        value['input'] = [event(0, 'PointerDownEvent'),
                          event(1_990_000, 'PointerMoveEvent'),
                          event(2_000_000, 'PointerUpEvent')]
        value['offsets'] = [offset(t, x) for t, x in [
            (0, 0), (100_000, 10), (2_010_000, 20),
            (2_060_000, 100), (2_070_000, 109), (2_080_000, 117),
            (2_090_000, 124), (2_100_000, 130), (2_200_000, 130),
        ]]
        measured = drag_metrics(value, 2)
        self.assertEqual(measured['segment'], 'released-ballistic')
        self.assertEqual(measured['smoothnessSamples'], 3)
        self.assertEqual(measured['jerkPxMean'], 2)
        self.assertEqual(measured['stepPxMean'], 15)

    def test_physical_pixel_alignment_includes_trimmed_startup(self):
        value = sample()
        value['offsets'].insert(0, offset(0, 0.25))
        measured = drag_metrics(value, 2)
        self.assertEqual(measured['fractionalFrames'], 1)
        self.assertEqual(measured['maxPixelResidual'], 0.5)
        self.assertEqual(measured['jerkPxMean'], 0)
        value['offsets'][0]['offset'] = 0.5
        self.assertEqual(drag_metrics(value, 2)['fractionalFrames'], 0)

    def test_keyboard_must_be_visible_in_every_recorded_frame(self):
        value = sample('editor-keyboard-fast')
        self.assertTrue(drag_metrics(value, 1)['keyboardVisibleAll'])
        value['offsets'].insert(0, offset(0, 0, keyboard=0))
        self.assertFalse(drag_metrics(value, 1)['keyboardVisibleAll'])
        del value['offsets'][0]['keyboardPx']
        self.assertFalse(drag_metrics(value, 1)['keyboardVisibleAll'])


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cookdex-polish-unit-')
        self.addCleanup(self.temp.cleanup)
        self.job = {'profile': 'synthetic-phone', 'screens': ['shopping'],
                    'speeds': ['fast'], 'repetitions': 2}
        self.raw = {}
        for stage in ('before', 'control', 'after'):
            self.job[stage] = str(Path(self.temp.name) / stage)
            name = 'text-fast' if stage == 'control' else 'shopping-fast'
            self.raw[stage] = {
                'complete': True, 'error': None, 'control': stage == 'control',
                'refreshHz': 120, 'dpr': 2, 'widthPx': 824, 'heightPx': 1784,
                'config': {'diagnostic': False, 'resampling': stage != 'control', 'samplingOffsetMs': -8},
                'results': [sample(name), sample(name)],
            }

    def write(self):
        for stage, data in self.raw.items():
            path = Path(self.job[stage]) / 'data/frames.json'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data), encoding='utf-8')

    def compare(self):
        self.write()
        return compare([self.job])

    def test_complete_matched_measurements_pass(self):
        rows, markdown = self.compare()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['result'], 'Pass')
        self.assertIn('2/2/2 | Pass', markdown)

    def test_incomplete_or_error_in_any_stage_is_rejected(self):
        for stage in self.raw:
            for field, bad in [('complete', False), ('error', 'interrupted')]:
                with self.subTest(stage=stage, field=field):
                    old = self.raw[stage][field]
                    self.raw[stage][field] = bad
                    with self.assertRaisesRegex(ValueError, f'Incomplete {stage}'):
                        self.compare()
                    self.raw[stage][field] = old

    def test_instrumented_config_in_any_stage_is_rejected(self):
        for stage in self.raw:
            with self.subTest(stage=stage):
                self.raw[stage]['config']['diagnostic'] = True
                with self.assertRaisesRegex(ValueError, f'Instrumented {stage}'):
                    self.compare()
                self.raw[stage]['config']['diagnostic'] = False

    def test_diagnostic_and_warmup_samples_never_count_as_repetitions(self):
        original = copy.deepcopy(self.raw['after']['results'])
        for flag in ('diagnostic', 'warmup'):
            with self.subTest(flag=flag):
                self.raw['after']['results'] = copy.deepcopy(original)
                self.raw['after']['results'][0][flag] = True
                with self.assertRaisesRegex(ValueError, 'Insufficient repetitions after'):
                    self.compare()
                summary = summarize(Path(self.job['after']) / 'data/frames.json')
                self.assertEqual(summary['rows']['shopping-fast']['runs'], 1)

    def test_mismatched_profile_dimensions_or_refresh_are_rejected(self):
        for field in ('refreshHz', 'dpr', 'widthPx', 'heightPx'):
            with self.subTest(field=field):
                old = self.raw['after'][field]
                self.raw['after'][field] = old + 1
                with self.assertRaisesRegex(ValueError, f'Unmatched {field}'):
                    self.compare()
                self.raw['after'][field] = old

    def test_reversed_app_control_identity_is_rejected(self):
        self.raw['control']['control'] = False
        with self.assertRaisesRegex(ValueError, 'identities reversed'):
            self.compare()

    def test_app_resampling_or_sampling_offset_mismatch_is_rejected(self):
        for field, bad in [('resampling', False), ('samplingOffsetMs', -4)]:
            with self.subTest(field=field):
                old = self.raw['after']['config'][field]
                self.raw['after']['config'][field] = bad
                with self.assertRaisesRegex(ValueError, f'Unmatched {field}'):
                    self.compare()
                self.raw['after']['config'][field] = old

    def test_normal_default_control_off_accepts_matching_apps_with_resampling_on(self):
        self.assertFalse(self.raw['control']['config']['resampling'])
        self.assertTrue(self.raw['before']['config']['resampling'])
        self.assertTrue(self.raw['after']['config']['resampling'])
        rows, markdown = self.compare()
        self.assertEqual(rows[0]['result'], 'Pass')
        self.assertIn('bare control uses its retained normal default (resampling off)', markdown)

    def test_control_sampling_offset_is_irrelevant_when_resampling_is_off(self):
        self.raw['control']['config']['samplingOffsetMs'] = -99
        self.assertEqual(self.compare()[0][0]['result'], 'Pass')

    def test_resampled_control_is_not_the_acceptance_reference(self):
        self.raw['control']['config']['resampling'] = True
        with self.assertRaisesRegex(ValueError, 'normal-default bare control'):
            self.compare()

    def test_one_invalid_repeat_cannot_hide_among_eleven_valid_repeats(self):
        self.job['repetitions'] = 12
        for data in self.raw.values():
            data['results'] = [copy.deepcopy(data['results'][0]) for _ in range(12)]
        for stage in self.raw:
            for field in ('frames', 'input'):
                with self.subTest(stage=stage, field=field):
                    old = self.raw[stage]['results'][7][field]
                    self.raw[stage]['results'][7][field] = []
                    with self.assertRaisesRegex(ValueError, f'Invalid individual repeat {stage}'):
                        self.compare()
                    self.raw[stage]['results'][7][field] = old

    def test_missing_boundary_evidence_in_one_repeat_is_rejected(self):
        for stage in self.raw:
            with self.subTest(stage=stage):
                self.raw[stage]['results'][1]['motion'].pop('boundaryLimited')
                with self.assertRaisesRegex(ValueError, f'Missing boundary evidence {stage}'):
                    self.compare()
                self.raw[stage]['results'][1]['motion']['boundaryLimited'] = False

    def test_boundary_limited_repeat_in_any_stage_is_unmeasured(self):
        for stage in self.raw:
            with self.subTest(stage=stage):
                self.raw[stage]['results'][1]['motion']['boundaryLimited'] = True
                rows, markdown = self.compare()
                self.assertEqual(rows[0]['result'], 'Unmeasured (boundary-limited motion)')
                self.assertIn('Unmeasured (boundary-limited motion)', markdown)
                self.raw[stage]['results'][1]['motion']['boundaryLimited'] = False

    def test_required_repetitions_and_separate_control_requirement_are_enforced(self):
        self.job['repetitions'] = 12
        with self.assertRaisesRegex(ValueError, 'Insufficient repetitions before'):
            self.compare()
        self.job['repetitions'] = 2
        self.job['controlRepetitions'] = 3
        with self.assertRaisesRegex(ValueError, 'Insufficient repetitions control'):
            self.compare()

    def test_missing_frames_or_insufficient_motion_cannot_pass(self):
        original = copy.deepcopy(self.raw['after']['results'])
        for failure in ('no frames', 'no input', 'too few motion triples'):
            with self.subTest(failure=failure):
                self.raw['after']['results'] = copy.deepcopy(original)
                for value in self.raw['after']['results']:
                    if failure == 'no frames':
                        value['frames'] = []
                    elif failure == 'no input':
                        value['input'] = []
                    else:
                        value['offsets'] = value['offsets'][:4]
                expected = 'Insufficient motion samples' if failure == 'too few motion triples' else 'Invalid individual repeat'
                with self.assertRaisesRegex(ValueError, expected):
                    self.compare()

    def test_stationary_and_sub_twenty_dp_gestures_are_rejected(self):
        for distance in (0, 19):
            for stage in self.raw:
                with self.subTest(distance=distance, stage=stage):
                    original = copy.deepcopy(self.raw[stage]['results'])
                    for value in self.raw[stage]['results']:
                        for index, point in enumerate(value['offsets']):
                            point['offset'] = distance * index / 10
                    with self.assertRaisesRegex(ValueError, f'Insufficient scroll distance {stage}'):
                        self.compare()
                    self.raw[stage]['results'] = original

    def test_twenty_dp_motion_boundary_is_accepted(self):
        for data in self.raw.values():
            for value in data['results']:
                for index, point in enumerate(value['offsets']):
                    point['offset'] = index * 2
        self.assertEqual(self.compare()[0][0]['result'], 'Pass')

    def test_keyboard_dismissal_in_any_stage_is_rejected(self):
        self.job['screens'] = ['editor-keyboard']
        for stage, data in self.raw.items():
            name = 'fields-keyboard-fast' if stage == 'control' else 'editor-keyboard-fast'
            for value in data['results']:
                value['interaction'] = name
        self.assertEqual(self.compare()[0][0]['result'], 'Pass')
        for stage in ('before', 'control', 'after'):
            with self.subTest(stage=stage):
                self.raw[stage]['results'][0]['offsets'][0]['keyboardPx'] = 0
                with self.assertRaisesRegex(ValueError, 'dismissed its keyboard'):
                    self.compare()
                self.raw[stage]['results'][0]['offsets'][0]['keyboardPx'] = 300

    def test_late_frame_tolerance_is_one_percentage_point(self):
        for value in self.raw['after']['results']:
            value['frames'][0]['buildUs'] = 20_000
        self.assertEqual(self.compare()[0][0]['result'], 'Pass')
        for value in self.raw['after']['results']:
            value['frames'][1]['rasterUs'] = 20_000
        self.assertEqual(self.compare()[0][0]['result'], 'Miss: late')

    def test_keyboard_control_requires_equal_gesture_distance_and_velocity(self):
        self.job['screens'] = ['editor-keyboard']
        for stage, data in self.raw.items():
            for value in data['results']:
                value['interaction'] = 'fields-keyboard-fast' if stage == 'control' else 'editor-keyboard-fast'
        for field in ('requestedDistanceDp', 'velocityDpPerSecond'):
            with self.subTest(field=field):
                self.raw['control']['results'][0]['motion'][field] += 1
                with self.assertRaisesRegex(ValueError, 'Unmatched gesture'):
                    self.compare()
                self.raw['control']['results'][0]['motion'][field] -= 1

    def test_other_surfaces_also_require_matching_gestures(self):
        self.raw['control']['results'][1]['motion']['requestedDistanceDp'] = 39
        with self.assertRaisesRegex(ValueError, 'Unmatched gesture'):
            self.compare()

    def test_fractional_pixels_and_worse_smoothness_are_reported_as_misses(self):
        self.raw['after']['results'][0]['offsets'].insert(0, offset(0, 0.25))
        self.assertEqual(self.compare()[0][0]['result'], 'Miss: pixels')
        self.raw['after']['results'][0]['offsets'].pop(0)
        self.raw['after']['results'][0]['offsets'][4]['offset'] += 1
        self.assertEqual(self.compare()[0][0]['result'], 'Miss: smoothness')


if __name__ == '__main__':
    unittest.main()
