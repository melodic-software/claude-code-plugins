#!/usr/bin/env python3
"""Measure a rotoscope work dir (traces plus source drawings) into a style pack's style.json.

usage: learn.py <work> <pack dir> [--cuts T,T,.. | --seg S] [--credit TEXT] [--negative SUMMARY.json ...]
Reads <work>/d/dNNN.json (palette, tone levels, fitted brush) and <work>/src/dNNN.png timed by d/index.json
(inkstats.py statistics), and writes <pack dir>/style.json. Keys it does not measure (`credit`, `brush`, and the
judgment knobs `movement`, `camera`, `backgrounds`) are kept from an existing style.json, so a re-run refreshes the
numbers without losing the author's work.

The check judges a whole film, so bands are learned from film-sized excerpts of the source. The source is cut into
parts at --cuts (its shots; without --cuts, --seg second segments). An excerpt is a set of parts holding FLOOR to
1 - FLOOR of the duration, paired with its complement (the rest of the source): every split by shot, both directions.
The pairs alternate between a calibration half, which sets the bands, and an evaluation half, which only tests them.
For each statistic the raw band spans the calibration excerpts' values (the median over their drawings; drawings per
second and offstep over their durations). Its widening, in the statistic's own units, is the largest miss of a
calibration pair against the band of the other calibration pairs, capped at CLEAR x the smallest distance by which a
--negative film (another style or a near miss) lies outside the raw band, counting each control only at the checked
row that rejects it most: coverage gives way to discrimination where they conflict. style.json records, per statistic, the widening, the control margins and the calibration and
evaluation pass rates, and `ref`, the whole source's value, which the distance is measured from. The palette tolerance
is the encode shift (the largest channel change in the clip's median ink or paper colour when its drawings are encoded
as capture.mjs encodes a scene and decoded again) plus the largest channel difference between an excerpt's median
colour and the clip's, rounded up. Statistics only: no geometry, no per-drawing rows, no frames.
"""
import argparse
import itertools
import json
import math
import sys
import tempfile
from collections import Counter
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'scripts'))
import controls  # noqa: E402
import inkstats  # noqa: E402

# Checked statistics, each chosen for what it separates (reference/statistics.md, "Which statistics separate"):
# straight, rough, offstep and sliver are drawing, timing and carving structure a post filter barely moves; grain,
# period and flat reject texture overlays; the rest reject other styles. straight and sliver follow the subject, so
# they are checked only inside the content classes every film of the style has (inkstats.CLASSES), and only where
# the source defines the class in at least two parts; over the whole frame they are MEASURED_ONLY.
CHECK = ['straight_border', 'straight_caption', 'rough', 'offstep', 'sliver_border', 'sliver_caption', 'grain',
         'period', 'flat', 'holes', 'boil', 'per_second']
MEASURED_ONLY = ['straight', 'sliver']
CLEAR = 0.5
# Shortest excerpt: a third of the source, about 10 s of a 30 s clip, the length SKILL.md asks a validation scene to be.
FLOOR = 1 / 3
MAX_SUBSETS = 4096


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


def duration(p):
    return p[-1]['t'] + p[-1]['hold'] - p[0]['t']


def value(parts, s):
    """A statistic over some parts: drawings per second over their summed durations, offstep over their drawings,
    else the median over their drawings."""
    rows = [r for p in parts for r in p]
    if s == 'per_second':
        return len(rows) / sum(map(duration, parts))
    if s == 'offstep':
        return inkstats.offstep(rows)
    return inkstats.median(rows, s)


def pairs(parts):
    """(excerpt, complement) index sets, each holding FLOOR to 1 - FLOOR of the duration; every such split when there
    are at most MAX_SUBSETS, else a seeded sample of that many."""
    d, n = [duration(p) for p in parts], len(parts)
    rest = range(1, n)   # part 0 always in the excerpt: each split once
    if 2 ** (n - 1) <= MAX_SUBSETS:
        combos = [(0, *c) for k in range(n) for c in itertools.combinations(rest, k)]
    else:
        rng = np.random.default_rng(0)
        combos = {(0, *sorted(i for i in rest if rng.random() < 0.5)) for _ in range(MAX_SUBSETS)}
    out = []
    for c in sorted(combos):
        if FLOOR <= sum(d[i] for i in c) / sum(d) <= 1 - FLOOR:
            out.append((c, tuple(i for i in range(n) if i not in c)))
    return out


