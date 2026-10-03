#!/usr/bin/env python3
"""Render one ManimCE scene to an MP4, silent or narrated, then check the file it wrote. Run it through pydeps.py run.

usage: render.py SCENE_FILE SCENE_CLASS --out DIR [--quality l|m|h] [--narration NDIR]

Checks, every render: ffprobe reads one video stream, no audio stream, and a duration within a frame per animation
of the scene's own timeline; a frame is extracted at the end of every animation and must not be blank while
something is on screen; no two text elements overlap and no element is cut off by the frame edge at the end of
any animation. A text element, or the top-level group holding it, with `allow_overlap = True` is skipped by the
overlap check.

With --narration NDIR, the folder holding script.txt, narration.wav and words.json from speech:narrate, the scene's
beat() calls follow the narration (narration.py) and the render is muxed with narration.wav and captions built from
words.json. Narrated checks: every beat cued within one frame of its narration start; one video, one audio and one
subtitle stream; the video and audio streams within a frame per animation, plus one, of each other.

Writes DIR/SCENE_CLASS.mp4, DIR/frames/fNNNN.png and DIR/report.json (plus DIR/captions.srt and DIR/timing.json when
narrated), and prints the report summary.
exit codes: 0 rendered and every check passed; 1 rendered with a defect (each one in report.json); 2 nothing to
check (ffmpeg or ffprobe missing, the narration unreadable, the scene raised, or no video was written).
"""
import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import narration

QUALITY = {'l': 'low_quality', 'm': 'medium_quality', 'h': 'high_quality'}
TEXT_TYPES = ('Text', 'MarkupText', 'Paragraph', 'Tex', 'MathTex', 'SingleStringMathTex', 'Typst', 'MathTypst',
              'DecimalNumber', 'Integer', 'Code')
MARGIN = 0.02      # scene units: boxes closer than this count as touching, not overlapping
MAX_FRAMES = 24    # frames read back per render; longer scenes are sampled evenly, the last one always kept
BLANK_RANGE = 8    # a frame whose gray levels span less than this shows nothing


def overlaps(texts, margin=MARGIN):
    """texts: [(label, (x0, y0, x1, y1), allowed)]. Every pair whose boxes intersect by more than margin on both
    axes, unless either is allowed."""
    found = []
    for i, (la, a, oka) in enumerate(texts):
        for lb, b, okb in texts[i + 1:]:
            if oka or okb:
                continue
            w = min(a[2], b[2]) - max(a[0], b[0])
            h = min(a[3], b[3]) - max(a[1], b[1])
            if w > margin and h > margin:
                found.append((la, lb))
    return found


def clipped(box, frame_w, frame_h, margin=MARGIN):
    """True when the box is partly on screen and partly past a frame edge. Wholly off screen is not a defect: it
    is how an element waits to slide in."""
    x0, y0, x1, y1 = box
    hw, hh = frame_w / 2, frame_h / 2
    on_screen = x1 > -hw and x0 < hw and y1 > -hh and y0 < hh
    past = x0 < -hw - margin or x1 > hw + margin or y0 < -hh - margin or y1 > hh + margin
    return on_screen and past


def probed_duration(probe):
    try:
        return float(probe['format']['duration'])
    except (KeyError, TypeError, ValueError):
        return None


def stream_defects(probe, expected, fps, animations):
    """ffprobe's JSON against the scene's timeline. A frame of rounding per animation is allowed."""
    streams = probe.get('streams', [])
    video = [s for s in streams if s.get('codec_type') == 'video']
    defects = []
    if len(video) != 1:
        defects.append(f'expected one video stream, ffprobe found {len(video)}')
    if any(s.get('codec_type') == 'audio' for s in streams):
        defects.append('the file has an audio stream; this render is meant to be silent (remove add_sound)')
    duration = probed_duration(probe)
    if duration is None:
        return defects + ['ffprobe reports no duration']
    tolerance = (animations + 1) / fps
    if duration <= 0 or abs(duration - expected) > tolerance:
        defects.append(f'ffprobe duration {duration:.3f} s differs from the scene timeline {expected:.3f} s '
                       f'by more than {tolerance:.3f} s')
    return defects


