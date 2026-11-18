"""stills.py end to end on fixtures/storyboard.json. The refusals need only the standard library; the renders need
ffmpeg, ffprobe and Playwright for Python with its Chromium, and skip without them unless
EXPLAINER_VIDEO_REQUIRE_DEPS=1 or MEDIA_RENDER_REQUIRE_DEPS=1, which fails instead."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
LONG_LIST = 9   # three of these two-line paths fill a frame, so nine need three frames
MIN_FRAME_SECONDS = 3.0   # a frame stays up at least a few seconds, the captions-only hold's floor
REST_NARRATION = 'The tests cover both paths, and the changelog has one new line.'
AFTER_NARRATION = 'Job length stays the same after the list.'
STILLS = HERE / 'stills.py'
BOARD = HERE / 'fixtures' / 'storyboard.json'
HAVE_DEPS = importlib.util.find_spec('playwright') is not None and all(shutil.which(t) for t in ('ffmpeg', 'ffprobe'))
# The same dependencies as lib/media-render's suite, so CI's MEDIA_RENDER_REQUIRE_DEPS also makes a gap fail.
REQUIRE = '1' in (os.environ.get('EXPLAINER_VIDEO_REQUIRE_DEPS'), os.environ.get('MEDIA_RENDER_REQUIRE_DEPS'))


def run(*args):
    return subprocess.run([sys.executable, str(STILLS), *map(str, args)], capture_output=True, text=True)


def run_1080p(*args):
    """stills.py's main in this process with frames captured at scale 1, 1920x1080 (the min_height floor) instead of
    3840x2160: the encode and the SSIM check, most of a render's time, handle a quarter of the pixels. Pagination and
    the fit check work in CSS pixels, which scale does not change. Only the narrated render asserts 4K."""
    import stills
    out, err = io.StringIO(), io.StringIO()
    with mock.patch.dict(stills.FRAMES, scale=1), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = stills.main([str(a) for a in args])
    return subprocess.CompletedProcess(args, code, out.getvalue(), err.getvalue())


def board_of(folder, ids, extra=()):
    """storyboard.json in folder holding only the fixture moments named in ids, then extra: a shorter video, so a
    render that checks structure and not the full fixture encodes fewer frames."""
    data = json.loads(BOARD.read_text(encoding='utf-8'))
    data['moments'] = [m for m in data['moments'] if m['id'] in ids] + list(extra)
    folder.mkdir(exist_ok=True)
    (folder / 'storyboard.json').write_text(json.dumps(data), encoding='utf-8')
    return folder / 'storyboard.json'


def streams(video):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type,codec_name,pix_fmt', '-of',
                          'json', str(video)], capture_output=True, text=True, check=True).stdout
    return json.loads(out)['streams']


def tone_narration(folder, script):
    """narrate.py's output shape for script, over a tone: words 0.35 s apart, paragraphs 0.6 s apart."""
    folder.mkdir()
    words, t = [], 0.2
    for para in [p.split() for p in script.split('\n\n') if p.split()]:
        for w in para:
            words.append({'word': w, 'start': round(t, 3), 'end': round(t + 0.3, 3)})
            t += 0.35
        t += 0.6
    duration = round(t + 0.4, 3)
    (folder / 'words.json').write_text(json.dumps({'audio': 'narration.wav', 'duration': duration, 'words': words}))
    (folder / 'voice.json').write_text(json.dumps({'backend': 'test-tone', 'voice': 'sine', 'attempts': []}))
    subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', f'sine=frequency=440:duration={duration}', '-ar',
                    '24000', '-ac', '1', str(folder / 'narration.wav')], check=True)
    return folder


def srt_cues(path):
    """[(start s, end s, text)] from an SRT file."""
    def seconds(stamp):
        h, m, rest = stamp.split(':')
        return int(h) * 3600 + int(m) * 60 + float(rest.replace(',', '.'))
    cues = []
    for block in path.read_text(encoding='utf-8').strip().split('\n\n'):
        lines = block.splitlines()
        a, b = lines[1].split(' --> ')
        cues.append((seconds(a), seconds(b), ' '.join(lines[2:])))
    return cues


