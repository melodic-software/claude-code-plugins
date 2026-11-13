"""stills.py end to end on fixtures/storyboard.json. The refusals need only the standard library; the renders need
ffmpeg, ffprobe and Playwright for Python with its Chromium, and skip without them unless
EXPLAINER_VIDEO_REQUIRE_DEPS=1, which fails instead."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
STILLS = HERE / 'stills.py'
BOARD = HERE / 'fixtures' / 'storyboard.json'
HAVE_DEPS = importlib.util.find_spec('playwright') is not None and all(shutil.which(t) for t in ('ffmpeg', 'ffprobe'))
REQUIRE = os.environ.get('EXPLAINER_VIDEO_REQUIRE_DEPS') == '1'


def run(*args):
    return subprocess.run([sys.executable, str(STILLS), *map(str, args)], capture_output=True, text=True)


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


class Renders(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not HAVE_DEPS:
            if REQUIRE:
                raise AssertionError('EXPLAINER_VIDEO_REQUIRE_DEPS=1 but Playwright, ffmpeg or ffprobe is missing')
            raise unittest.SkipTest('Playwright for Python, ffmpeg or ffprobe not installed')
        cls.dir = Path(tempfile.mkdtemp())
        script = run('--storyboard', BOARD, '--out', cls.dir / 'probe', '--no-audio')
        cls.silent = (script, cls.dir / 'probe')
        narration = tone_narration(cls.dir / 'narration', (cls.dir / 'probe' / 'script.txt').read_text())
        cls.narrated = (run('--storyboard', BOARD, '--out', cls.dir / 'narrated', '--narration', narration),
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
        r = run('--storyboard', BOARD, '--out', out, '--no-audio', '--stylesheet', css,
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
