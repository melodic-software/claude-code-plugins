#!/usr/bin/env python3
"""Read-only prerequisite report for the speech plugin: one PASS or FAIL row per prerequisite, then a summary.
Standard library only, and it installs nothing.

usage: check.py [--data-dir DIR]

Rows: each cli and runtime entry in ../prerequisites.json (found on PATH, at its version floor), each env entry (set
or not; an unset optional one is an INFO row, and the value is never printed), the hash-locked
Python packages the SessionStart hook installs, and the Kokoro model files /speech:setup apply downloads. A FAIL row
carries the entry's degrade line and its install hints, or the repair command. Exit 1 when any row fails.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import assets
import pydeps

PREREQUISITES = Path(__file__).resolve().parent.parent / 'prerequisites.json'


def version_tuple(text):
    return tuple(int(p) for p in text.split('.'))


def declared_rows(path=PREREQUISITES, which=shutil.which):
    """(status, id, detail) for each cli and runtime entry: the first name in detect.any on PATH, at its floor."""
    rows = []
    for entry in json.loads(Path(path).read_text(encoding='utf-8'))['requires']:
        detect = entry['detect']
        if entry['kind'] == 'env':   # the value is never read into a row
            name = detect['name']
            rows.append(('PASS', entry['id'], f'{name} is set') if os.environ.get(name, '').strip()
                        else ('INFO', entry['id'], f'{name} is not set (optional). {entry["degrade"]}'))
            continue
        if entry['kind'] not in ('cli', 'runtime'):
            continue
        found = next((p for p in map(which, detect['any']) if p), None)
        status, detail = 'PASS', found
        if not found:
            status, detail = 'FAIL', f'none of {", ".join(detect["any"])} is on PATH'
        elif 'version' in detect:
            v = detect['version']
            r = subprocess.run([found, *v['args']], capture_output=True, text=True)
            m = re.search(v['pattern'], r.stdout + r.stderr)
            if not m:
                detail = f'{found} (version unreadable, not verified)'
            elif version_tuple(m.group(1)) < version_tuple(v['min']):
                status, detail = 'FAIL', f'{found} is {m.group(1)}, below {v["min"]}'
            else:
                detail = f'{found} {m.group(1)}'
        if status == 'FAIL':
            hints = '; '.join(f'{k}: {val}' for k, val in entry['install'].items())
            detail += f'. {entry["degrade"]} Install: {hints}'
        rows.append((status, entry['id'], detail))
    return rows


def package_row(data):
    target = pydeps.env_dir(data, pydeps.REQUIREMENTS)
    if target.is_dir() and pydeps.loads(target, pydeps.PROBE):
        return 'PASS', 'python-packages', f'{", ".join(pydeps.PROBE)} load from {target}'
    return ('FAIL', 'python-packages',
            f'not installed for {sys.implementation.cache_tag}; the SessionStart hook installs them, or run: '
            f'{pydeps.repair_line(data)}')


def model_row(data):
    gaps = assets.missing(data)
    if not gaps:
        return 'PASS', 'kokoro-model', str(assets.assets_dir(data))
    size = sum(assets.manifest()['files'][g]['size'] for g in gaps) / 1e6
    return ('FAIL', 'kokoro-model',
            f'{len(gaps)} of the pinned files are missing ({size:.0f} MB); run /speech:setup apply install-model to download them')


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--data-dir')
    a = ap.parse_args(argv)
    rows = declared_rows()
    try:
        data = pydeps.data_dir(a.data_dir)
        rows += [package_row(data), model_row(data)]
    except pydeps.Broken as e:
        rows.append(('FAIL', 'data-dir', str(e)))
    for status, name, detail in rows:
        print(f'{status}  {name}: {detail}')
    failed = sum(s == 'FAIL' for s, _, _ in rows)
    info = sum(s == 'INFO' for s, _, _ in rows)
    print(f'{len(rows) - failed - info} passed, {failed} failed' + (f', {info} optional not set' if info else ''))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
