#!/usr/bin/env python3
"""Style statistics of an ink film, computed the same way for a source clip and for any render.

usage: inkstats.py <film> [--fps N] [--cuts T,T,.. | --seg S] [--region X,Y,W,H] [--t T0-T1] [--json OUT]
                   [--rows OUT] [--pack PACK]
  <film>    a video, a folder of capture.mjs frames (fNNNN.png, played at --fps, default 24), or a rotoscope work dir
            (src/dNNN.png timed by d/index.json)
  --cuts    shot boundaries in seconds; each shot is a column of the table. Without it, columns are --seg seconds
            long (default 3.35). Columns are for reading only: the check judges the whole film.
  --region  measure only this box of every frame (a prop, a dark field); --t keeps only frames with T0 <= t < T1
  --json    write the summary: per statistic p10/p50/p90 over drawings, the timing values, and per column medians
  --rows    write the per-drawing rows (for analysis; a style pack never holds them)
  --pack    a style pack directory or its style.json. Each statistic in the pack's `check` must have its film value
            (the median over drawings, or a timing value such as per_second) inside the pack's band, and the ink and
            paper colours must sit within the palette tolerance. A statistic the film leaves undefined (flat with no
            dark drawings, boil with no held pairs, grain with no ink interior) is n/a: neither pass nor fail, and
            left out of the distance. Prints each row with its distance to source and exits 1 if any row fails.
            The pack's `measured_only` statistics (subject-sensitive) print beside the source value, unjudged.
            Distance of a row: |film - source| / |band edge - source| on the film's side of the source value, so 0 is
            the source and 1 is the band edge on either side; a row fails above 1. The film's distance is the mean
            over the rows it defines, and ranks films that all pass.
Frames that repeat a drawing (fewer than DUP_PX pixels changed by more than 64 gray levels) are dropped, so a 24 fps
capture and a variable-rate source both reduce to distinct drawings with their hold times.

Per drawing (gray = RGB2GRAY; ink and paper = the gray histogram modes below and above 128; T = their midpoint):
  ink       fraction of the frame darker than T
  soft      mid-gray pixels (between ink + 16 and paper - 16) per ink edge pixel: the edge ramp width in px
  w10 w50 w90   ink stroke width percentiles, px: 2 x the distance transform on its ridge
  pw50      paper width median, px: the same on paper (slivers and gaps between strokes)
  rough     raw contour length / length after approxPolyDP(4 px) - 1, contours over 50 px: edge wobble
            plus the share of small marks (nicks, dashes, specks), each rough by construction under a 4 px fit
  straight  share of contour length in straight runs of 30 px or more (approxPolyDP 1.5 px): ruled lines
  straight_border straight_caption   the same over the contour segments whose midpoint lies in that content class,
            leaving out segments that run along the frame edge; None under 200 px of such contour
  specks    ink islands of 2-200 px per megapixel      gaps  paper islands of 2-200 px per megapixel
  holes     paper share of the ink after a 7 px closing: streaks and gouges inside masses
  ink_sd paper_sd   gray standard deviation inside eroded ink and paper: dry brush and paper grain
  field_sd  the same inside the largest connected ink area (the dark field), eroded; 0 when it has no core
  flat      dark drawings only (ink >= 0.5): share of mostly-ink 32 px blocks that lie fully inside eroded ink
            with gray sd under 2: the balance of flat black to textured ink
  grain     inside the ink interior (ink eroded 5 px), sd of the 5x5 box-mean gray over sd of the gray: near 1 for
            texture in patches wider than 5 px, near 0.2 for pixel noise, lower for 1-2 px stripes. On a near-flat
            black a few stray pixels and codec residue set it, not visible texture
  period    inside the eroded ink, over spatial frequencies at pitches of 3-24 px, the largest ratio of a bin's
            power to the mean power of all bins at the same frequency (every direction), divided by ln(eroded ink
            pixels): large for a texture at one fixed pitch and direction (ruled stripes, combed dry brush), near
            the noise level for irregular texture and for smooth tone drift, whose power falls with frequency
            alike in every direction. The largest of many such ratios grows as the log of the ink area; the
            division takes the area out
  sliver    median area / width^2 of the paper islands inside the ink (carved slivers and gouges, 6-20000 px, not
            touching the frame edge; width = 2 x the largest distance to ink): long thin lines high, chunky cuts low
  sliver_border sliver_caption   the same over the islands whose centroid lies in that content class; None under 3
Content classes, from the ink mask alone, so a source and any film get them the same way:
  border    the ring within BORDER (3%) of the short side of the frame edge, for every border row: the hand-drawn
            frame stroke with the paper margin outside it. On the woodcut source the stroke starts 9 px in (p95
            10) and is 19 px wide (median), so it ends by 29 px = 3% of the 982 px short side. A drawing has the
            class when the ring is PRESENT (10%) or more ink
  (the caption box grows by CAPTION (1.3% of the short side) for every caption row: its hand-drawn outline. On the
            woodcut source the outline starts at the paper edge and is 13 px wide (median over 231 box sides with an
            outer edge), 1.3% of the 982 px short side)
  caption   a caption panel: a paper rectangle (after a 5 px closing of the ink) in the top quarter of the frame, not
            touching its edge, 0.2-6% of the frame, at least 1.5x as wide as tall, filling 80% of its rotated box
            and holding ink (lettering), outside the border ring
  interior  everything else: the subject. straight and sliver there and over the whole frame follow what is drawn
  ink_rgb paper_rgb median colours of the ink and paper cores
Per pair of consecutive drawings:
  boil      over the border and caption classes of both drawings (the anchor), on pairs whose anchor ink share
            changes under 1 point and that have 500 or more anchor edge pixels: ink/paper disagreement there per
            anchor edge pixel, the mean edge displacement in px of the frame and caption between two drawings. The
            anchor holds still in every film of the style, so boil does not depend on what the subject does
  held      share of pairs boil is measured on
Per drawing duration: hold in 24 fps frames (on 1s, 2s, 3s, 4+), drawings per second, and offstep: the share of
consecutive drawing pairs whose two holds do not add up to twice the most common hold. It is 0 for a film strictly on
3s, and it ignores a drawing that re-timing onto a 24 fps grid moves one frame early or late (a 2 then a 4 on 3s).
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
STATS = ('ink', 'soft', 'w10', 'w50', 'w90', 'pw50', 'rough', 'straight', 'straight_border', 'straight_caption',
         'specks', 'gaps', 'holes', 'ink_sd', 'paper_sd', 'field_sd', 'flat', 'grain', 'period', 'sliver',
         'sliver_border', 'sliver_caption', 'boil')
FLAT_B, FLAT_SD = 32, 2   # flat black: a 32 px block fully inside eroded ink with gray sd under 2
BORDER = 0.03             # border class, every border row: this share of the short side, from each edge (the stroke)
PRESENT = 0.1             # a drawing has the border class when its ring is at least this share ink
CAPTION = 0.013           # caption class: each detected box grown by this share of the short side (its outline)
CLASSES = ('border', 'caption')   # labels 0 and 1; label 2 is the interior


def frames(film, fps):
    """Yield (rgb, t) for every stored frame of a video, frame folder or rotoscope work dir; any other iterable of
    (rgb, t) passes through (filtered or synthetic frames)."""
    if not isinstance(film, (str, Path)):
        yield from film
        return
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
        try:
            for t in pts:
                buf = p.stdout.read(w * h * 3)
                if len(buf) < w * h * 3:
                    break
                yield np.frombuffer(buf, np.uint8).reshape(h, w, 3), t
        finally:   # a caller that stops early (--t) must not leave ffmpeg writing into a closed pipe
            p.kill()
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
            if x < 0 or y < 0 or w < 1 or h < 1 or x + w > rgb.shape[1] or y + h > rgb.shape[0]:
                sys.exit(f'inkstats: --region {x},{y},{w},{h} is not inside the {rgb.shape[1]}x{rgb.shape[0]} frame')
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


def captions(ink):
    """Caption panel boxes (x0, y0, x1, y1): see the caption class above."""
    H, W = ink.shape
    paper = 1 - cv2.morphologyEx(ink.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    cs, hier = cv2.findContours(paper, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    out = []
    for c, (_, _, child, parent) in zip(cs, hier[0] if cs else []):
        x, y, w, h = cv2.boundingRect(c)
        a = cv2.contourArea(c)
        if parent == -1 and child != -1 and 0.002 * H * W <= a <= 0.06 * H * W and x > 0 and y > 0 and x + w < W \
                and y + h <= H / 4 and w >= 1.5 * h and a >= 0.8 * np.prod(cv2.minAreaRect(c)[1]):
            out.append((x, y, x + w, y + h))
    return out


def classes(ink, boxes):
    """Content class per pixel: 0 border (the BORDER ring), 1 caption (each box grown by CAPTION),
    2 interior."""
    H, W = ink.shape
    e, p = round(BORDER * min(H, W)), round(CAPTION * min(H, W))
    lab = np.full((H, W), 2, np.uint8)
    for x0, y0, x1, y1 in boxes:
        lab[max(0, y0 - p):y1 + p, max(0, x0 - p):x1 + p] = 1
    lab[:e], lab[-e:], lab[:, :e], lab[:, -e:] = 0, 0, 0, 0
    return lab


def at(lab, xy):
    """Class of each (x, y) point."""
    xy = np.clip(np.round(xy).astype(int), 0, [lab.shape[1] - 1, lab.shape[0] - 1])
    return lab[xy[:, 1], xy[:, 0]]


def contour_stats(ink, lab):
    """(rough, straight, {class: straight share}) over contours of 50 px or more."""
    cs, _ = cv2.findContours(ink.astype(np.uint8), cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
    H, W = ink.shape
    raw = smooth = total = straight = 0.0
    segs = [np.zeros((0, 2))]
    for c in cs:
        L = cv2.arcLength(c, True)
        if L < 50:
            continue
        raw += L
        smooth += cv2.arcLength(cv2.approxPolyDP(c, 4, True), True)
        p = cv2.approxPolyDP(c, 1.5, True)[:, 0].astype(float)
        q = np.roll(p, -1, 0)
        seg = np.hypot(*(q - p).T)
        total += seg.sum()
        straight += seg[seg >= 30].sum()
        frame = ((p <= 0) & (q <= 0)).any(1) | ((p[:, 0] >= W - 1) & (q[:, 0] >= W - 1)) \
            | ((p[:, 1] >= H - 1) & (q[:, 1] >= H - 1))   # a run along the frame edge is the frame, not a stroke
        segs.append(np.c_[at(lab, (p + q) / 2), seg][~frame])
    segs = np.vstack(segs)
    per = {}
    for k, n in enumerate(CLASSES):
        s = segs[segs[:, 0] == k, 1]
        per[n] = float(s[s >= 30].sum() / s.sum()) if s.sum() >= 200 else None
    return (raw / smooth - 1, straight / total, per) if total else (None, None, per)   # no contour over 50 px: n/a


def texture(g, ink):
    """(grain, period) of the gray inside the ink; None where the interior is too small to say."""
    gf = g.astype(np.float32)
    inner = cv2.erode(ink, np.ones((11, 11), np.uint8)).astype(bool)   # every 5x5 box mean lies inside eroded ink
    s = gf[inner].std() if inner.sum() >= 1000 else 0
    grain = float(cv2.blur(gf, (5, 5))[inner].std() / s) if s > 0 else None
    core = cv2.erode(ink, np.ones((7, 7), np.uint8)).astype(bool)
    if core.sum() < 5000:
        return grain, None
    p = np.abs(np.fft.rfft2(np.where(core, gf - gf[core].mean(), 0))) ** 2
    f = np.hypot(np.fft.rfftfreq(g.shape[1])[None, :], np.fft.fftfreq(g.shape[0])[:, None])
    ring = np.round(f * max(g.shape)).astype(int)   # bins at one spatial frequency, every direction
    level = (np.bincount(ring.ravel(), p.ravel()) / np.maximum(np.bincount(ring.ravel()), 1))[ring]
    ok = (f > 1 / 24) & (f < 0.35) & (level > 0)   # pitch 3-24 px: clear of the cutoff and the 2 px codec grid
    return grain, float((p[ok] / level[ok]).max() / np.log(core.sum())) if ok.any() else None


def sliver(ink, cls):
    """Median shape of the carved paper inside the ink: area / width^2 of each paper island that does not touch the
    frame edge (6 to 20000 px; width = 2 x its largest distance to ink). Long thin gouge lines score high, chunky
    cuts low; None with no such island. Returns it and {class: the median over the islands centred in that class,
    None under 3}."""
    paper = (~ink).astype(np.uint8)
    n, lab, st, cen = cv2.connectedComponentsWithStats(paper, connectivity=4)
    x, y, w, h, a = st[1:].T
    keep = (x > 0) & (y > 0) & (x + w < ink.shape[1]) & (y + h < ink.shape[0]) & (a >= 6) & (a <= 20000)
    if not keep.any():
        return None, dict.fromkeys(CLASSES)
    width = np.zeros(n)
    np.maximum.at(width, lab.ravel(), cv2.distanceTransform(paper, cv2.DIST_L2, 5).ravel())
    i = np.nonzero(keep)[0] + 1
    v, k = a[i - 1] / np.maximum(2 * width[i], 1) ** 2, at(cls, cen[i])
    return float(np.median(v)), {c: float(np.median(v[k == j])) if (k == j).sum() >= 3 else None
                                 for j, c in enumerate(CLASSES)}


def one(rgb):
    g = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    h = np.bincount(g.ravel(), minlength=256)
    ink_g, paper_g = int(np.argmax(h[:128])), 128 + int(np.argmax(h[128:]))
    T = (ink_g + paper_g) / 2
    ink = g < T
    edge = int((ink[:, 1:] != ink[:, :-1]).sum() + (ink[1:] != ink[:-1]).sum())
    mid = int(((g > ink_g + 16) & (g < paper_g - 16)).sum())
    w, pw = ridge_widths(ink), ridge_widths(~ink)
    boxes = captions(ink)
    cls = classes(ink, boxes)
    rough, straight, straight_c = contour_stats(ink, cls)
    sliver_all, sliver_c = sliver(ink, cls)
    grain, period = texture(g, ink.astype(np.uint8))
    k5 = np.ones((5, 5), np.uint8)
    closed = cv2.morphologyEx(ink.astype(np.uint8), cv2.MORPH_CLOSE,
                              cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))).astype(bool)
    core_i = cv2.erode(ink.astype(np.uint8), k5).astype(bool)
    core_p = cv2.erode((~ink).astype(np.uint8), k5).astype(bool)
    flat = None
    if ink.mean() >= 0.5:   # dark drawings only: share of mostly-ink blocks that are flat, untextured black
        H, W = (g.shape[0] // FLAT_B) * FLAT_B, (g.shape[1] // FLAT_B) * FLAT_B

        def blocks(a):
            return a[:H, :W].reshape(H // FLAT_B, FLAT_B, W // FLAT_B, FLAT_B)
        inkb = blocks(ink).mean((1, 3)) > 0.5
        flat = float((blocks(core_i).all((1, 3)) & (blocks(g.astype(np.float32)).std((1, 3)) < FLAT_SD)).sum()
                     / max(inkb.sum(), 1))
    n, lab, st, _ = cv2.connectedComponentsWithStats(ink.astype(np.uint8), connectivity=8)
    field = core_i & (lab == 1 + int(np.argmax(st[1:, 4]))) if n > 1 else core_i

    # a statistic with nothing to measure in this drawing is None (n/a), never 0
    def pct(v, q):
        return float(np.percentile(v, q)) if len(v) else None

    def sd(m):
        return float(g[m].std()) if m.any() else None

    def med(m):
        return [int(c) for c in np.median(rgb[m], 0)] if m.any() else None
    return dict(ink=float(ink.mean()), soft=mid / edge if edge else None, w10=pct(w, 10), w50=pct(w, 50),
                w90=pct(w, 90), pw50=pct(pw, 50), rough=rough, straight=straight, specks=islands(ink, 8),
                gaps=islands(~ink, 4), holes=float((closed & ~ink).sum() / closed.sum()) if closed.any() else None,
                ink_sd=sd(core_i), paper_sd=sd(core_p), field_sd=sd(field), flat=flat, grain=grain, period=period,
                sliver=sliver_all, **{f'straight_{c}': v for c, v in straight_c.items()},
                **{f'sliver_{c}': v for c, v in sliver_c.items()},
                ink_rgb=med(core_i), paper_rgb=med(core_p), edge=edge, T=T, mask=ink, anchor=cls < 2,
                has_border=bool(ink[cls == 0].mean() >= PRESENT), has_caption=bool(boxes))


def boil(a, b):
    """Edge displacement over the anchor (border and caption) of consecutive drawings a, b; None when the anchor
    changes or has too few edges to say."""
    m = a['anchor'] | b['anchor']

    def edges(ink):
        return int((ink[:, 1:] != ink[:, :-1])[m[:, 1:]].sum() + (ink[1:] != ink[:-1])[m[1:]].sum())
    e = max(edges(a['mask']), edges(b['mask']))
    if e < 500 or abs(a['mask'][m].mean() - b['mask'][m].mean()) >= 0.01:
        return None
    return float((a['mask'] ^ b['mask'])[m].sum() / e)


def measure(film, fps=24, region=None, window=None):
    """Per-drawing rows: every statistic above plus t (start) and hold (s). film is a path or an iterable of
    (rgb, t) frames."""
    rows, prev = [], None
    for rgb, t in drawings(film, fps, region, window):
        if rows:
            rows[-1]['hold'] = t - rows[-1]['t']
        if rgb is None:
            break
        r = one(rgb)
        r['t'] = t
        r['boil'] = boil(prev, r) if prev else None
        if prev:
            prev.pop('mask'), prev.pop('anchor')
        prev = r
        rows.append(r)
    if prev:
        prev.pop('mask'), prev.pop('anchor')
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


def frames24(rows):
    return np.array([max(1, round(r['hold'] * 24)) for r in rows])


def offstep(rows):
    """Share of consecutive drawing pairs whose holds do not add up to twice the most common hold."""
    f = frames24(rows)
    return round(float((f[:-1] + f[1:] != 2 * np.bincount(f).argmax()).mean()), 4) if len(f) > 1 else None


def summary(rows, cuts=None, seg=SEG):
    def pcts(v):
        v = [x for x in v if x is not None]
        return dict(zip(('p10', 'p50', 'p90'), (round(float(np.percentile(v, q)), 4) for q in (10, 50, 90)))) if v \
            else None
    dur = rows[-1]['t'] + rows[-1]['hold'] - rows[0]['t']
    f24 = frames24(rows)
    e = edges(rows, cuts, seg)
    return dict(drawings=len(rows), duration=round(dur, 3), per_second=round(len(rows) / dur, 3),
                holds={f'on{n}s': round(float((f24 == n).mean()), 3) for n in (1, 2, 3)} |
                {'on4s+': round(float((f24 >= 4).mean()), 3)}, offstep=offstep(rows),
                held=round(float(np.mean([r['boil'] is not None for r in rows[1:]])), 3) if len(rows) > 1 else 0,
                stats={s: pcts([r[s] for r in rows]) for s in STATS},
                **{k: ([int(c) for c in np.median(v, 0)] if (v := [r[k] for r in rows if r[k]]) else None)
                   for k in ('ink_rgb', 'paper_rgb')},
                T=float(np.median([r['T'] for r in rows])),
                present={c: round(float(np.mean([r[f'has_{c}'] for r in rows])), 3) for c in CLASSES},
                segments=[dict(t0=round(a, 3), t1=round(b, 3), n=len(sr), per_second=round(len(sr) / (b - a), 3),
                               **{s: median(sr, s) for s in STATS})
                          for (a, b), sr in zip(zip(e, e[1:]), segment(rows, e)) if sr])


def film_value(m, s):
    return m[s] if s in m else m['stats'][s]['p50'] if m['stats'].get(s) else None


def distance(v, ref, lo, hi):
    """|v - ref| over |band edge - ref| on v's side of ref: 0 at the source value, 1 at either band edge."""
    if v is None:
        return None
    side = hi - ref if v >= ref else ref - lo
    return abs(v - ref) / side if side > 0 else 0.0 if v == ref else float('inf')


