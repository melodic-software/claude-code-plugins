#!/usr/bin/env python3
"""Render a storyboard.json (ADR 0102) to a narrated video of held still frames, then check and describe it.

usage: stills.py --storyboard FILE --out DIR (--narration NDIR | --no-audio | --script-only) [--stylesheet CSS]
                 [--stitcher COMMAND] [--upload-limit-mb N] [--head-sha SHA]

Steps: parse the storyboard -> scan its narration, frame text and screenshot sidecars (ADR 0107) -> write
DIR/script.txt -> capture each moment's frame at 3840x2160 -> lay out the holds from NDIR/words.json (speech's
narrate.py output) or, with --no-audio, captions-only holds -> captions (burned and soft) -> narration rebuilt in
video time and loudness-normalized -> one encode (profile reviewer-stills, or --stitcher) -> verify streams, size,
blank frames and luma SSIM of every hold's frame against its source -> contact sheets -> split at chapter starts
when over the upload limit -> DIR/manifest.json, the list of files a caller may publish.

--stitcher: a command with {inputs} (DIR/stitch.json: frames with seconds, audio, captions) and {out}; absent or
'ffmpeg' is the built-in reviewer-stills encode.
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


def capture(board, chapters, out, stylesheet, base):
    """Frames at 4K. On the first stills render Playwright's Chromium is not downloaded yet: install it once
    (only stills renders need it, so a manim-only user never downloads it), then capture again."""
    import media_capture
    frames = out / 'frames'
    frames.mkdir(parents=True, exist_ok=True)
    n = len(board['moments'])
    size = (FRAMES['width'], FRAMES['height'])
    pages = [(media_templates.page(m, board.get('title', ''), chapters[m['chapter']], (k, n), size, BAND, stylesheet,
                                   base),
              frames / f'm{k:03d}.png') for k, m in enumerate(board['moments'], 1)]
    try:
        return media_capture.capture(pages, FRAMES['width'], FRAMES['height'], FRAMES['scale'])
    except media_capture.ChromiumMissing:
        pass
    sys.stderr.write('explainer-video stills: installing Playwright\'s Chromium (first stills render only)\n')
    media_capture.install(CHROMIUM_INSTALL_S)
    return media_capture.capture(pages, FRAMES['width'], FRAMES['height'], FRAMES['scale'])


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


def quality(video, frame_paths, holds):
    """Luma SSIM of the frame shown mid-hold against its source PNG, above the caption band; blank frames."""
    rows, defects = [], []
    check = video.parent / 'check.png'
    for png, h in zip(frame_paths, holds):
        t = (h['start'] + h['end']) / 2
        media_verify.frame_at(video, t, check)
        ssim = media_verify.luma_ssim(png, check, 1 - BAND)
        rows.append({'id': h['id'], 't': round(t, 3), 'luma_ssim': round(ssim, 6)})
        if ssim < FRAMES['min_luma_ssim']:
            defects.append(f'moment {h["id"]}: luma SSIM {ssim:.6f} is under {FRAMES["min_luma_ssim"]}')
        if media_verify.blank(check):
            defects.append(f'moment {h["id"]}: the frame at {t:.2f} s is blank')
    check.unlink(missing_ok=True)
    return rows, defects


def main(argv=None):
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
    a = ap.parse_args(argv)
    stitcher = None if a.stitcher in (None, '', 'ffmpeg') else a.stitcher
    started = time.monotonic()
    missing = [t for t in ('ffmpeg', 'ffprobe') if not shutil.which(t)]
    if missing:
        return fail(2, f'{" and ".join(missing)} not found on PATH; install FFmpeg (https://ffmpeg.org/download.html)')
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
    scan = media_scan.scan(scan_texts(board, chapters, side))
    if not scan.ok:
        why = 'its rules did not load' if scan.fail_closed else ', '.join(f'{f["source"]} ({f["kind"]})'
                                                                           for f in scan.findings)
        return fail(4, f'scan: stopped before anything was rendered: {why}')
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
        tl = media_timeline.timeline(board, words, DEFAULTS['captions_only_hold'])
    except (OSError, ValueError, KeyError) as e:
        return fail(2, f'the narration in {a.narration} is unusable: {e}')
    steps = []
    try:
        frame_paths = capture(board, chapters, out, stylesheet, base)
        steps.append('capture')
        limits = DEFAULTS['captions']
        cues = media_captions.captions(tl['words'], tl['beats'], limits['max_words'], limits['min_seconds'],
                                       limits['seconds_per_word'])
        defects, flags = media_captions.caption_findings(cues, limits['min_seconds'], limits['seconds_per_word'])
        srt, ass = out / 'captions.srt', out / 'frames' / 'captions.ass'
        srt.write_text(media_captions.srt(cues), encoding='utf-8')
        ass.write_text(media_captions.ass(cues, FRAMES['width'] * FRAMES['scale'],
                                          FRAMES['height'] * FRAMES['scale'], BAND), encoding='utf-8')
        audio, loudness = (None, None) if a.no_audio else narration_audio(tl, a.narration.resolve(), out, steps)
        frames = [(p, h['end'] - h['start']) for p, h in zip(frame_paths, tl['holds'])]
        video = encode(frames, out, audio, srt, ass, stitcher, steps)
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
        rows, qdefects = quality(video, frame_paths, tl['holds'])
        defects += qdefects
        sheets = media_sheet.sheets(frame_paths, out, max_bytes=DEFAULTS['contact_sheet_max_bytes'])
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
    except (media_encode.EncodeError, subprocess.SubprocessError, OSError, RuntimeError, ValueError) as e:
        return fail(2, f'{type(e).__name__}: {e}')

    def rel(p):
        return str(Path(p).relative_to(out))
    manifest = {
        'head_sha': a.head_sha, 'storyboard_sha256': hashlib.sha256(raw).hexdigest(),
        'video': {'path': rel(video), 'bytes': video.stat().st_size, 'duration_s': tl['duration'],
                  'width': vstream.get('width'), 'height': vstream.get('height'), 'captions': 'stitcher' if stitcher else 'burned'},
        'captions_srt': rel(srt), 'chapters': tl['chapters'],
        'contact_sheet': [{'path': rel(s['path']), 'bytes': s['bytes'], 'frames': s['frames']} for s in sheets],
        'screenshots': [m['data']['image'] for m in board['moments'] if m['template'] == 'screenshot'],
        'parts': [{**p, 'path': rel(p['path'])} for p in parts], 'oversize': oversize,
        'voice': {'backend': voice.get('backend'), 'voice': voice.get('voice')} if voice else
                 {'backend': None if a.no_audio else 'unknown', 'voice': None},
        'scan': {'status': 'pass', 'floor_rules': scan.rule_count},
        'encode': {'profile': 'stitcher' if stitcher else PROFILE, 'steps': steps,
                   'seconds': round(time.monotonic() - started, 1)},
        'quality': {'frames': rows, 'min_luma_ssim': min(r['luma_ssim'] for r in rows), 'loudness': loudness,
                    'caption_flags': flags},
        'defects': defects, 'status': 'defect' if defects else 'pass'}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(f'{manifest["status"].upper()}: {video} ({tl["duration"]} s, {vstream.get("width")}x{vstream.get("height")}, '
          f'{video.stat().st_size} bytes, min luma SSIM {manifest["quality"]["min_luma_ssim"]})')
    for d in defects:
        print(f'DEFECT: {d}')
    for f in flags:
        print(f'FLAG: {f}')
    if oversize:
        print(f'OVERSIZE: {oversize}; host the whole video as an Actions artifact instead')
    return 1 if defects else 0


if __name__ == '__main__':
    sys.exit(main())
