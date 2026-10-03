"""narration.py and the narrated half of render.py: timing, beat cues, captions, stream checks (standard library
only), and a real ffmpeg mux (skipped without ffmpeg and ffprobe)."""
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _load(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


narration = _load('explainer_video_narration', 'narration.py')
render = _load('explainer_video_render_n', 'render.py')

SCRIPT = 'Take a right triangle.\n\nCall its sides a and b.\n\n\nDone.\n'


def record(script, starts, duration):
    """A words.json record whose paragraph k starts at starts[k]: a word every 0.25 s, each 0.2 s long."""
    words = []
    for para, t in zip(narration.paragraphs(script), starts):
        for i, token in enumerate(para):
            words.append({'word': token, 'start': round(t + 0.25 * i, 3), 'end': round(t + 0.25 * i + 0.2, 3)})
    return {'audio': 'narration.wav', 'duration': duration, 'words': words}


class Timing(unittest.TestCase):
    def test_each_paragraph_starts_at_its_first_word_and_the_list_ends_with_the_narration(self):
        t = narration.timing(SCRIPT, record(SCRIPT, [0.3, 2.0, 4.5], 6.0))
        self.assertEqual(t['starts'], [0.3, 2.0, 4.5, 6.0])
        self.assertEqual(t['beats'], [(0, 4), (4, 6), (10, 1)])

    def test_a_script_that_does_not_match_the_words_raises(self):
        rec = record(SCRIPT, [0.3, 2.0, 4.5], 6.0)
        with self.assertRaisesRegex(ValueError, 'narrate the script again'):
            narration.timing(SCRIPT + '\nExtra words.\n', rec)


class FakeScene:
    def __init__(self, t=0.0):
        self.renderer = type('R', (), {'time': t})()
        self.waits = []

    def wait(self, seconds):
        self.waits.append(round(seconds, 6))
        self.renderer.time += seconds


class Beat(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = Path(tmp.name) / 'timing.json'
        self.path.write_text(json.dumps({'starts': [0.0, 2.0, 5.0]}))
        self.addCleanup(os.environ.pop, narration.ENV, None)

    def test_silent_holds_only_the_given_seconds(self):
        os.environ.pop(narration.ENV, None)
        scene = FakeScene()
        narration.beat(scene, 0)
        narration.beat(scene, 1, hold=1.5)
        self.assertEqual(scene.waits, [1.5])
        self.assertFalse(hasattr(scene, 'beat_marks'))

    def test_narrated_holds_until_the_beat_starts_and_records_the_cue(self):
        os.environ[narration.ENV] = str(self.path)
        scene = FakeScene(t=0.5)
        narration.beat(scene, 1, hold=9)
        self.assertEqual((scene.waits, scene.beat_marks), ([1.5], [(1, 2.0)]))

    def test_an_overrun_beat_does_not_wait_and_records_the_late_time(self):
        os.environ[narration.ENV] = str(self.path)
        scene = FakeScene(t=5.4)
        narration.beat(scene, 2)
        self.assertEqual((scene.waits, scene.beat_marks), ([], [(2, 5.4)]))

    def test_a_beat_past_the_end_raises(self):
        os.environ[narration.ENV] = str(self.path)
        with self.assertRaisesRegex(ValueError, 'beats run 0 to 2'):
            narration.beat(FakeScene(), 3)


class BeatDefects(unittest.TestCase):
    STARTS = [0.0, 2.0, 5.0]

    def test_every_beat_on_time_passes(self):
        self.assertEqual(narration.beat_defects([(0, 0.0), (1, 2.0), (2, 5.03)], self.STARTS, 15), [])

    def test_a_late_beat_names_the_overrun(self):
        (d,) = narration.beat_defects([(0, 0.0), (1, 2.6), (2, 5.0)], self.STARTS, 15)
        self.assertIn('beat 1 narration starts at 2.00 s but the scene reaches it at 2.60 s', d)

    def test_running_past_the_narration_end_is_named(self):
        (d,) = narration.beat_defects([(0, 0.0), (1, 2.0), (2, 6.0)], self.STARTS, 15)
        self.assertIn('the narration ends at 5.00 s', d)

    def test_a_missing_beat_fails(self):
        (d,) = narration.beat_defects([(0, 0.0), (2, 5.0)], self.STARTS, 15)
        self.assertIn('cued beats [0, 2]', d)


class Captions(unittest.TestCase):
    def test_cues_stay_inside_a_beat_and_break_after_a_sentence_or_the_word_limit(self):
        script = 'One two. Three four five\n\nSix'
        rec = record(script, [0.0, 3.0], 4.0)
        cues = narration.captions(rec, narration.timing(script, rec)['beats'], limit=2)
        self.assertEqual([c[2] for c in cues], ['One two.', 'Three four', 'five', 'Six'])
        self.assertEqual(cues[0][:2], (0.0, 0.45))

    def test_a_sentence_end_inside_a_closing_quote_or_bracket_still_breaks_the_caption(self):
        script = '"Done." (Yes.) Next one'
        rec = record(script, [0.0], 2.0)
        cues = narration.captions(rec, narration.timing(script, rec)['beats'])
        self.assertEqual([c[2] for c in cues], ['"Done."', '(Yes.)', 'Next one'])

    def test_srt_numbers_cues_and_formats_hours_minutes_seconds_millis(self):
        self.assertEqual(narration.srt([(0.0, 1.25, 'Hi'), (3661.5, 3662.0, 'Later')]),
                         '1\n00:00:00,000 --> 00:00:01,250\nHi\n\n2\n01:01:01,500 --> 01:01:02,000\nLater\n\n')


class NarratedDefects(unittest.TestCase):
    @staticmethod
    def probe(*streams):
        return {'streams': [{'codec_type': k, 'duration': d} for k, d in streams]}

    def test_one_of_each_stream_at_the_same_length_passes(self):
        p = self.probe(('video', '6.0'), ('audio', '6.02'), ('subtitle', '5.8'))
        self.assertEqual(render.narrated_defects(p, 15, 5), [])

    def test_a_missing_caption_track_fails(self):
        (d,) = render.narrated_defects(self.probe(('video', '6.0'), ('audio', '6.0')), 15, 5)
        self.assertEqual(d, 'expected one subtitle stream, ffprobe found 0')

    def test_video_and_audio_of_different_lengths_fail(self):
        (d,) = render.narrated_defects(self.probe(('video', '8.0'), ('audio', '6.0'), ('subtitle', '6')), 15, 5)
        self.assertIn('differ by more than 0.400 s', d)


@unittest.skipUnless(all(shutil.which(t) for t in ('ffmpeg', 'ffprobe')), 'needs ffmpeg and ffprobe')
class Mux(unittest.TestCase):
    def test_the_muxed_file_has_one_video_audio_and_caption_stream_of_the_same_length(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc=duration=3:size=320x240:rate=15',
                            '-pix_fmt', 'yuv420p', str(d / 'v.mp4')], check=True)
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3',
                            '-ar', '24000', '-ac', '1', str(d / 'n.wav')], check=True)
            (d / 'c.srt').write_text(narration.srt([(0.0, 1.0, 'Take a right triangle.')]), encoding='utf-8')
            render.mux(d / 'v.mp4', d / 'n.wav', d / 'c.srt', d / 'out.mp4')
            self.assertEqual(render.narrated_defects(render.probe_file(d / 'out.mp4'), 15, 1), [])


if __name__ == '__main__':
    unittest.main()
