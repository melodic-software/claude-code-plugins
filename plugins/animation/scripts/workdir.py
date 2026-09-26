"""The rotoscope work-dir layout and the dNNN / fNNNN names: the one owner of every path a script reads or writes.

<work>/src/dNNN.png       a source drawing            <work>/d/index.json   {w, h, duration, drawings: [[k, pts, t1]]}
<work>/d/dNNN.json        a drawing's trace           <work>/overrides.json the override file
<work>/out/<tag>/         a measured run (rep/, heat/, ab/, crops/ hold dNNN.png)
<work>/learnings.md       the run log                 <frames>/fNNNN.png    a render.py frame folder
roto.js reads the same d/ layout through its ?dir= parameter; capture.mjs names the frames and drawings it writes.
"""
from pathlib import Path


def name(k):
    """A drawing's file stem: d000."""
    return f'd{k:03d}'


def drawing(folder, k):
    """Drawing k's image in any folder of drawings (src, rep, heat, ab, crops)."""
    return Path(folder) / f'{name(k)}.png'


def src(work):
    return Path(work) / 'src'


def traces_dir(work):
    return Path(work) / 'd'


def index(work):
    return traces_dir(work) / 'index.json'


def trace(work, k):
    return traces_dir(work) / f'{name(k)}.json'


def traces(work):
    """Every trace file, in name order (index.json excluded)."""
    return sorted(traces_dir(work).glob('d[0-9]*.json'))


def source(work, k):
    return drawing(src(work), k)


def out(work, tag):
    return Path(work) / 'out' / tag


def rep(work, tag):
    return out(work, tag) / 'rep'


def overrides(work):
    return Path(work) / 'overrides.json'


def learnings(work):
    return Path(work) / 'learnings.md'


def frames(folder):
    """A frame folder's fNNNN.png files in name order."""
    return sorted(Path(folder).glob('f*.png'))
