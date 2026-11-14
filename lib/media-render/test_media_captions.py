import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import media_captions as mc

LIMITS = {'max_words': 8, 'min_seconds': 0.834, 'seconds_per_word': 0.3}


def words(*spec):
    """spec: (word, start, end) triples."""
    return [{'word': w, 'start': a, 'end': b} for w, a, b in spec]


class CaptionsTest(unittest.TestCase):
    def test_one_cue_per_sentence_held_for_reading_time(self):
        record = {'words': words(('Hello', 0.0, 0.3), ('there.', 0.3, 0.6), ('Bye.', 2.0, 2.3)), 'duration': 3.0}
        cues = mc.captions(record, [(0, 2), (2, 1)], **LIMITS)
        self.assertEqual(cues, [(0.0, 0.834, 'Hello there.'), (2.0, 2.834, 'Bye.')])

    def test_long_sentence_splits_into_balanced_runs(self):
        spec = [(f'w{i}', i * 0.5, i * 0.5 + 0.4) for i in range(9)]
        spec[-1] = ('w8.', 4.0, 4.4)
        cues = mc.captions({'words': words(*spec), 'duration': 5.0}, [(0, 9)], **LIMITS)
        self.assertEqual([len(t.split()) for _, _, t in cues], [5, 4])

    def test_short_cue_is_a_defect_slow_reading_is_a_flag(self):
        defects, flags = mc.caption_findings([(0.0, 0.5, 'a'), (1.0, 1.9, 'a b c d')], 0.834, 0.3)
        self.assertEqual(len(defects), 1)
        self.assertEqual(len(flags), 1)

    def test_srt_stamps(self):
        self.assertEqual(mc.srt([(0.0, 1.5, 'Hi')]), '1\n00:00:00,000 --> 00:00:01,500\nHi\n\n')

    def test_ass_shows_override_characters_literally_and_raises_margin(self):
        text = mc.ass([(0.0, 1.0, 'a {b} \\N c')], 3840, 2160, 0.24)
        self.assertIn('PlayResX: 3840', text)
        self.assertIn('Dialogue: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,a \\{b\\} \\⁠N c', text)
        margin_v = int(text.split('Style: Default,')[1].split(',')[20])
        self.assertGreaterEqual(margin_v, 2160 // 8)

    @unittest.skipUnless(shutil.which('ffmpeg'), 'ffmpeg is not on PATH')
    def test_two_line_cue_box_stays_inside_the_caption_band(self):
        w, h, band = 3840, 2160, 0.24
        cue = 'a caption long enough that libass has to wrap it onto a second line of words at this font size, even on a 4K frame'
        with tempfile.TemporaryDirectory() as d:
            Path(d, 'c.ass').write_text(mc.ass([(0.0, 1.0, cue)], w, h, band), encoding='utf-8')
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', f'color=gray:s={w}x{h}:d=1',
                            '-vf', 'ass=c.ass', '-frames:v', '1', '-pix_fmt', 'gray', '-f', 'rawvideo', 'f.raw'],
                           cwd=d, check=True)
            raw = Path(d, 'f.raw').read_bytes()
        rows = [y for y in range(h) if raw[y * w:(y + 1) * w].count(raw[0]) != w]
        self.assertGreater(rows[-1] - rows[0], h * 0.075, 'the cue did not wrap to two lines')
        self.assertGreaterEqual(rows[0], h * (1 - band))

    def test_band_must_clear_the_control_bar_margin(self):
        with self.assertRaises(ValueError):
            mc.ass([], 3840, 2160, mc.MARGIN_V)


if __name__ == '__main__':
    unittest.main()