def narrated_defects(probe, fps, animations):
    """ffprobe's JSON of the muxed file: one video, audio and subtitle stream; video and audio the same length
    within a frame per animation, plus one."""
    streams = probe.get('streams', [])
    defects = []
    for kind in ('video', 'audio', 'subtitle'):
        n = sum(s.get('codec_type') == kind for s in streams)
        if n != 1:
            defects.append(f'expected one {kind} stream, ffprobe found {n}')
    lengths = {}
    for s in streams:
        try:
            lengths[s.get('codec_type')] = float(s['duration'])
        except (KeyError, TypeError, ValueError):
            pass
    v, a = lengths.get('video'), lengths.get('audio')
    tolerance = (animations + 1) / fps
    if v is None or a is None:
        defects.append('ffprobe reports no video or audio stream duration')
    elif abs(v - a) > tolerance:
        defects.append(f'the video stream ({v:.3f} s) and the narration ({a:.3f} s) differ by more than '
                       f'{tolerance:.3f} s')
    return defects


def sample(checkpoints, limit=MAX_FRAMES):
    """At most limit checkpoints, evenly spaced, the last one always included."""
    if len(checkpoints) <= limit:
        return list(checkpoints)
    step = (len(checkpoints) - 1) / (limit - 1)
    return [checkpoints[round(i * step)] for i in range(limit)]


def _box(m):
    from manim import DL, UR
    (x0, y0, _), (x1, y1, _) = m.get_critical_point(DL), m.get_critical_point(UR)
    return (float(x0), float(y0), float(x1), float(y1))


def _shown(m):
    for f in m.get_family():
        if not f.has_points():
            continue
        if not hasattr(f, 'get_fill_opacity'):
            return True   # an image or point cloud: drawn whenever it has points
        if f.get_fill_opacity() > 0 or (f.get_stroke_opacity() > 0 and f.get_stroke_width() > 0):
            return True
    return False


def _label(m):
    text = next((v for v in (getattr(m, k, None) for k in ('original_text', 'tex_string', 'text')) if v), None)
    return f'{type(m).__name__}({str(text)[:40]!r})' if text else type(m).__name__


def _allowed(m):
    return bool(getattr(m, 'allow_overlap', False))


def elements(mobjects, containers, allowed=False):
    """(element, allowed) for each element on screen. Plain Group and VGroup containers are opened (FadeIn of
    several mobjects adds one), passing their allow_overlap down."""
    for m in mobjects:
        if type(m) in containers:
            yield from elements(m.submobjects, containers, allowed or _allowed(m))
        elif _shown(m):
            yield m, allowed or _allowed(m)


def snapshot(scene, text_types, containers):
    """What is on screen at the end of an animation: the elements and the text elements inside them."""
    tops, texts = [], []
    for top, allowed in elements(scene.mobjects, containers):
        tops.append((_label(top), _box(top)))
        stack = [top]
        while stack:
            m = stack.pop()
            if isinstance(m, text_types):
                if _shown(m):
                    texts.append((_label(m), _box(m), allowed or _allowed(m)))
            else:
                stack.extend(m.submobjects)
    return {'t': float(scene.renderer.time), 'tops': tops, 'texts': texts}


def clear_previous(out, scene_class):
    """Drop the last run's report, video, captions and frames, so a rerender that fails part-way leaves no PASS
    report."""
    for name in ('report.json', f'{scene_class}.mp4', f'{scene_class}.silent.mp4', 'captions.srt', 'timing.json'):
        (out / name).unlink(missing_ok=True)
    shutil.rmtree(out / 'frames', ignore_errors=True)