def outside(v, lo, hi):
    """How far v lies outside [lo, hi], in the statistic's units; 0 inside."""
    return lo - v if v < lo else v - hi if v > hi else 0.0


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('work', type=Path)
    ap.add_argument('pack', type=Path)
    ap.add_argument('--credit')
    ap.add_argument('--cuts', help='the source\'s shot boundaries in seconds; each shot is a part')
    ap.add_argument('--seg', type=float, default=inkstats.SEG, help='part length in seconds when there are no cuts')
    ap.add_argument('--negative', nargs='*', default=[], type=Path,
                    help='inkstats --json summaries of films in other styles or near misses (negative controls)')
    a = ap.parse_args(argv)
    f = a.pack / 'style.json'
    old = json.load(open(f)) if f.exists() else {}
    tr, rows = traces(a.work), inkstats.measure(a.work)
    cuts = inkstats.nums(a.cuts)
    m = inkstats.summary(rows, cuts, a.seg)
    parts = [p for p in inkstats.segment(rows, inkstats.edges(rows, cuts, a.seg)) if p]
    ps = pairs(parts)
    if len(ps) < 4:
        sys.exit(f'learn: only {len(ps)} excerpt splits of {len(parts)} parts; give more cuts or a shorter --seg')
    calib, evals = ps[0::2], ps[1::2]
    negs = {n.stem: json.load(open(n)) for n in a.negative}

    def vals(group, s):   # both directions: the excerpt and its complement
        return [(i, v) for i, pair in enumerate(group) for side in pair
                if (v := value([parts[j] for j in side], s)) is not None]
    rule, bands, ref, raw = {}, {}, {}, {}
    for s in [*inkstats.STATS, 'per_second', 'offstep']:
        cv = vals(calib, s)
        ref[s] = value(parts, s)
        if not cv or ref[s] is None:
            continue
        lo, hi = min(min(v for _, v in cv), ref[s]), max(max(v for _, v in cv), ref[s])
        need = 0.0
        for i in {i for i, _ in cv}:   # each calibration pair against the band of the others
            others = [v for j, v in cv if j != i] or [ref[s]]
            need = max(need, *(outside(v, min(others), max(others)) for j, v in cv if j == i))
        raw[s] = lo, hi, need, {n: v for n, nm in negs.items() if (v := inkstats.film_value(nm, s)) is not None}
    # A control caps only the checked row that rejects it most (largest distance under the raw bands), so that row
    # keeps rejecting it by a clear margin while the other rows keep full held-out coverage.
    best = {n: max((s for s in CHECK if s in raw and n in raw[s][3]),
                   key=lambda s: inkstats.distance(raw[s][3][n], ref[s], *raw[s][:2]), default=None) for n in negs}
    for s, (lo, hi, need, nv) in raw.items():
        margins = {n: outside(v, lo, hi) for n, v in nv.items()}
        clear = [x for n, x in margins.items() if x > 0 and best[n] == s]
        w = min(need, CLEAR * min(clear)) if clear else need
        bands[s] = [round(max(0.0, lo - w), 4), round(hi + w, 4)]

        def rate(group, s=s):
            v = [x for _, x in vals(group, s)]
            return f"{sum(bands[s][0] <= x <= bands[s][1] for x in v)}/{len(v)}"
        rule[s] = dict(raw=[round(lo, 4), round(hi, 4)], heldout_max_miss=round(need, 4), widening=round(w, 4),
                       control_margins={n: round(x, 4) for n, x in margins.items()},
                       capped_by=sorted(n for n in margins if best[n] == s and margins[n] > 0),
                       calibration_pass=rate(calib), evaluation_pass=rate(evals))
        ref[s] = round(ref[s], 4)
    check = [s for s in CHECK if s in bands and sum(value([p], s) is not None for p in parts) >= 2]

    def whole(group):   # excerpts passing every checked row
        sides = [side for pair in group for side in pair]
        ok = sum(all(v is None or bands[s][0] <= v <= bands[s][1]
                     for s in check for v in [value([parts[j] for j in side], s)]) for side in sides)
        return f'{ok}/{len(sides)}'
    def colour(rs, k):
        return np.median([r[k] for r in rs if r[k]], 0)
    # palette tolerance = what encoding does to the colours + how far a source excerpt's colours stray from the clip's
    with tempfile.TemporaryDirectory() as tmp:
        enc = inkstats.measure(str(controls.encode(a.work, 'src', Path(tmp) / 'source.mp4')))
    shift = max(float(np.abs(colour(enc, k) - m[k]).max()) for k in ('ink_rgb', 'paper_rgb'))
    stray = max(float(np.abs(colour([r for j in side for r in parts[j]], k) - m[k]).max())
                for pair in ps for side in pair for k in ('ink_rgb', 'paper_rgb'))
    tol = math.ceil(shift + stray)
    st = m['stats']
    step = max(m['holds'], key=m['holds'].get)
    knobs = old.get('knobs', {}) | dict(
        color=dict(palette_size=2, ink=tr['ink'], paper=tr['paper'], fill='flat, soft gray edge ramp',
                   tone_ramp=tr['tones']),
        line=dict(weight_px=st['w50'], weight_p90_px=st['w90'], paper_gap_px=st['pw50']['p50'],
                  roughness=st['rough']['p50'], straight_share=st['straight']['p50'],
                  boil=dict(edge_shift_px=st['boil']['p50'], variants='a new drawing every hold', on_holds=True)),
        frame_rate=dict(base_fps=24, step=int(step[2]) if step[2].isdigit() else 4, drawings_per_second=m['per_second'],
                        holds=m['holds'], offstep=m['offstep']),
        texture=dict(edge_ramp_px=st['soft']['p50'], ink_gray_sd=st['ink_sd']['p50'], field_gray_sd=st['field_sd']['p50'],
                     paper_gray_sd=st['paper_sd']['p50'], grain=st['grain']['p50'], period=st['period']['p50'],
                     gaps_per_mpx=st['gaps']['p50'], specks_per_mpx=st['specks']['p50'], holes=st['holes']['p50'],
                     ink_coverage=st['ink']))
    pack = dict(
        name=a.pack.name, credit=a.credit or old.get('credit', ''),
        measured_from=dict(drawings=m['drawings'], duration=m['duration'], size=tr['size'], parts=len(parts),
                           cuts=cuts, segment_seconds=None if cuts else a.seg),
        palette=dict(ink=tr['ink'], paper=tr['paper'], T=tr['T'], tones=tr['tones'], tolerance=tol,
                     encode_shift=round(shift, 2), excerpt_stray=round(stray, 2)),
        knobs=knobs, stats=st, timing=dict(per_second=m['per_second'], holds=m['holds'], offstep=m['offstep'],
                                           held=m['held']),
        heldout=dict(excerpt_share=[round(FLOOR, 3), round(1 - FLOOR, 3)], splits=len(ps), calibration=len(calib),
                     evaluation=len(evals), clear=CLEAR, negatives=sorted(negs), calibration_pass=whole(calib),
                     evaluation_pass=whole(evals), rule=rule),
        ref={s: ref[s] for s in bands}, bands=bands, check=check,
        measured_only=[s for s in MEASURED_ONLY if s in bands], brush=old.get('brush', {}), rotoscope_fits=tr['fits'])
    a.pack.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps(pack, indent=1) + '\n')
    print(f'{f}: {m["drawings"]} drawings, {len(parts)} parts, {len(ps)} splits ({len(calib)} calibration, '
          f'{len(evals)} evaluation), palette tolerance {tol}; excerpts passing every row: calibration '
          f'{whole(calib)}, evaluation {whole(evals)}')
    for s in check:
        r = rule[s]
        print(f"  {s}: band {bands[s][0]:.4g}-{bands[s][1]:.4g} (source {ref[s]:.4g}); widening {r['widening']:.4g} "
              f"(held-out max miss {r['heldout_max_miss']:.4g}); pass calibration {r['calibration_pass']}, "
              f"evaluation {r['evaluation_pass']}; control margins "
              + ', '.join(f'{n} {x:.4g}' for n, x in r['control_margins'].items()))
    return 0


if __name__ == '__main__':
    sys.exit(main())
