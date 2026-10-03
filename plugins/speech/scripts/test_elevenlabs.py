"""elevenlabs.py: the statement before every call, the proceed gate, the egress floor, the key never leaking, and
the mapping from character alignment to word timings. No test reaches the network: the transport is injected, or
urlopen is replaced."""
import base64
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import wave
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import elevenlabs  # noqa: E402

KEY = 'sk-test-key-0123456789'
TEXT = 'Hello, world. Two words!\n'


def reply(text=TEXT.strip(), seconds=0.5):
    """What the with-timestamps endpoint returns: audio plus a start and end for every character, 0.1 s each."""
    chars = list(text)
    return {
        'audio_base64': base64.b64encode(b'\x00\x01' * int(elevenlabs.SAMPLE_RATE * seconds)).decode(),
        'alignment': {
            'characters': chars,
            'character_start_times_seconds': [round(i * 0.1, 3) for i in range(len(chars))],
            'character_end_times_seconds': [round((i + 1) * 0.1, 3) for i in range(len(chars))],
        },
    }


def cli(env_extra=None, *args):
    """Run the script as a user would, with the key and floor variables cleared first."""
    env = {k: v for k, v in os.environ.items() if k not in (elevenlabs.KEY_VAR, elevenlabs.FLOOR_VAR)}
    env.update(env_extra or {})
    with tempfile.TemporaryDirectory() as tmp:
        script = Path(tmp) / 'script.txt'
        script.write_text(TEXT, encoding='utf-8')
        return subprocess.run([sys.executable, str(HERE / 'elevenlabs.py'), '--script', str(script), *args],
                              capture_output=True, text=True, env=env)


class Recorder:
    """A transport that logs when it ran, against the statement the user was shown."""
    def __init__(self, events):
        self.events = events

    def __call__(self, text, voice, model, key):
        self.events.append(('send', text, voice, model, key))
        return reply()


def run(out, proceed=True, env=None, **kw):
    events = []
    env = {elevenlabs.KEY_VAR: KEY} if env is None else env
    record = elevenlabs.narrate(TEXT, Path(out), proceed=proceed, env=env, send=Recorder(events),
                                say=lambda s: events.append(('say', s)), **kw)
    return record, events


class Statement(unittest.TestCase):
    def test_characters_host_and_cost_are_stated_before_the_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, events = run(tmp)
        self.assertEqual([e[0] for e in events], ['say', 'send'])
        said = events[0][1]
        self.assertIn(f'{len(TEXT.strip())} characters', said)
        self.assertIn(elevenlabs.HOST, said)
        self.assertIn('$0.0019', said)   # 24 characters at $0.08 per 1,000 is $0.00192

    def test_the_flash_rate_is_half(self):
        self.assertAlmostEqual(elevenlabs.estimate(1000, 'eleven_flash_v2_5'), 0.04)
        self.assertAlmostEqual(elevenlabs.estimate(1000, 'eleven_multilingual_v2'), 0.08)

    def test_without_proceed_the_estimate_is_shown_and_nothing_is_sent(self):
        with tempfile.TemporaryDirectory() as tmp:
            record, events = run(tmp, proceed=False)
            self.assertIsNone(record)
            self.assertFalse((Path(tmp) / 'narration.wav').exists())
        self.assertEqual([e[0] for e in events], ['say'])

    def test_the_cli_without_proceed_exits_3_and_prints_the_statement(self):
        r = cli({elevenlabs.KEY_VAR: KEY})
        self.assertEqual(r.returncode, 3, r.stderr)
        self.assertIn('characters of text to api.elevenlabs.io', r.stdout)
        self.assertIn('Estimated cost', r.stdout)
        self.assertNotIn(KEY, r.stdout + r.stderr)


class CliGates(unittest.TestCase):

    def test_no_key_is_exit_2_naming_the_variable(self):
        r = cli()
        self.assertEqual(r.returncode, 2)
        self.assertIn(elevenlabs.KEY_VAR, r.stderr)

    def test_the_egress_floor_blocks_with_a_stated_reason(self):
        r = cli({elevenlabs.KEY_VAR: KEY, elevenlabs.FLOOR_VAR: 'local'}, '--proceed')
        self.assertEqual(r.returncode, 4)
        self.assertIn('forbidden', r.stderr)
        self.assertIn(elevenlabs.FLOOR_VAR, r.stderr)
        self.assertNotIn(KEY, r.stdout + r.stderr)

    def test_the_floor_wins_over_a_missing_key(self):
        self.assertEqual(cli({elevenlabs.FLOOR_VAR: 'local'}).returncode, 4)

    def test_an_unrecognized_floor_value_blocks(self):
        self.assertEqual(cli({elevenlabs.KEY_VAR: KEY, elevenlabs.FLOOR_VAR: 'strict'}).returncode, 4)

    def test_floor_any_allows_the_backend(self):
        r = cli({elevenlabs.KEY_VAR: KEY, elevenlabs.FLOOR_VAR: 'any'})
        self.assertEqual(r.returncode, 3)   # reached the estimate; nothing sent without --proceed


