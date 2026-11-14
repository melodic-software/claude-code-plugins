"""narrate.py --backend-chain: whole-script fallback across voice backends, retries at 1, 2 and 4 s, the per-call
timeout, the paid gate (exit 3), the secret floor before any online backend (exit 4), no audio at all (exit 5), and
voice.json. Backends are fakes or the `command` backend running local commands; no test reaches a network voice."""
import json
import shlex
import shutil
import sys
import tempfile
import time
import unittest
import wave
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import narrate  # noqa: E402

SCRIPT = 'First line of the script.\nSecond line, with a comma.\n\nThird paragraph — last.'
TOKENS = SCRIPT.split()
WAV_WRITER = ('import sys, wave\n'
              'with wave.open(sys.argv[1], "wb") as w:\n'
              '    w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); w.writeframes(bytes(2 * 24000))\n')


def silent_wav(path, seconds=1.0, rate=24000):
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(2 * int(rate * seconds)))
    return path


class Fake:
    """A backend that records each call and voices the whole script as one second of silence."""

    def __init__(self, fail=0):
        self.calls, self.fail = [], fail

    def __call__(self, script, out_dir, voice, timeout):
        self.calls.append(voice)
        if len(self.calls) <= self.fail:
            raise RuntimeError('fake failure')
        wav = silent_wav(out_dir / 'narration.wav')
        return wav, narrate.estimate_words(script, 1.0)


def backend(name, fn, online=False, paid=False):
    return narrate.Backend(name, fn, default_voice=f'{name}-voice', online=online, paid=paid)


