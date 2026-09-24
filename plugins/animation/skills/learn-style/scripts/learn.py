#!/usr/bin/env python3
"""Measure a rotoscope work dir (traces plus source drawings) into a style pack's style.json.

usage: learn.py <work> <pack dir> [--credit TEXT] [--seg S]
Reads <work>/d/dNNN.json (palette, tone levels, fitted brush) and <work>/src/dNNN.png timed by d/index.json
(inkstats.py statistics), and writes <pack dir>/style.json. Keys it does not measure (`credit`, `brush`, the judgment
knobs `movement`, `camera`, `backgrounds`, and a hand-edited `check` or `segment_check`) are kept from an existing
style.json, so a re-run refreshes the numbers without losing the author's work.

Bands come from held-out validation, not from a chosen margin. The source is cut into --seg second segments. For
each statistic, bands are learned from some segments (their lowest to highest segment median) and tested on the
rest (the median over their drawings), for every split: alternating segments and first/second half, both ways, and
each segment left out in turn. A statistic's widening is the largest relative miss any held-out part needed; its
final band spans all segment medians widened by that much. Drawings per second is treated the same way from segment
rates. The palette tolerance is the largest channel difference between a segment's median ink or paper colour and
the whole clip's. Statistics only: no geometry, no per-drawing rows, no frames.
"""
import argparse
import json
import math
import sys
from collections import Counter
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'scripts'))
import inkstats  # noqa: E402

# Separated the shfred0 source from round 3 or from three other styles under the held-out bands
# (reference/statistics.md); the rest follow the subject, not the style, and stay unchecked.
CHECK = ['soft', 'w50', 'w90', 'pw50', 'rough', 'holes', 'ink_sd', 'paper_sd', 'boil', 'per_second']
SEGMENT_CHECK = ['field_sd']
# A shot of fewer drawings is a transition too short for a stable median: shfred0's 0.5 s flash (4 drawings) has a
# dark-field sd of 1.23 against its 3.35 s segments' 2.3-7.9.
SEGMENT_MIN_DRAWINGS = 8


def traces(work):
    ds = [json.load(open(f)) for f in sorted((work / 'd').glob('d[0-9]*.json'))]
    if not ds:
        sys.exit(f'learn: no traces in {work / "d"}; run the rotoscope extract.py first')
    tones, common = {}, Counter(tuple(d['levels']) for d in ds).most_common(1)[0][0]   # skip per-shot level overrides
    for d in (d for d in ds if tuple(d['levels']) == common):
        for t in d['tones']:
            if 'tint' not in t:
                tones.setdefault(t['lv'], []).append(t['color'])
    brush = Counter(json.dumps(d.get('brush') or {}, sort_keys=True) for d in ds)
    return dict(
        size=[ds[0]['w'], ds[0]['h']], T=float(np.median([d['T'] for d in ds])),
        ink=Counter(d['ink'] for d in ds).most_common(1)[0][0], paper=Counter(d['paper'] for d in ds).most_common(1)[0][0],
        tones=[dict(lv=lv, color=Counter(c).most_common(1)[0][0]) for lv, c in sorted(tones.items())],
        fits={k: round(n / len(ds), 3) for k, n in brush.most_common(5)})


def value(parts, s):
    """A statistic over some segments: drawings per second over their summed durations, else the median."""
    if s == 'per_second':
        return sum(map(len, parts)) / sum(p[-1]['t'] + p[-1]['hold'] - p[0]['t'] for p in parts)
    return inkstats.median([r for p in parts for r in p], s)


