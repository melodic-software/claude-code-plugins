#!/usr/bin/env python3
"""Decode a reference video into its distinct drawings and trace each one to vector paths.

usage: extract.py <work> [--video V] [--overrides F] [--only K0-K1] [--apply] [--jobs N]
  --video      decode V into <work>/src/dNNN.png and <work>/d/index.json (needed once per work dir)
  --overrides  override file (default <work>/overrides.json when present), see SKILL.md
  --apply      keep existing traces; retrace only drawings whose sharp/levels changed, then re-apply brush and tint

Writes <work>/d/dNNN.json:
  {k, pts, t1, w, h, S, eps, interp, sharp, levels, ink, paper, T, t_color, gray:{...},
   paths:[{d, holes:[d...]}], tones:[{lv, color, paths, tint?}], brush?}
Coordinates are canvas coordinates (pixel (x,y) covers [x,x+1)), flattened [x0,y0,x1,y1,...], 2 decimals.
Method (reference/method.md): gray = cv2 RGB2GRAY; T = midpoint of the ink and paper gray modes; unsharp mask
(keeping the raw gray on the outer 1 px frame border); supersample S x; threshold; findContours RETR_CCOMP;
approxPolyDP(eps * S); map an upsampled pixel centre u to (u + 0.5) / S.
"""
import argparse
import json
import sys
from multiprocessing import Pool
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'scripts'))
from decode import MID, frames, is_repeat, modes, probe  # noqa: E402
import workdir  # noqa: E402
from render import WORKERS  # noqa: E402

S, EPS, INTERP = 4, 0.25, 'cubic'   # supersample, approxPolyDP epsilon (source px), upsampler
SHARP = (2.0, 0.9)                   # (amount, sigma) unsharp mask before tracing, or None
LEVELS = (50, 90, 165, 205)          # extra gray isolines traced as tone layers
TINT_RG, TINT_SIGN_RG, TINT_SIGN_PX = 4, 6, 15000   # warm paper: median R-G >= 4; a 'sign' is one >15k px region at >= 6


def decode(video, work):
    """Write src/dNNN.png for every distinct drawing and d/index.json {w, h, duration, drawings: [[k, pts, t1], ...]}."""
    w, h, pts = probe(video)
    workdir.src(work).mkdir(parents=True, exist_ok=True)
    workdir.traces_dir(work).mkdir(exist_ok=True)
    ts, prev = [], None
    for rgb, t in frames(video, None):
        if is_repeat(prev, rgb):
            continue
        prev = rgb.astype(np.int16)
        cv2.imwrite(str(workdir.source(work, len(ts))), cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))
        ts.append(t)
    gap = float(np.median(np.diff(ts))) if len(ts) > 1 else 1 / 8
    t1 = ts[1:] + [round(ts[-1] + gap, 6)]
    ix = dict(w=w, h=h, duration=t1[-1], drawings=[[k, t, e] for k, (t, e) in enumerate(zip(ts, t1))])
    json.dump(ix, open(workdir.index(work), 'w', encoding='utf-8'))
    print(f'{len(ts)} drawings from {len(pts)} frames, {w}x{h}')
    return ix


def load_overrides(path):
    return json.load(open(path, encoding='utf-8'))['overrides'] if path and Path(path).exists() else []


def overrides_for(ovr, k):
    """Merge every entry whose k range holds k, in file order; later entries win, `brush` merges key by key."""
    o = {}
    for e in ovr:
        k0, k1 = e['k'] if isinstance(e['k'], list) else (e['k'], e['k'])
        if k0 <= k <= k1:
            for key, v in e.items():
                if key in ('k', 'why'):
                    continue
                o[key] = {**o.get(key, {}), **v} if key == 'brush' else v
    return o


def hexcol(v):
    return '#%02x%02x%02x' % tuple(int(c) for c in v)


def stats(rgb, g):
    ink_g, paper_g, T = modes(g)
    ink, paper = g < T, g >= T
    core_i, core_p = np.abs(g.astype(int) - ink_g) <= 8, np.abs(g.astype(int) - paper_g) <= 8
    return dict(ink=hexcol(np.median(rgb[core_i], 0)), paper=hexcol(np.median(rgb[core_p], 0)), T=T, gray=dict(
        ink_mode=ink_g, paper_mode=paper_g,
        ink_mean=round(float(g[ink].mean()), 2), ink_sd=round(float(g[ink].std()), 2),
        paper_mean=round(float(g[paper].mean()), 2), paper_sd=round(float(g[paper].std()), 2),
        edge_frac=round(float(((g > ink_g + MID) & (g < paper_g - MID)).mean()), 5),
        ink_frac=round(float(ink.mean()), 5)))


