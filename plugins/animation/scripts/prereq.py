#!/usr/bin/env python3
"""Prerequisite probe for the animation plugin: the one place a missing tool is detected and its remedy named.
Standard library only, so it can report a missing numpy.

usage: prereq.py [--playwright-core DIR]   print the PASS/FAIL/INFO table; exit 1 if any row fails
  check(playwright_core=None) -> [(name, status, detail, remedy)]   status PASS, FAIL or INFO
  require(names, playwright_core=None)   exit 2 with the remedy line of the first failed row among names

The -fps_mode minimum: FFmpeg 5.1.
  Claim: ffmpeg's -fps_mode option (decode.py passes -fps_mode passthrough) first ships in FFmpeg 5.1.
  Basis: doc/ffmpeg.texi documents -fps_mode at tag n5.1 and not at tag n5.0 (github.com/FFmpeg/FFmpeg).
  As of: 2026-09-26.
  Recheck trigger: decode.py passes a new ffmpeg option, or a row reports a build that fails -fps_mode.
"""
import argparse
import functools
import importlib.metadata
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FFMPEG_MIN = (5, 1)
FFMPEG_URL = 'https://ffmpeg.org/download.html'
PACKAGES = {   # the pinned distribution first; any of the others also provides the module (cv2)
    'numpy': ('numpy',),
    'opencv': ('opencv-python-headless', 'opencv-python', 'opencv-contrib-python-headless', 'opencv-contrib-python'),
}


def playwright_dir(v):
    """A --playwright-core value, or None when empty or an unsubstituted ${user_config...} placeholder."""
    return None if not v or v.startswith('${') else v


def pins():
    """{distribution: version} from the plugin's requirements.txt."""
    lines = (HERE.parent / 'requirements.txt').read_text(encoding='utf-8').splitlines()
    return dict(ln.split('==') for ln in (ln.split('#')[0].strip() for ln in lines) if '==' in ln)


@functools.cache
def _run(*cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True)
    except OSError:
        return None
    return r


def _tool(name, remedy):
    path = shutil.which(name)
    return (name, 'PASS', path, '') if path else (name, 'FAIL', 'not on PATH', remedy)


def _row(name, playwright_core):
    if name in ('ffmpeg', 'ffprobe', 'node'):
        remedy = f'install ffmpeg ({FFMPEG_URL}); it ships ffprobe' if name != 'node' else \
            'install Node.js (https://nodejs.org)'
        return _tool(name, remedy)
    if name == 'libx264':
        r = shutil.which('ffmpeg') and _run('ffmpeg', '-hide_banner', '-encoders')
        if not r:
            return name, 'FAIL', 'ffmpeg missing', f'install ffmpeg ({FFMPEG_URL})'
        ok = re.search(r'\blibx264\b', r.stdout)
        return (name, 'PASS', 'ffmpeg -encoders lists libx264', '') if ok else \
            (name, 'FAIL', 'this ffmpeg has no libx264 encoder', f'install an ffmpeg build with libx264 ({FFMPEG_URL})')
    if name == 'ffmpeg-version':
        r = shutil.which('ffmpeg') and _run('ffmpeg', '-version')
        if not r:
            return name, 'FAIL', 'ffmpeg missing', f'install ffmpeg ({FFMPEG_URL})'
        first = r.stdout.splitlines()[0] if r.stdout else ''
        m = re.match(r'ffmpeg version n?(\d+)\.(\d+)', first)
        if not m:
            return name, 'INFO', f'{first!r}: version not parsed; -fps_mode needs {FFMPEG_MIN[0]}.{FFMPEG_MIN[1]}', ''
        v = (int(m[1]), int(m[2]))
        return (name, 'PASS', f'{v[0]}.{v[1]}', '') if v >= FFMPEG_MIN else \
            (name, 'FAIL', f'{v[0]}.{v[1]} is older than {FFMPEG_MIN[0]}.{FFMPEG_MIN[1]} (-fps_mode)',
             f'install ffmpeg {FFMPEG_MIN[0]}.{FFMPEG_MIN[1]} or later ({FFMPEG_URL})')
    if name == 'playwright_core':   # the userConfig option, when set, must name playwright-core itself
        d = Path(playwright_core)
        pkgs = [d / 'package.json', d / 'node_modules/playwright-core/package.json']
        ok = any(p.is_file() and json.loads(p.read_text(encoding='utf-8')).get('name') == 'playwright-core' for p in pkgs)
        return (name, 'PASS', str(d), '') if ok else \
            (name, 'FAIL', f'{d} holds no playwright-core', 'set the playwright_core option to the playwright-core '
             'package directory or a folder holding node_modules/playwright-core, or clear it')
    if name == 'chromium':
        if not shutil.which('node'):
            return name, 'FAIL', 'node missing', 'install Node.js (https://nodejs.org)'
        pw = ['--playwright-core', str(playwright_core)] if playwright_core else []
        r = _run('node', str(HERE / 'capture.mjs'), *pw, '--probe')
        if r and r.returncode == 0:
            return name, 'PASS', f"playwright-core with Chromium {json.loads(r.stdout)['browser_build']}", ''
        msg = (r.stderr.strip().splitlines() or ['capture.mjs --probe failed'])[-1] if r else 'node failed'
        return name, 'FAIL', 'playwright-core or Chromium not found', msg.removeprefix('capture.mjs: ')
    pinned, *alts = PACKAGES[name]
    want = pins()[pinned]
    for dist in (pinned, *alts):
        try:
            have = importlib.metadata.version(dist)
        except importlib.metadata.PackageNotFoundError:
            continue
        return (name, 'PASS', have, '') if (dist, have) == (pinned, want) else \
            (name, 'INFO', f'{dist} {have}, not the pinned {pinned} {want}: statistics may differ from the shipped '
             'pack and regression', '')
    return name, 'FAIL', f'{pinned} not installed', \
        'run the scripts through `uv run --with-requirements ${CLAUDE_PLUGIN_ROOT}/requirements.txt python ...`'


ROWS = ('ffmpeg', 'ffprobe', 'libx264', 'ffmpeg-version', 'node', 'chromium', 'numpy', 'opencv')


def check(playwright_core=None, names=ROWS):
    names = [*names, *(['playwright_core'] if playwright_core else [])]
    return [_row(n, playwright_core) for n in names]


def require(names, playwright_core=None):
    """Exit 2 with the first failed row's remedy line (later rows often follow from it, as libx264 from ffmpeg);
    return quietly when every row passes."""
    for name in names:
        name, status, detail, remedy = _row(name, playwright_core)
        if status == 'FAIL':
            sys.stderr.write(f'animation: {name}: {detail}; {remedy}\n')
            sys.exit(2)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--playwright-core', type=playwright_dir)
    a = ap.parse_args(argv)
    rows = check(a.playwright_core)
    print('| prerequisite | status | detail | remedy |\n|---|---|---|---|')
    for r in rows:
        print('| ' + ' | '.join(x or '-' for x in r) + ' |')
    return 1 if any(r[1] == 'FAIL' for r in rows) else 0


if __name__ == '__main__':
    sys.exit(main())
