"""Sound effects and MML render to WAV with the standard library only."""
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import mml  # noqa: E402
import presets  # noqa: E402
import sfx  # noqa: E402
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

    def test_gameboy_rejects_a_fifth_channel(self):
        score = "c | d | e | f | g"
        with self.assertRaises(ValueError):
            mml.render_mml(score, "gameboy")

    def test_campfire_score_renders(self):
        score = (ROOT / "examples" / "campfire.mml").read_text()
        samples = mml.render_mml(score, "gameboy", rate=22050)
        self.assertAlmostEqual(len(samples) / 22050, 3.2, delta=0.02)
        self.assertGreater(max(abs(sample) for sample in samples), 0.05)
        self.assertIn("gameboy", presets.CHIPS)


if __name__ == "__main__":
    unittest.main()
