#!/usr/bin/env python3
"""Render a scene module to a frame folder (and optionally encode it): the one entry point for every render.

usage: render.py <scene.js> <out dir> (--fps N | --drawings K0-K1|k,k,...) [--query Q] [--root DIR ...]
                 [--backend native] [--encode none|mp4|webm|gif] [--workers N]
Serves, over one loopback server on an OS-chosen port, the scene's directory, then this scripts/ directory
(render.html, ink.js), then each --root in order; a path resolves to the first root holding it. Opens
render.html?scene=<scene file>&<query> in headless Chromium through capture.mjs and writes
  --fps N        every frame of the film, fNNNN.png (frame i shows t = i / N)
  --drawings     one dNNN.png per drawing through window.renderDrawing(k)
plus render.json {scene, adapter, adapter_version, browser_build, fps, size, frames, duration}. --encode writes the
frame folder to <out dir>.<fmt> beside it.
exit 0  every requested frame written, render.json written
exit 1  the scene failed: a page error, a missing or non-positive DURATION, a missing renderDrawing
exit 2  a prerequisite is missing (the remedy is printed)
"""
import argparse
import functools
import http.server
import json
import os
import subprocess
import sys
import threading
from pathlib import Path

HERE = Path(__file__).resolve().parent
WORKERS = min(8, os.cpu_count() or 1)   # pages capture.mjs renders in parallel; every worker default routes here
FORMATS = {   # ffmpeg output arguments per delivered format
    'mp4': ['-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '16'],
    'webm': ['-c:v', 'libvpx-vp9', '-pix_fmt', 'yuv420p', '-crf', '30', '-b:v', '0'],
    'gif': ['-vf', 'split[a][b];[a]palettegen[p];[b][p]paletteuse'],
}


class Roots(http.server.SimpleHTTPRequestHandler):
    """Serve several directories as one: a path resolves to the first root that holds it."""

    def __init__(self, *a, roots, **kw):
        self.roots = roots
        super().__init__(*a, directory=roots[0], **kw)

    def translate_path(self, path):
        for r in self.roots:
            self.directory = r
            p = super().translate_path(path)
            if os.path.exists(p):
                return p
        return p

    def log_message(self, *a):
        pass


def ks(spec):
    """K0-K1 or k,k,... -> list of drawing numbers."""
    if '-' in spec:
        k0, k1 = map(int, spec.split('-'))
        return list(range(k0, k1 + 1))
    return [int(k) for k in spec.split(',')]


def render(scene, out, fps=None, drawings=None, query='', roots=(), workers=WORKERS):
    """Capture a scene into out; return the render.json dict. Exits 1 when the scene fails, 2 when a tool is missing."""
    scene, out = Path(scene).resolve(), Path(out)
    served = [str(scene.parent), str(HERE), *map(str, roots)]
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Roots, roots=served))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        url = f'http://127.0.0.1:{srv.server_address[1]}/render.html?scene={scene.name}&{query}'
        sel = ['--fps', f'{fps:g}'] if fps else [','.join(map(str, drawings))]
        r = subprocess.run(['node', str(HERE / 'capture.mjs'), url, str(out), *sel, str(workers)],
                           stdout=subprocess.PIPE, text=True)
    except FileNotFoundError:
        sys.stderr.write('render: node not found on PATH; install Node.js (https://nodejs.org)\n')
        sys.exit(2)
    finally:
        srv.shutdown()
        srv.server_close()
    if r.returncode:
        sys.stderr.write(f'render: {scene.name} failed\n')
        sys.exit(r.returncode if r.returncode == 2 else 1)
    cap = json.loads(r.stdout.strip().splitlines()[-1])
    plugin = json.load(open(HERE.parent / '.claude-plugin/plugin.json'))
    meta = dict(scene=str(scene), adapter='native', adapter_version=plugin['version'],
                browser_build=cap['browser_build'], fps=int(fps) if fps and fps == int(fps) else fps, size=cap['size'], frames=cap['frames'],
                duration=cap['duration'])
    (out / 'render.json').write_text(json.dumps(meta, indent=1) + '\n')
    return meta


def encode(frames, fmt, fps, out):
    """The one ffmpeg write path: pipe BGR images (an iterable, each held as many frames as it repeats) as rawvideo
    bgr24 at fps into out; return out."""
    frames = iter(frames)
    first = next(frames)
    h, w = first.shape[:2]
    try:
        p = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', f'{w}x{h}',
                              '-framerate', f'{fps:g}', '-i', '-', *FORMATS[fmt], str(out)], stdin=subprocess.PIPE)
    except FileNotFoundError:
        sys.stderr.write('render: ffmpeg not found on PATH; install ffmpeg (https://ffmpeg.org/download.html)\n')
        sys.exit(2)
    p.stdin.write(first.tobytes())
    for img in frames:
        p.stdin.write(img.tobytes())
    p.stdin.close()
    if p.wait():
        sys.exit(f'render: ffmpeg failed encoding {out}')
    return out


def folder(out):
    """The frame folder's fNNNN.png images in frame order, read as BGR."""
    import cv2
    for f in sorted(Path(out).glob('f*.png'), key=lambda f: int(f.stem[1:])):
        yield cv2.imread(str(f))


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('scene', type=Path)
    ap.add_argument('out', type=Path)
    sel = ap.add_mutually_exclusive_group(required=True)
    sel.add_argument('--fps', type=float)
    sel.add_argument('--drawings', type=ks)
    ap.add_argument('--query', default='')
    ap.add_argument('--root', type=Path, action='append', default=[])
    ap.add_argument('--backend', choices=['native'], default='native')
    ap.add_argument('--encode', choices=['none', *FORMATS], default='none')
    ap.add_argument('--workers', type=int, default=WORKERS)
    a = ap.parse_args(argv)
    if a.encode != 'none' and not a.fps:
        ap.error('--encode needs --fps (a film, not drawings)')
    meta = render(a.scene, a.out, a.fps, a.drawings, a.query, [r.resolve() for r in a.root], a.workers)
    if a.encode != 'none':
        out = a.out.resolve()
        dest = out.parent / f'{out.name}.{a.encode}'
        encode(folder(a.out), a.encode, a.fps, dest)
        print(dest)
    print(f"render: {meta['frames']} frames, {meta['size'][0]}x{meta['size'][1]}, {a.out}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
