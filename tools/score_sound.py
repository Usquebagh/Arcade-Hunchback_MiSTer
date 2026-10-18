#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Compare sound capture directories without ROMs, MAME, scipy or resampling.

Reference class: capture compatibility, not board/analog accuracy. Segments are
half-open REF command intervals; the final one ends at the common WAV span.
Waveform timing is measured before alignment, shape after alignment. Duration
is the span of active 10 ms frames (including intervening gaps), not clip size.
Pitch is the interpolated dominant FFT peak, not a fundamental-frequency model.

Thresholds are upper bounds on errors (envelope error = 1 - correlation).
Calibration uses exactly 3 * max(worst observed error, numeric floor), without
fitting the DUT or correcting its clock. Floors are numerical tolerances only.
Missing calibration never passes; known hard failures still return exit 1.
"""

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import wave

import numpy as np


DEFAULT_THRESHOLDS = Path(__file__).resolve().parents[1] / 'sim/harness/sound_thresholds.json'
FLOOR_DBFS = -50.0
NUMERIC_FLOORS = {
    'interval_ratio_max_abs_deviation': 1e-9,
    'lag_ms': 1e-6,
    'onset_error_ms': 1e-6,
    'duration_error_ms': 1e-6,
    'envelope_correlation_error': 1e-9,
    'log_spectral_distance_db': 1e-6,
    'pitch_error_cents': 1e-6,
}
METHOD = {
    'segmentation': 'REF [command i, command i+1); final end = min(REF, DUT WAV frames) / sample rate',
    'intervals': 'diff(audio_cpu_cycle) / manifest.audio_cpu_cycle_hz; DUT / REF; no clock correction',
    'alignment': 'DC removal, unit RMS; FFT cross-correlation, +/-20 ms; positive lag = DUT later',
    'activity': 'nonoverlapping 10 ms RMS frames, first/last above -40 dB relative to segment peak absolute amplitude; before alignment',
    'duration': 'last active frame end minus first active frame start, including gaps',
    'envelope': 'Pearson correlation of aligned nonoverlapping 10 ms RMS frames; equal constants = 1, unequal constants = 0',
    'stft': '2048 samples (42.666667 ms at 48000 Hz), symmetric Hann (numpy.hanning), 1024-sample hop (50%); zero-pad final frame',
    'spectral_distance': 'RMS difference of 20log10 magnitudes, floor -100 dB, on REF active frames; unit-RMS clips',
    'pitch': 'median absolute cents on shared voiced frames between log-parabolic dominant FFT peaks; voiced = peak power >=20% total power and active; report shared/REF/DUT counts; no shared frames with voiced REF is unavailable',
    'silence': 'DC-removed RMS relative to signed PCM full scale; hard failure before normalization',
}


def finite(value):
    value = float(value)
    if not math.isfinite(value):
        raise ValueError('non-finite number')
    return value


def rows(path, header):
    with path.open(newline='') as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames != header:
            raise ValueError(f'{path.name}: expected header {header}')
        return list(reader)


def load_capture(directory):
    directory = Path(directory)
    manifest = json.loads((directory / 'manifest.json').read_text())
    required = ('source', 'version', 'sample_rate', 'audio_cpu_cycle_hz',
                'duration_seconds', 'timeline', 'seed', 'notes')
    if not isinstance(manifest, dict) or any(key not in manifest for key in required):
        raise ValueError('manifest missing required fields')
    if manifest['source'] not in ('rtl', 'mame') or not isinstance(manifest['notes'], list):
        raise ValueError('invalid manifest source/notes')
    hz = finite(manifest['audio_cpu_cycle_hz'])
    duration = finite(manifest['duration_seconds'])
    if hz <= 0 or duration <= 0:
        raise ValueError('clock rate and duration must be positive')
    timeline = [(finite(row['seconds']), int(row['command'], 16))
                for row in rows(directory / 'timeline.csv', ['seconds', 'command'])]
    if not timeline or any(not 0 <= t < duration or not 0 <= c <= 255 for t, c in timeline):
        raise ValueError('empty or invalid command timeline')
    if any(b[0] <= a[0] for a, b in zip(timeline, timeline[1:])):
        raise ValueError('command times must strictly increase')
    declared = [(finite(t), int(c, 16)) for t, c in manifest['timeline']]
    if timeline != declared:
        raise ValueError('manifest and CSV timelines differ')
    events = []
    for row in rows(directory / 'dac-events.csv', ['seconds', 'audio_cpu_cycle', 'address', 'value']):
        t, cycle = finite(row['seconds']), int(row['audio_cpu_cycle'])
        address, value = int(row['address'], 16), int(row['value'], 16)
        if not (0 <= t < duration and cycle >= 0 and 0 <= value <= 255
                and (address == 0x1840 or 0x1880 <= address <= 0x1887)):
            raise ValueError('invalid DAC event')
        if events and (t < events[-1][0] or cycle < events[-1][1]):
            raise ValueError('DAC events must be ordered in time and cycles')
        events.append((t, cycle, address, value))
    with wave.open(str(directory / 'mix.wav'), 'rb') as wav:
        rate = wav.getframerate()
        if wav.getnchannels() != 1 or wav.getsampwidth() != 2 or wav.getcomptype() != 'NONE':
            raise ValueError('mix.wav must be mono signed 16-bit PCM')
        count = wav.getnframes()
        raw = wav.readframes(count)
        if len(raw) != count * 2:
            raise ValueError('truncated WAV')
    if count == 0 or rate != manifest['sample_rate'] or count != round(duration * rate):
        raise ValueError('WAV rate/duration disagrees with manifest')
    audio = np.frombuffer(raw, dtype='<i2').astype(float) / 32768
    identities = {name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
                  for name in ('manifest.json', 'timeline.csv', 'dac-events.csv', 'mix.wav')}
    return dict(manifest=manifest, timeline=timeline, events=events, audio=audio,
                rate=rate, hz=hz, duration=duration, sha256=identities)


def rms(x):
    return float(np.sqrt(np.mean(x * x))) if len(x) else 0.0


def envelope(x, size):
    # Include the final partial frame, averaging only its real samples.
    return np.array([rms(x[i:i + size]) for i in range(0, len(x), size)])


def activity(x, rate):
    size = round(rate * .01)
    env = envelope(x, size)
    active = np.flatnonzero(env > (np.max(abs(x)) * .01 if len(x) else 0))
    if not len(active):
        return None, 0.0
    onset = active[0] * size / rate * 1000
    end = min((active[-1] + 1) * size, len(x)) / rate * 1000
    return float(onset), float(end - onset)


def align(ref, dut, rate):
    limit = min(round(.02 * rate), len(ref) - 1, len(dut) - 1)
    size = 1 << (len(ref) + len(dut) - 2).bit_length()
    corr = np.fft.irfft(np.fft.rfft(dut, size) * np.conj(np.fft.rfft(ref, size)), size)
    lags = np.arange(-limit, limit + 1)
    values = corr[lags % size]
    # Prefer the nearest zero for numerically tied periodic peaks.
    candidates = lags[values >= values.max() - max(1.0, abs(values.max())) * 1e-12]
    lag = int(candidates[np.argmin(abs(candidates))])
    start_ref, start_dut = max(0, -lag), max(0, lag)
    count = min(len(ref) - start_ref, len(dut) - start_dut)
    return ref[start_ref:start_ref + count], dut[start_dut:start_dut + count], lag


def spectrum(x):
    count = max(1, 1 + math.ceil((len(x) - 2048) / 1024))
    padded = np.pad(x, (0, (count - 1) * 1024 + 2048 - len(x)))
    frames = np.lib.stride_tricks.sliding_window_view(padded, 2048)[::1024]
    return abs(np.fft.rfft(frames * np.hanning(2048), axis=1)) / 1024


def pitches(spec, rate):
    power = spec * spec
    bins = np.argmax(power[:, 1:], axis=1) + 1
    peak = power[np.arange(len(spec)), bins]
    active = np.sqrt(power.sum(axis=1))
    voiced = (peak >= .2 * power.sum(axis=1)) & (active > active.max() * .01)
    frequencies = []
    for row, k in zip(spec, bins):
        if k < len(row) - 1:
            a, b, c = np.log(np.maximum(row[k - 1:k + 2], 1e-12))
            denominator = a - 2 * b + c
            offset = .5 * (a - c) / denominator if abs(denominator) > 1e-12 else 0
        else:
            offset = 0
        frequencies.append((k + float(np.clip(offset, -.5, .5))) * rate / 2048)
    return np.array(frequencies), voiced


def waveform(ref, dut, rate):
    ref, dut = ref - np.mean(ref), dut - np.mean(dut)
    rr, dr = rms(ref), rms(dut)
    floor = 10 ** (FLOOR_DBFS / 20)
    result = dict(ref_rms=rr, dut_rms=dr, silence_fail=rr > floor and dr < floor)
    result['metrics'] = {key: None for key in NUMERIC_FLOORS if not key.startswith('interval')}
    if rr <= floor and dr <= floor:
        result['applicability'] = 'both below silence floor; waveform metrics not applicable'
        return result
    if rr == 0 or dr == 0:
        result['applicability'] = 'one clip has zero AC energy; waveform metrics unavailable'
        return result
    ro, rd = activity(ref, rate)
    do, dd = activity(dut, rate)
    ref, dut, lag = align(ref / rr, dut / dr, rate)
    re, de = envelope(ref, round(rate * .01)), envelope(dut, round(rate * .01))
    if np.std(re) < 1e-12 or np.std(de) < 1e-12:
        correlation = 1.0 if np.allclose(re, de, rtol=1e-9, atol=1e-12) else 0.0
    else:
        correlation = float(np.clip(np.corrcoef(re, de)[0, 1], -1, 1))
    rs, ds = spectrum(ref), spectrum(dut)
    active = np.sqrt((rs * rs).sum(axis=1))
    mask = active > active.max() * .01
    distance = float(np.sqrt(np.mean((20 * np.log10(np.maximum(rs[mask], 1e-5))
                                     - 20 * np.log10(np.maximum(ds[mask], 1e-5))) ** 2)))
    rp, rv = pitches(rs, rate)
    dp, dv = pitches(ds, rate)
    voiced = rv & dv
    pitch = float(np.median(abs(1200 * np.log2(dp[voiced] / rp[voiced])))) if np.any(voiced) else None
    result.update(lag_samples=lag, envelope_correlation=correlation,
                  ref_voiced_frames=int(rv.sum()), dut_voiced_frames=int(dv.sum()),
                  shared_voiced_frames=int(voiced.sum()),
                  pitch_applicable=bool(rv.any()))
    result['metrics'] = dict(lag_ms=abs(lag * 1000 / rate),
                             onset_error_ms=abs(do - ro), duration_error_ms=abs(dd - rd),
                             envelope_correlation_error=max(0.0, 1 - correlation),
                             log_spectral_distance_db=distance, pitch_error_cents=pitch)
    result['lag_ms'] = lag * 1000 / rate
    result['onset_error_ms'] = do - ro
    result['duration_error_ms'] = dd - rd
    return result


def event_view(events, extracted=False):
    return [(a, ((v >> 7) & 1 if a <= 0x1883 else v & 1)
             if extracted and 0x1880 <= a <= 0x1887 else v) for _, _, a, v in events]


def divergence(ref, dut):
    for i, (a, b) in enumerate(zip(ref, dut)):
        if a != b:
            return i
    return min(len(ref), len(dut)) if len(ref) != len(dut) else None


def compare(ref, dut):
    if ref['rate'] != dut['rate']:
        raise ValueError('sample-rate mismatch; resampling is not supported')
    # Only RTL master-edge rounding and the capture CSV's nanosecond precision
    # may move a command; no alignment or free timeline fitting is permitted.
    tolerance = .5 / 57272724 + 1e-9 if 'rtl' in (ref['manifest']['source'], dut['manifest']['source']) else 1e-9
    if len(ref['timeline']) != len(dut['timeline']) or any(
            a[1] != b[1] or abs(a[0] - b[0]) > tolerance
            for a, b in zip(ref['timeline'], dut['timeline'])):
        raise ValueError('REF and DUT command timelines differ')
    ref_frames, dut_frames = len(ref['audio']), len(dut['audio'])
    difference = dut_frames - ref_frames
    common_frames = min(ref_frames, dut_frames)
    duration = common_frames / ref['rate']
    if abs(difference) > ref['rate'] * .010:
        raise ValueError(f'capture WAV lengths differ by {difference} samples; maximum is 10 ms')
    if any(t >= duration for t, _ in ref['timeline'] + dut['timeline']):
        raise ValueError('command timeline extends beyond common WAV span')
    segments, all_ratios = [], []
    for i, (start, command) in enumerate(ref['timeline']):
        end = ref['timeline'][i + 1][0] if i + 1 < len(ref['timeline']) else duration
        re = [e for e in ref['events'] if start <= e[0] < end]
        de = [e for e in dut['events'] if start <= e[0] < end]
        raw_index = divergence(event_view(re), event_view(de))
        bit_index = divergence(event_view(re, True), event_view(de, True))
        ri = np.diff([e[1] for e in re]) / ref['hz']
        di = np.diff([e[1] for e in de]) / dut['hz']
        ratios = []
        if raw_index is None:
            for a, b in zip(ri, di):
                ratios.append(float(b / a) if a > 0 else (1.0 if b == 0 else None))
        valid = [r for r in ratios if r is not None]
        all_ratios.extend(valid)
        interval_error = max(abs(r - 1) for r in valid) if valid else None
        intervals = dict(ref_seconds=ri.tolist(), dut_seconds=di.tolist(), ratios=ratios,
                         median=float(np.median(valid)) if valid else None,
                         max_abs_deviation=interval_error,
                         undefined_ratio=any(r is None for r in ratios))
        rate = ref['rate']
        lo, hi = round(start * rate), round(end * rate)
        if hi <= lo:
            raise ValueError('command segment shorter than one sample')
        audio = waveform(ref['audio'][lo:hi], dut['audio'][lo:hi], rate)
        metrics = dict(audio['metrics'], interval_ratio_max_abs_deviation=interval_error)
        segments.append(dict(index=i, command=f'0x{command:02x}', start_seconds=start,
                             end_seconds=end, events=dict(raw_match=raw_index is None,
                             first_divergence_index=raw_index, extracted_match=bit_index is None,
                             extracted_first_divergence_index=bit_index, ref_count=len(re), dut_count=len(de)),
                             intervals=intervals, waveform=audio, metrics=metrics))
    median = float(np.median(all_ratios)) if all_ratios else None
    spread = max(abs(r - median) for r in all_ratios) if all_ratios else None
    return dict(schema_version=1, method=METHOD, silence_floor_dbfs=FLOOR_DBFS,
                capture_span=dict(ref_frames=ref_frames, dut_frames=dut_frames,
                                  difference_samples=difference, difference_seconds=difference / ref['rate'],
                                  common_frames=common_frames, common_seconds=duration,
                                  maximum_difference_seconds=.010),
                timeline_deltas_seconds=[b[0] - a[0] for a, b in zip(ref['timeline'], dut['timeline'])],
                reference=dict(manifest=ref['manifest'], sha256=ref['sha256']),
                dut=dict(manifest=dut['manifest'], sha256=dut['sha256']), segments=segments,
                clock_ratio=dict(dut_over_ref=median, max_abs_deviation_from_median=spread,
                                 uniform=spread <= 1e-6 if spread is not None else None,
                                 corrected=False))


def assess(report, thresholds):
    if not isinstance(thresholds, dict):
        raise ValueError('thresholds must be a JSON object')
    missing = [key for key in NUMERIC_FLOORS if thresholds.get(key) is None]
    for key in NUMERIC_FLOORS:
        value = thresholds.get(key)
        if value is not None and (isinstance(value, bool) or finite(value) < 0):
            raise ValueError(f'invalid threshold {key}')
    report['thresholds'] = thresholds
    incomplete = [f'uncalibrated threshold: {key}' for key in missing]
    if not thresholds.get('provenance') or thresholds['provenance'] == 'not yet calibrated':
        incomplete.append('threshold provenance is not calibrated')
    thresholds_incomplete = bool(incomplete)
    for segment in report['segments']:
        failures, unavailable = [], []
        if not segment['events']['raw_match']:
            failures.append('event_match')
        if segment['waveform']['silence_fail']:
            failures.append('silence')
        if segment['intervals']['undefined_ratio']:
            failures.append('interval_ratio_undefined')
        for key, value in segment['metrics'].items():
            if value is None:
                if key.startswith('interval'):
                    # No consecutive writes means no interval to compare.
                    continue
                audio = segment['waveform']
                if audio.get('applicability', '').startswith('both below'):
                    continue
                if key == 'pitch_error_cents' and audio.get('pitch_applicable') is False:
                    continue
                unavailable.append(key)
            elif thresholds.get(key) is not None and value > float(thresholds[key]):
                failures.append(key)
        segment.update(failures=failures, unavailable=unavailable)
        segment['status'] = 'FAIL' if failures else ('NOT_SCORABLE' if unavailable or thresholds_incomplete else 'PASS')
        incomplete.extend(f'segment {segment["index"]}: unavailable {key}' for key in unavailable)
    failed = any(s['failures'] for s in report['segments'])
    report['status'] = 'FAIL' if failed else ('NOT_SCORABLE' if incomplete else 'PASS')
    report['incomplete'] = incomplete
    return 1 if failed else (2 if incomplete else 0)


def calibrate(report):
    if any(not s['events']['raw_match'] or s['waveform']['silence_fail'] or
           s['intervals']['undefined_ratio'] for s in report['segments']):
        raise ValueError('calibration pair has event or silence failures')
    observed = {}
    for key in NUMERIC_FLOORS:
        values = [s['metrics'][key] for s in report['segments'] if s['metrics'][key] is not None]
        if not values:
            raise ValueError(f'calibration pair has no coverage for {key}')
        observed[key] = max(values)
    # Also reject missing metrics within a covered segment, e.g. lost DUT pitch.
    probe = json.loads(json.dumps(report))
    assess(probe, dict.fromkeys(NUMERIC_FLOORS, 1e100) | {'provenance': 'calibration coverage check'})
    if probe['incomplete']:
        raise ValueError('calibration pair has unavailable waveform metrics')
    result = {key: 3 * max(observed[key], floor) for key, floor in NUMERIC_FLOORS.items()}
    result.update(provenance='Reference-vs-reference noise floor; exact rule: threshold = 3 * max(worst observed absolute error across segments, numeric_floor). No DUT fitting or clock correction. Same sample rate required.',
                  observed_errors=observed, numeric_floors=NUMERIC_FLOORS, margin=3,
                  reference_a=report['reference'], reference_b=report['dut'], method=METHOD)
    return result


def summary(report):
    lines = ['| Segment | Raw / bits | Ratio | Lag ms | Spectral dB | Pitch cents | Result |',
             '| --- | --- | --- | --- | --- | --- | --- |']
    def fmt(value):
        return 'n/a' if value is None else f'{value:.6g}'
    for s in report.get('segments', []):
        events, audio = s['events'], s['waveform']
        raw = 'yes' if events['raw_match'] else f'no @{events["first_divergence_index"]}'
        bits = 'yes' if events['extracted_match'] else f'no @{events["extracted_first_divergence_index"]}'
        lines.append(f'| {s["index"]} {s["command"]} | {raw} / {bits} | {fmt(s["intervals"]["median"])} | '
                     f'{fmt(audio.get("lag_ms"))} | {fmt(s["metrics"]["log_spectral_distance_db"])} | '
                     f'{fmt(s["metrics"]["pitch_error_cents"])} | {s["status"]} {", ".join(s["failures"])} |')
    lines.append(f'\nResult: {report["status"]}; clock_ratio DUT/REF = {fmt(report.get("clock_ratio", {}).get("dut_over_ref"))}; no clock correction.')
    if report.get('incomplete'):
        lines.append('Incomplete: ' + '; '.join(report['incomplete']))
    return '\n'.join(lines)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, allow_nan=False) + '\n')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directories', nargs='*', type=Path)
    parser.add_argument('--calibrate', nargs=2, type=Path, metavar=('REF_A', 'REF_B'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--thresholds', type=Path, default=DEFAULT_THRESHOLDS)
    parser.add_argument('--force', action='store_true', help='allow replacing calibrated thresholds')
    args = parser.parse_args(argv)
    if (args.calibrate and args.directories) or (not args.calibrate and len(args.directories) != 2):
        parser.error('provide REF_DIR DUT_DIR, or --calibrate REF_A REF_B')
    try:
        if args.calibrate and args.output.exists() and not args.force:
            existing = json.loads(args.output.read_text())
            if any(existing.get(key) is not None for key in NUMERIC_FLOORS):
                raise ValueError('refusing to overwrite calibrated thresholds without --force')
        ref, dut = [load_capture(p) for p in (args.calibrate or args.directories)]
        report = compare(ref, dut)
        if args.calibrate:
            result = calibrate(report)
            write_json(args.output, result)
            print('| Threshold | Calibrated upper bound |\n| --- | --- |')
            for key in NUMERIC_FLOORS:
                print(f'| {key} | {result[key]:.9g} |')
            return 0
        try:
            thresholds = json.loads(args.thresholds.read_text())
        except (OSError, ValueError) as error:
            # Retain computable metrics and hard failures even without a file.
            thresholds = dict.fromkeys(NUMERIC_FLOORS) | {
                'provenance': f'thresholds unavailable: {error}'}
        code = assess(report, thresholds)
    except (OSError, ValueError, KeyError, TypeError, wave.Error, EOFError, OverflowError) as error:
        # Never overwrite a thresholds file on a rejected calibration.
        if args.calibrate:
            print(f'NOT_SCORABLE: {error}')
            return 2
        report = dict(status='NOT_SCORABLE', segments=[], incomplete=[str(error)])
        code = 2
    write_json(args.output, report)
    print(summary(report))
    return code


if __name__ == '__main__':
    raise SystemExit(main())