def load_narration(folder, out):
    """Read speech:narrate's output, write out/timing.json and point narration.beat at it."""
    record = json.loads((folder / 'words.json').read_text(encoding='utf-8'))
    wav = folder / record.get('audio', 'narration.wav')
    if not wav.is_file():
        raise FileNotFoundError(f'{wav} is missing')
    timing = narration.timing((folder / 'script.txt').read_text(encoding='utf-8'), record)
    path = out / 'timing.json'
    path.write_text(json.dumps(timing, indent=2) + '\n', encoding='utf-8')
    os.environ[narration.ENV] = str(path)
    return {'record': record, 'wav': wav, 'timing': timing}


def render(scene_file, scene_class, out, quality):
    """Render with a timeline hook on Scene.play (Scene.wait plays a Wait). Returns (movie, checkpoints, frame,
    beat marks)."""
    import manim
    text_types = tuple(t for t in (getattr(manim, n, None) for n in TEXT_TYPES) if isinstance(t, type))
    spec = importlib.util.spec_from_file_location('explainer_scene', scene_file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    cls = getattr(module, scene_class)
    checkpoints = []
    original = manim.Scene.play

    def play(self, *args, **kwargs):
        original(self, *args, **kwargs)
        checkpoints.append(snapshot(self, text_types, (manim.Group, manim.VGroup)))

    manim.Scene.play = play
    settings = {'quality': QUALITY[quality], 'media_dir': str(out / 'media'), 'disable_caching': True,
                'write_to_movie': True, 'format': 'mp4', 'output_file': scene_class, 'progress_bar': 'none',
                'verbosity': 'WARNING'}
    try:
        with manim.tempconfig(settings):
            frame = {'fps': float(manim.config.frame_rate), 'width': float(manim.config.frame_width),
                     'height': float(manim.config.frame_height)}
            scene = cls()
            scene.render()
            movie = Path(scene.renderer.file_writer.movie_file_path or '')
    finally:
        manim.Scene.play = original
    return movie, checkpoints, frame, list(getattr(scene, 'beat_marks', []))


def extract(movie, t, path):
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', f'{t:.3f}', '-i', str(movie), '-frames:v', '1', str(path)],
                   check=True, capture_output=True)


def mux(video, audio, captions, out):
    """The silent render's video, unchanged, with the narration as AAC and the captions as an MP4 text track."""
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(video), '-i', str(audio), '-i', str(captions),
                    '-map', '0:v:0', '-map', '1:a:0', '-map', '2:s:0', '-c:v', 'copy', '-c:a', 'aac',
                    '-c:s', 'mov_text', '-metadata:s:s:0', 'language=eng', str(out)],
                   check=True, capture_output=True)


def probe_file(path):
    return json.loads(subprocess.run(
        ['ffprobe', '-v', 'error', '-show_entries', 'format=duration:stream=codec_type,duration', '-of', 'json',
         str(path)], check=True, capture_output=True, text=True).stdout)


