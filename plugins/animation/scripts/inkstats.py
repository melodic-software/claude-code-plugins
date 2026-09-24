#!/usr/bin/env python3
"""Style statistics of an ink film, computed the same way for a source clip and for any render.

usage: inkstats.py <film> [--fps N] [--cuts T,T,.. | --seg S] [--region X,Y,W,H] [--t T0-T1] [--json OUT]
                   [--rows OUT] [--pack PACK]
  <film>    a video, a folder of capture.mjs frames (fNNNN.png, played at --fps, default 24), or a rotoscope work dir
            (src/dNNN.png timed by d/index.json)
  --cuts    shot boundaries in seconds; each shot is a segment. Without it, segments are --seg seconds long (default
            3.35: nine on a 30 s clip)
  --region  measure only this box of every frame (a prop, a dark field); --t keeps only frames with T0 <= t < T1
  --json    write the summary: per statistic p10/p50/p90 over drawings, and per segment medians
  --rows    write the per-drawing rows (for analysis; a style pack never holds them)
  --pack    a style pack directory or its style.json. Each statistic in `check` must have its film median inside the
            pack's band, each in `segment_check` must have every segment median inside it (segments of at least
            the pack's `segment_min_drawings`), and the ink and paper
            colours must sit within the palette tolerance. Prints the tables; exit 1 if any row fails.
Frames that repeat a drawing (fewer than DUP_PX pixels changed by more than 64 gray levels) are dropped, so a 24 fps
capture and a variable-rate source both reduce to distinct drawings with their hold times.

Per drawing (gray = RGB2GRAY; ink and paper = the gray histogram modes below and above 128; T = their midpoint):
  ink       fraction of the frame darker than T
  soft      mid-gray pixels (between ink + 16 and paper - 16) per ink edge pixel: the edge ramp width in px
  w10 w50 w90   ink stroke width percentiles, px: 2 x the distance transform on its ridge
  pw50      paper width median, px: the same on paper (slivers and gaps between strokes)
  rough     raw contour length / length after approxPolyDP(4 px) - 1, contours over 50 px: edge wobble
  straight  share of contour length in straight runs of 30 px or more (approxPolyDP 1.5 px): ruled lines
  specks    ink islands of 2-200 px per megapixel      gaps  paper islands of 2-200 px per megapixel
  holes     paper share of the ink after a 7 px closing: streaks and gouges inside masses
  ink_sd paper_sd   gray standard deviation inside eroded ink and paper: dry brush and paper grain
  field_sd  the same inside the largest connected ink area (the dark field), eroded; 0 when it has no core
  ink_rgb paper_rgb median colours of the ink and paper cores
Per pair of consecutive drawings:
  boil      on held pairs only (phase-correlation shift under 1 px and ink change under 1 point), ink/paper
            disagreement per edge pixel: the mean edge displacement in px between two drawings of the same pose
  held      share of pairs that are held
Per drawing duration: hold in 24 fps frames (on 1s, 2s, 3s, 4+) and drawings per second.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

DUP_PX = 50
SEG = 3.35
STATS = ('ink', 'soft', 'w10', 'w50', 'w90', 'pw50', 'rough', 'straight', 'specks', 'gaps', 'holes', 'ink_sd',
         'paper_sd', 'field_sd', 'boil')


def frames(film, fps):
    """Yield (rgb, t) for every stored frame of a video, frame folder or rotoscope work dir."""
    film = Path(film)
    if (film / 'src').is_dir():
        for k, t, *_ in json.load(open(film / 'd/index.json'))['drawings']:
            yield cv2.cvtColor(cv2.imread(str(film / f'src/d{k:03d}.png')), cv2.COLOR_BGR2RGB), t
    elif film.is_dir():
        for i, f in enumerate(sorted(film.glob('f*.png'))):
            yield cv2.cvtColor(cv2.imread(str(f)), cv2.COLOR_BGR2RGB), i / fps
    else:
        def probe(entries):
            return subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', entries,
                                   '-of', 'csv=p=0', str(film)], capture_output=True, text=True, check=True).stdout
        w, h = map(int, probe('stream=width,height').strip().split(',')[:2])
        pts = [float(t) for t in probe('frame=pts_time').replace(',', ' ').split()]
        p = subprocess.Popen(['ffmpeg', '-v', 'error', '-i', str(film), '-map', '0:v:0', '-fps_mode', 'passthrough',
                              '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], stdout=subprocess.PIPE)
        for t in pts:
            buf = p.stdout.read(w * h * 3)
            if len(buf) < w * h * 3:
                break
            yield np.frombuffer(buf, np.uint8).reshape(h, w, 3), t
        p.wait()


def drawings(film, fps, region=None, window=None):
    """Yield (rgb, t0) for each distinct drawing (cropped to region, inside window), and finally (None, end time)."""
    prev, t, dt = None, 0.0, 1 / fps
    t0, t1 = window or (-1e9, 1e9)
    for rgb, t in frames(film, fps):
        if t < t0:
            continue
        if t >= t1:
            t = t1
            break
        if region:
            x, y, w, h = region
            rgb = rgb[y:y + h, x:x + w]
        g = rgb.astype(np.int16)
        if prev is not None and (np.abs(g - prev) > 64).sum() < DUP_PX:
            continue
        prev = g
        yield rgb, t
    else:
        t += dt
    yield None, t


def ridge_widths(mask):
    m = cv2.copyMakeBorder(mask.astype(np.uint8), 1, 1, 1, 1, cv2.BORDER_CONSTANT, value=0)   # frame edge ends a stroke
    dt = cv2.distanceTransform(m, cv2.DIST_L2, 5)[1:-1, 1:-1]
    r = (dt >= 1) & (dt >= cv2.dilate(dt, np.ones((3, 3), np.uint8)) - 1e-3)
    return 2 * dt[r]


def islands(mask, conn):
    n, _, st, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=conn)
    a = st[1:, 4]
    return int(((a >= 2) & (a <= 200)).sum()) * 1e6 / mask.size


def contour_stats(ink):
    cs, _ = cv2.findContours(ink.astype(np.uint8), cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
    raw = smooth = total = straight = 0.0
    for c in cs:
        L = cv2.arcLength(c, True)
        if L < 50:
            continue
        raw += L
        smooth += cv2.arcLength(cv2.approxPolyDP(c, 4, True), True)
        p = cv2.approxPolyDP(c, 1.5, True)[:, 0].astype(float)
        seg = np.hypot(*(np.roll(p, -1, 0) - p).T)
        total += seg.sum()
        straight += seg[seg >= 30].sum()
    return raw / max(smooth, 1) - 1, straight / max(total, 1)


def one(rgb):
    g = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    h = np.bincount(g.ravel(), minlength=256)
    ink_g, paper_g = int(np.argmax(h[:128])), 128 + int(np.argmax(h[128:]))
    T = (ink_g + paper_g) / 2
    ink = g < T
    edge = int((ink[:, 1:] != ink[:, :-1]).sum() + (ink[1:] != ink[:-1]).sum())
    mid = int(((g > ink_g + 16) & (g < paper_g - 16)).sum())
    w, pw = ridge_widths(ink), ridge_widths(~ink)
    rough, straight = contour_stats(ink)
    k5 = np.ones((5, 5), np.uint8)
    closed = cv2.morphologyEx(ink.astype(np.uint8), cv2.MORPH_CLOSE,
                              cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))).astype(bool)
    core_i = cv2.erode(ink.astype(np.uint8), k5).astype(bool)
    core_p = cv2.erode((~ink).astype(np.uint8), k5).astype(bool)
    n, lab, st, _ = cv2.connectedComponentsWithStats(ink.astype(np.uint8), connectivity=8)
    field = core_i & (lab == 1 + int(np.argmax(st[1:, 4]))) if n > 1 else core_i

    def pct(v, q):
        return float(np.percentile(v, q)) if len(v) else 0.0

    def sd(m):
        return float(g[m].std()) if m.any() else 0.0

    def med(m):
        return [int(c) for c in np.median(rgb[m], 0)] if m.any() else [0, 0, 0]
    return dict(ink=float(ink.mean()), soft=mid / max(edge, 1), w10=pct(w, 10), w50=pct(w, 50), w90=pct(w, 90),
                pw50=pct(pw, 50), rough=rough, straight=straight, specks=islands(ink, 8), gaps=islands(~ink, 4),
                holes=float((closed & ~ink).sum() / max(closed.sum(), 1)), ink_sd=sd(core_i), paper_sd=sd(core_p),
                field_sd=sd(field), ink_rgb=med(core_i), paper_rgb=med(core_p), edge=edge, T=T, gray=g, mask=ink)


def boil(a, b):
    """Edge displacement between consecutive drawings a, b if they hold one pose, else None."""
    (dx, dy), _ = cv2.phaseCorrelate(a['gray'].astype(np.float32), b['gray'].astype(np.float32))
    if abs(dx) >= 1 or abs(dy) >= 1 or abs(a['ink'] - b['ink']) >= 0.01:
        return None
    return float((a['mask'] ^ b['mask']).sum() / max(a['edge'], b['edge'], 1))


def measure(film, fps=24, region=None, window=None):
    """Per-drawing rows: every statistic above plus t (start) and hold (s)."""
    rows, prev = [], None
    for rgb, t in drawings(film, fps, region, window):
        if rows:
            rows[-1]['hold'] = t - rows[-1]['t']
        if rgb is None:
            break
        r = one(rgb)
        r['t'] = t
        r['boil'] = boil(prev, r) if prev else None
        prev = r
        rows.append(r)
    for r in rows:
        r.pop('gray'), r.pop('mask')
    if not rows:
        sys.exit(f'inkstats: no drawings in {film}' + (f' between {window[0]} and {window[1]} s' if window else ''))
    return rows


def edges(rows, cuts=None, seg=SEG):
    """Segment boundaries in film seconds: the given cuts, else every seg seconds."""
    t0, t1 = rows[0]['t'], rows[-1]['t'] + rows[-1]['hold']
    inner = [c for c in cuts if t0 < c < t1] if cuts else list(np.arange(t0 + seg, t1 - 1e-6, seg))
    return [t0, *inner, t1]


def segment(rows, e):
    """Rows split at boundaries e."""
    return [[r for r in rows if a <= r['t'] < b] for a, b in zip(e, e[1:])]


def median(rows, s):
    v = [r[s] for r in rows if r[s] is not None]
    return round(float(np.median(v)), 4) if v else None


def summary(rows, cuts=None, seg=SEG):
    def pcts(v):
        v = [x for x in v if x is not None]
        return dict(zip(('p10', 'p50', 'p90'), (round(float(np.percentile(v, q)), 4) for q in (10, 50, 90)))) if v \
            else None
    dur = rows[-1]['t'] + rows[-1]['hold'] - rows[0]['t']
    frames24 = np.array([max(1, round(r['hold'] * 24)) for r in rows])
    e = edges(rows, cuts, seg)
    return dict(drawings=len(rows), duration=round(dur, 3), per_second=round(len(rows) / dur, 3),
                holds={f'on{n}s': round(float((frames24 == n).mean()), 3) for n in (1, 2, 3)} |
                {'on4s+': round(float((frames24 >= 4).mean()), 3)},
                held=round(float(np.mean([r['boil'] is not None for r in rows[1:]])), 3) if len(rows) > 1 else 0,
                stats={s: pcts([r[s] for r in rows]) for s in STATS},
                ink_rgb=[int(c) for c in np.median([r['ink_rgb'] for r in rows], 0)],
                paper_rgb=[int(c) for c in np.median([r['paper_rgb'] for r in rows], 0)],
                T=float(np.median([r['T'] for r in rows])),
                segments=[dict(t0=round(a, 3), t1=round(b, 3), n=len(sr), per_second=round(len(sr) / (b - a), 3),
                               **{s: median(sr, s) for s in STATS})
                          for (a, b), sr in zip(zip(e, e[1:]), segment(rows, e)) if sr])


def check(m, pack):
    """Rows (name, value, band, ok): each `check` statistic's film median (or a top-level value such as per_second),
    each `segment_check` statistic per segment, and the largest ink or paper RGB channel difference from the palette."""
    out = []
    for s in pack['check']:
        lo, hi = pack['bands'][s]
        v = m[s] if s in m else m['stats'][s]['p50'] if m['stats'].get(s) else None
        out.append((s, v, (lo, hi), v is not None and lo <= v <= hi))
    for s in pack.get('segment_check', []):
        lo, hi = pack['bands'][s]
        for g in (g for g in m['segments'] if g['n'] >= pack.get('segment_min_drawings', 1)):
            out.append((f"{s} {g['t0']:g}-{g['t1']:g} s", g[s], (lo, hi), g[s] is not None and lo <= g[s] <= hi))
    for s in ('ink_rgb', 'paper_rgb'):
        want = pack['palette'][s[:-4]].lstrip('#')
        v = max(abs(c - int(want[2 * i:2 * i + 2], 16)) for i, c in enumerate(m[s]))
        out.append((s, v, (0, pack['palette']['tolerance']), v <= pack['palette']['tolerance']))
    return out


def load_pack(p):
    p = Path(p)
    return json.load(open(p / 'style.json' if p.is_dir() else p))


def nums(s, n=None):
    v = [float(x) for x in s.replace('-', ',').split(',')] if s else None
    if v and n and len(v) != n:
        sys.exit(f'inkstats: expected {n} numbers, got {s!r}')
    return v


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('film')
    ap.add_argument('--fps', type=float, default=24)
    ap.add_argument('--seg', type=float, default=SEG)
    ap.add_argument('--cuts')
    ap.add_argument('--region')
    ap.add_argument('--t')
    ap.add_argument('--json', type=Path)
    ap.add_argument('--rows', type=Path)
    ap.add_argument('--pack', type=Path)
    a = ap.parse_args(argv)
    pack = load_pack(a.pack) if a.pack else None   # fail on a bad pack path before the long measure
    region = [int(v) for v in nums(a.region, 4)] if a.region else None
    rows = measure(a.film, a.fps, region, nums(a.t, 2))
    m = summary(rows, nums(a.cuts), a.seg)
    if a.json:
        a.json.write_text(json.dumps(m, indent=1) + '\n')
    if a.rows:
        a.rows.write_text(json.dumps(rows) + '\n')
    print(f"{a.film}{f' region {region}' if region else ''}: {m['drawings']} drawings, {m['duration']} s, "
          f"{m['per_second']}/s, holds {m['holds']}, held pairs {m['held']}")
    print('| stat | p10 | p50 | p90 | ' + ' | '.join(f"{g['t0']:g}-{g['t1']:g} s" for g in m['segments']) + ' |')
    print('|---|---|---|---|' + '---|' * len(m['segments']))
    for s, v in m['stats'].items():
        print(f'| {s} | ' + (' | '.join(f'{v[q]:.4g}' for q in ('p10', 'p50', 'p90')) if v else '- | - | -') + ' | '
              + ' | '.join('-' if g[s] is None else f'{g[s]:.4g}' for g in m['segments']) + ' |')
    if not pack:
        return 0
    out = check(m, pack)
    print(f'\ncheck against {a.pack}\n\n| check | film | band | pass |\n|---|---|---|---|')
    for s, v, (lo, hi), ok in out:
        print(f"| {s} | {'-' if v is None else f'{v:.4g}'} | {lo:.4g}-{hi:.4g} | {'yes' if ok else 'NO'} |")
    print(f'{sum(r[3] for r in out)}/{len(out)} pass')
    return 0 if all(r[3] for r in out) else 1


if __name__ == '__main__':
    sys.exit(main())
