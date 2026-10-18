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
        self.assertEqual(cues[0][:2], (0.0, 0.5))   # held past its last word up to the next cue's start

    def test_a_sentence_end_inside_a_closing_quote_or_bracket_still_breaks_the_caption(self):
        script = '"Done." (Yes.) Next one'
        rec = record(script, [0.0], 2.0)
        # no minimum, so the 0.25 s words are not joined and only the sentence breaks show
        cues = narration.captions(rec, narration.timing(script, rec)['beats'], min_seconds=0)
        self.assertEqual([c[2] for c in cues], ['"Done."', '(Yes.)', 'Next one'])

    def test_a_sentence_one_word_over_the_limit_splits_evenly_instead_of_leaving_an_orphan_word(self):
        script = 'Each claim carries its sources and a confidence label.'
        rec = record(script, [0.0], 3.0)
        cues = narration.captions(rec, narration.timing(script, rec)['beats'], limit=8)
        self.assertEqual([c[2] for c in cues], ['Each claim carries its sources', 'and a confidence label.'])

    def test_a_short_cue_stays_up_for_the_minimum_when_a_pause_follows_it(self):
        script = 'Done.\n\nNext part'
        rec = record(script, [0.0, 3.0], 4.0)   # 'Done.' spoken 0.0-0.2 s, then 2.8 s of pause
        (first, *_) = narration.captions(rec, narration.timing(script, rec)['beats'], min_seconds=0.834)
        self.assertEqual(first, (0.0, 0.834, 'Done.'))

    def test_a_cue_too_short_to_hold_joins_its_neighbor_in_the_beat(self):
        script = 'Yes. Then the rest follows'
        rec = record(script, [0.0], 2.0)   # 'Yes.' has 0.25 s before 'Then' starts
        cues = narration.captions(rec, narration.timing(script, rec)['beats'], limit=8)
        self.assertEqual([c[2] for c in cues], ['Yes. Then the rest follows'])

    def test_findings_fail_a_cue_under_the_minimum_and_flag_one_read_too_fast(self):
        defects, flags = narration.caption_findings(
            [(0.0, 0.5, 'Done.'), (1.0, 3.0, 'one two three four five six seven eight'), (4.0, 6.0, 'Fine here')],
            min_seconds=0.834, per_word=0.3)
        self.assertEqual(len(defects), 1)
        self.assertIn("caption 1 'Done.' is on screen 0.50 s", defects[0])
        self.assertEqual(len(flags), 1)
        self.assertIn('caption 2', flags[0])
        self.assertIn('8 words in 2.00 s', flags[0])

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

    def test_quiet_narration_is_normalized_to_the_target_and_measured_again_after_the_mux(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc=duration=6:size=320x240:rate=15',
                            '-pix_fmt', 'yuv420p', str(d / 'v.mp4')], check=True)
            # a tone 22 dB under full scale, far under the narrated target
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=6',
                            '-af', 'volume=-22dB', '-ar', '24000', '-ac', '1', str(d / 'n.wav')], check=True)
            (d / 'c.srt').write_text(narration.srt([(0.0, 1.0, 'Take a right triangle.')]), encoding='utf-8')
            source = render.measure_loudness(d / 'n.wav')
            self.assertTrue(render.loudness_defects(source), source)   # too quiet before normalizing
            mode = render.normalize(d / 'n.wav', d / 'norm.wav', source)
            self.assertIn(mode, ('linear', 'dynamic'))
            render.mux(d / 'v.mp4', d / 'norm.wav', d / 'c.srt', d / 'out.mp4')
            delivered = render.measure_loudness(d / 'out.mp4')
            self.assertEqual(render.loudness_defects(delivered), [], delivered)
            self.assertEqual(render.narrated_defects(render.probe_file(d / 'out.mp4'), 15, 1), [])


class LoudnessDefects(unittest.TestCase):
    TARGET = {'integrated_lufs': -16.0, 'tolerance_lu': 1.0, 'true_peak_max_dbtp': -1.0}

    def test_on_target_under_the_ceiling_passes(self):
        self.assertEqual(render.loudness_defects({'input_i': '-16.4', 'input_tp': '-1.9'}, self.TARGET), [])

    def test_too_quiet_fails(self):
        (d,) = render.loudness_defects({'input_i': '-22.2', 'input_tp': '-4.8'}, self.TARGET)
        self.assertIn('-22.2 LUFS is more than 1.0 LU from the -16.0 LUFS target', d)

    def test_a_peak_over_the_ceiling_fails_even_on_target(self):
        (d,) = render.loudness_defects({'input_i': '-16.0', 'input_tp': '-0.9'}, self.TARGET)
        self.assertIn('true peak -0.9 dBTP is over the -1.0 dBTP ceiling', d)

    def test_the_shipped_target_is_narrated_level_with_a_one_dbtp_ceiling(self):
        self.assertEqual((render.LOUDNESS['integrated_lufs'], render.LOUDNESS['true_peak_max_dbtp']), (-16.0, -1.0))
        self.assertLess(render.LOUDNESS['limiter_true_peak_dbtp'], render.LOUDNESS['true_peak_max_dbtp'])


class Stills(unittest.TestCase):
    LOG = ('[freezedetect @ 0x1] lavfi.freezedetect.freeze_start: 2.5\n'
           '[freezedetect @ 0x1] lavfi.freezedetect.freeze_duration: 4.1\n'
           '[freezedetect @ 0x1] lavfi.freezedetect.freeze_end: 6.6\n'
           '[freezedetect @ 0x1] lavfi.freezedetect.freeze_start: 9.0\n')

    def test_spans_are_read_from_the_log_and_an_open_one_ends_with_the_file(self):
        self.assertEqual(render.parse_freezes(self.LOG, 12.0), [(2.5, 6.6), (9.0, 12.0)])

    def test_each_span_counts_the_words_spoken_while_the_picture_holds(self):
        words = [{'word': w, 'start': t} for w, t in (('a', 1.0), ('b', 3.0), ('c', 6.0), ('d', 7.0))]
        self.assertEqual(render.stills_report([(2.5, 6.6)], words),
                         [{'start': 2.5, 'end': 6.6, 'seconds': 4.1, 'words': 2}])

    def test_silent_spans_carry_no_word_count(self):
        self.assertEqual(render.stills_report([(0.0, 3.0)]), [{'start': 0.0, 'end': 3.0, 'seconds': 3.0}])


@unittest.skipUnless(all(shutil.which(t) for t in ('ffmpeg', 'ffprobe')), 'needs ffmpeg and ffprobe')
class StillSpans(unittest.TestCase):
    def test_a_held_picture_is_reported_and_moving_picture_is_not(self):
        with tempfile.TemporaryDirectory() as tmp:
            v = Path(tmp) / 'v.mp4'
            # 2 s of moving test pattern, then its last frame held 4 s
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc=duration=2:size=320x240:rate=15',
                            '-vf', 'tpad=stop_mode=clone:stop_duration=4', '-pix_fmt', 'yuv420p', str(v)], check=True)
            (span,) = render.still_spans(v, 6.0, {'min_seconds': 3.0, 'noise': 0.003})
            self.assertAlmostEqual(span[0], 2.0, delta=0.2)
            self.assertAlmostEqual(span[1], 6.0, delta=0.2)


if __name__ == '__main__':
    unittest.main()