def check(m, pack):
    """Rows (name, value, band, distance): each `check` statistic's film value against its band and the source value
    `ref`, then the largest ink or paper RGB channel difference from the palette (distance = difference / tolerance).
    A row passes at distance <= 1; distance None (n/a) is a statistic the film leaves undefined. A content-class row
    the film leaves undefined although it has that class (boil: border or caption) fails at distance inf: the class
    is there but shows none of what the source's does."""
    out = []
    for s in pack['check']:
        lo, hi = pack['bands'][s]
        v = film_value(m, s)
        d = distance(v, pack['ref'][s], lo, hi)
        cs = CLASSES if s == 'boil' else [c for c in CLASSES if s.endswith('_' + c)]
        if v is None and any(m.get('present', {}).get(c) for c in cs):
            d = float('inf')
        out.append((s, v, (lo, hi), d))
    for s in ('ink_rgb', 'paper_rgb'):
        want, tol = pack['palette'][s[:-4]].lstrip('#'), pack['palette']['tolerance']
        v = max(abs(c - int(want[2 * i:2 * i + 2], 16)) for i, c in enumerate(m[s])) if m[s] else None
        out.append((s, v, (0, tol), distance(v, 0, 0, tol)))
    return out


def load_pack(p):
    p = Path(p)
    return json.load(open(p / 'style.json' if p.is_dir() else p))