class Egress(unittest.TestCase):
    def test_a_blocked_run_never_calls_the_transport(self):
        events = []
        with self.assertRaises(elevenlabs.Blocked):
            elevenlabs.narrate(TEXT, Path('unused'), proceed=True,
                               env={elevenlabs.KEY_VAR: KEY, elevenlabs.FLOOR_VAR: 'local'}, send=Recorder(events),
                               say=events.append)
        self.assertEqual(events, [])


class Outputs(unittest.TestCase):
    def test_writes_a_wav_and_a_timed_word_for_every_script_word(self):
        with tempfile.TemporaryDirectory() as tmp:
            record, _ = run(tmp)
            with wave.open(str(Path(tmp) / 'narration.wav')) as w:
                self.assertEqual((w.getnchannels(), w.getsampwidth(), w.getframerate()), (1, 2, 24000))
                self.assertEqual(w.getnframes(), 12000)
            on_disk = json.loads((Path(tmp) / 'words.json').read_text(encoding='utf-8'))
        self.assertEqual(on_disk, record)
        self.assertEqual([w['word'] for w in record['words']], TEXT.split())
        self.assertEqual((record['backend'], record['audio'], record['duration']), ('elevenlabs', 'narration.wav', 0.5))

    def test_a_word_spans_its_first_to_last_character(self):
        words = elevenlabs.word_times('ab cd', reply('ab cd')['alignment'])
        self.assertEqual(words, [{'word': 'ab', 'start': 0.0, 'end': 0.2}, {'word': 'cd', 'start': 0.3, 'end': 0.5}])

    def test_a_word_missing_from_the_alignment_fails(self):
        with self.assertRaises(elevenlabs.Failed):
            elevenlabs.word_times('ab zz', reply('ab cd')['alignment'])

    def test_a_script_over_the_model_limit_is_refused_before_any_statement(self):
        events = []
        with self.assertRaises(ValueError):
            elevenlabs.narrate('x ' * 6000, Path('unused'), model='eleven_v3', env={elevenlabs.KEY_VAR: KEY},
                               send=Recorder(events), say=events.append)
        self.assertEqual(events, [])

    def test_an_unexpected_response_is_a_failure_not_a_traceback(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(elevenlabs.Failed):
                elevenlabs.narrate(TEXT, Path(tmp), proceed=True, env={elevenlabs.KEY_VAR: KEY},
                                   send=lambda *a: {'oops': 1}, say=lambda s: None)


class KeyHandling(unittest.TestCase):
    def test_the_key_never_reaches_the_statement_or_the_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, events = run(tmp)
            written = ''.join(p.read_text(encoding='utf-8', errors='ignore') for p in Path(tmp).glob('*.json'))
        self.assertNotIn(KEY, events[0][1] + written)

    def test_the_key_travels_in_a_header_only(self):
        seen = []

        def fake(req, timeout):
            seen.append(req)
            return io.BytesIO(json.dumps(reply()).encode())

        with mock.patch('urllib.request.urlopen', fake):
            elevenlabs.request('hi', elevenlabs.DEFAULT_VOICE, elevenlabs.DEFAULT_MODEL, KEY)
        (req,) = seen
        self.assertEqual(req.get_header('Xi-api-key'), KEY)
        self.assertNotIn(KEY, req.full_url)
        self.assertNotIn(KEY, req.data.decode())
        self.assertTrue(req.full_url.startswith(f'https://{elevenlabs.HOST}/'))

    def test_an_http_error_names_the_status_and_not_the_key(self):
        err = urllib.error.HTTPError('https://api.elevenlabs.io/x', 401, 'Unauthorized', {},
                                     io.BytesIO(b'{"detail": {"message": "invalid api key"}}'))
        self.addCleanup(err.close)
        with mock.patch('urllib.request.urlopen', side_effect=err):
            with self.assertRaises(elevenlabs.Failed) as e:
                elevenlabs.request('hi', elevenlabs.DEFAULT_VOICE, elevenlabs.DEFAULT_MODEL, KEY)
        self.assertIn('401', str(e.exception))
        self.assertIn('invalid api key', str(e.exception))
        self.assertNotIn(KEY, str(e.exception))

    def test_a_voice_id_cannot_alter_the_url_path(self):
        with self.assertRaises(ValueError):
            elevenlabs.narrate(TEXT, Path('unused'), voice='abc/../x', env={elevenlabs.KEY_VAR: KEY},
                               say=lambda s: None)


class CheckRow(unittest.TestCase):
    def row(self, env):
        import check
        base = {k: v for k, v in os.environ.items() if k != elevenlabs.KEY_VAR}
        with mock.patch.dict(os.environ, {**base, **env}, clear=True):
            return next(r for r in check.declared_rows() if r[1] == 'elevenlabs-api-key')

    def test_an_unset_optional_key_is_info_and_a_set_one_passes_without_its_value(self):
        self.assertEqual(self.row({})[0], 'INFO')
        status, _, detail = self.row({elevenlabs.KEY_VAR: KEY})
        self.assertEqual(status, 'PASS')
        self.assertNotIn(KEY, detail)


if __name__ == '__main__':
    unittest.main()
