"""Checks for wav.py, tone.py, presets.py, sfx.py, and mml.py.

Sound effects and MML render to WAV with the standard library only.
"""
import contextlib
import io
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import mml  # noqa: E402
import presets  # noqa: E402
import sfx  # noqa: E402
import tone  # noqa: E402
import wav  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]


class AudioTest(unittest.TestCase):
    def test_coin_and_explosion_are_audible_wavs(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp)
            for name in ("coin", "explosion"):
                code = sfx.main(["--preset", name, "--out", str(out / f"{name}.wav")])
                self.assertEqual(code, 0)
                rate, samples = wav.read_wav(out / f"{name}.wav")
                self.assertEqual(rate, 44100)
                self.assertLess(len(samples) / rate, 1.0)
                self.assertGreater(max(abs(sample) for sample in samples), 0.05)

    def test_square_wave_period(self):
        samples = sfx.render_sfx({
            "wave": "square", "freq": 440, "duty": 0.5,
            "attack": 0, "sustain": 0.1, "decay": 0, "volume": 1,
        }, rate=44100)
        # 440 Hz at 44100 is about 100 samples per cycle. Count rising edges.
        edges = 0
        for previous, current in zip(samples, samples[1:]):
            if previous < 0 <= current:
                edges += 1
        self.assertAlmostEqual(edges, 44, delta=2)

    def test_quarter_notes_last_two_seconds_at_120_bpm(self):
        samples = mml.render_mml("t120 o4 l4 c d e f", "gameboy", rate=22050)
        self.assertAlmostEqual(len(samples) / 22050, 2.0, delta=0.02)
        self.assertGreater(max(abs(sample) for sample in samples), 0.05)

    def test_dotted_notes_last_one_and_a_half_beats(self):
        for score in ("t120 c4.", "t120 l4 c."):
            samples = mml.render_mml(score, "gameboy", rate=22050)
            self.assertAlmostEqual(len(samples) / 22050, 0.75, delta=0.01)

    def test_sine_is_not_the_stepped_triangle(self):
        self.assertAlmostEqual(tone.oscillate("sine", 0.25, 0.5), 1.0)
        self.assertNotEqual(tone.oscillate("sine", 0.1, 0.5), tone.oscillate("triangle", 0.1, 0.5))

    def test_bad_params_exit_one_without_traceback(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = str(pathlib.Path(tmp) / "x.wav")
            self.assertEqual(sfx.main(["--params", "{bad", "--out", out]), 1)
            self.assertEqual(sfx.main(["--params", str(pathlib.Path(tmp) / "missing.json"), "--out", out]), 1)

    def test_non_object_or_null_field_params_exit_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = str(pathlib.Path(tmp) / "x.wav")
            for body in ("[]", "null"):
                f = pathlib.Path(tmp) / "p.json"
                f.write_text(body)
                self.assertEqual(sfx.main(["--params", str(f), "--out", out]), 1)
            self.assertEqual(sfx.main(["--params", '{"freq": null}', "--out", out]), 1)

    def test_gameboy_rejects_a_fifth_channel(self):
        score = "c | d | e | f | g"
        with self.assertRaises(ValueError):
            mml.render_mml(score, "gameboy")

    def test_presets_cap_channels_and_noise_but_not_the_voice_mix(self):
        self.assertTrue(mml.render_mml("@1 c | @1 d | @1 e | @1 f", "gameboy", rate=22050))
        for chip in ("gameboy", "nes", "pico-8"):
            with self.assertRaises(ValueError):
                mml.render_mml("c | d | e | f | g", chip)
            with self.assertRaises(ValueError):
                mml.render_mml("n | n", chip)

    def test_stray_closing_bracket_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "unmatched"):
            mml.render_mml("c d ] e f", "gameboy")

    def test_zero_tempo_or_length_exits_one_with_a_message(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "x.wav"
            for score in ("t0 c", "l0 c", "c0"):
                stderr = io.StringIO()
                with contextlib.redirect_stderr(stderr):
                    self.assertEqual(mml.main(["--out", str(out), score]), 1)
                self.assertIn("mml.py: ", stderr.getvalue())
                self.assertIn("greater than zero", stderr.getvalue())
                self.assertFalse(out.exists())

    def test_zero_repeat_count_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "at least 1"):
            mml.render_mml("[c]0", "gameboy")

    def test_repeat_count_defaults_to_two_and_honours_an_explicit_count(self):
        for score in ("[c]", "[c]2"):
            samples = mml.render_mml(f"t120 l4 {score}", "gameboy", rate=22050)
            self.assertAlmostEqual(len(samples) / 22050, 1.0, delta=0.01)
        samples = mml.render_mml("t120 l4 [c]3", "gameboy", rate=22050)
        self.assertAlmostEqual(len(samples) / 22050, 1.5, delta=0.01)

    def test_campfire_score_renders(self):
        score = (ROOT / "examples" / "campfire.mml").read_text()
        samples = mml.render_mml(score, "gameboy", rate=22050)
        self.assertAlmostEqual(len(samples) / 22050, 3.2, delta=0.02)
        self.assertGreater(max(abs(sample) for sample in samples), 0.05)
        self.assertIn("gameboy", presets.CHIPS)


if __name__ == "__main__":
    unittest.main()
