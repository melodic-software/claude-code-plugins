#!/usr/bin/env python3
"""Render a storyboard.json (ADR 0102) to a narrated video of held still frames, then check and describe it.

usage: stills.py --storyboard FILE --out DIR (--narration NDIR | --no-audio | --script-only) [--stylesheet CSS]
                 [--stitcher COMMAND] [--upload-limit-mb N] [--head-sha SHA] [--scan-pattern REGEX ...]

Steps: parse the storyboard -> scan its narration, frame text and screenshot sidecars (ADR 0107) -> write
DIR/script.txt -> capture each moment at 3840x2160, a long list (also-changed files, code-hunk lines, risk-map rows)
continued over as many frames as it needs, each frame fit-checked in the capture browser -> lay out the holds from
NDIR/words.json (speech's narrate.py output) or, with --no-audio, captions-only holds; every frame gets a reading
minimum, a moment whose frames need more than its paragraph holds on past it in silence, and its frames share the
spare time by entry count -> captions (burned and soft) -> narration rebuilt in video time and loudness-normalized -> one
encode (profile reviewer-stills, or --stitcher) -> verify streams, size, blank frames and luma SSIM of every frame
against its source -> contact sheets -> split at chapter starts when over the upload limit -> DIR/manifest.json, the
list of files a caller may publish. A frame whose content lies outside it or over its header, or that is held under
its reading minimum, is a defect. A narrated moment held past its paragraph longer than silent_hold.report_over_seconds
is a SILENT line and a manifest silent_holds entry, not a defect.

--stitcher: a command with {inputs} (DIR/stitch.json: frames with seconds, audio, captions) and {out}; absent or
'ffmpeg' is the built-in reviewer-stills encode. --scan-pattern (repeatable): a regex the scan also refuses
(scan.extra_patterns); it adds to the floor and never lowers it.
exit codes: 0 produced and every check passed; 1 produced with a defect (manifest.json lists each); 2 nothing
produced (bad storyboard, missing tool, capture failed); 3 a screenshot's sidecar is missing; 4 the scan found
secret or machine data, or could not load its rules. Exits 3 and 4 write no video.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import media_captions
import media_encode
import media_loudness
import media_scan
import media_sheet
import media_size
import media_templates
import media_timeline
import media_verify

DEFAULTS = json.loads(Path(__file__).with_name('defaults.json').read_text(encoding='utf-8'))
FRAMES = DEFAULTS['frames']
BAND = FRAMES['caption_band']   # bottom share kept free for burned captions; SSIM compares above it
PROFILE = 'reviewer-stills'
FPS = media_encode.PROFILES[PROFILE]['fps']
CHROMIUM_INSTALL_S = 600
MARKER = '.stills-output'   # only a folder holding it is cleared on the next run


def fail(code, message):
    sys.stderr.write(f'explainer-video stills: {message}\n')
    return code


def sidecars(board, base):
    """{moment id: sidecar text} for screenshot moments; FileNotFoundError naming the moment when one is missing."""
    out = {}
    for m in board['moments']:
        if m['template'] == 'screenshot':
            path = media_templates.inside(base, m['data']['sidecar'])
            if not path.is_file():
                raise FileNotFoundError(f'moment {m["id"]!r}: sidecar {m["data"]["sidecar"]} is missing')
            out[m['id']] = path.read_text(encoding='utf-8')
    return out


def scan_texts(board, chapters, side):
    texts = {'title': board.get('title', '')}
    for m in board['moments']:
        texts[f'{m["id"]}:narration'] = m.get('narration', '')
        texts[f'{m["id"]}:frame'] = media_templates.frame_text(m, board.get('title', ''), chapters[m['chapter']])
        if m['id'] in side:
            texts[f'{m["id"]}:sidecar'] = side[m['id']]
    return texts


def published(path, out):
    """{path relative to out, bytes, sha256} of the file as it sits on disk now; call it after the last write."""
    with open(path, 'rb') as f:
        digest = hashlib.file_digest(f, 'sha256').hexdigest()
        size = f.tell()
    return {'path': str(Path(path).relative_to(out)), 'bytes': size, 'sha256': digest}


def place_screenshots(board, base, side, out):
    """Copy each screenshot and write the sidecar text the scan read into out/screenshots; their manifest entries."""
    folder = out / 'screenshots'
    entries = []
    for k, m in enumerate(board['moments'], 1):
        if m['template'] != 'screenshot':
            continue
        folder.mkdir(exist_ok=True)
        src = media_templates.inside(base, m['data']['image'])
        image, sidecar = folder / f'm{k:03d}{src.suffix.lower()}', folder / f'm{k:03d}.txt'
        image.write_bytes(src.read_bytes())
        sidecar.write_text(side[m['id']], encoding='utf-8', newline='')
        shot, text = published(image, out), published(sidecar, out)
        entries.append({'path': shot['path'], 'sha256': shot['sha256'], 'sidecar': text['path'],
                        'sidecar_sha256': text['sha256']})
    return entries


def html(board, chapters, k, m, stylesheet, base, entries=None, part=None):
    if entries:
        m = media_templates.subset(m, *entries)
    return media_templates.page(m, board.get('title', ''), chapters[m['chapter']], (k, len(board['moments'])),
                                (FRAMES['width'], FRAMES['height']), BAND, stylesheet, base, part=part)


def paginate(board, chapters, stylesheet, base):
    """Per moment, the entry ranges of its frames: [None] for one frame showing everything. A candidate frame is
    measured with the longest continuation label, so the label the frame finally gets never makes it taller."""
    import media_capture
    jobs, at = [], []
    for k, m in enumerate(board['moments'], 1):
        total = media_templates.entries(m)
        if total > 1:
            at.append(k - 1)
            jobs.append((lambda a, b, k=k, m=m, total=total: html(
                board, chapters, k, m, stylesheet, base, (a, b), None if (a, b) == (0, total) else (2, total)),
                total))
    plans = [[None] for _ in board['moments']]
    for i, cuts in zip(at, media_capture.paginate(jobs, FRAMES['width'], FRAMES['height'], FRAMES['scale'], BAND)):
        if len(cuts) > 1:
            plans[i] = cuts
    return plans


def frames_of(board, chapters, out, stylesheet, base):
    """[{'id', 'k', 'part', 'parts', 'entries', 'png', 'problems'}], one per captured frame, at 4K and fit-checked.
    On the first stills render Playwright's Chromium is not downloaded yet: install it once (only stills renders
    need it, so a manim-only user never downloads it), then try again."""
    import media_capture
    folder = out / 'frames'
    folder.mkdir(parents=True, exist_ok=True)

    def work():
        frames = []
        for k, (m, plan) in enumerate(zip(board['moments'], paginate(board, chapters, stylesheet, base)), 1):
            for j, entries in enumerate(plan, 1):
                part = (j, len(plan)) if entries else None
                shown = media_templates.subset(m, *entries) if entries else m
                frames.append({'id': m['id'], 'k': k, 'part': j, 'parts': len(plan), 'entries': entries,
                               'minimum': minimum(shown, board.get('title', '')),
                               'png': folder / (f'm{k:03d}.png' if j == 1 else f'm{k:03d}-p{j}.png'),
                               'html': html(board, chapters, k, m, stylesheet, base, entries, part)})
        shots = media_capture.capture_checked([(f.pop('html'), f['png']) for f in frames], FRAMES['width'],
                                              FRAMES['height'], FRAMES['scale'], BAND)
        for f, (_, problems) in zip(frames, shots):
            f['problems'] = problems
        return frames
    try:
        return work()
    except media_capture.ChromiumMissing:
        pass
    sys.stderr.write('explainer-video stills: installing Playwright\'s Chromium (first stills render only)\n')
    media_capture.install(CHROMIUM_INSTALL_S)
    return work()


def visible_words(moment, board_title):
    """Whitespace-separated words of the strings a frame draws from its data (keys and file paths excluded)."""
    words = len(board_title.split()) if moment['template'] == 'title' else 0
    hidden = ('image', 'sidecar', 'alt') if moment['template'] == 'screenshot' else ()

    def walk(v):
        if isinstance(v, dict):
            return sum(walk(x) for k, x in v.items() if k not in hidden)
        if isinstance(v, list):
            return sum(walk(x) for x in v)
        return len(str(v).split()) if v is not None else 0
    return words + walk(moment.get('data') or {})


def minimum(moment, board_title):
    """Seconds a frame must stay on screen to be read: its words at the caption reading rate (captions
    seconds_per_word, the rate captions are held to), never under the captions-only hold's floor (min_seconds),
    the producer's own shortest hold for a frame with no narration."""
    return round(max(DEFAULTS['captions_only_hold']['min_seconds'],
                     visible_words(moment, board_title) * DEFAULTS['captions']['seconds_per_word']), 3)


