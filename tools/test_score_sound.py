#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Independent synthetic sound fixtures; no ROM, MAME or captured game bytes.

Mutation-shaped output corruptions are repeated twice. These prove scorer
detection, not that a particular RTL mutation changes the captured CPU writes.
"""

import contextlib
import csv
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import wave

import numpy as np

from tools import score_sound as scorer


RATE = 48000
TIMELINE = [[0.0, '0xe6'], [0.5, '0x65']]


def tone(frequency=440, delay=0, duration=.30, rate=RATE):
    """Two independent gated notes with exact known onset/duration."""
    t = np.arange(rate) / rate
    signal = np.zeros(rate)
    for start in (.05 + delay, .55 + delay):
        local = t - start
        mask = (local >= 0) & (local < duration)
        # A varying envelope makes correlation meaningful instead of constant.
        signal[mask] = .4 * np.sin(2 * np.pi * frequency * local[mask]) * (
            .6 + .4 * np.sin(np.pi * local[mask] / duration))
    return signal


def fixture(path, signal=None, events=None, rate=RATE, source='mame'):
    path.mkdir(parents=True, exist_ok=True)
    if signal is None:
        signal = tone(rate=rate)
    if events is None:
        events = [(start + delta, round((start + delta) * 1000000), address, value)
                  for start in (0, .5)
                  for delta, address, value in ((.05, 0x1840, 0x64), (.10, 0x1880, 0x80),
                                                (.15, 0x1882, 0x80), (.20, 0x1884, 0x01))]
    with (path / 'timeline.csv').open('w', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['seconds', 'command'])
        writer.writerows(TIMELINE)
    with (path / 'dac-events.csv').open('w', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['seconds', 'audio_cpu_cycle', 'address', 'value'])
        writer.writerows((f'{t:.9f}', c, f'0x{a:04x}', f'0x{v:02x}') for t, c, a, v in events)
    manifest = dict(source=source, version='synthetic-independent-fixture-v1',
                    sample_rate=rate, audio_cpu_cycle_hz=1000000,
                    duration_seconds=len(signal) / rate, timeline=TIMELINE, seed=1234,
                    notes=['Synthetic: cycle count = seconds * 1000000; no board/reference claim'])
    (path / 'manifest.json').write_text(json.dumps(manifest))
    with wave.open(str(path / 'mix.wav'), 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(np.round(signal * 32767).astype('<i2').tobytes())
    return events


class SoundScoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.ref, self.dut = self.root / 'ref', self.root / 'dut'
        self.events = fixture(self.ref)
        fixture(self.dut, source='rtl')
        self.thresholds = self.root / 'thresholds.json'
        self.output = self.root / 'score.json'
        self.assertEqual(self.invoke('--calibrate', self.ref, self.ref,
                                     '--output', self.thresholds)[0], 0)

    def invoke(self, *args):
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            code = scorer.main([str(a) for a in args])
        return code, stream.getvalue()

    def score(self, thresholds=None):
        code, table = self.invoke(self.ref, self.dut, '--output', self.output,
                                  '--thresholds', thresholds or self.thresholds)
        return code, json.loads(self.output.read_text()), table

    def test_identical_cli_pass(self):
        result = subprocess.run([sys.executable, 'tools/score_sound.py', str(self.ref),
                                 str(self.dut), '--output', str(self.output),
                                 '--thresholds', str(self.thresholds)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(self.output.read_text())
        self.assertEqual(report['status'], 'PASS')
        self.assertIn('| 0 0xe6 | yes / yes | 1 | 0 | 0 | 0 | PASS', result.stdout)
        self.assertEqual(report['clock_ratio']['dut_over_ref'], 1)
        for segment in report['segments']:
            self.assertGreater(segment['waveform']['ref_voiced_frames'], 0)
            self.assertAlmostEqual(segment['waveform']['envelope_correlation'], 1)
            self.assertTrue(all(v is not None for v in segment['metrics'].values()))

    def test_dropped_and_altered_events_twice(self):
        for kind in ('drop', 'alter', 'append'):
            for repeat in range(2):
                with self.subTest(kind=kind, repeat=repeat):
                    events = list(self.events)
                    if kind == 'drop':
                        del events[2]
                    elif kind == 'alter':
                        t, c, a, v = events[2]
                        events[2] = (t, c, a, v ^ 0x80)
                    else:
                        events.insert(4, (.25, 250000, 0x1840, 0))
                    fixture(self.dut, events=events)
                    code, report, _ = self.score()
                    self.assertEqual(code, 1)
                    segment = report['segments'][0]
                    self.assertIn('event_match', segment['failures'])
                    self.assertEqual(segment['events']['first_divergence_index'], 4 if kind == 'append' else 2)

    def test_extracted_bits_are_additional_not_primary(self):
        events = [(t, c, a, v ^ 0x02 if a != 0x1840 else v) for t, c, a, v in self.events]
        fixture(self.dut, events=events)
        code, report, _ = self.score()
        self.assertEqual(code, 1)
        for segment in report['segments']:
            self.assertFalse(segment['events']['raw_match'])
            self.assertTrue(segment['events']['extracted_match'])
            self.assertEqual(segment['events']['first_divergence_index'], 1)
        # Each relevant bit and alias must be extracted using its own rule.
        events = [(0, i, a, 0x81) for i, a in enumerate(range(0x1880, 0x1888))]
        self.assertEqual(scorer.event_view(events, True), [(a, 1) for a in range(0x1880, 0x1888)])
        events = [(0, i, a, 0x7e) for i, a in enumerate(range(0x1880, 0x1888))]
        self.assertEqual(scorer.event_view(events, True), [(a, 0) for a in range(0x1880, 0x1888)])

    def test_silence_hard_fail_null_and_lenient_twice(self):
        nulls = self.root / 'null.json'
        nulls.write_text(json.dumps(dict.fromkeys(scorer.NUMERIC_FLOORS) |
                                   {'provenance': 'not yet calibrated'}))
        lenient = self.root / 'lenient.json'
        lenient.write_text(json.dumps(dict.fromkeys(scorer.NUMERIC_FLOORS, 1e20) |
                                     {'provenance': 'synthetic lenient test'}))
        for thresholds in (nulls, lenient):
            for repeat in range(2):
                with self.subTest(thresholds=thresholds.name, repeat=repeat):
                    fixture(self.dut, signal=np.zeros(RATE))
                    code, report, _ = self.score(thresholds)
                    self.assertEqual(code, 1)
                    self.assertEqual(report['silence_floor_dbfs'], -50)
                    self.assertIn('silence', report['segments'][0]['failures'])
                    self.assertGreater(report['segments'][0]['waveform']['ref_rms'], .01)
                    self.assertEqual(report['segments'][0]['waveform']['dut_rms'], 0)

    def test_uniform_slow_clock_reported_without_correction(self):
        # Times and cycle-derived seconds both increase; no command boundary is crossed.
        events = [(t * 1.0108, round(c * 1.0108), a, v) for t, c, a, v in self.events]
        fixture(self.dut, events=events)
        code, report, _ = self.score()
        self.assertEqual(code, 1)
        self.assertAlmostEqual(report['clock_ratio']['dut_over_ref'], 1.0108, places=9)
        self.assertTrue(report['clock_ratio']['uniform'])
        self.assertFalse(report['clock_ratio']['corrected'])
        for segment in report['segments']:
            self.assertTrue(segment['events']['raw_match'])
            self.assertIn('interval_ratio_max_abs_deviation', segment['failures'])
            self.assertAlmostEqual(segment['intervals']['max_abs_deviation'], .0108)

    def test_spectral_and_pitch_failure_twice(self):
        for repeat in range(2):
            with self.subTest(repeat=repeat):
                fixture(self.dut, signal=tone(880))
                code, report, _ = self.score()
                self.assertEqual(code, 1)
                segment = report['segments'][0]
                self.assertTrue(segment['events']['raw_match'])
                self.assertIn('log_spectral_distance_db', segment['failures'])
                self.assertIn('pitch_error_cents', segment['failures'])
                self.assertGreater(segment['metrics']['log_spectral_distance_db'], 5)
                self.assertAlmostEqual(segment['metrics']['pitch_error_cents'], 1200, delta=5)

    def test_mutation_shaped_outputs_designated_failures_twice(self):
        # The five contract mutation classes, represented at the output boundary.
        for mutation in ('wrong_bit', 'stuck_lat2', 'no_irq', 'half_ce', 'reversed_weights'):
            for repeat in range(2):
                with self.subTest(mutation=mutation, repeat=repeat):
                    signal, events = tone(), list(self.events)
                    if mutation == 'wrong_bit':
                        events = [(t, c, a, v & 1 if 0x1880 <= a <= 0x1883 else v)
                                  for t, c, a, v in events]
                    elif mutation == 'stuck_lat2':
                        events = [(t, c, a, 0 if a == 0x1882 else v) for t, c, a, v in events]
                        signal = np.zeros(RATE)
                    elif mutation == 'no_irq':
                        events, signal = [], np.zeros(RATE)
                    elif mutation == 'half_ce':
                        # Count-derived intervals doubled while keeping fixed REF segments.
                        events = [(t, c * 2, a, v) for t, c, a, v in events]
                    else:
                        signal = tone(880)
                    fixture(self.dut, signal=signal, events=events)
                    code, report, _ = self.score()
                    self.assertEqual(code, 1)
                    failures = report['segments'][0]['failures']
                    expected = {'wrong_bit': ['event_match'], 'stuck_lat2': ['event_match', 'silence'],
                                'no_irq': ['event_match', 'silence'],
                                'half_ce': ['interval_ratio_max_abs_deviation'],
                                'reversed_weights': ['log_spectral_distance_db']}[mutation]
                    for failure in expected:
                        self.assertIn(failure, failures)

    def test_uncalibrated_default_reports_metrics_never_passes(self):
        code, table = self.invoke(self.ref, self.dut, '--output', self.output)
        self.assertEqual(code, 2)
        report = json.loads(self.output.read_text())
        self.assertEqual(report['status'], 'NOT_SCORABLE')
        self.assertEqual(report['segments'][0]['metrics']['log_spectral_distance_db'], 0)
        self.assertIn('uncalibrated threshold', table)

    def test_calibrate_overwrite_guard_force_and_exact_margin(self):
        before = self.thresholds.read_bytes()
        code, table = self.invoke('--calibrate', self.ref, self.ref, '--output', self.thresholds)
        self.assertEqual(code, 2)
        self.assertIn('without --force', table)
        self.assertEqual(self.thresholds.read_bytes(), before)
        fixture(self.dut, signal=tone(442, delay=.002))
        code, _ = self.invoke('--calibrate', self.ref, self.dut, '--output', self.thresholds, '--force')
        self.assertEqual(code, 0)
        data = json.loads(self.thresholds.read_text())
        self.assertIn('3 * max', data['provenance'])
        self.assertGreater(data['observed_errors']['pitch_error_cents'], 5)
        for key, floor in scorer.NUMERIC_FLOORS.items():
            self.assertEqual(data[key], 3 * max(data['observed_errors'][key], floor))

    def test_calibration_rejects_event_mismatch_and_preserves_file(self):
        fixture(self.dut, events=self.events[1:])
        before = self.thresholds.read_bytes()
        code, table = self.invoke('--calibrate', self.ref, self.dut, '--output', self.thresholds, '--force')
        self.assertEqual(code, 2)
        self.assertIn('event or silence failures', table)
        self.assertEqual(self.thresholds.read_bytes(), before)

    def test_alignment_onset_duration_and_gain(self):
        fixture(self.dut, signal=tone(delay=.01))
        _, report, _ = self.score()
        segment = report['segments'][0]
        self.assertAlmostEqual(segment['waveform']['lag_ms'], 10, delta=.03)
        self.assertAlmostEqual(segment['metrics']['onset_error_ms'], 10, delta=.01)
        self.assertAlmostEqual(segment['metrics']['duration_error_ms'], 0)
        self.assertGreater(segment['waveform']['envelope_correlation'], .9999)
        fixture(self.dut, signal=tone(duration=.20))
        _, report, _ = self.score()
        self.assertAlmostEqual(report['segments'][0]['metrics']['duration_error_ms'], 100)
        # Exact integer gain/offset, avoiding quantization as an extra stimulus.
        fixture(self.dut, signal=(2 * np.round(tone() * 32767) + 3277) / 32767)
        _, report, _ = self.score()
        self.assertFalse(report['segments'][0]['waveform']['silence_fail'])
        self.assertLess(report['segments'][0]['metrics']['log_spectral_distance_db'], 1e-6)

    def test_sample_rate_mismatch_and_missing_files(self):
        fixture(self.dut, signal=tone(rate=44100), rate=44100)
        code, report, _ = self.score()
        self.assertEqual(code, 2)
        self.assertIn('sample-rate mismatch', report['incomplete'][0])
        (self.dut / 'mix.wav').unlink()
        code, report, _ = self.score()
        self.assertEqual(code, 2)
        self.assertIn('mix.wav', report['incomplete'][0])

    def test_missing_thresholds_retain_metrics_and_hard_failure(self):
        missing = self.root / 'missing.json'
        code, report, _ = self.score(missing)
        self.assertEqual(code, 2)
        self.assertEqual(report['segments'][0]['metrics']['log_spectral_distance_db'], 0)
        fixture(self.dut, signal=np.zeros(RATE))
        code, report, _ = self.score(missing)
        self.assertEqual(code, 1)
        self.assertIn('silence', report['segments'][0]['failures'])

    def test_alignment_is_bounded_and_covers_negative_lag(self):
        fixture(self.dut, signal=tone(delay=-.01))
        _, report, _ = self.score()
        self.assertAlmostEqual(report['segments'][0]['waveform']['lag_ms'], -10, delta=.03)
        # A nonperiodic deterministic stimulus avoids periodic-tone ambiguity.
        random = np.random.default_rng(2026).normal(0, .1, RATE)
        random[:4800] = 0
        random[-4800:] = 0
        delayed = np.concatenate((np.zeros(1440), random[:-1440]))
        fixture(self.ref, signal=random)
        fixture(self.dut, signal=delayed)
        _, report, _ = self.score()
        for segment in report['segments']:
            self.assertLessEqual(abs(segment['waveform']['lag_ms']), 20)
        self.assertAlmostEqual(report['segments'][0]['metrics']['onset_error_ms'], 30)

    def test_calibration_requires_metric_coverage(self):
        fixture(self.ref, signal=np.zeros(RATE), events=[])
        path = self.root / 'new-thresholds.json'
        code, table = self.invoke('--calibrate', self.ref, self.ref, '--output', path)
        self.assertEqual(code, 2)
        self.assertIn('no coverage', table)
        self.assertFalse(path.exists())

    def test_fixed_ref_boundaries_and_unequal_clocks(self):
        # A write exactly at the second command belongs to that segment.
        events = self.events + [(.5, 500000, 0x1840, 0x33)]
        events.sort()
        fixture(self.ref, events=events)
        fixture(self.dut, events=[(t, c * 2, a, v) for t, c, a, v in events])
        path = self.dut / 'manifest.json'
        data = json.loads(path.read_text())
        data['audio_cpu_cycle_hz'] = 2000000
        path.write_text(json.dumps(data))
        code, report, _ = self.score()
        self.assertEqual(code, 0)
        self.assertEqual([s['events']['ref_count'] for s in report['segments']], [4, 5])
        self.assertEqual(report['segments'][1]['intervals']['ratios'], [1, 1, 1, 1])

    def test_bad_inputs_do_not_pass(self):
        for change, message in (('timeline', 'timelines differ'), ('nan', 'non-finite'),
                                ('truncate', 'duration'), ('header', 'expected header')):
            with self.subTest(change=change):
                fixture(self.dut)
                if change in ('timeline', 'nan', 'truncate'):
                    path = self.dut / 'manifest.json'
                    data = json.loads(path.read_text())
                    if change == 'timeline':
                        data['timeline'][0][1] = '0x00'
                        (self.dut / 'timeline.csv').write_text('seconds,command\n0.0,0x00\n0.5,0x65\n')
                    elif change == 'nan':
                        data['audio_cpu_cycle_hz'] = float('nan')
                    else:
                        data['duration_seconds'] = 2
                    path.write_text(json.dumps(data))
                else:
                    (self.dut / 'dac-events.csv').write_text('invalid,header\n')
                code, report, _ = self.score()
                self.assertEqual(code, 2)
                self.assertIn(message, report['incomplete'][0])


if __name__ == '__main__':
    unittest.main()
