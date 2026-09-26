#!/usr/bin/env python3
"""Render traced drawings and measure each against its source drawing, at 1:1.

usage: measure.py <work> [--only K0-K1] [--tag name] [--mode a|b] [--brush JSON] [--brushes FILE]
                  [--no-render] [--workers N]
Renders roto.js through scripts/render.py (with <work> served as an extra root for its JSON), then writes to <work>/out/<tag>/ (tag defaults to the mode):
  rep/dNNN.png   the replica         heat/dNNN.png  XOR heatmap: red = replica-only ink, blue = source-only ink
  ab/dNNN.png    source above replica, 1:1            table-K0-K1.md one row per drawing
and appends a one-line summary to <work>/learnings.md.
Metrics (gray = RGB2GRAY of both images; T = the drawing's threshold):
  xor      % of frame pixels whose ink/paper state (gray < T) disagrees
  floor    % of source pixels within FLOOR_GRAY levels of T: the band codec noise decides, a copy cannot predict
  rep/src  replica-only and source-only XOR pixels; their ratio is the first diagnostic (reference/method.md)
  ssim     grayscale SSIM (Wang 2004: 11x11 gaussian sigma 1.5, K1 .01, K2 .03), mean over the frame
  ssim_e   the same SSIM map averaged over the edge band (pixels within 2 px of a source ink edge)
  paper_err, paper_d  mean abs and signed replica-source RGB over source paper (gray > T + 16): tint the gray metrics miss
Exit 0 only if every drawing has xor <= FLOOR_X * floor, ssim >= SSIM_MIN and ssim_e >= SSIME_MIN.
"""
import argparse
import datetime
import json
import sys
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / 'scripts'))
import render  # noqa: E402
from decode import MID  # noqa: E402

FLOOR_GRAY, FLOOR_X, SSIM_MIN, SSIME_MIN = 4, 1.2, 0.980, 0.980
BRUSH_BIAS = 0.12   # roto.js BRUSH.bias


def replicas(work, ks, rep_dir, query='', workers=render.WORKERS):
    """Render drawings ks through roto.js into rep_dir, with work served for its JSON."""
    render.render(HERE / 'roto.js', rep_dir, drawings=ks, query=query, roots=[work], workers=workers)


def ssim_map(a, b):
    a, b = a.astype(np.float64), b.astype(np.float64)

    def f(x):
        return cv2.GaussianBlur(x, (11, 11), 1.5)
    C1, C2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    ma, mb = f(a), f(b)
    va, vb, cab = f(a * a) - ma ** 2, f(b * b) - mb ** 2, f(a * b) - ma * mb
    return ((2 * ma * mb + C1) * (2 * cab + C2)) / ((ma ** 2 + mb ** 2 + C1) * (va + vb + C2))


def paper(src, rep, T):
    """Mean abs and mean signed replica-source RGB over source paper (BGR images in)."""
    pm = cv2.cvtColor(src, cv2.COLOR_BGR2GRAY) > T + MID
    if not pm.any():
        return 0.0, np.zeros(3)
    pd = rep[pm].astype(float)[:, ::-1] - src[pm].astype(float)[:, ::-1]
    return float(np.abs(pd).mean()), pd.mean(0)


def measure(k, work, out, images=True):
    d = json.load(open(work / f'd/d{k:03d}.json'))
    src, rep = cv2.imread(str(work / f'src/d{k:03d}.png')), cv2.imread(str(out / f'rep/d{k:03d}.png'))
    gs, gr = cv2.cvtColor(src, cv2.COLOR_BGR2GRAY), cv2.cvtColor(rep, cv2.COLOR_BGR2GRAY)
    ms, mr = gs < d['T'], gr < d['T']
    x = ms ^ mr
    sm = ssim_map(gs, gr)
    ker, m8 = np.ones((5, 5), np.uint8), ms.astype(np.uint8)
    band = (cv2.dilate(m8, ker) ^ cv2.erode(m8, ker)).astype(bool)
    if images:
        heat = np.full(src.shape, 255, np.uint8)
        heat[ms & mr] = (200, 200, 200)                               # agreed ink, light gray
        heat[mr & ~ms] = (0, 0, 255)                                  # BGR: red replica-only
        heat[ms & ~mr] = (255, 0, 0)                                  # blue source-only
        cv2.imwrite(str(out / f'heat/d{k:03d}.png'), heat)
        cv2.imwrite(str(out / f'ab/d{k:03d}.png'), np.vstack([src, rep]))
    pe, pd = paper(src, rep, d['T'])
    return dict(k=k, pts=d['pts'], xor=x.mean() * 100, floor=(np.abs(gs.astype(float) - d['T']) < FLOOR_GRAY).mean() * 100,
                rep_only=int((mr & ~ms).sum()), src_only=int((ms & ~mr).sum()), paper_err=pe, paper_d=pd,
                ssim=float(sm.mean()), ssim_e=float(sm[band].mean()) if band.any() else 1.0)


