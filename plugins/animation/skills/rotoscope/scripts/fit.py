#!/usr/bin/env python3
"""Fit the brush bias per drawing from the balance of replica-only and source-only XOR, and write the override file.

usage: fit.py <work> [--only K0-K1] [--start BIAS] [--step 0.04] [--ratio 1.3] [--rounds 6] [--out FILE]
Start at each drawing's current bias (or --start). Render, read r = source-only / replica-only. While r > RATIO the
replica is too thin: bias + STEP; below 1 / RATIO too fat: bias - STEP. Once two biases bracket r = 1, bisect them
(0.01 grid). Stop when r is inside the band, the bracket is one grid step wide, or ROUNDS run out. Keep the tried bias
with the lowest XOR among those meeting the target (else the lowest XOR / floor). All drawings still fitting render in
one batch per round. Appends one {"k": [k0, k1], "brush": {"bias": b}} entry per run of equal bias to the override
file (default <work>/overrides.json; later entries win), then `extract.py <work> --apply` puts them in the drawings.
Bias only: blur, sharpening and tone levels stay as the drawing has them (reference/method.md says when to change them).
"""
import argparse
import json
from pathlib import Path

import measure
import workdir
from measure import BRUSH, ok, render


def ratio(r):
    return r['src_only'] / max(r['rep_only'], 1)


def next_bias(tried, b, R, step):
    """tried {bias: row}; b the bias just measured. Returns the next bias to try, or None when done."""
    r = ratio(tried[b])
    if 1 / R <= r <= R:
        return None
    thin = [x for x in tried if ratio(tried[x]) > 1]
    fat = [x for x in tried if ratio(tried[x]) < 1]
    if thin and fat and min(fat) > max(thin):
        lo, hi = max(thin), min(fat)
        mid = round((lo + hi) / 2, 2)
        return None if hi - lo <= 0.011 or mid in tried else mid
    nb = round(b + step if r > R else b - step, 2)
    return None if nb in tried or not -0.2 <= nb <= 0.5 else nb


def best(tried):
    rows = sorted(tried.items(), key=lambda br: (not ok(br[1]), br[1]['xor'] if ok(br[1]) else br[1]['xor'] / br[1]['floor']))
    return rows[0]


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('work', type=Path)
    ap.add_argument('--only', help='K0-K1')
    ap.add_argument('--start', type=float)
    ap.add_argument('--step', type=float, default=0.04)
    ap.add_argument('--ratio', type=float, default=1.3)
    ap.add_argument('--rounds', type=int, default=6)
    ap.add_argument('--out', type=Path)
    ap.add_argument('--workers', type=int, default=render.WORKERS)
    a = ap.parse_args(argv)
    work = a.work.resolve()
    k0, k1 = map(int, a.only.split('-')) if a.only else (0, 10 ** 9)
    ks = [k for k, *_ in json.load(open(workdir.index(work)))['drawings'] if k0 <= k <= k1]
    start = {k: a.start if a.start is not None else
             json.load(open(workdir.trace(work, k))).get('brush', {}).get('bias', BRUSH['bias']) for k in ks}
    tried, cand = {k: {} for k in ks}, dict(start)
    out = workdir.out(work, 'fit')
    workdir.rep(work, 'fit').mkdir(parents=True, exist_ok=True)
    for rnd in range(a.rounds):
        if not cand:
            break
        (work / 'fit-brushes.json').write_text(json.dumps({k: {'bias': b} for k, b in cand.items()}))
        measure.replicas(work, list(cand), workdir.rep(work, 'fit'), 'brushes=fit-brushes.json', a.workers)
        nxt = {}
        for k, b in cand.items():
            tried[k][b] = measure.measure(k, work, out, images=False)
            n = next_bias(tried[k], b, a.ratio, a.step)
            if n is not None:
                nxt[k] = n
        print(f'round {rnd}: {len(cand)} rendered, {len(nxt)} still fitting', flush=True)
        cand = nxt
    lines = ['| k | start bias | fit bias | src/rep | xor % | xor/floor | ssim | ssim_e | pass | tried |', '|---|---|---|---|---|---|---|---|---|---|']
    fit = {}
    for k in ks:
        b, r = best(tried[k])
        fit[k] = b
        lines.append(f"| {k} | {start[k]:.2f} | {b:.2f} | {ratio(r):.2f} | {r['xor']:.3f} | {r['xor'] / r['floor']:.2f} | {r['ssim']:.4f} | "
                     f"{r['ssim_e']:.4f} | {'yes' if ok(r) else 'NO'} | {' '.join(f'{x:.2f}' for x in sorted(tried[k]))} |")
    (out / f'fit-{ks[0]:03d}-{ks[-1]:03d}.md').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))
    path = a.out or workdir.overrides(work)
    doc = json.load(open(path)) if path.exists() else {'overrides': []}
    run = [ks[0]]
    for k in ks[1:] + [None]:
        if k is not None and fit[k] == fit[run[0]] and k == run[-1] + 1:
            run.append(k)
            continue
        doc['overrides'].append({'k': [run[0], run[-1]], 'brush': {'bias': fit[run[0]]}, 'why': 'fit.py'})
        run = [k]
    path.write_text(json.dumps(doc, indent=1) + '\n')
    print(f'appended to {path}; apply with extract.py {work} --apply')
    return 0 if all(ok(best(tried[k])[1]) for k in ks) else 1


if __name__ == '__main__':
    raise SystemExit(main())