def moment_minimums(board, frames):
    """Per moment, the seconds its frames need together; media_timeline.timeline extends a shorter hold."""
    return [round(sum(f['minimum'] for f in frames if f['id'] == m['id']), 3) for m in board['moments']]


def silent_holds(board, tl, needs, over):
    """Narrated moments held more than `over` seconds past their paragraph's slice of the narration, because their
    frames need longer: [{'id', 'past_s', 'needs_s', 'narration_s'}]. A report, never a defect."""
    spans = iter(e for e in tl['audio'] if e[0] == 'narration')
    out = []
    for m, h, need in zip(board['moments'], tl['holds'], needs):
        if not m['narration'].strip():
            continue
        _, a0, a1 = next(spans)
        past = (h['end'] - h['start']) - (a1 - a0)
        if past > over:
            out.append({'id': m['id'], 'past_s': round(past, 3), 'needs_s': need, 'narration_s': round(a1 - a0, 3)})
    return out


def frame_holds(holds, frames):
    """Each frame's span of its moment's hold: its minimum, plus the hold's spare time shared by entry count. A
    hold shorter than its frames' minimums (never made by timeline) is split by entry count alone, and quality()
    reports the frames it leaves short."""
    out = []
    for h in holds:
        mine = [f for f in frames if f['id'] == h['id']]
        weights = [f['entries'][1] - f['entries'][0] if f['entries'] else 1 for f in mine]
        length = h['end'] - h['start']
        spare = length - sum(f['minimum'] for f in mine)
        floors, spare = ([f['minimum'] for f in mine], spare) if spare > -0.005 else ([0] * len(mine), length)
        edges, t = [h['start']], h['start']
        for floor, w in zip(floors, weights):
            t += floor + spare * w / sum(weights)
            edges.append(round(t, 3))
        edges[-1] = h['end']
        out += [{**f, 'start': a, 'end': b} for f, a, b in zip(mine, edges, edges[1:])]
    return out


