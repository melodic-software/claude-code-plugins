"""Two-pass ffmpeg loudnorm against a caller's target. Standard library and media_encode only.

target: {'integrated_lufs', 'limiter_true_peak_dbtp', 'loudness_range_lu', 'tolerance_lu', 'true_peak_max_dbtp'}.
measure(path, target) -> loudnorm's first-pass JSON (strings) for the first audio stream.
normalize(wav, out, measured, target) -> normalization_type of the second pass (measure the result again).
defects(measured, target) -> integrated loudness off target or true peak over the ceiling.
"""
import json

import media_encode


def _filter(target, measured=None):
    f = (f'loudnorm=I={target["integrated_lufs"]}:TP={target["limiter_true_peak_dbtp"]}'
         f':LRA={target["loudness_range_lu"]}')
    if measured:
        f += (f':measured_I={measured["input_i"]}:measured_TP={measured["input_tp"]}'
              f':measured_LRA={measured["input_lra"]}:measured_thresh={measured["input_thresh"]}'
              f':offset={measured["target_offset"]}:linear=true')
    return f + ':print_format=json'


def _json(stderr):
    """The JSON block loudnorm prints last on stderr."""
    return json.loads(stderr[stderr.rindex('{'):stderr.rindex('}') + 1])


def measure(path, target):
    r = media_encode.run(['-i', path, '-map', '0:a:0', '-af', _filter(target), '-f', 'null', '-'], report=True)
    return _json(r.stderr)


def normalize(wav, out, measured, target):
    r = media_encode.run(['-i', wav, '-af', _filter(target, measured), '-ar', '48000', out], report=True)
    return _json(r.stderr).get('normalization_type')


def levels(measured):
    return {'integrated_lufs': float(measured['input_i']), 'true_peak_dbtp': float(measured['input_tp'])}


def defects(measured, target):
    integrated, true_peak = float(measured['input_i']), float(measured['input_tp'])
    out = []
    if abs(integrated - target['integrated_lufs']) > target['tolerance_lu']:
        out.append(f'integrated loudness {integrated:.1f} LUFS is more than {target["tolerance_lu"]} LU from the '
                   f'{target["integrated_lufs"]} LUFS target')
    if true_peak > target['true_peak_max_dbtp']:
        out.append(f'true peak {true_peak:.1f} dBTP is over the {target["true_peak_max_dbtp"]} dBTP ceiling')
    return out
