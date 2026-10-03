"""render.py: the check functions (standard library only, always run) and two real renders (need ManimCE, ffmpeg and
ffprobe; skipped without them unless EXPLAINER_VIDEO_REQUIRE_DEPS=1, which fails instead)."""
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
PLUGIN = HERE.parent
sys.path.insert(0, str(HERE))
import render  # noqa: E402

HAVE_DEPS = importlib.util.find_spec('manim') is not None and all(shutil.which(t) for t in ('ffmpeg', 'ffprobe'))
REQUIRE = os.environ.get('EXPLAINER_VIDEO_REQUIRE_DEPS') == '1'


class Overlaps(unittest.TestCase):
    def test_intersecting_boxes_overlap(self):
        texts = [('A', (0, 0, 2, 1), False), ('B', (1, 0.5, 3, 2), False)]
        self.assertEqual(render.overlaps(texts), [('A', 'B')])

    def test_touching_boxes_do_not(self):
        texts = [('A', (0, 0, 2, 1), False), ('B', (2 - render.MARGIN / 2, 0, 4, 1), False)]
        self.assertEqual(render.overlaps(texts), [])

    def test_separate_boxes_do_not(self):
        self.assertEqual(render.overlaps([('A', (0, 0, 1, 1), False), ('B', (0, 2, 1, 3), False)]), [])

    def test_an_allowed_element_is_skipped(self):
        self.assertEqual(render.overlaps([('A', (0, 0, 2, 1), True), ('B', (1, 0, 3, 1), False)]), [])


class Clipped(unittest.TestCase):
    W, H = 14.2, 8.0

    def test_inside_the_frame(self):
        self.assertFalse(render.clipped((-1, -1, 1, 1), self.W, self.H))

    def test_past_the_right_edge(self):
        self.assertTrue(render.clipped((6, 0, 8, 1), self.W, self.H))

    def test_past_the_top_edge(self):
        self.assertTrue(render.clipped((0, 3.5, 1, 4.5), self.W, self.H))

    def test_wholly_off_screen_waits_to_enter(self):
        self.assertFalse(render.clipped((8, 0, 9, 1), self.W, self.H))


class StreamDefects(unittest.TestCase):
    @staticmethod
    def probe(duration='8.0', *kinds):
        return {'format': {'duration': duration}, 'streams': [{'codec_type': k} for k in kinds or ('video',)]}

    def test_matching_duration_passes(self):
        self.assertEqual(render.stream_defects(self.probe('8.033'), 8.0, 15, 8), [])

    def test_a_short_file_fails(self):
        (d,) = render.stream_defects(self.probe('6.0'), 8.0, 15, 8)
        self.assertIn('differs from the scene timeline', d)

    def test_an_audio_stream_fails(self):
        (d,) = render.stream_defects(self.probe('8.0', 'video', 'audio'), 8.0, 15, 8)
        self.assertIn('audio stream', d)

    def test_no_video_stream_fails(self):
        self.assertIn('expected one video stream, ffprobe found 0',
                      render.stream_defects(self.probe('8.0', 'audio'), 8.0, 15, 8)[0])

    def test_no_duration_fails(self):
        self.assertEqual(render.stream_defects({'streams': [{'codec_type': 'video'}]}, 8.0, 15, 8),
                         ['ffprobe reports no duration'])


class Sample(unittest.TestCase):
    def test_short_lists_are_kept(self):
        self.assertEqual(render.sample([1, 2, 3], limit=5), [1, 2, 3])

    def test_long_lists_are_thinned_keeping_both_ends(self):
        picked = render.sample(list(range(100)), limit=5)
        self.assertEqual((len(picked), picked[0], picked[-1]), (5, 0, 99))


@unittest.skipUnless(HAVE_DEPS or REQUIRE, 'needs ManimCE (run through pydeps.py run), ffmpeg and ffprobe')
class Renders(unittest.TestCase):
    def setUp(self):
        if not HAVE_DEPS:
            self.fail('EXPLAINER_VIDEO_REQUIRE_DEPS=1 but ManimCE, ffmpeg or ffprobe is missing')
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.out = Path(tmp.name)

    def render(self, scene_file, scene_class):
        r = subprocess.run([sys.executable, str(HERE / 'render.py'), str(scene_file), scene_class,
                            '--out', str(self.out)], capture_output=True, text=True)
        report = self.out / 'report.json'
        return r, json.loads(report.read_text(encoding='utf-8')) if report.is_file() else None

    def test_the_sample_renders_a_silent_mp4_that_passes(self):
        r, report = self.render(PLUGIN / 'skills/produce/examples/pythagoras.py', 'Pythagoras')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(report['defects'], [])
        self.assertTrue((self.out / 'Pythagoras.mp4').is_file())
        self.assertEqual(len(report['frames']), report['animations'])
        self.assertTrue(all(Path(f['path']).is_file() for f in report['frames']))

    def test_overlap_and_edge_defects_fail_the_run(self):
        r, report = self.render(HERE / 'fixtures/defects.py', 'Defects')
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        joined = '\n'.join(report['defects'])
        self.assertIn("'first label'", joined)
        self.assertIn("overlaps Text('second label')", joined)
        self.assertIn("Text('cut off at the edge') is cut off by the frame edge", joined)
        self.assertNotIn('stacked on purpose', joined)


if __name__ == '__main__':
    unittest.main()