def narration_audio(tl, ndir, out, steps):
    """The narration rebuilt in video time and loudness-normalized; (path, loudness report)."""
    assembled, normalized = out / 'narration.assembled.wav', out / 'narration.normalized.wav'
    record = json.loads((ndir / 'words.json').read_text(encoding='utf-8'))
    media_encode.assemble_audio(ndir / record.get('audio', 'narration.wav'), tl['audio'], assembled)
    steps.append('assemble-audio')
    source = media_loudness.measure(assembled, DEFAULTS['loudness'])
    mode = media_loudness.normalize(assembled, normalized, source, DEFAULTS['loudness'])
    steps.append(f'loudnorm-{mode}')
    assembled.unlink(missing_ok=True)
    return normalized, {'normalization_type': mode, 'source': media_loudness.levels(source)}


def encode(frames, out, audio, srt, ass, stitcher, steps):
    video = out / 'video.mp4'
    if stitcher:
        spec = out / 'stitch.json'
        spec.write_text(json.dumps({'frames': [{'path': str(p), 'seconds': s} for p, s in frames],
                                    'audio': str(audio) if audio else None, 'captions_srt': str(srt),
                                    'captions_ass': str(ass)}, indent=2) + '\n', encoding='utf-8')
        media_encode.stitcher(stitcher, [spec], video)
        steps.append('stitcher')
    else:
        media_encode.stills(frames, video, PROFILE, audio=audio, srt=srt, ass=ass, cwd=out / 'frames')
        steps.append(PROFILE)
    return video


def quality(video, frames):
    """Per frame: the fit check, its time on screen against its reading minimum (one video frame of slack for
    rounding), then luma SSIM of the frame shown mid-hold against its source PNG, above the caption band, and blank
    frames."""
    rows, defects = [], []
    check = video.parent / 'check.png'
    for f in frames:
        name = f'moment {f["id"]}' + (f' frame {f["part"]} of {f["parts"]}' if f['parts'] > 1 else '')
        if f['problems']:
            more = f' (and {len(f["problems"]) - 1} more)' if len(f['problems']) > 1 else ''
            defects.append(f'{name}: content does not fit the frame: {f["problems"][0]}{more}')
        shown = round(f['end'] - f['start'], 3)
        if shown < f['minimum'] - 1 / FPS:
            defects.append(f'{name}: on screen {shown:.2f} s, under its {f["minimum"]:.2f} s reading minimum')
        t = (f['start'] + f['end']) / 2
        media_verify.frame_at(video, t, check)
        ssim = media_verify.luma_ssim(f['png'], check, 1 - BAND)
        rows.append({'id': f['id'], 'part': f['part'], 'parts': f['parts'],
                     'entries': list(f['entries']) if f['entries'] else None, 'start': f['start'], 'end': f['end'],
                     'minimum': f['minimum'],
                     't': round(t, 3), 'luma_ssim': round(ssim, 6), 'fit': f['problems'][:5]})
        if ssim < FRAMES['min_luma_ssim']:
            defects.append(f'{name}: luma SSIM {ssim:.6f} is under {FRAMES["min_luma_ssim"]}')
        if media_verify.blank(check):
            defects.append(f'{name}: the frame at {t:.2f} s is blank')
    check.unlink(missing_ok=True)
    return rows, defects