class Refusals(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)

    def board(self, change):
        data = json.loads(BOARD.read_text(encoding='utf-8'))
        change(data)
        path = self.dir / 'storyboard.json'
        path.write_text(json.dumps(data), encoding='utf-8')
        return path

    def test_script_only_writes_one_paragraph_per_narrated_moment_and_no_frames(self):
        r = run('--storyboard', BOARD, '--out', self.dir / 'out', '--script-only')
        self.assertEqual(r.returncode, 0, r.stderr)
        script = (self.dir / 'out' / 'script.txt').read_text(encoding='utf-8')
        self.assertEqual(len(script.strip().split('\n\n')), 5)
        self.assertFalse((self.dir / 'out' / 'frames').exists())

    def test_a_folder_stills_did_not_create_is_never_cleared(self):
        out = self.dir / 'mine'
        out.mkdir()
        (out / 'keep.txt').write_text('mine')
        r = run('--storyboard', BOARD, '--out', out, '--script-only')
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertEqual((out / 'keep.txt').read_text(), 'mine')
        self.assertEqual(run('--storyboard', BOARD, '--out', self.dir / 'fresh', '--script-only').returncode, 0)
        self.assertEqual(run('--storyboard', BOARD, '--out', self.dir / 'fresh', '--script-only').returncode, 0)

    def test_planted_home_path_stops_before_any_video(self):
        home = '/' + 'home/' + 'someone/project/notes.txt'   # assembled at run time, as the redact tests do
        path = self.board(lambda d: d['moments'][2]['data']['lines'].append({'n': 47, 'kind': '+', 'text': home}))
        r = run('--storyboard', path, '--out', self.dir / 'out', '--no-audio')
        self.assertEqual(r.returncode, 4, r.stderr)
        self.assertIn('scan', r.stderr)
        self.assertNotIn(home, r.stderr)
        self.assertFalse((self.dir / 'out' / 'video.mp4').exists())

    def test_a_scan_pattern_stops_its_match_before_any_frame(self):
        path = self.board(lambda d: d['moments'][2]['data']['lines'].append({'n': 47, 'kind': '+', 'text': 'BLUEJAY'}))
        r = run('--storyboard', path, '--out', self.dir / 'out', '--script-only', '--scan-pattern', r'\bBLUEJAY\b')
        self.assertEqual(r.returncode, 4, r.stderr)
        self.assertIn('config-pattern', r.stderr)
        self.assertEqual(run('--storyboard', path, '--out', self.dir / 'plain', '--script-only').returncode, 0)

    def test_a_failure_that_produced_nothing_exits_2_not_1(self):
        cases = {'missing storyboard': ('--storyboard', self.dir / 'nope.json', '--out', self.dir / 'a'),
                 'out is a file': ('--storyboard', BOARD, '--out', BOARD)}
        for reason, args in cases.items():
            with self.subTest(reason):
                r = run(*args, '--script-only')
                self.assertEqual(r.returncode, 2, r.stderr)
                self.assertNotIn('Traceback', r.stderr)

    def test_screenshot_without_sidecar_is_refused(self):
        path = self.board(lambda d: d['moments'].append({'id': 'shot', 'chapter': 'risk', 'template': 'screenshot',
                                                         'data': {'image': 'shot.png'}, 'narration': 'The page.',
                                                         'covers': []}))
        r = run('--storyboard', path, '--out', self.dir / 'out', '--no-audio')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('sidecar', r.stderr)
        self.assertFalse((self.dir / 'out' / 'video.mp4').exists())

    def test_screenshot_whose_sidecar_file_is_missing_is_refused(self):
        path = self.board(lambda d: d['moments'].append({'id': 'shot', 'chapter': 'risk', 'template': 'screenshot',
                                                         'data': {'image': 'shot.png', 'sidecar': 'shot.txt'},
                                                         'narration': 'The page.', 'covers': []}))
        r = run('--storyboard', path, '--out', self.dir / 'out', '--no-audio')
        self.assertEqual(r.returncode, 3, r.stderr)
        self.assertIn('sidecar', r.stderr)


class SilentHolds(unittest.TestCase):
    def test_only_a_moment_held_more_than_the_threshold_past_its_paragraph_is_reported(self):
        sys.path.insert(0, str(HERE))
        self.addCleanup(sys.path.remove, str(HERE))
        import media_timeline
        import stills
        narration = {'dense': 'One short sentence.', 'edge': 'Two words.',
                     'covered': 'This paragraph runs long enough to cover the frame it narrates.'}
        board = {'chapters': [{'id': 'c', 'title': 'C'}],
                 'moments': [{'id': k, 'chapter': 'c', 'template': 'code-hunk', 'narration': v}
                             for k, v in narration.items()]}
        starts = [0.0, 0.5, 1.0, 2.0, 2.5] + [3.0 + 0.4 * i for i in range(11)]
        tokens = [w for v in narration.values() for w in v.split()]
        words = {'duration': 8.0, 'words': [{'word': w, 'start': s, 'end': s + 0.3} for w, s in zip(tokens, starts)]}
        needs = [9.5, 4.0, 4.0]   # paragraphs span 2.0, 1.0 and 5.0 s of narration.wav
        tl = media_timeline.timeline(board, words, minimum=needs)
        self.assertEqual(stills.silent_holds(board, tl, needs, 3.0),
                         [{'id': 'dense', 'past_s': 7.5, 'needs_s': 9.5, 'narration_s': 2.0}],
                         'edge holds exactly 3.0 s past and covered not at all; neither is reported')


