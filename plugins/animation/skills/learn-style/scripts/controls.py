#!/usr/bin/env python3
"""Adversarial controls for a style pack's check: films that must fail it, and same-style films that must pass.

usage: controls.py measure <out> --near FILM [--other FILM ...] [--source FILM] [--replica WORK] [--tag TAG] [--jobs N]
       controls.py check <out> <pack dir>
       controls.py selftest <pack dir> [--near FILM]
measure  writes an inkstats --json summary per film into <out>/calibration, <out>/evaluation (controls, alternating
         within each family) and <out>/positive:
           near/<filter>   the near-miss film (round 3) through every post filter below, alone and combined
           poly/<filter>   synthetic flat ink polygons with vertex boil and the source's hold mix, through filters
           other/<name>    each --other film (clips in other styles), unfiltered
           source, replica the --source clip, and the rotoscope replica (<work>/out/<tag>/rep/dNNN.png timed by
                           <work>/d/index.json) encoded as capture.mjs encodes a scene
         Pass <out>/calibration/*.json to learn.py --negative; the evaluation half never sets a band.
check    prints every film's rows failed and margin (largest row distance - 1: a control needs a margin above 0, a
         positive at or below 0); exit 1 if any control passes or any positive fails.
selftest exit 1 unless a gamed film fails the pack: synthetic polygons, and --near when given, through game.py's
         filter (gaussian blur sigma 0.9, then +12 gray on every 3rd column of the dark left half).
Filters, applied in order: blurS (gaussian, sigma S px), noiseA (gaussian gray noise of sd A on dark pixels, new every
frame), stripesA (+A gray on every 3rd column of dark pixels, left half), dryA / dryhalfA (static dry-brush streaks
+A gray on dark pixels, whole frame / left half), warpA (a static smooth displacement of A px sd: contour jitter).
"""
import argparse
import json
import subprocess
import sys
from multiprocessing import Pool
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'scripts'))
import inkstats  # noqa: E402

GAME = 'blur0.9+stripes12'
NEAR = ['none', 'blur0.9', 'stripes12', GAME, 'blur0.6', 'blur1.3', 'blur0.9+noise4', 'blur0.9+noise8',
        'blur0.9+noise16', 'noise8+blur0.9', 'blur0.9+stripes6', 'blur0.9+stripes24', 'blur0.9+dry8', 'blur0.9+dry16',
        'blur0.9+dry32', 'blur0.9+dryhalf16', 'warp1.5+blur0.9', 'warp3+blur0.9', 'blur0.9+noise8+stripes12+dry16',
        'warp0.7+blur0.9']
POLY = ['none', 'blur0.9', 'blur0.9+noise8', 'noise8+blur0.9', GAME, 'blur0.9+dry16', 'warp3+blur0.9+noise8']
INK, PAPER = (0x13, 0x11, 0x0f), (0xef, 0xe9, 0xe0)


def poly(w=1762, h=982, seconds=30.0, seed=7):
    """Frames at 24 fps of flat ink polygons: a new set and a dark field every 30 drawings, every vertex moved about
    2.5 px each drawing, holds on 1s/2s/3s/4s in the woodcut source's shares."""
    rng = np.random.default_rng(seed)
    fi, shapes = 0, []
    for d in range(10 ** 6):
        if d % 30 == 0:
            shapes = [np.c_[rng.uniform(0, w), rng.uniform(0, h)]
                      + rng.normal(0, rng.uniform(40, 250), (rng.integers(4, 9), 2)) for _ in range(rng.integers(4, 9))]
            shapes.append(np.array([[0, h * 0.6], [w, h * 0.55], [w, h], [0, h]]))
        img = np.empty((h, w, 3), np.uint8)
        img[:] = PAPER
        for s in shapes:
            cv2.fillPoly(img, [np.round(s + rng.normal(0, 2.5, s.shape)).astype(np.int32)], INK, cv2.LINE_AA)
        for _ in range(rng.choice([1, 2, 3, 4], p=[0.01, 0.03, 0.92, 0.04])):
            if fi / 24 >= seconds:
                return
            yield img, fi / 24
            fi += 1


