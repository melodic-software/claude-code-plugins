#!/usr/bin/env python3
"""Turn the manual review of a measured run into table columns and 1:1 crops.

usage: review.py <work> <tag> [--only K0-K1]
Reads <work>/src, <work>/d and the replicas in <work>/out/<tag>/rep; writes <work>/out/<tag>/review-K0-K1.md and
<work>/out/<tag>/crops/dNNN.png (source | replica | XOR heat, 1:1, the CROP window with the most XOR). Columns:
  largest     the largest single-colour XOR component (R replica-only, B source-only), px, and `sliver` (no 4x4 square
              fits: at most 3 px thick, an edge coin-flip) or `blob` (a real miss)
  blob        the largest blob of either colour, px (0: every cluster is a sliver)
  edge        XOR px inside the 2 px frame border: tracers and filters mishandle border rows, and a full-frame heatmap
              hides a 1 px run along the edge
  tile        max |mean gray difference| over 32 px tiles after a sigma-3 blur of both images: a wrong tone inside ink
              or paper that XOR cannot see
  paper_err, paper_d  mean abs and signed replica-source RGB over source paper: a tint
  flags       blob; tone (tile > TILE_MAX); paper (paper_err > PAPER_MAX)
"""
import argparse
import json
from multiprocessing import Pool
from pathlib import Path

import cv2
import numpy as np

from measure import paper

CROP = (500, 400)          # w, h of each panel; three panels side by side stay under 2576 px
TILE, TILE_BLUR, TILE_MAX = 32, 3, 8
PAPER_MAX = 5.0            # judgment: the reviewed 239/239 shfred0 replica runs 0.2-5.0
EDGE = 2


def one(job):
    work, out, k = job
    d = json.load(open(work / f'd/d{k:03d}.json'))
    src, rep = cv2.imread(str(work / f'src/d{k:03d}.png')), cv2.imread(str(out / f'rep/d{k:03d}.png'))
    gs, gr = cv2.cvtColor(src, cv2.COLOR_BGR2GRAY), cv2.cvtColor(rep, cv2.COLOR_BGR2GRAY)
    ms, mr = gs < d['T'], gr < d['T']
    red, blue = mr & ~ms, ms & ~mr
    largest, blob = ('-', 0, 'sliver'), ('-', 0)
    for name, m in (('R', red), ('B', blue)):
        m8 = m.astype(np.uint8)
        n, lab, st, _ = cv2.connectedComponentsWithStats(m8, connectivity=8)
        if n < 2:
            continue
        cored = set(np.unique(lab[cv2.erode(m8, np.ones((4, 4), np.uint8)) > 0]).tolist()) - {0}
        i = 1 + int(np.argmax(st[1:, 4]))
        if st[i, 4] > largest[1]:
            largest = (name, int(st[i, 4]), 'blob' if i in cored else 'sliver')
        for j in cored:
            if st[j, 4] > blob[1]:
                blob = (name, int(st[j, 4]))
    x = red | blue
    border = np.ones_like(x)
    border[EDGE:-EDGE, EDGE:-EDGE] = False
    diff = cv2.GaussianBlur(gr.astype(np.float32), (0, 0), TILE_BLUR) - cv2.GaussianBlur(gs.astype(np.float32), (0, 0), TILE_BLUR)
    h, w = (diff.shape[0] // TILE) * TILE, (diff.shape[1] // TILE) * TILE
    tile = float(np.abs(diff[:h, :w].reshape(h // TILE, TILE, w // TILE, TILE).mean((1, 3))).max())
    pe, pd = paper(src, rep, d['T'])
    cw, ch = min(CROP[0], x.shape[1]), min(CROP[1], x.shape[0])
    s = cv2.boxFilter(x.astype(np.float32), -1, (cw, ch), normalize=False, anchor=(0, 0), borderType=cv2.BORDER_CONSTANT)
    y0, x0 = np.unravel_index(np.argmax(s[:x.shape[0] - ch + 1, :x.shape[1] - cw + 1]), (x.shape[0] - ch + 1, x.shape[1] - cw + 1))
    heat = np.full(src.shape, 255, np.uint8)
    heat[ms & mr] = (200, 200, 200)
    heat[red] = (0, 0, 255)
    heat[blue] = (255, 0, 0)
    win = np.s_[y0:y0 + ch, x0:x0 + cw]
    (out / 'crops').mkdir(exist_ok=True)
    cv2.imwrite(str(out / f'crops/d{k:03d}.png'), np.hstack([src[win], rep[win], heat[win]]))
    flags = [f for f, on in (('blob', blob[1] > 0), ('tone', tile > TILE_MAX), ('paper', pe > PAPER_MAX)) if on]
    return (f"| {k} | {largest[0]} {largest[1]} {largest[2]} | {blob[0]} {blob[1]} | {int((x & border).sum())} | {tile:.1f} | "
            f"{pe:.2f} | {','.join(f'{c:+.2f}' for c in pd)} | ({int(x0)},{int(y0)}) | {' '.join(flags)} |")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('work', type=Path)
    ap.add_argument('tag')
    ap.add_argument('--only', help='K0-K1')
    a = ap.parse_args(argv)
    work = a.work.resolve()
    out = work / 'out' / a.tag
    k0, k1 = map(int, a.only.split('-')) if a.only else (0, 10 ** 9)
    ks = [k for k, *_ in json.load(open(work / 'd/index.json'))['drawings']
          if k0 <= k <= k1 and (out / f'rep/d{k:03d}.png').exists()]
    with Pool() as p:
        rows = p.map(one, [(work, out, k) for k in ks])
    lines = [f'# review {a.tag} d{ks[0]:03d}-d{ks[-1]:03d}', '',
             '| k | largest | blob | edge px | tile | paper_err | paper_d R,G,B | crop at | flags |',
             '|---|---|---|---|---|---|---|---|---|'] + rows
    (out / f'review-{ks[0]:03d}-{ks[-1]:03d}.md').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    main()