def ok(r):
    return r['xor'] <= FLOOR_X * r['floor'] and r['ssim'] >= SSIM_MIN and r['ssim_e'] >= SSIME_MIN


def table(tag, rows):
    def rgb(v):
        return ','.join(f'{c:+.2f}' for c in v)

    def mean(f):
        return sum(r[f] for r in rows) / len(rows)
    lines = [f'# {tag} d{rows[0]["k"]:03d}-d{rows[-1]["k"]:03d}  target: xor <= {FLOOR_X} x floor, ssim >= {SSIM_MIN}, '
             f'ssim_e >= {SSIME_MIN}', '',
             '| k | pts | xor % | floor % | xor/floor | replica-only px | source-only px | ssim | ssim_e | paper_err | paper_d R,G,B | pass |',
             '|---|---|---|---|---|---|---|---|---|---|---|---|']
    lines += [f"| {r['k']} | {r['pts']:.3f} | {r['xor']:.3f} | {r['floor']:.3f} | {r['xor'] / max(r['floor'], 1e-9):.2f} | "
              f"{r['rep_only']} | {r['src_only']} | {r['ssim']:.4f} | {r['ssim_e']:.4f} | {r['paper_err']:.2f} | "
              f"{rgb(r['paper_d'])} | {'yes' if ok(r) else 'NO'} |" for r in rows]
    lines.append(f"| mean | | {mean('xor'):.3f} | {mean('floor'):.3f} | | | | {mean('ssim'):.4f} | {mean('ssim_e'):.4f} | "
                 f"{mean('paper_err'):.2f} | {rgb(mean('paper_d'))} | {sum(map(ok, rows))}/{len(rows)} |")
    return lines


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('work', type=Path)
    ap.add_argument('--only', help='K0-K1 or k,k,...')
    ap.add_argument('--tag')
    ap.add_argument('--mode', default='b')
    ap.add_argument('--brush', default='')
    ap.add_argument('--brushes', help='JSON file {"k": {brush}} inside <work>')
    ap.add_argument('--no-render', action='store_true')
    ap.add_argument('--workers', type=int, default=render.WORKERS)
    a = ap.parse_args(argv)
    work = a.work.resolve()
    ks = [k for k, *_ in json.load(open(work / 'd/index.json'))['drawings']]
    if a.only and '-' in a.only:
        k0, k1 = map(int, a.only.split('-'))
        ks = [k for k in ks if k0 <= k <= k1]
    elif a.only:
        ks = [int(k) for k in a.only.split(',')]
    tag = a.tag or a.mode
    out = work / 'out' / tag
    for sub in ('rep', 'heat', 'ab'):
        (out / sub).mkdir(parents=True, exist_ok=True)
    if not a.no_render:
        q = f'mode={a.mode}' + (f'&brush={a.brush}' if a.brush else '') + (f'&brushes={a.brushes}' if a.brushes else '')
        replicas(work, ks, out / 'rep', q, a.workers)
    rows = [measure(k, work, out) for k in ks]
    lines = table(tag, rows)
    (out / f'table-{ks[0]:03d}-{ks[-1]:03d}.md').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))
    worst = sorted(rows, key=lambda r: -r['xor'] / max(r['floor'], 1e-9))[:3]
    with open(work / 'learnings.md', 'a') as f:
        f.write(f"- {datetime.date.today()} measure {tag} d{ks[0]:03d}-d{ks[-1]:03d}: {sum(map(ok, rows))}/{len(rows)} pass; "
                f"mean xor {np.mean([r['xor'] for r in rows]):.3f}%, ssim {np.mean([r['ssim'] for r in rows]):.4f}; worst xor/floor "
                + ', '.join(f"d{r['k']:03d} {r['xor'] / max(r['floor'], 1e-9):.2f}" for r in worst) + '\n')
    return 0 if all(map(ok, rows)) else 1


if __name__ == '__main__':
    sys.exit(main())
