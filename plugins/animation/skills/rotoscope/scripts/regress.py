#!/usr/bin/env python3
"""Regression: shfred0 video + empty work dir -> extract with the shipped overrides, render, measure every drawing.

usage: regress.py <shfred0 video> <empty work dir>
       regress.py --synthetic <empty work dir>
shfred0  exit 0 only when every drawing meets the measure.py target (239/239 on shfred0) and the replica, encoded as
         a scene is (controls.replica), passes the woodcut-ink pack (inkstats.py --pack): the same-style control.
--synthetic  needs no unshipped input: renders fixtures/synthetic.js at 24 fps to mp4 through render.py, decodes it
         with extract.py --video and measures the replica. Exit 0 only when the render, encode and decode contracts
         hold (render.json, the mp4, 24 drawings at their first frames) and each regression case below does. The
         replica's fidelity table is printed and kept, not asserted: at the default brush the synthetic scene does
         not reach the measure.py target (design O5, fallback b).
         Regression cases: a scene without DURATION makes render.py exit 1 (D18).
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

import extract
import measure

HERE = Path(__file__).resolve().parent
PLUGIN = HERE.parents[2]
FIXTURE = HERE.parent / 'fixtures/shfred0.overrides.json'
SYNTHETIC = HERE.parent / 'fixtures/synthetic.js'
SYN_HOLDS = [2, 3] * 12   # synthetic.js HOLDS: 24 drawings held 2 and 3 frames at 24 fps
PACK = PLUGIN / 'styles/woodcut-ink'
EXPECTED = 239   # distinct drawings in shfred0; a decode change that drops one must fail, not pass 238/238

sys.path.insert(0, str(PLUGIN / 'skills/learn-style/scripts'))
import controls  # noqa: E402
import inkstats  # noqa: E402
import workdir  # noqa: E402


def empty(work):
    work = Path(work)
    if work.exists() and any(work.iterdir()):
        sys.exit(f'{work} is not empty')
    work.mkdir(parents=True, exist_ok=True)
    return work


def render_cli(scene, out, *args):
    return subprocess.run([sys.executable, str(PLUGIN / 'scripts/render.py'), str(scene), str(out), '--fps', '24',
                           *args]).returncode


def synthetic(work):
    work, bad = empty(work), []

    def case(name, ok):
        print(f"synthetic: {name}: {'ok' if ok else 'FAILED'}", flush=True)
        bad.extend([] if ok else [name])

    frames = work / 'frames'
    case('render.py --encode mp4 exits 0', render_cli(SYNTHETIC, frames, '--encode', 'mp4') == 0)
    meta = json.load(open(frames / 'render.json')) if (frames / 'render.json').is_file() else {}
    n = sum(SYN_HOLDS)
    case(f'render.json: fps 24, {n} frames, 480x270, {n / 24} s',
         (meta.get('fps'), meta.get('frames'), meta.get('size'), meta.get('duration')) == (24, n, [480, 270], n / 24))
    case(f'{n} fNNNN.png frames', len(workdir.frames(frames)) == n)
    mp4 = work / 'frames.mp4'
    case('frames.mp4 written', mp4.is_file())
    if not mp4.is_file():
        return 1
    extract.main([str(work / 'work'), '--video', str(mp4)])
    ds = json.load(open(workdir.index(work / 'work')))['drawings']
    starts = [sum(SYN_HOLDS[:k]) / 24 for k in range(len(SYN_HOLDS))]
    case(f'decode: {len(SYN_HOLDS)} drawings at their first frames',
         len(ds) == len(starts) and all(abs(t - s) < 1e-3 for (_, t, _), s in zip(ds, starts)))
    measure.main([str(work / 'work'), '--tag', 'synthetic'])   # fidelity recorded, not asserted (O5 fallback b)
    scene = work / 'no-duration/scene.js'
    scene.parent.mkdir()
    src = SYNTHETIC.read_text(encoding='utf-8')
    cut = '\n'.join(ln for ln in src.splitlines() if not ln.startswith('window.DURATION'))
    scene.write_text(cut, encoding='utf-8')   # ./ink.js still resolves: render.py serves scripts/
    case('D18: a scene without DURATION makes render.py exit 1',
         cut != src and render_cli(scene, work / 'no-duration/frames') == 1)
    print(f"synthetic: {len(bad)} case(s) failed" + (f": {', '.join(bad)}" if bad else ''))
    return 1 if bad else 0


def main(video, work):
    work = empty(work)
    shutil.copy(FIXTURE, workdir.overrides(work))
    extract.main([str(work), '--video', str(video)])
    n = len(json.load(open(workdir.index(work)))['drawings'])
    if n != EXPECTED:
        sys.exit(f'decoded {n} drawings, expected {EXPECTED}')
    rc = measure.main([str(work), '--tag', 'regress'])
    rep = controls.replica(work, 'regress', workdir.out(work, 'regress'))
    pack_rc = inkstats.main([str(rep), '--pack', str(PACK)])
    print(f"pack control: the replica {'passes' if pack_rc == 0 else 'FAILS'} {PACK.name}")
    return rc or pack_rc


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(synthetic(sys.argv[2]) if sys.argv[1] == '--synthetic' else main(*sys.argv[1:]))