def nums(s, n=None):
    v = [float(x) for x in s.replace('-', ',').split(',')] if s else None
    if v and n and len(v) != n:
        sys.exit(f'inkstats: expected {n} numbers, got {s!r}')
    return v


def report(m, pack, name):
    """Print the check table; return (rows, film distance, margin): margin is the largest row distance minus 1, so a
    film passes at margin <= 0."""
    out = check(m, pack)
    print(f'\ncheck against {name}\n\n| check | film | band | distance | pass |\n|---|---|---|---|---|')
    for s, v, (lo, hi), d in out:
        print(f"| {s} | {'n/a' if v is None else f'{v:.4g}'} | {lo:.4g}-{hi:.4g} | "
              f"{'n/a' if d is None else f'{d:.2f}'} | {'n/a' if d is None else 'yes' if d <= 1 else 'NO'} |")
    for s in pack.get('measured_only', []):   # subject-sensitive: reported beside the source, never judged
        v = film_value(m, s)
        print(f"| {s} | {'n/a' if v is None else f'{v:.4g}'} | source {pack['ref'][s]:.4g} | - | measured only |")
    ds = [r[3] for r in out if r[3] is not None]
    stat_ds = [r[3] for r in out[:len(pack['check'])] if r[3] is not None]
    dist = float(np.mean(stat_ds)) if stat_ds else None
    margin = max(ds) - 1 if ds else None
    print(f"{sum(d <= 1 for d in ds)}/{len(ds)} pass, {len(out) - len(ds)} n/a; distance to source "
          f"{'n/a' if dist is None else f'{dist:.3f}'} over {len(stat_ds)}/{len(pack['check'])} statistics; "
          f"margin {'n/a' if margin is None else f'{margin:+.2f}'}")
    return out, dist, margin


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
          f"{m['per_second']}/s, holds {m['holds']}, offstep {m['offstep']}, held pairs {m['held']}")
    print('| stat | p10 | p50 | p90 | ' + ' | '.join(f"{g['t0']:g}-{g['t1']:g} s" for g in m['segments']) + ' |')
    print('|---|---|---|---|' + '---|' * len(m['segments']))
    for s, v in m['stats'].items():
        print(f'| {s} | ' + (' | '.join(f'{v[q]:.4g}' for q in ('p10', 'p50', 'p90')) if v else '- | - | -') + ' | '
              + ' | '.join('-' if g[s] is None else f'{g[s]:.4g}' for g in m['segments']) + ' |')
    if not pack:
        return 0
    _, _, margin = report(m, pack, a.pack)
    return 1 if margin is None or margin > 0 else 0


if __name__ == '__main__':
    sys.exit(main())
