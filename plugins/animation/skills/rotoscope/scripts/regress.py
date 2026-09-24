#!/usr/bin/env python3
"""Regression: shfred0 video + empty work dir -> extract with the shipped overrides, render, measure every drawing.

usage: regress.py <shfred0 video> <empty work dir>
Exit 0 only when every drawing meets the measure.py target (239/239 on shfred0).
"""
import json
import shutil
import sys
from pathlib import Path

import extract
import measure

FIXTURE = Path(__file__).resolve().parents[1] / 'fixtures/shfred0.overrides.json'
EXPECTED = 239   # distinct drawings in shfred0; a decode change that drops one must fail, not pass 238/238


def main(video, work):
    work = Path(work)
    if work.exists() and any(work.iterdir()):
        sys.exit(f'{work} is not empty')
    work.mkdir(parents=True, exist_ok=True)
    shutil.copy(FIXTURE, work / 'overrides.json')
    extract.main([str(work), '--video', str(video)])
    n = len(json.load(open(work / 'd/index.json'))['drawings'])
    if n != EXPECTED:
        sys.exit(f'decoded {n} drawings, expected {EXPECTED}')
    return measure.main([str(work), '--tag', 'regress'])


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