def main(argv=None):
    try:
        return _run(argv)
    except Exception as e:   # exit 1 means a manifest lists the defects; any other failure produced nothing
        return fail(2, f'{type(e).__name__}: {e}')


def _run(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--storyboard', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True)
    voice = ap.add_mutually_exclusive_group(required=True)
    voice.add_argument('--narration', type=Path, help="folder with narrate.py's narration.wav and words.json")
    voice.add_argument('--no-audio', action='store_true', help='captions-only: no voice produced audio')
    voice.add_argument('--script-only', action='store_true', help='validate, scan and write script.txt, then stop')
    ap.add_argument('--stylesheet', type=Path, help='CSS replacing the bundled frame stylesheet (frame_stylesheet)')
    ap.add_argument('--stitcher', help='custom stitcher command with {inputs} and {out} (stitcher)')
    ap.add_argument('--upload-limit-mb', type=float, default=DEFAULTS['upload_limit_mb'])
    ap.add_argument('--head-sha', default=None)
    ap.add_argument('--scan-pattern', action='append', default=[], help='a regex the scan also refuses (repeatable)')
    a = ap.parse_args(argv)
    stitcher = None if a.stitcher in (None, '', 'ffmpeg') else a.stitcher
    started = time.monotonic()
    raw = a.storyboard.read_bytes()
    try:
        board = media_timeline.parse(json.loads(raw))
    except (ValueError, AttributeError, TypeError) as e:
        return fail(2, f'storyboard rejected: {e}')
    base = a.storyboard.resolve().parent
    chapters = {c['id']: c['title'] for c in board['chapters']}
    try:
        side = sidecars(board, base)
    except (FileNotFoundError, ValueError) as e:
        return fail(3, f'sidecar: {e}; a screenshot needs its frame text for the scan, so it is refused')
    scan = media_scan.scan(scan_texts(board, chapters, side), extra=a.scan_pattern)
    if not scan.ok:
        why = 'its rules did not load' if scan.fail_closed else ', '.join(f'{f["source"]} ({f["kind"]})'
                                                                           for f in scan.findings)
        return fail(4, f'scan: stopped before anything was rendered: {why}')
    missing = [] if a.script_only else [t for t in ('ffmpeg', 'ffprobe') if not shutil.which(t)]
    if missing:
        return fail(2, f'{" and ".join(missing)} not found on PATH; install FFmpeg (https://ffmpeg.org/download.html)')
    out = a.out.resolve()
    if out.exists() and any(out.iterdir()):
        if not (out / MARKER).is_file():
            return fail(2, f'{out} is not empty and was not written by stills.py; name a new or empty folder')
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)
    (out / MARKER).write_text('written by explainer-video stills.py; the next run clears this folder\n',
                              encoding='utf-8')
    (out / 'script.txt').write_text(media_timeline.script(board), encoding='utf-8')
    if a.script_only:
        print(f'SCRIPT: {out / "script.txt"} (storyboard valid, scan passed)')
        return 0
    stylesheet = a.stylesheet.read_text(encoding='utf-8') if a.stylesheet else None
    try:
        words = None if a.no_audio else json.loads((a.narration / 'words.json').read_text(encoding='utf-8'))
        tl = media_timeline.timeline(board, words, DEFAULTS['captions_only_hold'], DEFAULTS['captions'])
    except (OSError, ValueError, KeyError) as e:
        return fail(2, f'the narration in {a.narration} is unusable: {e}')
    steps = []
    try:
        frames = frames_of(board, chapters, out, stylesheet, base)
        steps.append('capture')
        needs = moment_minimums(board, frames)
        tl = media_timeline.timeline(board, words, DEFAULTS['captions_only_hold'], DEFAULTS['captions'],
                                     minimum=needs)
        silent = silent_holds(board, tl, needs, DEFAULTS['silent_hold']['report_over_seconds']) \
            if words is not None and needs else []
        frames = frame_holds(tl['holds'], frames)
        limits = DEFAULTS['captions']
        cues = media_captions.captions(tl['words'], tl['beats'], limits['max_words'], limits['min_seconds'],
                                       limits['seconds_per_word'])
        defects, flags = media_captions.caption_findings(cues, limits['min_seconds'], limits['seconds_per_word'])
        srt, ass = out / 'captions.srt', out / 'frames' / 'captions.ass'
        srt.write_text(media_captions.srt(cues), encoding='utf-8')
        ass.write_text(media_captions.ass(cues, FRAMES['width'] * FRAMES['scale'],
                                          FRAMES['height'] * FRAMES['scale'], BAND), encoding='utf-8')
        audio, loudness = (None, None) if a.no_audio else narration_audio(tl, a.narration.resolve(), out, steps)
        video = encode([(f['png'], f['end'] - f['start']) for f in frames], out, audio, srt, ass, stitcher, steps)
        info = media_verify.probe(video)
        defects += media_verify.stream_defects(info, tl['duration'], FPS, audio=audio is not None, subtitle=not stitcher)
        vstream = next((s for s in info['streams'] if s.get('codec_type') == 'video'), {})
        if int(vstream.get('height') or 0) < FRAMES['min_height']:
            defects.append(f'video height {vstream.get("height")} is under the {FRAMES["min_height"]}p floor')
        if audio:
            delivered = media_loudness.measure(video, DEFAULTS['loudness'])
            defects += media_loudness.defects(delivered, DEFAULTS['loudness'])
            loudness['delivered'] = media_loudness.levels(delivered)
            audio.unlink(missing_ok=True)
        voice = json.loads((a.narration / 'voice.json').read_text(encoding='utf-8')) \
            if a.narration and (a.narration / 'voice.json').is_file() else None
        rows, qdefects = quality(video, frames)
        defects += qdefects
        sheets = media_sheet.sheets([f['png'] for f in frames], out, max_bytes=DEFAULTS['contact_sheet_max_bytes'])
        steps.append('contact-sheet')
        limit = media_size.limit_bytes(a.upload_limit_mb)
        parts, oversize = [], None
        if video.stat().st_size > limit:
            try:
                parts = media_size.split(video, [c['start_s'] for c in tl['chapters']], tl['duration'],
                                         out / 'parts', limit)
                steps.append('chapter-split')
            except media_size.SizeError as e:
                oversize = str(e)
        shots = place_screenshots(board, base, side, out)
    except (media_encode.EncodeError, subprocess.SubprocessError, OSError, RuntimeError, ValueError) as e:
        return fail(2, f'{type(e).__name__}: {e}')

    def rel(p):
        return str(Path(p).relative_to(out))
    manifest = {
        'head_sha': a.head_sha, 'storyboard_sha256': hashlib.sha256(raw).hexdigest(),
        'video': {**published(video, out), 'duration_s': tl['duration'], 'width': vstream.get('width'),
                  'height': vstream.get('height'), 'captions': 'stitcher' if stitcher else 'burned'},
        'captions_srt': rel(srt), 'chapters': tl['chapters'],
        'contact_sheet': [{**published(s['path'], out), 'frames': s['frames']} for s in sheets],
        'screenshots': shots,
        'parts': [{**p, **published(p['path'], out)} for p in parts], 'oversize': oversize,
        'voice': {'backend': voice.get('backend'), 'voice': voice.get('voice')} if voice else
                 {'backend': None if a.no_audio else 'unknown', 'voice': None},
        'scan': {'status': 'pass', 'floor_rules': scan.rule_count},
        'encode': {'profile': 'stitcher' if stitcher else PROFILE, 'steps': steps,
                   'seconds': round(time.monotonic() - started, 1)},
        'quality': {'frames': rows, 'min_luma_ssim': min(r['luma_ssim'] for r in rows), 'loudness': loudness,
                    'caption_flags': flags},
        'silent_holds': silent,
        'defects': defects, 'status': 'defect' if defects else 'pass'}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(f'{manifest["status"].upper()}: {video} ({tl["duration"]} s, {vstream.get("width")}x{vstream.get("height")}, '
          f'{video.stat().st_size} bytes, min luma SSIM {manifest["quality"]["min_luma_ssim"]})')
    for d in defects:
        print(f'DEFECT: {d}')
    for f in flags:
        print(f'FLAG: {f}')
    for s in silent:
        print(f'SILENT: moment {s["id"]} holds {s["past_s"]:.1f} s past its narration '
              f'(frames need {s["needs_s"]:.1f} s, narration {s["narration_s"]:.1f} s)')
    if oversize:
        print(f'OVERSIZE: {oversize}; host the whole video as an Actions artifact instead')
    return 1 if defects else 0


if __name__ == '__main__':
    sys.exit(main())
