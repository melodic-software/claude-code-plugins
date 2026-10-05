"""Smoke test for the demo-video pipeline, network-free: a synthetic capture of a three-step flow
(navigate, type with results, navigate) goes through build_edl.py, produce.py and qc.py, and QC must
pass. Then defects are planted in the rendered frames (a crossfade across the page cut, a white
frame, a frozen stretch, a 1.0x render under a zoomed EDL, a zoom rect that cuts text) and QC must
fail each one by name. Needs numpy, Pillow, ffmpeg and ffprobe; skips without them.
"""
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

try:
    import numpy as np
    from PIL import Image, ImageDraw
    HAVE_DEPS = shutil.which('ffmpeg') is not None and shutil.which('ffprobe') is not None
except ImportError:
    HAVE_DEPS = False

W, H = 960, 540
T0 = 1000.0


def _font(size):
    from demo_common import font
    return font(size)


def draw_page(name, typed='', results=False):
    """One synthetic page state at CSS resolution: dark text on white with real glyphs, so the
    gutter and ink analysis see what they see on a real page."""
    img = Image.new('RGB', (W, H), (255, 255, 255))
    d = ImageDraw.Draw(img)
    small, mid, big = _font(15), _font(20), _font(40)
    d.rectangle([0, 0, W, 44], fill=(245, 246, 248))
    d.text((24, 12), 'Fixture', font=mid, fill=(20, 20, 30))
    for k, item in enumerate(('Docs', 'API', 'Community')):
        d.text((640 + k * 90, 14), item, font=small, fill=(40, 40, 60))
    if name == 'home':
        d.text((120, 150), 'Ship demos', font=big, fill=(10, 10, 20))
        d.text((120, 200), 'that show the change', font=big, fill=(10, 10, 20))
        d.text((120, 262), 'Record once, replay, and post a produced video.', font=mid, fill=(60, 60, 70))
        d.rounded_rectangle([120, 310, 280, 352], radius=8, fill=(30, 110, 230))
        d.text((146, 320), 'Get started', font=mid, fill=(255, 255, 255))
    else:
        for k, item in enumerate(('Introduction', 'Installation', 'Writing tests', 'Trace viewer', 'Debugging')):
            d.text((24, 80 + k * 32), item, font=small, fill=(40, 40, 60))
        title = 'Installation' if name == 'docs' else 'Trace viewer'
        d.text((260, 70), title, font=big, fill=(10, 10, 20))
        lines = ['Install the package and run the first test.', 'Every command below runs in a terminal.',
                 'The configuration file lives at the root.'] if name == 'docs' else \
            ['The trace viewer shows every action.', 'Open a trace to step through the run.', 'Each step has a snapshot.']
        for k, line in enumerate(lines):
            d.text((260, 130 + k * 26), line, font=small, fill=(60, 60, 70))
        if name == 'docs':
            d.rectangle([260, 230, 620, 266], outline=(150, 150, 160), width=2)
            d.text((272, 238), typed or 'Search', font=small, fill=(20, 20, 30) if typed else (160, 160, 170))
            if results:
                for k, line in enumerate(('Trace viewer: open a trace', 'Trace viewer: snapshots', 'Tracing API')):
                    d.text((272, 286 + k * 28), line, font=small, fill=(20, 60, 160))
    return img


def state_at(t):
    """Page state shown at source time t (the flow below)."""
    if t < 1004.4:
        return ('home', '', False)
    if t < 1005.0:
        return ('loading', '', False)   # mid-navigation: must never reach the output
    if t < 1009.3:
        return ('docs', '', False)
    if t < 1010.8:
        n = sum(1 for k in (1009.3, 1009.7, 1010.1) if t >= k)
        return ('docs', 'abc'[:n], False)
    if t < 1015.4:
        return ('docs', 'abc', True)
    return ('trace', '', False)


