"""narrate.py: splitting a script into words, packing model calls, turning token durations into word timings, the
exit-2 paths for a missing prerequisite, and (opt-in) a real end-to-end run.

The timing tests drive synthesize() with a fake session that reports known durations, so they need numpy but not
the model. SPEECH_E2E_DATA_DIR names a data directory holding the installed packages and the downloaded model; with
it set and espeak-ng on PATH, EndToEnd narrates a sample script for real and checks every word is timed.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import narrate  # noqa: E402

try:
    import numpy as np
except ImportError:
    np = None

VOCAB = {c: i for i, c in enumerate(' ,.!?;:—…"()“”abcdefghijklmnopqrstuvwxyzˈ', start=1)}


def fake_phonemize(word):
    """Lowercase letters stand in for phonemes; digits become two 'words', as espeak-ng expands a number."""
    return 'tu tu' if word.isdigit() else ''.join(c for c in word.lower() if c.isalpha())


class Plan(unittest.TestCase):
    def test_every_whitespace_token_is_a_word_in_order(self):
        words = narrate.plan('Hello, world. A — 42!', fake_phonemize, VOCAB)
        self.assertEqual([w['word'] for w in words], ['Hello,', 'world.', 'A', '—', '42!'])

    def test_the_timed_span_is_the_phonemes_not_the_punctuation(self):
        (w,) = narrate.plan('(hi),', fake_phonemize, VOCAB)
        self.assertEqual(w['ids'], [VOCAB['('], VOCAB['h'], VOCAB['i'], VOCAB[')'], VOCAB[',']])
        self.assertEqual(w['span'], (1, 3))

    def test_a_punctuation_only_token_spans_its_pause(self):
        (w,) = narrate.plan('—', fake_phonemize, VOCAB)
        self.assertEqual((w['ids'], w['span']), ([VOCAB['—']], (0, 1)))

    def test_sentence_ends_are_marked(self):
        words = narrate.plan('One two. Three?', fake_phonemize, VOCAB)
        self.assertEqual([w['ends_sentence'] for w in words], [False, True, True])


class Chunks(unittest.TestCase):
    def words(self, text):
        return narrate.plan(text, fake_phonemize, VOCAB)

    def test_a_short_script_is_one_call(self):
        self.assertEqual(len(narrate.chunks(self.words('one two. three four.'))), 1)

    def test_calls_break_between_sentences_and_stay_under_the_limit(self):
        words = self.words('aaaa bbbb. cccc dddd. eeee ffff.')
        batches = narrate.chunks(words, limit=12)
        self.assertEqual([[w['word'] for w in b] for b in batches],
                         [['aaaa', 'bbbb.'], ['cccc', 'dddd.'], ['eeee', 'ffff.']])

    def test_a_long_sentence_breaks_between_words(self):
        batches = narrate.chunks(self.words('aaaa bbbb cccc dddd'), limit=9)
        self.assertEqual([len(b) for b in batches], [2, 2])
        self.assertEqual(sum(len(b) for b in batches), 4)

    def test_a_word_longer_than_one_call_is_an_error(self):
        with self.assertRaises(ValueError):
            narrate.chunks(self.words('abcdefghij'), limit=5)


class FakeSession:
    """Reports `frames` frames per input id, pads included, and 10 samples per frame."""
    def __init__(self, frames=2):
        self.frames = frames
        self.calls = []

    def run(self, _outputs, feed):
        n = feed['input_ids'].shape[1]
        self.calls.append(feed['input_ids'][0].tolist())
        durations = np.full((1, n), self.frames, dtype=np.float32)
        return np.zeros((1, n * self.frames * 10), dtype=np.float32), durations


@unittest.skipIf(np is None, 'needs numpy')
class Synthesize(unittest.TestCase):
    def test_word_spans_follow_the_token_durations(self):
        words = narrate.plan('ab, c', fake_phonemize, VOCAB)
        session = FakeSession()
        audio, spans = narrate.synthesize(narrate.chunks(words), session, np.zeros((10, 256)), 1.0, VOCAB[' '])
        # ids: pad a b , space c pad; 20 samples per id
        self.assertEqual(session.calls, [[0, VOCAB['a'], VOCAB['b'], VOCAB[','], VOCAB[' '], VOCAB['c'], 0]])
        self.assertEqual(spans, [(20, 60), (100, 120)])
        self.assertEqual(len(audio), 140)

    def test_later_calls_are_offset_by_the_audio_before_them(self):
        words = narrate.plan('aaaa. bbbb.', fake_phonemize, VOCAB)
        _, spans = narrate.synthesize(narrate.chunks(words, limit=6), FakeSession(), np.zeros((10, 256)), 1.0,
                                      VOCAB[' '])
        self.assertEqual(spans, [(20, 100), (140 + 20, 140 + 100)])


class MissingPrerequisites(unittest.TestCase):
    def test_no_model_files_is_exit_2_naming_setup(self):
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / 'script.txt'
            script.write_text('Hello.', encoding='utf-8')
            r = subprocess.run([sys.executable, str(HERE / 'narrate.py'), '--data-dir', tmp, '--script', str(script)],
                               capture_output=True, text=True)
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn('/speech:setup apply', r.stderr)

    def test_no_espeak_ng_on_path_names_the_check(self):
        real = shutil.which
        narrate.shutil.which = lambda name: None
        try:
            with self.assertRaises(narrate.Missing) as e:
                narrate.espeak_phonemizer('en-us')
        finally:
            narrate.shutil.which = real
        self.assertIn('/speech:check', str(e.exception))
        self.assertIn('never ships it', str(e.exception))

    def test_an_unknown_voice_is_exit_1(self):
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / 'script.txt'
            script.write_text('Hello.', encoding='utf-8')
            r = subprocess.run([sys.executable, str(HERE / 'narrate.py'), '--data-dir', tmp, '--script', str(script),
                                '--voice', 'zz_nobody'], capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn('unknown voice', r.stderr)


@unittest.skipUnless(os.environ.get('SPEECH_E2E_DATA_DIR') and shutil.which('espeak-ng'),
                     'set SPEECH_E2E_DATA_DIR to a data dir with the packages and model, with espeak-ng on PATH')
class EndToEnd(unittest.TestCase):
    def test_a_sample_script_yields_audio_and_a_time_for_every_word(self):
        data = os.environ['SPEECH_E2E_DATA_DIR']
        text = 'Hello, world. Kokoro reads this sample script — and times every word, all 2026 of them.\n'
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / 'script.txt'
            script.write_text(text, encoding='utf-8')
            r = subprocess.run([sys.executable, str(HERE / 'pydeps.py'), 'run', '--data-dir', data, '--',
                                str(HERE / 'narrate.py'), '--data-dir', data, '--script', str(script)],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            record = json.loads((Path(tmp) / 'words.json').read_text(encoding='utf-8'))
            with wave.open(str(Path(tmp) / 'narration.wav')) as w:
                seconds = w.getnframes() / w.getframerate()
        self.assertEqual([w['word'] for w in record['words']], text.split())
        for prev, w in zip([None, *record['words']], record['words']):
            self.assertLessEqual(w['start'], w['end'], w)
            if prev:
                self.assertLessEqual(prev['end'], w['start'], (prev, w))
        self.assertGreater(seconds, 2)
        self.assertLessEqual(record['words'][-1]['end'], seconds)


if __name__ == '__main__':
    unittest.main()