def trace(gray, T, s=S, eps=EPS, interp=INTERP, sharp=SHARP):
    if sharp:   # unsharp mask undoes the source blur so render-side blur restores it
        g = gray.astype(np.float32)
        sg = g + sharp[0] * (g - cv2.GaussianBlur(g, (0, 0), sharp[1]))
        # the blur reflects the dark row 1 onto row 0, pushing a near-T border row across T; keep the raw border
        sg[[0, -1]] = g[[0, -1]]
        sg[:, [0, -1]] = g[:, [0, -1]]
        gray = sg
    h, w = gray.shape
    big = cv2.resize(gray, (w * s, h * s), interpolation=getattr(cv2, 'INTER_' + interp.upper())) if s > 1 else gray
    cs, hier = cv2.findContours((big < T).astype(np.uint8), cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    if hier is None:
        return []
    hier = hier[0]

    def flat(c):
        return np.round(((cv2.approxPolyDP(c, eps * s, True) if eps else c).reshape(-1) + 0.5) / s, 2).tolist()
    out = []
    for i, c in enumerate(cs):
        if hier[i][3] != -1:
            continue   # holes are collected under their parent
        holes, j = [], hier[i][2]
        while j != -1:
            holes.append(flat(cs[j]))
            j = hier[j][0]
        out.append(dict(d=flat(c), holes=holes))
    return out


def tones(rgb, g, T, levels, **kw):
    """Tone layer lv fills g < lv; its visible band is [next lower level, lv), coloured by that band's median RGB.
    Returns (tone layers, colour of the T layer)."""
    lv = sorted(set(levels) | {T})
    col = {}
    for lo, hi in zip([-1] + lv, lv):
        m = (g >= lo) & (g < hi)
        col[hi] = hexcol(np.median(rgb[m], 0)) if m.any() else '#000000'
    return [dict(lv=v, color=col[v], paths=trace(g, v, **kw)) for v in levels], col[T]


def tint(rgb, g, T):
    """Warm-paper layers (lv 252, 251): paper regions whose median R-G is warmer than neutral. One colour per frame
    cannot follow a spatial tint, and gray XOR/SSIM cannot see it; paper_err can."""
    m = cv2.erode((g > 200).astype(np.uint8), np.ones((5, 5), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    rg = rgb[..., 0].astype(np.float32) - rgb[..., 1]
    groups = {}
    for i in range(1, n):
        if st[i, 4] < 300:
            continue
        v = float(np.median(rg[lab == i]))
        if v >= TINT_RG:
            groups.setdefault('sign' if v >= TINT_SIGN_RG and st[i, 4] > TINT_SIGN_PX else 'warm', []).append(i)
    out = []
    for lv, (name, ids) in zip((252, 251), sorted(groups.items())):
        mk = np.isin(lab, ids)
        color = hexcol(np.median(rgb[mk], 0))
        mk = cv2.dilate(mk.astype(np.uint8), np.ones((7, 7), np.uint8)) & (g > T).astype(np.uint8)
        cs, _ = cv2.findContours(mk, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        paths = [dict(d=[round(float(v) + 0.5, 2) for p in cv2.approxPolyDP(c, 0.5, True)[:, 0] for v in p], holes=[])
                 for c in cs if len(c) >= 3]
        out.append(dict(lv=lv, color=color, paths=paths, tint=name))
    return out


def npoints(paths):
    return sum(len(p['d']) + sum(len(h) for h in p['holes']) for p in paths) // 2


def one(job):
    """Trace (or, with apply, reuse) drawing k and apply its overrides. Returns a summary line."""
    work, k, t, t1, ov, apply = job
    f = workdir.trace(work, k)
    sharp = tuple(ov['sharp']) if ov.get('sharp') else (None if 'sharp' in ov else SHARP)
    levels = list(ov.get('levels', LEVELS))
    d = json.load(open(f, encoding='utf-8')) if apply and f.exists() else None
    rgb = g = None
    if d is None or (tuple(d['sharp']) if d['sharp'] else None) != sharp or d.get('levels') != levels:
        rgb = cv2.cvtColor(cv2.imread(str(workdir.source(work, k))), cv2.COLOR_BGR2RGB)
        g = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
        st = stats(rgb, g)
        kw = dict(s=S, eps=EPS, interp=INTERP, sharp=sharp)
        tl, t_color = tones(rgb, g, st['T'], levels, **kw)
        d = dict(k=k, pts=t, t1=t1, w=g.shape[1], h=g.shape[0], S=S, eps=EPS, interp=INTERP, sharp=sharp, levels=levels,
                 **st, t_color=t_color, paths=trace(g, st['T'], **kw), tones=tl)
    d['tones'] = [x for x in d['tones'] if 'tint' not in x]
    if ov.get('tint'):
        if rgb is None:
            rgb = cv2.cvtColor(cv2.imread(str(workdir.source(work, k))), cv2.COLOR_BGR2RGB)
            g = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
        d['tones'] += tint(rgb, g, d['T'])
    d.pop('brush', None)
    if ov.get('brush'):
        d['brush'] = ov['brush']
    json.dump(d, open(f, 'w', encoding='utf-8'), separators=(',', ':'))
    return f'{workdir.name(k)} T={d["T"]} points={npoints(d["paths"])} ' + (json.dumps(ov) if ov else '')


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('work', type=Path)
    ap.add_argument('--video', type=Path)
    ap.add_argument('--overrides', type=Path)
    ap.add_argument('--only', help='K0-K1')
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--jobs', type=int, default=WORKERS)
    a = ap.parse_args(argv)
    work = a.work.resolve()
    ix = decode(a.video, work) if a.video else json.load(open(workdir.index(work), encoding='utf-8'))
    ovr = load_overrides(a.overrides or workdir.overrides(work))
    k0, k1 = map(int, a.only.split('-')) if a.only else (0, 10 ** 9)
    jobs = [(work, k, t, t1, overrides_for(ovr, k), a.apply) for k, t, t1 in ix['drawings'] if k0 <= k <= k1]
    with Pool(a.jobs) as p:
        for line in p.imap(one, jobs):
            print(line, flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