def make_capture(out):
    """A timeline.json in record.mjs's shape: frames every 0.2 s plus the step events."""
    (out / 'frames').mkdir(parents=True)
    frames, cache = [], {}
    t = T0
    n = 0
    while t <= 1017.2 + 1e-9:
        key = state_at(t)
        if key not in cache:
            img = Image.new('RGB', (W, H), (255, 255, 255)) if key[0] == 'loading' else draw_page(*key)
            buf = io.BytesIO()
            img.save(buf, 'PNG')
            cache[key] = buf.getvalue()
        f = f'frames/{n:05d}.png'
        (out / f).write_bytes(cache[key])
        frames.append({'file': f, 't': round(t, 4), 't0': round(t - 0.05, 4), 'digest': hashlib.md5(cache[key]).hexdigest()})
        n += 1
        t += 0.2
    button, field, hit = [120, 310, 160, 42], [260, 230, 360, 36], [268, 282, 230, 24]
    url_a, url_b, url_c = 'file:///home.html', 'file:///docs.html', 'file:///trace.html'
    ev = [
        {'name': 'start', 't': 1000.6},
        {'name': 'move', 'step': 'get-started', 't': 1001.8, 't1': 1003.9, 'from': {'x': 595, 'y': 297}, 'to': {'x': 200, 'y': 331}},
        {'name': 'click', 'step': 'get-started', 't': 1004.15, 'x': 200, 'y': 331, 'box': button,
         'block': [110, 140, 560, 222], 'url': url_a},
        {'name': 'settled', 'step': 'get-started', 't': 1005.2, 'url': url_b},
        {'name': 'move', 'step': 'search', 't': 1006.4, 't1': 1008.5, 'from': {'x': 200, 'y': 331}, 'to': {'x': 440, 'y': 248}},
        {'name': 'click', 'step': 'search', 't': 1008.75, 'x': 440, 'y': 248, 'box': field, 'block': [250, 222, 380, 150], 'url': url_b},
        {'name': 'type', 'step': 'search', 't': 1009.3, 'box': field, 'modal': None, 'text': 'abc'},
        {'name': 'key', 'step': 'search', 't': 1009.3, 'ch': 'a'},
        {'name': 'key', 'step': 'search', 't': 1009.7, 'ch': 'b'},
        {'name': 'key', 'step': 'search', 't': 1010.1, 'ch': 'c'},
        {'name': 'typed', 'step': 'search', 't': 1010.5},
        {'name': 'settled', 'step': 'search', 't': 1011.2, 'url': url_b, 'box': [260, 230, 360, 130]},
        {'name': 'move', 'step': 'open-result', 't': 1012.4, 't1': 1014.5, 'from': {'x': 440, 'y': 248}, 'to': {'x': 383, 'y': 294}},
        {'name': 'click', 'step': 'open-result', 't': 1014.75, 'x': 383, 'y': 294, 'box': hit,
         'block': [260, 276, 360, 92], 'url': url_b},
        {'name': 'settled', 'step': 'open-result', 't': 1015.6, 'url': url_c},
        {'name': 'end', 't': 1017.2},
    ]
    (out / 'timeline.json').write_text(json.dumps({'width': W, 'height': H, 'dsf': 1, 'frames': frames, 'events': ev}))


SCRIPT = {
    'title': 'Fixture tour',
    'subtitle': 'Get started  >  Search  >  Trace viewer',
    'steps': {
        'get-started': {'caption': 'Open Get started', 'outcome': 'Installation open'},
        'search': {'caption': 'Search the docs'},
        'open-result': {'caption': 'Open the first result', 'outcome': 'Trace viewer open'},
    },
}


def run(*args):
    return subprocess.run([sys.executable, *map(str, args)], capture_output=True, text=True, cwd=HERE)


