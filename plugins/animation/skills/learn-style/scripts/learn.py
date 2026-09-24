#!/usr/bin/env python3
"""Measure a rotoscope work dir (traces plus source drawings) into a style pack's style.json.

usage: learn.py <work> <pack dir> [--credit TEXT] [--seg S]
Reads <work>/d/dNNN.json (palette, tone levels, fitted brush) and <work>/src/dNNN.png timed by d/index.json
(inkstats.py statistics), and writes <pack dir>/style.json. Keys it does not measure (`credit`, `brush`, the judgment
knobs `movement`, `camera`, `backgrounds`, and a hand-edited `check` or `segment_check`) are kept from an existing
style.json, so a re-run refreshes the numbers without losing the author's work.

Bands come from held-out validation and negative controls, not from a chosen margin. The source is cut into --seg
second segments. For each statistic, bands are learned from some segments (their lowest to highest segment median)
and tested on the rest (the median over their drawings), for every split: alternating segments and first/second
half, both ways, and each segment left out in turn. A statistic's raw band spans all segment medians; its widening
is the largest held-out miss, capped at CLEAR x the smallest margin by which a --negative film (another style or a
near miss) lies outside the raw band. So coverage gives way to discrimination where they conflict, and style.json
records each band's held-out pass rate and control margins. Drawings per second is treated the same way from
segment rates. The palette tolerance is the largest channel difference between a segment's median ink or paper colour and
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
CHECK = ['soft', 'w50', 'w90', 'pw50', 'rough', 'holes', 'ink_sd', 'paper_sd', 'field_sd', 'flat', 'boil', 'per_second']
SEGMENT_CHECK = ['field_sd']
# Widening rule: cover the largest held-out miss, but never more than CLEAR x the smallest margin by which a
# negative control lies outside the raw band, so a band that a control fails keeps it failing by a clear margin.
CLEAR = 0.5
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


def miss(v, lo, hi):
    """Relative distance of v outside [lo, hi]; 0 inside."""
    return (lo - v) / lo if v < lo else (v - hi) / hi if v > hi else 0.0


def splits(parts):
    n = len(parts)
    out = [(parts[0::2], parts[1::2]), (parts[1::2], parts[0::2]),
           (parts[:n // 2], parts[n // 2:]), (parts[n // 2:], parts[:n // 2])]
    return out + [(parts[:i] + parts[i + 1:], [parts[i]]) for i in range(n)]


def heldout(parts, stats, widen=None):
    """Per statistic, over every split: the relative misses of the held-out part against the band learned from the
    other parts (widened by widen[s] when given)."""
    out = {s: [] for s in stats}
    for train, test in splits(parts):
        for s in stats:
            med = [v for v in (value([p], s) for p in train) if v is not None]
            v = value(test, s)
            if v is None or not med:
                continue
            w = (widen or {}).get(s, 0)
            out[s].append(miss(v, min(med) * (1 - w), max(med) * (1 + w)))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('work', type=Path)
    ap.add_argument('pack', type=Path)
    ap.add_argument('--credit')
    ap.add_argument('--seg', type=float, default=inkstats.SEG)
    ap.add_argument('--negative', nargs='*', default=[], type=Path,
                    help='inkstats --json summaries of films in other styles or near misses (negative controls)')
    a = ap.parse_args(argv)
    f = a.pack / 'style.json'
    old = json.load(open(f)) if f.exists() else {}
    tr, rows = traces(a.work), inkstats.measure(a.work)
    m = inkstats.summary(rows, seg=a.seg)
    parts = [p for p in inkstats.segment(rows, inkstats.edges(rows, None, a.seg)) if len(p) > 1]
    stats = [*inkstats.STATS, 'per_second']
    raw = {s: (min(v), max(v)) for s in stats if (v := [x for x in (value([p], s) for p in parts) if x is not None])}
    misses = heldout(parts, stats)
    negs = {n.stem: json.load(open(n)) for n in a.negative}

    def neg_value(nm, s):
        return nm[s] if s in nm else nm['stats'][s]['p50'] if nm['stats'].get(s) else None
    rule, bands, segment_bands = {}, {}, {}
    for s in raw:
        need = max(misses[s], default=0.0)
        margins = {n: miss(v, *raw[s]) for n, nm in negs.items() if (v := neg_value(nm, s)) is not None}
        outside = [x for x in margins.values() if x > 0]
        w = min(need, CLEAR * min(outside)) if outside else need
        rule[s] = dict(heldout_max_miss=round(need, 3), control_margins={n: round(x, 3) for n, x in margins.items()},
                       widening=round(w, 3))
        bands[s] = [round(raw[s][0] * (1 - w), 4), round(raw[s][1] * (1 + w), 4)]
        if s in SEGMENT_CHECK:   # per shot is a coverage check (every shot's dark field textured): full held-out miss
            segment_bands[s] = [round(raw[s][0] * (1 - need), 4), round(raw[s][1] * (1 + need), 4)]
    final = heldout(parts, stats, {s: r['widening'] for s, r in rule.items()})
    for s in rule:
        rule[s]['heldout_pass'] = f"{sum(x == 0 for x in final[s])}/{len(final[s])}"
    nsplits = len(splits(parts))
    tol = max(math.ceil(float(np.abs(np.median(v, 0) - m[k]).max())) for p in parts
              for k in ('ink_rgb', 'paper_rgb') if (v := [r[k] for r in p if r[k]]))
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
        heldout=dict(splits=nsplits, clear=CLEAR, negatives=sorted(negs), rule=rule), bands=bands, segment_bands=segment_bands, check=old.get('check', CHECK),
        segment_check=old.get('segment_check', SEGMENT_CHECK),
        segment_min_drawings=old.get('segment_min_drawings', SEGMENT_MIN_DRAWINGS), brush=old.get('brush', {}), rotoscope_fits=tr['fits'])
    a.pack.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps(pack, indent=1) + '\n')
    print(f'{f}: {m["drawings"]} drawings, {len(parts)} segments, {nsplits} held-out splits, palette tolerance {tol}')
    for s in dict.fromkeys([*pack['check'], *pack['segment_check']]):
        r = rule[s]
        print(f"  {s}: band {bands[s][0]:.4g}-{bands[s][1]:.4g}; widening {r['widening']:.1%} (held-out max miss "
              f"{r['heldout_max_miss']:.1%}); held-out pass {r['heldout_pass']}; control margins "
              + ', '.join(f'{n} {x:+.1%}' for n, x in r['control_margins'].items()))
    return 0


if __name__ == '__main__':
    sys.exit(main())