def blank(path):
    from PIL import Image
    lo, hi = Image.open(path).convert('L').getextrema()
    return hi - lo < BLANK_RANGE


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('scene_file', type=Path)
    ap.add_argument('scene_class')
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--quality', choices=sorted(QUALITY), default='l')
    ap.add_argument('--narration', type=Path, help='folder with script.txt, narration.wav and words.json')
    a = ap.parse_args(argv)
    missing = [t for t in ('ffmpeg', 'ffprobe') if not shutil.which(t)]
    if missing:
        sys.stderr.write(f'explainer-video: {" and ".join(missing)} not found on PATH. Install FFmpeg '
                         '(https://ffmpeg.org/download.html), which ships both, then rerun.\n')
        return 2
    out = a.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    clear_previous(out, a.scene_class)
    os.environ.pop(narration.ENV, None)
    narrated = None
    if a.narration:
        try:
            narrated = load_narration(a.narration.resolve(), out)
        except (OSError, ValueError, KeyError, TypeError) as e:
            sys.stderr.write(f'explainer-video: the narration in {a.narration} is unusable: {e}\n')
            return 2
    try:
        movie, checkpoints, frame, marks = render(a.scene_file.resolve(), a.scene_class, out, a.quality)
    except Exception as e:   # the scene's own error: report it, there is nothing to check
        import traceback
        traceback.print_exc()
        sys.stderr.write(f'explainer-video: the scene raised {type(e).__name__}; fix the scene and rerun.\n')
        return 2
    if not checkpoints or not movie.is_file():
        sys.stderr.write('explainer-video: no video was written. A scene needs at least one self.play or '
                         'self.wait.\n')
        return 2
    final = out / f'{a.scene_class}.mp4'
    silent = out / f'{a.scene_class}.silent.mp4' if narrated else final
    shutil.move(str(movie), silent)
    shutil.rmtree(out / 'media', ignore_errors=True)

    probe = probe_file(silent)
    expected = checkpoints[-1]['t']
    defects = stream_defects(probe, expected, frame['fps'], len(checkpoints))
    if narrated:
        timing = narrated['timing']
        defects += narration.beat_defects(marks, timing['starts'], frame['fps'])
        captions = out / 'captions.srt'
        captions.write_text(narration.srt(narration.captions(narrated['record'], timing['beats'])), encoding='utf-8')
        try:
            mux(silent, narrated['wav'], captions, final)
        except subprocess.CalledProcessError as e:
            reason = e.stderr.decode(errors='replace').strip()
            sys.stderr.write(f'explainer-video: ffmpeg could not mux the narration: {reason}\n')
            return 2
        silent.unlink()
        probe = probe_file(final)
        defects += narrated_defects(probe, frame['fps'], len(checkpoints))

    frames_dir = out / 'frames'
    shutil.rmtree(frames_dir, ignore_errors=True)
    frames_dir.mkdir()
    seen = set()
    for k, cp in enumerate(checkpoints):
        for la, lb in overlaps(cp['texts']):
            if (la, lb) not in seen:
                seen.add((la, lb))
                defects.append(f'at {cp["t"]:.2f} s, {la} overlaps {lb}')
        for label, box in cp['tops']:
            if clipped(box, frame['width'], frame['height']) and (label, 'edge') not in seen:
                seen.add((label, 'edge'))
                defects.append(f'at {cp["t"]:.2f} s, {label} is cut off by the frame edge')
        cp['index'] = k
    frames = []
    for cp in sample(checkpoints):
        path = frames_dir / f'f{cp["index"]:04d}.png'
        extract(final, max(0.0, cp['t'] - 1 / frame['fps']), path)
        frames.append({'t': round(cp['t'], 3), 'path': str(path), 'elements': len(cp['tops'])})
        if cp['tops'] and blank(path):
            defects.append(f'the frame at {cp["t"]:.2f} s is blank while {len(cp["tops"])} element(s) are on screen')

    probed = probed_duration(probe)
    report = {'scene': a.scene_class, 'quality': a.quality, 'video': str(final),
              'duration': {'timeline': round(expected, 3), 'ffprobe': probed},
              'animations': len(checkpoints), 'frames': frames,
              'narration': {'audio': str(narrated['wav']), 'captions': str(out / 'captions.srt'),
                            'beats': narrated['timing']['starts']} if narrated else None,
              'defects': defects,
              'status': 'defect' if defects else 'pass'}
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f'{report["status"].upper()}: {final} ({probed} s, {len(checkpoints)} animations)')
    for d in defects:
        print(f'DEFECT: {d}')
    print('Read these frames:')
    for f in frames:
        print(f'  {f["path"]}  (t={f["t"]} s)')
    return 1 if defects else 0


if __name__ == '__main__':
    sys.exit(main())