class Chain(unittest.TestCase):
    def setUp(self):
        self.out = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.out, True)
        self.slept = []

    def run_chain(self, chain, backends, **kw):
        kw.setdefault('scan', lambda text: [])
        kw.setdefault('env', {})
        return narrate.run_chain(SCRIPT, self.out, chain, backends, sleep=self.slept.append, **kw)

    def voice_json(self):
        return json.loads((self.out / 'voice.json').read_text(encoding='utf-8'))

    def test_a_command_failing_every_line_hands_the_whole_script_to_the_next_backend(self):
        nxt = Fake()
        backends = {'command': backend('command', narrate.command_backend('false {script} {out}').voice),
                    'kokoro': backend('kokoro', nxt)}
        self.assertEqual(self.run_chain(['command', 'kokoro'], backends), 0)
        record = json.loads((self.out / 'words.json').read_text(encoding='utf-8'))
        self.assertEqual([w['word'] for w in record['words']], TOKENS)
        self.assertEqual(record['backend'], 'kokoro')
        v = self.voice_json()
        self.assertEqual((v['backend'], v['voice']), ('kokoro', 'kokoro-voice'))
        self.assertEqual([(a['backend'], a['status']) for a in v['attempts']],
                         [('command', 'failed')] * 4 + [('kokoro', 'ok')])
        self.assertEqual(self.slept, [1, 2, 4], 'retries wait 1, 2 and 4 seconds')
        self.assertEqual(nxt.calls, ['kokoro-voice'], 'the next backend voices the script once, whole')

    def test_every_backend_failing_exits_5_with_no_audio(self):
        backends = {'a': backend('a', Fake(fail=99)), 'b': backend('b', Fake(fail=99))}
        self.assertEqual(self.run_chain(['a', 'b'], backends), 5)
        self.assertFalse((self.out / 'narration.wav').exists())
        v = self.voice_json()
        self.assertEqual((v['backend'], v['voice']), (None, None))
        self.assertEqual(len(v['attempts']), 8)

    def test_a_hanging_backend_times_out_then_the_next_backend_voices(self):
        if not shutil.which('sleep'):
            self.skipTest('no sleep command')
        backends = {'command': backend('command', narrate.command_backend('sleep 30').voice),
                    'kokoro': backend('kokoro', Fake())}
        start = time.monotonic()
        self.assertEqual(self.run_chain(['command', 'kokoro'], backends, timeout=0.5), 0)
        self.assertLess(time.monotonic() - start, 15, 'four 0.5 s timeouts, not four 30 s sleeps')
        self.assertEqual([a['status'] for a in self.voice_json()['attempts']], ['timeout'] * 4 + ['ok'])

    def test_an_in_process_backend_that_hangs_is_abandoned_at_the_timeout(self):
        def hang(script, out_dir, voice, timeout):
            time.sleep(30)
        backends = {'slow': backend('slow', hang), 'kokoro': backend('kokoro', Fake())}
        start = time.monotonic()
        self.assertEqual(self.run_chain(['slow', 'kokoro'], backends, timeout=0.2), 0)
        self.assertLess(time.monotonic() - start, 15)
        self.assertEqual(self.voice_json()['backend'], 'kokoro')

    def test_a_planted_secret_reaches_no_online_backend(self):
        online = Fake()
        backends = {'edge-tts': backend('edge-tts', online, online=True)}
        token = 'ghp_' + 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8'
        code = narrate.run_chain(f'Read this {token} aloud.', self.out, ['edge-tts'], backends,
                                 sleep=self.slept.append, env={})
        self.assertEqual(code, 4)
        self.assertEqual(online.calls, [], 'no text was sent')
        self.assertEqual(self.voice_json()['attempts'][0]['status'], 'scan')

    def test_a_clean_script_does_reach_the_online_backend(self):
        online = Fake()
        backends = {'edge-tts': backend('edge-tts', online, online=True)}
        code = narrate.run_chain('The cache is warm now.', self.out, ['edge-tts'], backends,
                                 sleep=self.slept.append, env={}, scan=lambda text: [])
        self.assertEqual((code, online.calls), (0, ['edge-tts-voice']))

    def test_the_real_scan_passes_plain_narration(self):
        self.assertEqual(narrate.scan_script('This change adds a retry to the upload step.'), [])

    def test_a_local_backend_runs_without_a_scan(self):
        def boom(text):
            raise AssertionError('scanned for a local backend')
        self.assertEqual(self.run_chain(['kokoro'], {'kokoro': backend('kokoro', Fake())}, scan=boom), 0)

    def test_a_paid_backend_without_the_allowance_exits_3_and_calls_nothing(self):
        paid = Fake()
        backends = {'openai': backend('openai', paid, online=True, paid=True)}
        self.assertEqual(self.run_chain(['openai'], backends), 3)
        self.assertEqual(paid.calls, [])
        self.assertEqual(self.voice_json()['attempts'][0]['status'], 'paid-gate')

    def test_the_allowance_lets_a_paid_backend_voice(self):
        paid = Fake()
        backends = {'openai': backend('openai', paid, online=True, paid=True)}
        self.assertEqual(self.run_chain(['openai'], backends, allow_paid=True), 0)
        self.assertEqual(paid.calls, ['openai-voice'])

    def test_the_egress_floor_skips_online_backends_for_local_ones(self):
        online, local = Fake(), Fake()
        backends = {'edge-tts': backend('edge-tts', online, online=True), 'kokoro': backend('kokoro', local)}
        code = self.run_chain(['edge-tts', 'kokoro'], backends, env={'SPEECH_EGRESS_FLOOR': 'local'})
        self.assertEqual((code, online.calls, local.calls), (0, [], ['kokoro-voice']))
        self.assertEqual(self.voice_json()['attempts'][0]['status'], 'forbidden')

    def test_an_unavailable_backend_is_not_retried(self):
        def missing(script, out_dir, voice, timeout):
            raise narrate.Unavailable('espeak-ng was not found')
        backends = {'kokoro': backend('kokoro', missing), 'b': backend('b', Fake())}
        self.assertEqual(self.run_chain(['kokoro', 'b'], backends), 0)
        self.assertEqual([a['status'] for a in self.voice_json()['attempts']], ['unavailable', 'ok'])
        self.assertEqual(self.slept, [])

    def test_words_that_do_not_cover_the_script_fail_the_attempt(self):
        def partial(script, out_dir, voice, timeout):
            return silent_wav(out_dir / 'narration.wav'), narrate.estimate_words('First line', 1.0)
        backends = {'p': backend('p', partial), 'b': backend('b', Fake())}
        self.assertEqual(self.run_chain(['p', 'b'], backends), 0)
        self.assertEqual(self.voice_json()['backend'], 'b')

    def test_a_voice_per_backend(self):
        a = Fake(fail=99)
        b = Fake()
        backends = {'a': backend('a', a), 'b': backend('b', b)}
        self.assertEqual(self.run_chain(['a', 'b'], backends, voices={'a': 'x', 'b': 'y'}), 0)
        self.assertEqual((set(a.calls), b.calls), ({'x'}, ['y']))


