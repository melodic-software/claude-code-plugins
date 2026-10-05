"""Shared pieces of the demo-video pipeline: the one config home (defaults.json plus an optional
override file), content-ink analysis of a capture, the gutter test for a camera rect, the eased-move
timing rule and the caption pill geometry. build_edl.py, produce.py and qc.py import it."""
import json
import math
import subprocess
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageFont

HERE = Path(__file__).resolve().parent
DEFAULTS = HERE / 'defaults.json'

# Quintic smoothstep: peak velocity and acceleration per unit change over unit time.
SMOOTH_PEAK_V = 1.875
SMOOTH_PEAK_A = 10 / 3 ** 0.5
# Fraction of an eased move between 10% and 90% of its change (s(u) = 0.1 at u ~ 0.2466).
SMOOTH_10_90 = 0.5068

FONT_CANDIDATES = (
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/TTF/DejaVuSans.ttf',
    '/Library/Fonts/Arial.ttf',
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    'C:/Windows/Fonts/segoeui.ttf',
    'C:/Windows/Fonts/arial.ttf',
)


def load_config(override=None):
    """defaults.json, with any keys of the override file (same shape) replacing the defaults."""
    cfg = json.loads(DEFAULTS.read_text())
    if override:
        for section, values in json.loads(Path(override).read_text()).items():
            if section not in cfg:
                raise SystemExit(f'config: unknown section {section!r} in {override}')
            unknown = set(values) - set(cfg[section])
            if unknown:
                raise SystemExit(f'config: unknown keys {sorted(unknown)} in section {section!r} of {override}')
            cfg[section].update(values)
    return cfg


def smooth(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * u * (u * (u * 6 - 15) + 10)


@lru_cache(maxsize=16)
def font(size, path=None):
    """A TrueType font at `size`: the given path, the first common system font found, else Pillow's
    bundled default (Pillow >= 10.1), so rendering never depends on one machine's font set."""
    for candidate in ([path] if path else []) + list(FONT_CANDIDATES):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default(size)


def pill_width(text, cfg, font_path=None):
    """Output px width of a caption pill: badge, gap, text, end padding."""
    c = cfg['captions']
    return int(font(c['font_size'], font_path).getlength(text) + c['pill_h'] + 36)


def anchor_box(name, w, W, H, cfg):
    c = cfg['captions']
    x = W - c['margin'] - w if name.endswith('right') else c['margin']
    return (x, H - c['margin'] - c['pill_h'], w, c['pill_h'])


def move_duration(r0, r1, nominal, W, motion):
    """Shortest duration >= nominal (and >= min_move_duration) for an eased move from rect r0 to r1
    that keeps zoom and pan rates and accelerations within the motion limits. Zoom is measured as
    d ln(scale)/dt; pan as content speed in frame widths per second."""
    z0, z1 = W / r0[2], W / r1[2]
    dz = abs(math.log(z1 / z0))
    dp = pan_travel(r0, r1, W)
    if dz < 1e-9 and dp < 1e-9:
        return 0.0
    zr, pr = motion['max_zoom_rate'], motion['max_pan_speed']
    za, pa = motion['max_zoom_accel'], motion['max_pan_accel']
    t = max(nominal, motion['min_move_duration'], SMOOTH_PEAK_V * dz / zr, SMOOTH_PEAK_V * dp / pr,
            math.sqrt(SMOOTH_PEAK_A * dz / za), math.sqrt(SMOOTH_PEAK_A * dp / pa))
    f = motion['combined_fraction']
    if SMOOTH_PEAK_V * dz / t > f * zr and SMOOTH_PEAK_V * dp / t > f * pr:
        t = max(t, SMOOTH_PEAK_V * min(dz / (f * zr), dp / (f * pr)))
    return round(t * 1.02, 3)   # 2% headroom so frame-measured peaks land inside the limits


def pan_travel(r0, r1, W):
    """Content travel of a move, in frame widths at the tighter of the two zooms."""
    c0 = (r0[0] + r0[2] / 2, r0[1] + r0[3] / 2)
    c1 = (r1[0] + r1[2] / 2, r1[1] + r1[3] / 2)
    return math.hypot(c1[0] - c0[0], c1[1] - c0[1]) * max(W / r0[2], W / r1[2]) / W


def clip_duration(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(path)],
                         capture_output=True, text=True, check=True)
    return float(out.stdout.strip())


class Ink:
    """Content mask of a capture at CSS resolution: pixels with a horizontal luminance step (glyph
    strokes, edges), closed across word gaps so a text line is one run, with an integral image for
    O(1) area counts. With content_box, only that box counts as content (an open modal over a
    dimmed page)."""

    def __init__(self, path, W, H, word_gap, content_box=None):
        g = np.asarray(Image.open(path).convert('L').resize((W, H), Image.BOX), np.float32)
        gx = np.zeros_like(g)
        gx[:, 1:] = np.abs(np.diff(g, axis=1))
        glyph = (gx > 5).astype(np.int32)
        if content_box is not None:
            glyph = np.zeros_like(glyph)
            x, y, w, h = map(int, content_box)
            glyph[max(y, 0):y + h, max(x, 0):x + w] = 1
        c = np.pad(glyph.cumsum(1), ((0, 0), (1, 0)))
        lo = np.clip(np.arange(W) - word_gap, 0, W)
        hi = np.clip(np.arange(W) + word_gap + 1, 0, W)
        self.mask = (c[:, hi] - c[:, lo]) > 0
        self.I = np.pad(self.mask.astype(np.float64).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
        self.W, self.H = W, H

    def count(self, x0, y0, x1, y1):
        x0, y0 = max(int(math.floor(x0)), 0), max(int(math.floor(y0)), 0)
        x1, y1 = min(int(math.ceil(x1)), self.W), min(int(math.ceil(y1)), self.H)
        if x1 <= x0 or y1 <= y0:
            return 0.0
        I = self.I
        return float(I[y1, x1] - I[y0, x1] - I[y1, x0] + I[y0, x0])

    def centroid(self):
        ys, xs = np.nonzero(self.mask)
        if not len(xs):
            return self.W / 2, self.H / 2
        return float(xs.mean()), float(ys.mean())


def edge_ink(ink, rect, band, W, H, tol=0.5):
    """Ink under each edge of rect that is not the page boundary: {edge: count}. A gutter-snapped
    rect has (near) zero on every such edge, so no text line or block is cut by the frame."""
    x0, y0, w, h = rect
    x1, y1 = x0 + w, y0 + h
    out = {}
    if x0 > tol:
        out['left'] = ink.count(x0 - band, y0, x0 + band, y1)
    if x1 < W - tol:
        out['right'] = ink.count(x1 - band, y0, x1 + band, y1)
    if y0 > tol:
        out['top'] = ink.count(x0, y0 - band, x1, y0 + band)
    if y1 < H - tol:
        out['bottom'] = ink.count(x0, y1 - band, x1, y1 + band)
    return out
