#!/usr/bin/env python3
"""Source-in: the one decode path for a video, a frame folder or a rotoscope work dir, the repeat-drawing rule, and
the gray modes every measure reads.

  probe(video)         -> (w, h, [pts_time, ...]) of the first video stream
  frames(film, fps)    yield (rgb, t) for every stored frame (a video, a frame folder played at fps, a work dir's
                       src/dNNN.png timed by d/index.json, or any iterable of (rgb, t) passed through)
  is_repeat(prev, rgb) a frame repeats the previous drawing when fewer than dup_px pixels changed by more than 64
                       gray levels (prev is the previous kept frame as int16, or None)
  modes(gray)          (ink mode, paper mode, T): the gray histogram modes below and above 128 and their midpoint;
                       MID gray levels either side of a mode count as that tone, the band between is mid-gray
"""
import json
import subprocess
from pathlib import Path

import prereq

prereq.require(['numpy', 'opencv'])
import cv2  # noqa: E402
import numpy as np  # noqa: E402

DUP_PX = 50
MID = 16
TOOLS = ['ffmpeg', 'ffprobe', 'ffmpeg-version']   # what decoding a video needs


def probe(video):
    prereq.require(TOOLS)
    out = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height',
                          '-of', 'csv=p=0', str(video)], capture_output=True, text=True, check=True).stdout
    w, h = map(int, out.strip().split(',')[:2])
    pts = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'frame=pts_time',
                          '-of', 'csv=p=0', str(video)], capture_output=True, text=True, check=True).stdout
    return w, h, [float(t) for t in pts.replace(',', ' ').split()]


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
        w, h, pts = probe(film)
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


def is_repeat(prev, rgb, dup_px=DUP_PX):
    return prev is not None and (np.abs(rgb.astype(np.int16) - prev) > 64).sum() < dup_px


def modes(gray):
    h = np.bincount(gray.ravel(), minlength=256)
    ink_g, paper_g = int(np.argmax(h[:128])), 128 + int(np.argmax(h[128:]))
    return ink_g, paper_g, (ink_g + paper_g) / 2