class Cli(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.script = self.dir / 'script.txt'
        self.script.write_text(SCRIPT, encoding='utf-8')
        self.writer = self.dir / 'writer.py'
        self.writer.write_text(WAV_WRITER, encoding='utf-8')

    def main(self, *args):
        with mock.patch.object(narrate, 'RETRY_DELAYS_S', (0, 0, 0)), mock.patch.object(narrate, 'scan_script',
                                                                                        lambda text: []):
            return narrate.main(['--script', str(self.script), '--out', str(self.dir / 'out'), *args])

    def test_a_custom_command_voices_the_script(self):
        template = f'{shlex.quote(sys.executable)} {shlex.quote(str(self.writer))} {{out}}'
        self.assertEqual(self.main('--backend-chain', 'command', '--command', template), 0)
        record = json.loads((self.dir / 'out' / 'words.json').read_text(encoding='utf-8'))
        self.assertEqual([w['word'] for w in record['words']], TOKENS)
        self.assertEqual((record['duration'], record['words'][-1]['end'], record['timing']), (1.0, 1.0, 'estimated'))
        v = json.loads((self.dir / 'out' / 'voice.json').read_text(encoding='utf-8'))
        self.assertEqual(v['backend'], 'command')

    def test_no_backend_producing_audio_exits_5(self):
        self.assertEqual(self.main('--backend-chain', 'command', '--command', 'false'), 5)

    def test_an_unknown_backend_exits_1(self):
        self.assertEqual(self.main('--backend-chain', 'edge-tts,piper'), 1)

    def test_a_voice_without_its_backend_exits_1_in_chain_mode(self):
        self.assertEqual(self.main('--backend-chain', 'edge-tts', '--voice', 'en-US-AndrewNeural'), 1)


class Words(unittest.TestCase):
    def test_estimated_words_share_the_duration_by_length(self):
        # weights len + 1: 'ab' 3, 'cdef' 5, total 8 -> 0..0.375, 0.375..1.0
        self.assertEqual(narrate.estimate_words('ab cdef', 1.0),
                         [{'word': 'ab', 'start': 0.0, 'end': 0.375}, {'word': 'cdef', 'start': 0.375, 'end': 1.0}])

    def test_boundaries_map_onto_every_script_token(self):
        marks = [('Hello', 0.1, 0.5), ('world', 0.6, 1.0), ('A', 1.2, 1.3), ('42', 1.5, 2.0)]
        self.assertEqual(narrate.align_boundaries('Hello, world. A — 42!', marks), [
            {'word': 'Hello,', 'start': 0.1, 'end': 0.5}, {'word': 'world.', 'start': 0.6, 'end': 1.0},
            {'word': 'A', 'start': 1.2, 'end': 1.3}, {'word': '—', 'start': 1.3, 'end': 1.3},
            {'word': '42!', 'start': 1.5, 'end': 2.0}])

    def test_no_boundary_matching_the_script_is_an_error(self):
        with self.assertRaises(RuntimeError):
            narrate.align_boundaries('Hello world', [('Bonjour', 0.0, 1.0)])


if __name__ == '__main__':
    unittest.main()