class Renders(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not HAVE_DEPS:
            if REQUIRE:
                raise AssertionError('a REQUIRE_DEPS variable is 1 but Playwright, ffmpeg or ffprobe is missing')
            raise unittest.SkipTest('Playwright for Python, ffmpeg or ffprobe not installed')
        sys.path.insert(0, str(HERE))   # run_1080p imports stills
        cls.addClassCleanup(sys.path.remove, str(HERE))
        cls.dir = Path(tempfile.mkdtemp())
        script = run_1080p('--storyboard', BOARD, '--out', cls.dir / 'probe', '--no-audio')
        cls.silent = (script, cls.dir / 'probe')
        small = board_of(cls.dir / 'small', ('title', 'compare', 'rest'))
        run('--storyboard', small, '--out', cls.dir / 'small-script', '--script-only')
        narration = tone_narration(cls.dir / 'narration', (cls.dir / 'small-script' / 'script.txt').read_text())
        cls.narrated = (run('--storyboard', small, '--out', cls.dir / 'narrated', '--narration', narration),
                        cls.dir / 'narrated')

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.dir, ignore_errors=True)

    def manifest(self, out):
        return json.loads((out / 'manifest.json').read_text(encoding='utf-8'))

    def test_narrated_render_is_4k_h264_with_aac_chapters_and_legible_frames(self):
        r, out = self.narrated
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        kinds = {(s['codec_type'], s['codec_name']) for s in streams(out / 'video.mp4')}
        self.assertTrue({('video', 'h264'), ('audio', 'aac'), ('subtitle', 'mov_text')} <= kinds)
        self.assertIn('yuv420p', {s.get('pix_fmt') for s in streams(out / 'video.mp4')})
        m = self.manifest(out)
        self.assertEqual((m['video']['width'], m['video']['height']), (3840, 2160))
        self.assertEqual([c['title'] for c in m['chapters']], ['Why', 'The change', 'Risk'])
        self.assertEqual(m['chapters'][0]['start_s'], 0.0)
        self.assertGreaterEqual(m['quality']['min_luma_ssim'], 0.999)
        self.assertEqual(m['voice']['backend'], 'test-tone')
        self.assertEqual(m['scan']['status'], 'pass')
        self.assertTrue(all((out / s['path']).is_file() for s in m['contact_sheet']))

    def test_captions_only_render_has_no_audio_and_burned_captions(self):
        r, out = self.silent
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotIn('audio', {s['codec_type'] for s in streams(out / 'video.mp4')})
        m = self.manifest(out)
        self.assertEqual(m['video']['captions'], 'burned')
        self.assertIsNone(m['voice']['backend'])
        self.assertIn('only retries server errors.', (out / 'captions.srt').read_text())

    def test_every_published_video_and_contact_sheet_names_the_sha256_of_its_bytes(self):
        r, out = self.narrated
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        m = self.manifest(out)
        for entry in [m['video'], *m['contact_sheet']]:
            data = (out / entry['path']).read_bytes()
            self.assertEqual(entry['sha256'], hashlib.sha256(data).hexdigest(), f'{entry["path"]} digest')
            self.assertEqual(entry['bytes'], len(data), f'{entry["path"]} size')

    def test_each_chapter_part_of_a_split_video_names_the_sha256_of_its_bytes(self):
        r, whole = self.silent
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        limit_mb = (whole / 'video.mp4').stat().st_size * 0.8 / 10 ** 6   # under the whole video, over any one chapter
        out = self.dir / 'split'
        r = run_1080p('--storyboard', BOARD, '--out', out, '--no-audio', '--upload-limit-mb', limit_mb)
        self.assertIn(r.returncode, (0, 1), r.stdout + r.stderr)
        m = self.manifest(out)
        self.assertIsNone(m['oversize'])
        self.assertGreaterEqual(len(m['parts']), 2, 'the video was not split at chapter starts')
        for part in m['parts']:
            self.assertFalse(Path(part['path']).is_absolute(), part['path'])
            data = (out / part['path']).read_bytes()
            self.assertEqual(part['bytes'], len(data), f'{part["path"]} size')
            self.assertEqual(part['sha256'], hashlib.sha256(data).hexdigest(), f'{part["path"]} digest')

    def test_each_screenshot_is_published_with_its_own_scanned_sidecar_inside_the_output(self):
        src = self.dir / 'shots'
        src.mkdir()
        texts = {'one': 'Settings page\nRetry count: 3\n', 'two': 'Audit log\nNo entries yet\n'}
        moments = []
        for name, text in texts.items():
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=0x336699:s=640x360', '-frames:v',
                            '1', str(src / f'{name}.png')], check=True)
            (src / f'{name}.txt').write_text(text, encoding='utf-8')
            moments.append({'id': f'shot-{name}', 'chapter': 'risk', 'template': 'screenshot',
                            'data': {'image': f'{name}.png', 'sidecar': f'{name}.txt', 'alt': name},
                            'narration': f'The {name} page.', 'covers': []})
        out = self.dir / 'screens'
        r = run_1080p('--storyboard', board_of(src, ('title',), moments), '--out', out, '--no-audio')
        self.assertIn(r.returncode, (0, 1), r.stdout + r.stderr)
        shots = self.manifest(out)['screenshots']
        self.assertEqual(len(shots), 2)
        for shot, (name, text) in zip(shots, texts.items()):
            self.assertEqual(set(shot), {'path', 'sha256', 'sidecar', 'sidecar_sha256'})
            for rel in (shot['path'], shot['sidecar']):
                self.assertFalse(Path(rel).is_absolute(), rel)
                self.assertTrue((out / rel).resolve().is_relative_to(out.resolve()), f'{rel} is outside the output')
            image, sidecar = out / shot['path'], out / shot['sidecar']
            self.assertEqual(image.read_bytes(), (src / f'{name}.png').read_bytes())
            self.assertEqual(sidecar.read_text(encoding='utf-8'), text)
            self.assertEqual(shot['sha256'], hashlib.sha256(image.read_bytes()).hexdigest())
            self.assertEqual(shot['sidecar_sha256'], hashlib.sha256(sidecar.read_bytes()).hexdigest())
        self.assertNotEqual(shots[0]['sidecar'], shots[1]['sidecar'])

    def list_board(self, folder, follow=False):
        """One also-changed moment of LONG_LIST long paths with a short paragraph; follow adds a narrated moment
        after it, whose frames and captions must move by the list's padding."""
        files = [{'path': f'plugins/example/scripts/a-long-directory-name/entry-{i:02d}/case.json',
                  'summary': f'case {i}'} for i in range(LONG_LIST)]
        moments = [{'id': 'rest', 'chapter': 'risk', 'template': 'also-changed', 'data': {'files': files},
                    'narration': REST_NARRATION, 'covers': [f['path'] for f in files]}]
        if follow:
            moments.append({'id': 'after', 'chapter': 'risk', 'template': 'risk-map',
                            'data': {'rows': [{'area': 'Job length', 'level': 'low', 'note': 'unchanged'}]},
                            'narration': AFTER_NARRATION, 'covers': []})
        folder.mkdir()
        (folder / 'storyboard.json').write_text(json.dumps({
            'version': 1, 'title': 'Long list', 'chapters': [{'id': 'risk', 'title': 'Risk'}], 'moments': moments}),
            encoding='utf-8')
        return folder / 'storyboard.json'

    def test_a_long_list_continues_over_fitting_frames_each_held_long_enough_to_read(self):
        src = self.list_board(self.dir / 'long-src', follow=True)
        self.assertEqual(run('--storyboard', src, '--out', self.dir / 'long-script', '--script-only').returncode, 0)
        narration = tone_narration(self.dir / 'long-narration', (self.dir / 'long-script' / 'script.txt').read_text())
        out = self.dir / 'long'
        r = run_1080p('--storyboard', src, '--out', out, '--narration', narration)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        m = self.manifest(out)
        rows = [row for row in m['quality']['frames'] if row['id'] == 'rest']
        after = [row for row in m['quality']['frames'] if row['id'] == 'after']
        self.assertGreaterEqual(len(rows), 3, 'the list was not continued over three frames')
        self.assertEqual([row['part'] for row in rows], list(range(1, len(rows) + 1)))
        self.assertEqual(rows[0]['entries'][0], 0)
        self.assertEqual(rows[-1]['entries'][1], LONG_LIST)
        for a, b in zip(rows, rows[1:]):
            self.assertEqual(a['entries'][1], b['entries'][0], 'an entry was skipped or shown twice')
            self.assertEqual(a['end'], b['start'], 'the frames do not follow each other')
        for row in m['quality']['frames']:
            self.assertGreaterEqual(row['minimum'], MIN_FRAME_SECONDS)
            self.assertGreaterEqual(row['end'] - row['start'], row['minimum'] - 1 / 30, row)
        self.assertEqual([row['fit'] for row in m['quality']['frames']], [[]] * len(m['quality']['frames']))
        self.assertEqual(len(list((out / 'frames').glob('m001*.png'))), len(rows))
        words = json.loads((narration / 'words.json').read_text())
        paragraph = words['words'][len(REST_NARRATION.split())]['start']
        padding = sum(row['minimum'] for row in rows) - paragraph
        self.assertGreater(padding, 3.0, 'the fixture paragraph should leave its frames over 3 s of silence')
        self.assertEqual([s['id'] for s in m['silent_holds']], ['rest'], 'after is covered by its paragraph')
        self.assertAlmostEqual(m['silent_holds'][0]['past_s'], padding, delta=0.01)
        self.assertEqual([line for line in r.stdout.splitlines() if line.startswith('SILENT:')],
                         [f'SILENT: moment rest holds {padding:.1f} s past its narration (frames need '
                          f'{padding + paragraph:.1f} s, narration {paragraph:.1f} s)'])
        self.assertAlmostEqual(rows[-1]['end'] - rows[0]['start'], paragraph + padding, delta=0.01)
        self.assertEqual(after[0]['start'], rows[-1]['end'])
        self.assertGreaterEqual(m['video']['duration_s'], words['duration'] + padding - 0.01)
        opening = ' '.join(AFTER_NARRATION.split()[:3])
        cue = next(c for c in srt_cues(out / 'captions.srt') if c[2].startswith(opening))
        self.assertAlmostEqual(cue[0], after[0]['start'], delta=0.002, msg='the captions drifted off the frames')

    def test_a_frame_that_overflows_or_is_held_under_its_reading_minimum_fails_the_render(self):
        """One cheap render covers both checks: with pagination and the hold minimums both switched off, the
        list lands on one frame too small for it, held only as long as its paragraph."""
        import stills
        out = self.dir / 'forced'
        with mock.patch.object(stills, 'paginate', lambda board, *_: [[None] for _ in board['moments']]), \
                mock.patch.object(stills, 'moment_minimums', lambda *_: None):
            r = run_1080p('--storyboard', self.list_board(self.dir / 'forced-src'), '--out', out, '--no-audio')
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        m = self.manifest(out)
        self.assertEqual(m['status'], 'defect')
        self.assertTrue(any(d.startswith('moment rest: content does not fit the frame') for d in m['defects']),
                        m['defects'])
        self.assertTrue(any(d.startswith('moment rest: on screen') and 'reading minimum' in d
                            for d in m['defects']), m['defects'])
        self.assertTrue(m['quality']['frames'][0]['fit'])

    def test_stylesheet_and_stitcher_come_from_configuration(self):
        css = self.dir / 'white.css'
        css.write_text('html,body{width:1920px;height:1080px;margin:0;background:#ffffff;color:#000}')
        stitcher = self.dir / 'stitch.py'
        stitcher.write_text(
            'import json, subprocess, sys\n'
            'spec = json.load(open(sys.argv[1]))\n'
            'lst = sys.argv[2] + ".txt"\n'
            'open(lst, "w").write("".join(f"file \'{f[\'path\']}\'\\nduration {f[\'seconds\']}\\n" for f in spec["frames"])'
            ' + f"file \'{spec[\'frames\'][-1][\'path\']}\'\\n")\n'
            'subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-vf", "fps=30",'
            ' "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", sys.argv[2]], check=True)\n')
        out = self.dir / 'custom'
        r = run_1080p('--storyboard', board_of(self.dir / 'custom-src', ('title',)), '--out', out, '--no-audio',
                      '--stylesheet', css,
                      '--stitcher', f'"{sys.executable}" "{stitcher}" {{inputs}} {{out}}')
        self.assertIn(r.returncode, (0, 1), r.stderr)
        m = self.manifest(out)
        self.assertEqual(m['encode']['profile'], 'stitcher')
        pixel = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(out / 'frames' / 'm001.png'), '-vf',
                                'crop=1:1:0:0', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
                               capture_output=True, check=True).stdout
        self.assertEqual(pixel, b'\xff\xff\xff')


if __name__ == '__main__':
    unittest.main()
