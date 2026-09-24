#!/usr/bin/env python3
"""Measure a rotoscope work dir (traces plus source drawings) into a style pack's style.json.

usage: learn.py <work> <pack dir> [--credit TEXT] [--seg S]
Reads <work>/d/dNNN.json (palette, tone levels, fitted brush) and <work>/src/dNNN.png timed by d/index.json
(inkstats.py statistics), and writes <pack dir>/style.json. Keys it does not measure (`credit`, `brush`, the judgment
knobs `movement`, `camera`, `backgrounds`, and any hand-edited `check`) are kept from an existing style.json, so a
re-run refreshes the numbers without losing the author's work.
Bands: a statistic's band runs from BAND_LO x the lowest to BAND_HI x the highest segment median of the source, so it
spans the source's own shot-to-shot spread; per_second gets RATE_TOL either side. Statistics only: no geometry, no
per-drawing rows, no frames.
"""
import argparse
import json
import sys
from collections import Counter
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'scripts'))
import inkstats  # noqa: E402

BAND_LO, BAND_HI, RATE_TOL, PALETTE_TOL = 0.9, 1.1, 0.15, 8
# Separated source from other styles in the shfred0 study (reference/statistics.md); ink, w10 and specks follow the
# subject, not the style, and stay unchecked.
CHECK = ['soft', 'w50', 'w90', 'pw50', 'rough', 'straight', 'gaps', 'holes', 'ink_sd', 'paper_sd', 'boil', 'per_second']


def traces(work):
    ds = [json.load(open(f)) for f in sorted((work / 'd').glob('d[0-9]*.json'))]
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


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('work', type=Path)
    ap.add_argument('pack', type=Path)
    ap.add_argument('--credit')
    ap.add_argument('--seg', type=float, default=inkstats.SEG)
    a = ap.parse_args(argv)
    f = a.pack / 'style.json'
    old = json.load(open(f)) if f.exists() else {}
    tr, m = traces(a.work), inkstats.measure(a.work, seg=a.seg)
    st = m['stats']
    bands = {}
    for s in inkstats.STATS:
        seg = [g[s] for g in m['segments'] if g[s] is not None]
        bands[s] = [round(min(seg) * BAND_LO, 4), round(max(seg) * BAND_HI, 4)]
    bands['per_second'] = [round(m['per_second'] * (1 - RATE_TOL), 3), round(m['per_second'] * (1 + RATE_TOL), 3)]
    step = max(m['holds'], key=m['holds'].get)
    knobs = old.get('knobs', {}) | dict(
        color=dict(palette_size=2, ink=tr['ink'], paper=tr['paper'], fill='flat, soft gray edge ramp',
                   tone_ramp=tr['tones']),
        line=dict(weight_px=st['w50'], weight_p90_px=st['w90'], paper_gap_px=st['pw50']['p50'],
                  roughness=st['rough']['p50'], straight_share=st['straight']['p50'],
                  boil=dict(edge_shift_px=st['boil']['p50'], variants='a new drawing every hold', on_holds=True)),
        frame_rate=dict(base_fps=24, step=int(step[2]) if step[2].isdigit() else 4, drawings_per_second=m['per_second'],
                        holds=m['holds']),
        texture=dict(edge_ramp_px=st['soft']['p50'], ink_gray_sd=st['ink_sd']['p50'], paper_gray_sd=st['paper_sd']['p50'],
                     gaps_per_mpx=st['gaps']['p50'], specks_per_mpx=st['specks']['p50'], holes=st['holes']['p50'],
                     ink_coverage=st['ink']))
    pack = dict(
        name=a.pack.name, credit=a.credit or old.get('credit', ''),
        measured_from=dict(drawings=m['drawings'], duration=m['duration'], size=tr['size'], segments=len(m['segments'])),
        palette=dict(ink=tr['ink'], paper=tr['paper'], T=tr['T'], tones=tr['tones'], tolerance=PALETTE_TOL),
        knobs=knobs, stats=st, timing=dict(per_second=m['per_second'], holds=m['holds'], held=m['held']),
        bands=bands, check=old.get('check', CHECK), brush=old.get('brush', {}), rotoscope_fits=tr['fits'])
    a.pack.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps(pack, indent=1) + '\n')
    print(f'{f}: {m["drawings"]} drawings, {len(pack["check"])} checked statistics')
    for s in pack['check']:
        print(f'  {s}: band {bands[s][0]:.4g}-{bands[s][1]:.4g}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
