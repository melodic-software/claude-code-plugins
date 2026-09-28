#!/usr/bin/env python3
"""Production directory for /animation:produce.

usage:
  produce.py init <dir> --title TEXT [--style NAME ...]
  produce.py check <dir>
  produce.py cuts <dir>
  produce.py gate <dir>

init writes brief.md, boards/storyboard.md and shots.json. It does not write
boards/APPROVED. gate exits 2 until that file exists and is non-empty, which is
the user's approval of the boards. Nothing past the storyboard renders before
that. cuts prints the interior shot starts from shots.json, the list inkstats
reads with --shots.
"""

import argparse
import json
import sys
from pathlib import Path

VERSION = 1


def production(path):
    return Path(path)


def shots_path(root):
    return production(root) / 'shots.json'


def approved_path(root):
    return production(root) / 'boards' / 'APPROVED'


def load_shots(root):
    path = shots_path(root)
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f'produce: cannot read {path}: {exc}') from exc
    errors = validate_shots(data)
    if errors:
        raise SystemExit('produce: shots.json: ' + '; '.join(errors))
    return data


def validate_shots(data):
    errors = []
    if not isinstance(data, dict):
        return ['not an object']
    if data.get('version') != VERSION:
        errors.append(f'version must be {VERSION}')
    if not isinstance(data.get('fps'), (int, float)) or data.get('fps', 0) <= 0:
        errors.append('fps must be a positive number')
    styles = data.get('styles')
    if not isinstance(styles, list) or not styles or not all(isinstance(s, str) and s for s in styles):
        errors.append('styles must be a non-empty list of names')
    shots = data.get('shots')
    if not isinstance(shots, list) or not shots:
        errors.append('shots must be a non-empty list')
        return errors
    prev = -1.0
    seen = set()
    for i, shot in enumerate(shots):
        if not isinstance(shot, dict):
            errors.append(f'shot {i} is not an object')
            continue
        sid = shot.get('id')
        if not isinstance(sid, str) or not sid:
            errors.append(f'shot {i} needs an id')
        elif sid in seen:
            errors.append(f'duplicate shot id {sid}')
        else:
            seen.add(sid)
        t0 = shot.get('t0')
        if not isinstance(t0, (int, float)) or isinstance(t0, bool) or t0 < 0 or t0 <= prev:
            errors.append(f'shot {i} t0 must increase from 0')
        else:
            prev = t0
        scene = shot.get('scene')
        if not isinstance(scene, str) or not scene.endswith('.js'):
            errors.append(f'shot {i} scene must be a .js path')
        title = shot.get('title')
        if not isinstance(title, str) or not title:
            errors.append(f'shot {i} needs a title')
    if shots and isinstance(shots[0], dict) and shots[0].get('t0') != 0:
        errors.append('the first shot starts at 0')
    return errors


def shot_cuts(data):
    """Interior boundaries, in seconds. shots.json owns them."""
    return [float(shot['t0']) for shot in data['shots'][1:]]


def init(root, title, styles):
    root = production(root)
    if (root / 'shots.json').exists() or (root / 'brief.md').exists():
        raise SystemExit(f'produce: {root} already has a production')
    (root / 'boards').mkdir(parents=True)
    (root / 'scenes').mkdir()
    (root / 'brief.md').write_text(
        f'# {title}\n\nStyles: {", ".join(styles)}.\n\n'
        'Boards are approved by writing boards/APPROVED. '
        'Nothing past the storyboard renders before that.\n',
        encoding='utf-8',
    )
    (root / 'boards' / 'storyboard.md').write_text(
        f'# Storyboard\n\n{title}\n\nOne panel per shot. Approve by writing boards/APPROVED.\n',
        encoding='utf-8',
    )
    shots = {
        'version': VERSION,
        'fps': 24,
        'styles': list(styles),
        'shots': [{
            'id': 's1',
            't0': 0,
            'scene': 'scenes/s1.js',
            'title': 'Open',
        }],
    }
    shots_path(root).write_text(json.dumps(shots, indent=1) + '\n', encoding='utf-8')
    print(f'produce: initialized {root}')
    return 0


def stage(root):
    root = production(root)
    missing = [name for name in ('brief.md', 'boards/storyboard.md', 'shots.json')
               if not (root / name).is_file()]
    if missing:
        return 'incomplete', missing
    load_shots(root)
    text = approved_path(root).read_text(encoding='utf-8').strip() if approved_path(root).is_file() else ''
    if not text:
        return 'boards', []
    return 'approved', []


def check(root):
    name, missing = stage(root)
    if missing:
        raise SystemExit('produce: missing ' + ', '.join(missing))
    print(f'produce: {name}')
    return 0


def cuts(root):
    data = load_shots(root)
    print(','.join(str(c) for c in shot_cuts(data)))
    return 0


def gate(root):
    name, missing = stage(root)
    if missing:
        raise SystemExit('produce: missing ' + ', '.join(missing))
    if name != 'approved':
        print(
            'produce: boards are not approved (write boards/APPROVED); '
            'nothing past the storyboard renders',
            file=sys.stderr,
        )
        raise SystemExit(2)
    print('produce: approved')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    ini = sub.add_parser('init')
    ini.add_argument('dir')
    ini.add_argument('--title', required=True)
    ini.add_argument('--style', action='append', default=[])
    for name in ('check', 'cuts', 'gate'):
        cmd = sub.add_parser(name)
        cmd.add_argument('dir')
    args = ap.parse_args(argv)
    if args.cmd == 'init':
        styles = args.style or ['woodcut-ink']
        return init(args.dir, args.title, styles)
    if args.cmd == 'check':
        return check(args.dir)
    if args.cmd == 'cuts':
        return cuts(args.dir)
    if args.cmd == 'gate':
        return gate(args.dir)
    raise SystemExit(f'produce: unknown command {args.cmd}')


if __name__ == '__main__':
    sys.exit(main())