def heldout(parts, stats):
    """Per statistic: the largest relative miss of a held-out part against bands learned from the others."""
    n = len(parts)
    splits = [(parts[0::2], parts[1::2]), (parts[1::2], parts[0::2]),
              (parts[:n // 2], parts[n // 2:]), (parts[n // 2:], parts[:n // 2])]
    splits += [(parts[:i] + parts[i + 1:], [parts[i]]) for i in range(n)]
    need = dict.fromkeys(stats, 0.0)
    for train, test in splits:
        for s in stats:
            med = [v for v in (value([p], s) for p in train) if v is not None]
            v = value(test, s)
            if v is None or not med:
                continue
            lo, hi = min(med), max(med)
            need[s] = max(need[s], (lo - v) / lo if v < lo else (v - hi) / hi if v > hi else 0.0)
    return {s: round(w, 3) for s, w in need.items()}, len(splits)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('work', type=Path)
    ap.add_argument('pack', type=Path)
    ap.add_argument('--credit')
    ap.add_argument('--seg', type=float, default=inkstats.SEG)
    a = ap.parse_args(argv)
    f = a.pack / 'style.json'
    old = json.load(open(f)) if f.exists() else {}
    tr, rows = traces(a.work), inkstats.measure(a.work)
    m = inkstats.summary(rows, seg=a.seg)
    parts = [p for p in inkstats.segment(rows, inkstats.edges(rows, None, a.seg)) if len(p) > 1]
    stats = [*inkstats.STATS, 'per_second']
    need, nsplits = heldout(parts, stats)
    bands = {}
    for s in stats:
        med = [v for v in (value([p], s) for p in parts) if v is not None]
        bands[s] = [round(min(med) * (1 - need[s]), 4), round(max(med) * (1 + need[s]), 4)]
    tol = max(math.ceil(float(np.abs(np.median([r[k] for r in p], 0) - m[k]).max())) for p in parts
              for k in ('ink_rgb', 'paper_rgb'))
    st = m['stats']
    step = max(m['holds'], key=m['holds'].get)
    knobs = old.get('knobs', {}) | dict(
        color=dict(palette_size=2, ink=tr['ink'], paper=tr['paper'], fill='flat, soft gray edge ramp',
                   tone_ramp=tr['tones']),
        line=dict(weight_px=st['w50'], weight_p90_px=st['w90'], paper_gap_px=st['pw50']['p50'],
                  roughness=st['rough']['p50'], straight_share=st['straight']['p50'],
                  boil=dict(edge_shift_px=st['boil']['p50'], variants='a new drawing every hold', on_holds=True)),
        frame_rate=dict(base_fps=24, step=int(step[2]) if step[2].isdigit() else 4, drawings_per_second=m['per_second'],
                        holds=m['holds']),
        texture=dict(edge_ramp_px=st['soft']['p50'], ink_gray_sd=st['ink_sd']['p50'], field_gray_sd=st['field_sd']['p50'],
                     paper_gray_sd=st['paper_sd']['p50'], gaps_per_mpx=st['gaps']['p50'],
                     specks_per_mpx=st['specks']['p50'], holes=st['holes']['p50'], ink_coverage=st['ink']))
    pack = dict(
        name=a.pack.name, credit=a.credit or old.get('credit', ''),
        measured_from=dict(drawings=m['drawings'], duration=m['duration'], size=tr['size'], segments=len(parts),
                           segment_seconds=a.seg),
        palette=dict(ink=tr['ink'], paper=tr['paper'], T=tr['T'], tones=tr['tones'], tolerance=tol),
        knobs=knobs, stats=st, timing=dict(per_second=m['per_second'], holds=m['holds'], held=m['held']),
        heldout=dict(splits=nsplits, widening=need), bands=bands, check=old.get('check', CHECK),
        segment_check=old.get('segment_check', SEGMENT_CHECK),
        segment_min_drawings=old.get('segment_min_drawings', SEGMENT_MIN_DRAWINGS), brush=old.get('brush', {}), rotoscope_fits=tr['fits'])
    a.pack.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps(pack, indent=1) + '\n')
    print(f'{f}: {m["drawings"]} drawings, {len(parts)} segments, {nsplits} held-out splits, palette tolerance {tol}')
    for s in [*pack['check'], *pack['segment_check']]:
        print(f'  {s}: band {bands[s][0]:.4g}-{bands[s][1]:.4g} (held-out widening {need[s]:.1%})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
