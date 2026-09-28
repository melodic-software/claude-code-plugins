#!/usr/bin/env python3
"""Production directory for /animation:produce: boards, the approval gate, shots, review.

usage: produce.py init <dir>
       produce.py boards <dir>
       produce.py approve <dir> --note TEXT
       produce.py shots <dir>
       produce.py cuts <dir>
       produce.py review <dir> [--frames DIR]
  init     create the production skeleton. Leaves an existing brief.md alone.
  boards   check pre-production boards. Exit 1 when any required field is missing.
  approve  write boards/approval.json bound to a digest of those boards. Refuses
           until boards passes. The skill calls this only after the user approves.
  shots    check shots.json. Exit 2 when approval is missing or the boards changed.
  cuts     print the shot t0 values, the list inkstats.py --cuts reads from shots.json.
  review   check frames/render.json against shots.json and print the inkstats commands.
           Same gate as shots. Exit 1 when the manifest does not cover the shot list.

Every path in a board or shot is relative to the production directory and must stay inside it.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

HEX = set('0123456789abcdefABCDEF')
BOARD_FILES = (
    'brief.md',
    'boards/style-guide.md',
    'boards/palette.json',
    'boards/vibe.md',
    'boards/storyboard.json',
)
BRIEF_FIELDS = ('Subject', 'Length', 'Audience', 'Packs', 'Delivery')


def production(path):
    prod = Path(path).resolve()
    if not prod.is_dir():
        sys.exit(f'produce: {path} is not a directory')
    return prod


def rel(prod, text, what):
    """A relative path inside prod, or an error string."""
    if not isinstance(text, str) or not text or text.startswith(('/', '\\')) or ':' in text[:3]:
        return None, f'{what} must be a relative path'
    path = (prod / text).resolve()
    if not path.is_relative_to(prod):
        return None, f'{what} escapes the production directory'
    return path, None


def digest(prod):
    """Hash of the board bytes approval is bound to. approval.json is not part of it."""
    h = hashlib.sha256()
    paths = [prod / name for name in BOARD_FILES]
    for folder in ('boards/storyboard', 'boards/models', 'boards/elements'):
        root = prod / folder
        if root.is_dir():
            paths.extend(p for p in root.rglob('*') if p.is_file())
    for path in sorted({p.resolve() for p in paths if p.is_file()}):
        h.update(str(path.relative_to(prod)).encode())
        h.update(b'\0')
        h.update(path.read_bytes())
    return h.hexdigest()


def load_json(path):
    try:
        return json.loads(path.read_text(encoding='utf-8')), None
    except (OSError, json.JSONDecodeError) as err:
        return None, str(err)


def color(value):
    if not isinstance(value, str) or len(value) != 7 or value[0] != '#' or any(c not in HEX for c in value[1:]):
        return False
    return True


def labeled(text, field):
    prefix = field + ':'
    for line in text.splitlines():
        if line.startswith(prefix):
            return line[len(prefix):].strip()
    return None


def palette_of(prod, problems):
    path = prod / 'boards/palette.json'
    data, err = load_json(path) if path.is_file() else (None, 'missing boards/palette.json')
    if err or not isinstance(data, dict):
        problems.append(f'boards/palette.json: {err or "not an object"}')
        return None
    pack = data.get('pack')
    if not isinstance(pack, str) or not pack.strip():
        problems.append('boards/palette.json pack must be a non-empty string')
    if not color(data.get('ink')) or not color(data.get('paper')):
        problems.append('boards/palette.json ink and paper must be #rrggbb')
    tones = data.get('tones')
    if not isinstance(tones, list):
        problems.append('boards/palette.json tones must be a list')
    else:
        for i, tone in enumerate(tones):
            if not isinstance(tone, dict) or not isinstance(tone.get('lv'), (int, float)) or not color(tone.get('color')):
                problems.append(f'boards/palette.json tones[{i}] needs lv and #rrggbb color')
    if 'tolerance' in data and not isinstance(data['tolerance'], (int, float)):
        problems.append('boards/palette.json tolerance must be a number')
    return data


def check_brief(prod, pack, problems):
    path = prod / 'brief.md'
    if not path.is_file():
        problems.append('brief.md is missing')
        return []
    text = path.read_text(encoding='utf-8')
    packs = []
    for field in BRIEF_FIELDS:
        value = labeled(text, field)
        if not value:
            problems.append(f'brief.md {field}: is empty')
        elif field == 'Packs':
            packs = [p.strip() for p in value.split(',') if p.strip()]
    if pack and packs and pack not in packs:
        problems.append(f'brief.md Packs does not name the palette pack {pack}')
    return packs


def check_style(prod, pack, problems):
    path = prod / 'boards/style-guide.md'
    if not path.is_file():
        problems.append('boards/style-guide.md is missing')
        return
    text = path.read_text(encoding='utf-8')
    named = labeled(text, 'Pack')
    if pack and named != pack:
        problems.append(f'boards/style-guide.md Pack: must be {pack}')
    differs = text.split('Differs from the pack:', 1)
    if len(differs) == 2:
        for line in differs[1].splitlines():
            if line.startswith('- ') and not any(word in line.lower() for word in ('measured', 'judgment')):
                problems.append(f'style-guide difference must say measured or judgment: {line.strip()}')


def check_vibe(prod, problems):
    path = prod / 'boards/vibe.md'
    if not path.is_file() or 'credit' not in path.read_text(encoding='utf-8').lower():
        problems.append('boards/vibe.md must credit each reference (the word credit)')


def sheet_dir(prod, folder, problems, required):
    root = prod / 'boards' / folder
    stems = set()
    if root.is_dir():
        for path in root.iterdir():
            if path.is_file() and path.suffix in ('.md', '.js', '.png'):
                stems.add(path.stem)
    if required and not stems:
        problems.append(f'boards/{folder} needs one sheet (.md, .js, and .png)')
    for stem in sorted(stems):
        missing = [ext for ext in ('.md', '.js', '.png') if not (root / f'{stem}{ext}').is_file()]
        if missing:
            problems.append(f'boards/{folder}/{stem} is missing {", ".join(missing)}')
        else:
            md = (root / f'{stem}.md').read_text(encoding='utf-8').strip()
            js = (root / f'{stem}.js').read_text(encoding='utf-8').strip()
            if not md or not js:
                problems.append(f'boards/{folder}/{stem} .md and .js must be non-empty')


def check_storyboard(prod, problems):
    path = prod / 'boards/storyboard.json'
    data, err = load_json(path) if path.is_file() else (None, 'missing')
    if err or not isinstance(data, dict) or not isinstance(data.get('panels'), list):
        problems.append(f'boards/storyboard.json: {err or "needs a panels list"}')
        return
    if not data['panels']:
        problems.append('boards/storyboard.json needs at least one panel')
    for i, panel in enumerate(data['panels']):
        if not isinstance(panel, dict):
            problems.append(f'boards/storyboard.json panels[{i}] must be an object')
            continue
        for key in ('shot', 'action', 'camera'):
            if not isinstance(panel.get(key), str) or not panel[key].strip():
                problems.append(f'boards/storyboard.json panels[{i}].{key} must be non-empty')
        if not isinstance(panel.get('panel'), int) or panel['panel'] < 1:
            problems.append(f'boards/storyboard.json panels[{i}].panel must be an integer >= 1')
        if not isinstance(panel.get('t'), (int, float)) or panel['t'] < 0:
            problems.append(f'boards/storyboard.json panels[{i}].t must be >= 0')
        if 'caption' in panel and panel['caption'] is not None and not isinstance(panel['caption'], str):
            problems.append(f'boards/storyboard.json panels[{i}].caption must be a string or null')
        png, why = rel(prod, panel.get('png'), f'panels[{i}].png')
        if why:
            problems.append(f'boards/storyboard.json {why}')
        elif not png.is_file():
            problems.append(f'boards/storyboard.json panels[{i}].png does not exist')


def board_problems(prod):
    problems = []
    pal = palette_of(prod, problems)
    pack = pal.get('pack').strip() if isinstance(pal, dict) and isinstance(pal.get('pack'), str) else None
    check_brief(prod, pack, problems)
    check_style(prod, pack, problems)
    check_vibe(prod, problems)
    sheet_dir(prod, 'models', problems, True)
    sheet_dir(prod, 'elements', problems, False)
    check_storyboard(prod, problems)
    return problems


def read_approval(prod):
    path = prod / 'boards/approval.json'
    data, err = load_json(path) if path.is_file() else (None, 'missing')
    if err or not isinstance(data, dict) or data.get('approved') is not True:
        return None
    if data.get('boards_digest') != digest(prod):
        return None
    if not isinstance(data.get('note'), str) or not data['note'].strip():
        return None
    return data


def brief_packs(prod):
    text = (prod / 'brief.md').read_text(encoding='utf-8') if (prod / 'brief.md').is_file() else ''
    value = labeled(text, 'Packs') or ''
    return [p.strip() for p in value.split(',') if p.strip()]


def shot_problems(prod):
    """Problems with shots.json. Gate failures are separate (exit 2)."""
    problems = []
    path = prod / 'shots.json'
    data, err = load_json(path) if path.is_file() else (None, 'missing shots.json')
    if err or not isinstance(data, dict):
        return [f'shots.json: {err or "not an object"}']
    if not isinstance(data.get('fps'), (int, float)) or data['fps'] <= 0:
        problems.append('shots.json fps must be a positive number')
    size = data.get('size')
    if not (isinstance(size, list) and len(size) == 2 and all(isinstance(n, int) and n > 0 for n in size)):
        problems.append('shots.json size must be [width, height] in positive integers')
    shots = data.get('shots')
    if not isinstance(shots, list) or not shots:
        problems.append('shots.json shots must be a non-empty list')
        return problems
    packs = set(brief_packs(prod))
    prev = None
    ids = set()
    for i, shot in enumerate(shots):
        if not isinstance(shot, dict):
            problems.append(f'shots[{i}] must be an object')
            continue
        sid = shot.get('id')
        if not isinstance(sid, str) or not sid.strip() or sid in ids:
            problems.append(f'shots[{i}].id must be a new non-empty string')
        else:
            ids.add(sid)
        t0, t1 = shot.get('t0'), shot.get('t1')
        if not isinstance(t0, (int, float)) or not isinstance(t1, (int, float)) or t1 <= t0:
            problems.append(f'shots[{i}] needs t0 < t1')
        elif prev is not None and abs(t0 - prev) > 1e-4:
            problems.append(f'shots[{i}].t0 must meet the previous t1 ({prev})')
        elif i == 0 and t0 != 0:
            problems.append('shots[0].t0 must be 0')
        if isinstance(t1, (int, float)):
            prev = t1
        scene, why = rel(prod, shot.get('scene'), f'shots[{i}].scene')
        if why:
            problems.append(why)
        elif not scene.is_file():
            problems.append(f'shots[{i}].scene does not exist')
        pack = shot.get('pack')
        if not isinstance(pack, str) or not pack.strip():
            problems.append(f'shots[{i}].pack must be a non-empty string')
        elif packs and pack not in packs:
            problems.append(f'shots[{i}].pack {pack} is not in the brief Packs')
        audio = shot.get('audio')
        if audio is not None:
            if not isinstance(audio, dict) or not isinstance(audio.get('path'), str) or not audio['path']:
                problems.append(f'shots[{i}].audio needs a path')
            elif not isinstance(audio.get('start'), (int, float)):
                problems.append(f'shots[{i}].audio.start must be a number')
            else:
                wav, why = rel(prod, audio['path'], f'shots[{i}].audio.path')
                if why:
                    problems.append(why)
                elif not wav.is_file():
                    problems.append(f'shots[{i}].audio.path does not exist')
    return problems


def load_shots(prod):
    data, _ = load_json(prod / 'shots.json')
    return data


def report(problems):
    for line in problems:
        print(f'produce: {line}')
    return 1 if problems else 0


def cmd_init(prod):
    if (prod / 'brief.md').is_file():
        print(f'produce: {prod} already has brief.md')
        return 0
    (prod / 'boards/models').mkdir(parents=True)
    (prod / 'boards/elements').mkdir(parents=True)
    (prod / 'boards/storyboard').mkdir(parents=True)
    (prod / 'brief.md').write_text(
        '# Brief\n\nSubject:\nLength:\nAudience:\nPacks:\nDelivery:\n', encoding='utf-8')
    (prod / 'boards/style-guide.md').write_text(
        '# Style guide\n\nPack:\n\nDiffers from the pack:\n', encoding='utf-8')
    (prod / 'boards/vibe.md').write_text('# Vibe\n\nCredit:\n', encoding='utf-8')
    (prod / 'boards/palette.json').write_text(
        json.dumps({'pack': '', 'ink': '', 'paper': '', 'tones': []}, indent=2) + '\n', encoding='utf-8')
    (prod / 'boards/storyboard.json').write_text(json.dumps({'panels': []}, indent=2) + '\n', encoding='utf-8')
    print(prod)
    return 0


def cmd_boards(prod):
    return report(board_problems(prod))


def cmd_approve(prod, note):
    if not note or not note.strip():
        sys.exit('produce: approve needs the user\'s note')
    problems = board_problems(prod)
    if problems:
        report(problems)
        return 1
    (prod / 'boards/approval.json').write_text(json.dumps(
        {'approved': True, 'note': note.strip(), 'boards_digest': digest(prod)}, indent=2) + '\n', encoding='utf-8')
    print(prod / 'boards/approval.json')
    return 0


def gate(prod):
    if read_approval(prod) is None:
        print('produce: boards are not approved, or they changed after approval')
        return 2
    return 0


def cmd_shots(prod):
    closed = gate(prod)
    if closed:
        return closed
    return report(shot_problems(prod))


def cmd_cuts(prod):
    problems = shot_problems(prod)
    if problems:
        return report(problems)
    data = load_shots(prod)
    print(','.join(format(shot['t0'], 'g') for shot in data['shots']))
    return 0


def cmd_review(prod, frames):
    closed = gate(prod)
    if closed:
        return closed
    problems = shot_problems(prod)
    if problems:
        return report(problems)
    data = load_shots(prod)
    frames = Path(frames) if frames else prod / 'frames'
    if not frames.is_absolute():
        frames = prod / frames
    meta_path = frames / 'render.json'
    meta, err = load_json(meta_path) if meta_path.is_file() else (None, f'missing {meta_path}')
    if err or not isinstance(meta, dict):
        print(f'produce: {err or "render.json is not an object"}')
        return 1
    last = data['shots'][-1]['t1']
    fps = data['fps']
    if meta.get('fps') != fps:
        problems.append(f'render.json fps {meta.get("fps")} != shots.json fps {fps}')
    if meta.get('size') != data['size']:
        problems.append(f'render.json size {meta.get("size")} != shots.json size {data["size"]}')
    duration = meta.get('duration')
    if not isinstance(duration, (int, float)) or abs(duration - last) > 1 / fps:
        problems.append(f'render.json duration {duration} does not cover the shot list through {last}')
    scene = meta.get('scene')
    if not isinstance(scene, str) or not Path(scene).is_file():
        problems.append('render.json scene is not a file')
    if problems:
        return report(problems)
    packs = []
    for shot in data['shots']:
        if shot['pack'] not in packs:
            packs.append(shot['pack'])
    cuts = prod / 'shots.json'
    for pack in packs:
        print(f'inkstats.py {frames} --cuts {cuts} --pack {pack}')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    for name in ('init', 'boards', 'shots', 'cuts'):
        sub.add_parser(name).add_argument('dir')
    approve = sub.add_parser('approve')
    approve.add_argument('dir')
    approve.add_argument('--note', required=True)
    review = sub.add_parser('review')
    review.add_argument('dir')
    review.add_argument('--frames')
    args = ap.parse_args(argv)
    prod = Path(args.dir)
    if args.cmd == 'init':
        prod.mkdir(parents=True, exist_ok=True)
        return cmd_init(prod.resolve())
    prod = production(prod)
    if args.cmd == 'boards':
        return cmd_boards(prod)
    if args.cmd == 'approve':
        return cmd_approve(prod, args.note)
    if args.cmd == 'shots':
        return cmd_shots(prod)
    if args.cmd == 'cuts':
        return cmd_cuts(prod)
    return cmd_review(prod, args.frames)


if __name__ == '__main__':
    sys.exit(main())