def post(spec, frames):
    """Frames through the '+'-joined filter spec, in order."""
    steps = [(p.rstrip('0123456789.'), float(p.lstrip('abcdefghijklmnopqrstuvwxyz'))) for p in spec.split('+')
             if p != 'none']
    rng, cache = np.random.default_rng(3), {}

    def static(kind, shape, v):
        if (kind, shape, v) not in cache:
            h, w = shape
            if kind == 'warp':
                f = [cv2.GaussianBlur(rng.normal(0, 1, (h, w)).astype(np.float32), (0, 0), 6) for _ in 'xy']
                gx, gy = np.meshgrid(np.arange(w, dtype=np.float32), np.arange(h, dtype=np.float32))
                cache[kind, shape, v] = (gx + f[0] * v / f[0].std(), gy + f[1] * v / f[1].std())
            elif kind == 'stripes':
                m = np.zeros((h, w), bool)
                m[:, :w // 2:3] = True
                cache[kind, shape, v] = m
            else:   # dry-brush streaks: short, slightly slanted 2 px lines over the frame or its left half
                m = np.zeros((h, w), np.float32)
                for _ in range(int(9000 * w * h / 1762 / 982)):
                    x, y, L, a = rng.uniform(0, w), rng.uniform(0, h), rng.uniform(30, 110), rng.normal(0, 0.15)
                    cv2.line(m, (int(x), int(y)), (int(x + L * np.cos(a)), int(y + L * np.sin(a))), 1.0, 2)
                if kind == 'dryhalf':
                    m[:, w // 2:] = 0
                cache[kind, shape, v] = m.astype(bool)
        return cache[kind, shape, v]
    for i, (rgb, t) in enumerate(frames):
        x = rgb.astype(np.float32)
        for kind, v in steps:
            dark = x.mean(2) < 60
            if kind == 'blur':
                x = cv2.GaussianBlur(x, (0, 0), v)
            elif kind == 'noise':
                x += (np.random.default_rng(i).normal(0, v, dark.shape) * dark)[..., None]
            elif kind == 'warp':
                x = cv2.remap(x, *static(kind, dark.shape, v), cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
            else:
                x[dark & static(kind, dark.shape, v)] += v
        yield np.clip(x, 0, 255).astype(np.uint8), t


def replica(work, tag, out):
    """Encode the rotoscope replica's drawings at 24 fps with capture.mjs's ffmpeg settings; return the mp4."""
    work, mp4 = Path(work), Path(out) / 'replica.mp4'
    ds = json.load(open(work / 'd/index.json'))['drawings']
    img = cv2.imread(str(work / f'out/{tag}/rep/d{ds[0][0]:03d}.png'))
    h, w = img.shape[:2]
    p = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', f'{w}x{h}',
                          '-framerate', '24', '-i', '-', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '16', str(mp4)],
                         stdin=subprocess.PIPE)
    fi = 0
    for (k, *_), nxt in zip(ds, [*ds[1:], [None, ds[-1][2]]]):
        img = cv2.imread(str(work / f'out/{tag}/rep/d{k:03d}.png'))
        while fi / 24 < nxt[1] - 1e-6:
            p.stdin.write(img.tobytes())
            fi += 1
    p.stdin.close()
    if p.wait():
        sys.exit(f'controls: ffmpeg failed encoding {mp4}')
    return mp4


def run(job):
    path, film, spec = job
    frames = post(spec, poly() if film == 'poly' else inkstats.frames(film, 24))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(inkstats.summary(inkstats.measure(frames, 24))) + '\n')
    return path


def measure(a):
    out, jobs = Path(a.out), []
    for fam, items in [('near', [(a.near, s) for s in NEAR]), ('poly', [('poly', s) for s in POLY]),
                       ('other', [(f, 'none') for f in a.other])]:
        for i, (film, spec) in enumerate(items):
            n = Path(film).stem if fam == 'other' else f'{fam}_{spec}'
            jobs.append((out / ('calibration', 'evaluation')[i % 2] / f'{n}.json', film, spec))
    if a.source:
        jobs.append((out / 'positive/source.json', a.source, 'none'))
    if a.replica:
        out.mkdir(parents=True, exist_ok=True)
        jobs.append((out / 'positive/replica.json', str(replica(a.replica, a.tag, out)), 'none'))
    with Pool(a.jobs) as pool:
        for p in pool.imap_unordered(run, jobs):
            print(p)
    return 0


def check(a):
    pack, bad = inkstats.load_pack(a.pack), []
    table = []
    for f in sorted(Path(a.out).glob('*/*.json')):
        m = json.load(open(f))
        ds = [(s, d) for s, _, _, d in inkstats.check(m, pack) if d is not None]
        margin = max(d for _, d in ds) - 1 if ds else None
        worst = max(ds, key=lambda r: r[1])[0] if ds else '-'
        role = f.parent.name
        ok = margin is not None and (margin <= 0 if role == 'positive' else margin > 0)
        bad += [] if ok else [f'{role}/{f.stem}']
        table.append(f"| {role} | {f.stem} | {sum(d > 1 for _, d in ds)}/{len(ds)} | "
                     f"{'n/a' if margin is None else f'{margin:+.2f}'} | {worst} | {'yes' if ok else 'NO'} |")
    print('| half | film | rows failed | margin | worst row | as required |\n|---|---|---|---|---|---|')
    print('\n'.join(table))
    print(f"{len(table) - len(bad)}/{len(table)} as required" + (f"; wrong: {', '.join(bad)}" if bad else ''))
    return 1 if bad or not table else 0


def selftest(a):
    pack, bad = inkstats.load_pack(a.pack), []
    for name, frames in [('poly', poly(seconds=10)), *([('near', inkstats.frames(a.near, 24))] if a.near else [])]:
        rows = inkstats.check(inkstats.summary(inkstats.measure(post(GAME, frames), 24)), pack)
        failed = [s for s, _, _, d in rows if d is not None and d > 1]
        print(f"{name} + {GAME}: fails {', '.join(failed) or 'nothing'}")
        bad += [] if failed else [name]
    if bad:
        print(f"selftest: the gamed {', '.join(bad)} passes the check: a post filter games it again")
    return 1 if bad else 0


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    m = sub.add_parser('measure')
    m.add_argument('out')
    m.add_argument('--near', required=True)
    m.add_argument('--other', nargs='*', default=[])
    m.add_argument('--source')
    m.add_argument('--replica')
    m.add_argument('--tag', default='regress')
    m.add_argument('--jobs', type=int, default=8)
    c = sub.add_parser('check')
    c.add_argument('out')
    c.add_argument('pack')
    s = sub.add_parser('selftest')
    s.add_argument('pack')
    s.add_argument('--near')
    a = ap.parse_args(argv)
    return dict(measure=measure, check=check, selftest=selftest)[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