def rewrite(src, dst, fn):
    """Re-encode src to dst, passing each RGB frame (with its neighbours) through fn(i, prev, cur, nxt)."""
    dec = subprocess.Popen(['ffmpeg', '-v', 'error', '-i', str(src), '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], stdout=subprocess.PIPE)
    enc = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', '30',
                            '-i', '-', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16', '-pix_fmt', 'yuv420p', str(dst)],
                           stdin=subprocess.PIPE)
    size = W * H * 3

    def read():
        b = dec.stdout.read(size)
        return np.frombuffer(b, np.uint8).reshape(H, W, 3).astype(np.float32) if len(b) == size else None
    cur, nxt, prev, i = read(), read(), None, 0
    while cur is not None:
        enc.stdin.write(np.clip(fn(i, prev, cur, nxt), 0, 255).astype(np.uint8).tobytes())
        prev, cur, nxt, i = cur, nxt, read(), i + 1
    enc.stdin.close()
    dec.stdout.close()
    enc.wait()
    dec.wait()
    shutil.copy(Path(src).with_suffix('.render.json'), Path(dst).with_suffix('.render.json'))


@unittest.skipUnless(HAVE_DEPS, 'needs numpy, Pillow, ffmpeg and ffprobe')
class DemoPipelineSmoke(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix='demo-video-'))
        make_capture(cls.tmp / 'capture')
        (cls.tmp / 'script.json').write_text(json.dumps(SCRIPT))
        cls.edl = cls.tmp / 'edl.json'
        r = run('build_edl.py', cls.tmp / 'capture', cls.tmp / 'script.json', cls.edl)
        assert r.returncode == 0, r.stdout + r.stderr
        cls.video = cls.tmp / 'demo.mp4'
        r = run('produce.py', cls.edl, cls.video, '--preset', 'veryfast')
        assert r.returncode == 0, r.stdout + r.stderr
        cls.fps = 30

    @classmethod
    def tearDownClass(cls):
        if not os.environ.get('DEMO_VIDEO_KEEP'):
            shutil.rmtree(cls.tmp, ignore_errors=True)

    def qc(self, video, edl=None, name='qc'):
        r = run('qc.py', edl or self.edl, video, self.tmp / name)
        report = json.loads((self.tmp / name / 'qc.json').read_text()) if (self.tmp / name / 'qc.json').exists() else None
        return r, report

    def failed(self, report):
        return {c['check'] for c in report['checks'] if c['status'] == 'FAIL'}

    def test_produced_video_passes_qc(self):
        r, report = self.qc(self.video)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.failed(report), set())
        share = next(c for c in report['checks'] if c['check'] == 'zoom-share')
        self.assertEqual(share['status'], 'PASS')

    def test_narration_trims_leading_silence_and_fits_the_edit(self):
        # One /speech:narrate-shaped clip: 0.35 s of leading silence (the Kokoro padding), then 1.0 s of tone;
        # words.json puts the first word at 0.35 s and the last word's end at 1.30 s.
        audio = self.tmp / 'audio'
        clip = audio / 'get-started'
        clip.mkdir(parents=True)
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'anullsrc=r=24000:cl=mono:d=0.35', '-f', 'lavfi',
                        '-i', 'sine=frequency=440:sample_rate=24000:duration=1.0', '-filter_complex', '[0:a][1:a]concat=n=2:v=0:a=1',
                        str(clip / 'narration.wav')], check=True)
        (clip / 'words.json').write_text(json.dumps({'duration': 1.35, 'words': [
            {'word': 'Open', 'start': 0.35, 'end': 0.8}, {'word': 'it', 'start': 0.85, 'end': 1.3}]}))
        edl_path = self.tmp / 'edl-narrated.json'
        r = run('build_edl.py', self.tmp / 'capture', self.tmp / 'script.json', edl_path, '--audio-dir', audio)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        edl = json.loads(edl_path.read_text())
        self.assertTrue(edl['layers']['narration'])
        (entry,) = edl['audio']
        self.assertAlmostEqual(entry['trim'], 0.30, places=3)       # first word 0.35 s minus the 0.05 s lead
        self.assertAlmostEqual(entry['duration'], 1.05, places=3)   # last word end 1.30 + 0.15 tail, capped at 1.35, minus trim
        nav_cut = edl['nav_cuts'][0]
        self.assertLessEqual(entry['end'], nav_cut - 0.3 + 1e-3)    # the step's line ends a pad before its page changes
        out = self.tmp / 'narrated.mp4'
        r = run('produce.py', edl_path, out, '--preset', 'veryfast')
        self.assertEqual(r.returncode, 0, r.stderr)
        streams = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type', '-of', 'csv=p=0', str(out)],
                                 capture_output=True, text=True, check=True).stdout.split()
        self.assertEqual(sorted(streams), ['audio', 'video'])

    def test_plain_style_drops_camera_title_and_captions(self):
        edl_path = self.tmp / 'edl-plain.json'
        r = run('build_edl.py', self.tmp / 'capture', self.tmp / 'script.json', edl_path, '--style', 'plain')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        layers = json.loads(edl_path.read_text())['layers']
        self.assertEqual({k for k, v in layers.items() if v}, {'cursor', 'ripple'})

    def test_edl_plan_keeps_navigation_cuts_at_one_x(self):
        edl = json.loads(self.edl.read_text())
        self.assertEqual(len(edl['nav_cuts']), 2)   # two navigating steps in the fixture flow
        for c in edl['nav_cuts']:
            before = [k for k in edl['camera'] if k['t'] <= c]
            self.assertEqual(before[-1]['rect'], [0.0, 0.0, float(W), float(H)])

    def test_crossfade_across_the_cut_fails(self):
        edl = json.loads(self.edl.read_text())
        c = int(round(edl['nav_cuts'][0] * self.fps))
        frames = {}

        def keep(i, prev, cur, nxt):
            if i in (c - 3, c + 3):
                frames[i] = cur
            return cur
        rewrite(self.video, self.tmp / 'probe.mp4', keep)
        a, b = frames[c - 3], frames[c + 3]

        def fade(i, prev, cur, nxt):
            if c - 2 <= i <= c + 2:
                w = (i - (c - 3)) / 6
                return a * (1 - w) + b * w
            return cur
        rewrite(self.video, self.tmp / 'xfade.mp4', fade)
        r, report = self.qc(self.tmp / 'xfade.mp4', name='qc-xfade')
        self.assertEqual(r.returncode, 1)
        self.assertIn('crossfade', self.failed(report))

    def test_white_frame_fails(self):
        k = int(round(5.0 * self.fps))
        rewrite(self.video, self.tmp / 'white.mp4', lambda i, p, cur, n: np.full_like(cur, 255) if i == k else cur)
        r, report = self.qc(self.tmp / 'white.mp4', name='qc-white')
        self.assertEqual(r.returncode, 1)
        self.assertIn('blank', self.failed(report))

    def test_frozen_stretch_fails(self):
        start = int(round(6.0 * self.fps))
        held = {}

        def freeze(i, prev, cur, nxt):
            if i == start:
                held['f'] = cur
            return held['f'] if start <= i < start + 60 else cur
        rewrite(self.video, self.tmp / 'frozen.mp4', freeze)
        r, report = self.qc(self.tmp / 'frozen.mp4', name='qc-frozen')
        self.assertEqual(r.returncode, 1)
        self.assertIn('stillness', self.failed(report))

    def test_full_frame_render_under_zoomed_edl_fails_zoom_share(self):
        flat = self.tmp / 'flat.mp4'
        r = run('produce.py', self.edl, flat, '--preset', 'veryfast', '--off', 'camera')
        self.assertEqual(r.returncode, 0, r.stderr)
        r, report = self.qc(flat, name='qc-flat')
        self.assertEqual(r.returncode, 1)
        self.assertIn('zoom-share', self.failed(report))

    def test_zoom_rect_cutting_text_fails_edge_clip(self):
        edl = json.loads(self.edl.read_text())
        bad = [330.0, 100.0, 640.0, 360.0]   # 1.5x; its left edge runs through the docs paragraphs
        for k in edl['camera']:
            if k['rect'] != [0.0, 0.0, float(W), float(H)]:
                k['rect'] = bad
        path = self.tmp / 'edl-clip.json'
        path.write_text(json.dumps(edl))
        out = self.tmp / 'clip.mp4'
        r = run('produce.py', path, out, '--preset', 'veryfast')
        self.assertEqual(r.returncode, 0, r.stderr)
        r, report = self.qc(out, edl=path, name='qc-clip')
        self.assertEqual(r.returncode, 1)
        self.assertIn('edge-clip', self.failed(report))


if __name__ == '__main__':
    unittest.main()
