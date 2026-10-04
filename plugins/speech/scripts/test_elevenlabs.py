"""elevenlabs.py: the statement and quota gate before every call, the proceed gate, the egress floor, the cache, the
retry policy, key delivery through vault-exec, the key never leaking, and the mapping from character alignment to word
timings. No test reaches the network: the transport is injected, or urlopen is replaced."""
import base64
import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import wave
from email.message import Message
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import elevenlabs  # noqa: E402

KEY = 'sk-test-key-0123456789'
TEXT = 'Hello, world. Two words!\n'
QUOTA = (9000, 10000)   # 1000 characters left


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


META = {'request_id': 'req-1', 'character_cost': '24'}


class Recorder:
    """A transport that logs when it ran, against the statement the user was shown."""
    def __init__(self, events, body=None):
        self.events, self.body = events, body

    def __call__(self, text, voice, model, settings, key):
        self.events.append(('send', text, voice, model, settings, key))
        return (self.body or reply()), META


def run(out, proceed=True, env=None, quota=None, **kw):
    events = []
    env = {elevenlabs.KEY_VAR: KEY} if env is None else env
    record = elevenlabs.narrate(TEXT, Path(out), proceed=proceed, env=env, send=Recorder(events),
                                quota=quota or (lambda key: QUOTA), say=lambda s: events.append(('say', s)), **kw)
    return record, events


def cli(env_extra=None, *args, vault=None, run_child=None):
    """main() as a user would run it, in process, with the key and floor cleared, the network replaced, and vault-exec
    resolvable only when the test says so."""
    env = {k: v for k, v in os.environ.items() if k not in (elevenlabs.KEY_VAR, elevenlabs.FLOOR_VAR,
                                                             elevenlabs.CHILD_VAR)}
    env.update(env_extra or {})
    out, err = io.StringIO(), io.StringIO()
    with tempfile.TemporaryDirectory() as tmp:
        script = Path(tmp) / 'script.txt'
        script.write_text(TEXT, encoding='utf-8')
        argv = ['--script', str(script), '--data-dir', str(Path(tmp) / 'data'), *args]
        with mock.patch.dict(os.environ, env, clear=True), \
                mock.patch.object(elevenlabs, 'subscription', lambda key: QUOTA), \
                mock.patch.object(elevenlabs, 'request', Recorder([])), \
                mock.patch.object(elevenlabs.shutil, 'which', lambda name: vault), \
                mock.patch.object(elevenlabs.subprocess, 'run', run_child or subprocess.run), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = elevenlabs.main(argv)
    return code, out.getvalue(), err.getvalue()


class Response(io.BytesIO):
    def __init__(self, body, headers=None):
        super().__init__(json.dumps(body).encode())
        self.headers = headers or {}


def http_error(code, body, headers=None):
    msg = Message()
    for k, v in (headers or {}).items():
        msg[k] = v
    return urllib.error.HTTPError('https://api.elevenlabs.io/x', code, 'error', msg, io.BytesIO(json.dumps(body).encode()))


class Statement(unittest.TestCase):
    def test_characters_host_quota_and_pricing_are_stated_before_the_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, events = run(tmp)
        self.assertEqual([e[0] for e in events], ['say', 'send'])
        said = events[0][1]
        self.assertIn(f'{len(TEXT.strip())} characters', said)
        self.assertIn(elevenlabs.HOST, said)
        self.assertIn('1000 of 10000 characters left', said)
        self.assertIn('https://elevenlabs.io/pricing', said)
        self.assertNotIn('$', said)

    def test_a_request_over_the_remaining_quota_is_flagged(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, events = run(tmp, proceed=False, quota=lambda key: (9990, 10000))
        self.assertIn('more than the plan has left', events[0][1])

    def test_an_unreadable_quota_is_stated_and_the_gate_still_holds(self):
        def broken(key):
            raise elevenlabs.Failed('ElevenLabs answered HTTP 401: missing_permissions: user_read')
        with tempfile.TemporaryDirectory() as tmp:
            record, events = run(tmp, proceed=False, quota=broken)
        self.assertIsNone(record)
        self.assertIn('could not be read', events[0][1])
        self.assertEqual([e[0] for e in events], ['say'])

    def test_without_proceed_the_statement_is_shown_and_nothing_is_sent(self):
        with tempfile.TemporaryDirectory() as tmp:
            record, events = run(tmp, proceed=False)
            self.assertIsNone(record)
            self.assertFalse((Path(tmp) / 'narration.wav').exists())
        self.assertEqual([e[0] for e in events], ['say'])

    def test_the_cli_without_proceed_exits_3_and_prints_the_statement(self):
        code, out, err = cli({elevenlabs.KEY_VAR: KEY})
        self.assertEqual(code, 3, err)
        self.assertIn('characters of text to api.elevenlabs.io', out)
        self.assertIn('characters left', out)
        self.assertNotIn(KEY, out + err)

    def test_the_subscription_quota_is_read_from_character_count_and_limit(self):
        body = {'character_count': 1200, 'character_limit': 30000, 'tier': 'creator'}
        with mock.patch('urllib.request.urlopen', lambda req, timeout: Response(body)):
            self.assertEqual(elevenlabs.subscription(KEY), (1200, 30000))

    def test_an_unverified_model_is_named_in_the_statement(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, events = run(tmp, proceed=False, model='eleven_v4')
        self.assertIn('not confirmed on the with-timestamps endpoint', events[0][1])


class CliGates(unittest.TestCase):
    def test_no_key_and_no_vault_is_exit_2_naming_the_variable(self):
        code, _, err = cli()
        self.assertEqual(code, 2)
        self.assertIn(elevenlabs.KEY_VAR, err)

    def test_the_egress_floor_blocks_with_a_stated_reason(self):
        code, out, err = cli({elevenlabs.KEY_VAR: KEY, elevenlabs.FLOOR_VAR: 'local'}, '--proceed')
        self.assertEqual(code, 4)
        self.assertIn('forbidden', err)
        self.assertIn(elevenlabs.FLOOR_VAR, err)
        self.assertNotIn(KEY, out + err)

    def test_the_floor_wins_over_a_missing_key(self):
        self.assertEqual(cli({elevenlabs.FLOOR_VAR: 'local'})[0], 4)

    def test_an_unrecognized_floor_value_blocks(self):
        self.assertEqual(cli({elevenlabs.KEY_VAR: KEY, elevenlabs.FLOOR_VAR: 'strict'})[0], 4)

    def test_floor_any_allows_the_backend(self):
        self.assertEqual(cli({elevenlabs.KEY_VAR: KEY, elevenlabs.FLOOR_VAR: 'any'})[0], 3)

    def test_an_unsubstituted_model_placeholder_means_the_default(self):
        code, out, _ = cli({elevenlabs.KEY_VAR: KEY}, '--model', '${user_config.elevenlabs_model}')
        self.assertEqual(code, 3)
        self.assertIn('model eleven_multilingual_v2', out)


class VaultDelivery(unittest.TestCase):
    def test_without_the_key_the_script_reruns_itself_under_vault_exec(self):
        calls = []

        def child(cmd, env, stderr, text):
            calls.append((cmd, env))
            return subprocess.CompletedProcess(cmd, 3, stderr='')
        code, _, _ = cli(None, '--proceed', vault='/usr/local/bin/vault-exec', run_child=child)
        self.assertEqual(code, 3)
        ((cmd, env),) = calls
        self.assertEqual(cmd[:5], ['/usr/local/bin/vault-exec', '--env', 'ELEVENLABS_API_KEY=elevenlabs-api-key',
                                   '--', sys.executable])
        self.assertEqual(Path(cmd[5]).name, 'elevenlabs.py')
        self.assertIn('--proceed', cmd[6:])
        self.assertEqual(env[elevenlabs.CHILD_VAR], '1')
        self.assertNotIn(elevenlabs.KEY_VAR, env)

    def test_a_set_key_is_used_directly_without_vault_exec(self):
        code, _, _ = cli({elevenlabs.KEY_VAR: KEY}, vault='/usr/local/bin/vault-exec',
                         run_child=lambda *a, **k: self.fail('vault-exec ran although the key was set'))
        self.assertEqual(code, 3)

    def test_vault_exec_exit_1_is_an_actionable_message_not_a_traceback(self):
        def child(cmd, env, stderr, text):
            return subprocess.CompletedProcess(cmd, 1, stderr='vault-exec: unknown secret elevenlabs-api-key\n')
        code, _, err = cli(None, vault='/usr/local/bin/vault-exec', run_child=child)
        self.assertEqual(code, 2)
        self.assertIn('could not supply ELEVENLABS_API_KEY', err)
        self.assertIn('elevenlabs-api-key', err)
        self.assertNotIn('Traceback', err)

    def test_the_childs_own_failure_passes_through_with_its_code(self):
        def child(cmd, env, stderr, text):
            return subprocess.CompletedProcess(cmd, 1, stderr='speech: ElevenLabs answered HTTP 422: bad\n')
        code, _, err = cli(None, vault='/usr/local/bin/vault-exec', run_child=child)
        self.assertEqual(code, 1)
        self.assertIn('HTTP 422', err)
        self.assertNotIn('could not supply', err)

    def test_the_vault_child_never_relaunches_itself(self):
        code, _, err = cli({elevenlabs.CHILD_VAR: '1'}, vault='/usr/local/bin/vault-exec',
                           run_child=lambda *a, **k: self.fail('the child relaunched'))
        self.assertEqual(code, 2)
        self.assertIn(elevenlabs.KEY_VAR, err)


class Cache(unittest.TestCase):
    def test_a_repeated_request_is_served_from_the_cache_without_a_key_or_a_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / 'cache'
            first, events = run(Path(tmp) / 'a', cache=cache)
            self.assertEqual([e[0] for e in events], ['say', 'send'])
            second, events = run(Path(tmp) / 'b', cache=cache, env={})
            self.assertEqual([e[0] for e in events], ['say'])
            self.assertIn('nothing is sent', events[0][1])
            self.assertTrue(second['cached'])
            self.assertEqual(second['words'], first['words'])
            self.assertEqual(second['request_id'], 'req-1')
            self.assertEqual((Path(tmp) / 'b' / 'narration.wav').read_bytes(),
                             (Path(tmp) / 'a' / 'narration.wav').read_bytes())

    def test_any_audio_affecting_change_misses_the_cache(self):
        base = elevenlabs.cache_key('hi', 'v1', 'eleven_v3', {'stability': 0.5})
        variants = {
            'text': elevenlabs.cache_key('hi!', 'v1', 'eleven_v3', {'stability': 0.5}),
            'voice': elevenlabs.cache_key('hi', 'v2', 'eleven_v3', {'stability': 0.5}),
            'model': elevenlabs.cache_key('hi', 'v1', 'eleven_flash_v2_5', {'stability': 0.5}),
            'setting value': elevenlabs.cache_key('hi', 'v1', 'eleven_v3', {'stability': 0.6}),
            'extra setting': elevenlabs.cache_key('hi', 'v1', 'eleven_v3', {'stability': 0.5, 'speed': 1.1}),
        }
        for name, key in variants.items():
            with self.subTest(name):
                self.assertNotEqual(key, base)
        self.assertEqual(base, elevenlabs.cache_key('hi', 'v1', 'eleven_v3', {'stability': 0.5}))

    def test_the_output_format_is_part_of_the_key(self):
        base = elevenlabs.cache_key('hi', 'v1', 'eleven_v3', {})
        with mock.patch.object(elevenlabs, 'OUTPUT_FORMAT', 'pcm_16000'):
            self.assertNotEqual(elevenlabs.cache_key('hi', 'v1', 'eleven_v3', {}), base)

    def test_no_cache_calls_again(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / 'cache'
            run(tmp, cache=cache)
            _, events = run(tmp, cache=cache, refresh=True)
        self.assertEqual([e[0] for e in events], ['say', 'send'])

    def test_the_key_is_never_stored_in_the_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / 'cache'
            run(tmp, cache=cache)
            stored = ''.join(p.read_text(encoding='utf-8') for p in cache.iterdir())
        self.assertTrue(stored)
        self.assertNotIn(KEY, stored)

    def test_a_failed_response_is_not_cached(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / 'cache'
            with self.assertRaises(elevenlabs.Failed):
                elevenlabs.narrate(TEXT, Path(tmp), proceed=True, env={elevenlabs.KEY_VAR: KEY}, cache=cache,
                                   send=Recorder([], {**reply(), 'audio_base64': ''}), quota=lambda k: QUOTA,
                                   say=lambda s: None)
            self.assertFalse(cache.exists() and any(cache.iterdir()))


class Retries(unittest.TestCase):
    def call(self, outcomes):
        """Run request() against a sequence of urlopen outcomes; return (result or exception, opens, sleeps)."""
        opens, sleeps = [], []
        for outcome in outcomes:
            if isinstance(outcome, urllib.error.HTTPError):
                self.addCleanup(outcome.close)

        def fake(req, timeout):
            opens.append(req)
            outcome = outcomes[len(opens) - 1]
            if isinstance(outcome, Exception):
                raise outcome
            return outcome
        with mock.patch('urllib.request.urlopen', fake), mock.patch.object(elevenlabs.time, 'sleep', sleeps.append):
            try:
                result = elevenlabs.request('hi', elevenlabs.DEFAULT_VOICE, elevenlabs.DEFAULT_MODEL, {}, KEY)
            except elevenlabs.Failed as e:
                result = e
        return result, opens, sleeps

    def test_429_is_retried_after_the_retry_after_seconds(self):
        busy = http_error(429, {'detail': {'code': 'rate_limit_exceeded', 'message': 'slow down'}}, {'Retry-After': '7'})
        result, opens, sleeps = self.call([busy, Response(reply('hi'))])
        self.assertEqual(len(opens), 2)
        self.assertEqual(sleeps, [7.0])
        self.assertEqual(result[0], reply('hi'))

    def test_5xx_backs_off_with_growing_jittered_delays_then_gives_up(self):
        errors = [http_error(503, {'detail': {'status': 'service_unavailable', 'message': 'busy'}})
                  for _ in range(elevenlabs.MAX_ATTEMPTS)]
        result, opens, sleeps = self.call(errors)
        self.assertEqual(len(opens), elevenlabs.MAX_ATTEMPTS)
        self.assertEqual(len(sleeps), elevenlabs.MAX_ATTEMPTS - 1)
        for attempt, delay in enumerate(sleeps, 1):   # attempt n waits within [step/2, step], step = 1 s * 2^(n-1)
            step = 2 ** (attempt - 1)
            self.assertTrue(step / 2 <= delay <= step, (attempt, delay))
        self.assertIsInstance(result, elevenlabs.Failed)
        self.assertIn('service_unavailable: busy', str(result))
        self.assertIn('after 4 attempts', str(result))

    def test_401_is_not_retried(self):
        denied = http_error(401, {'detail': {'status': 'invalid_api_key', 'message': 'Invalid API key'}})
        result, opens, sleeps = self.call([denied, Response(reply('hi'))])
        self.assertEqual((len(opens), sleeps), (1, []))
        self.assertIsInstance(result, elevenlabs.Failed)
        self.assertIn('invalid_api_key: Invalid API key', str(result))
        self.assertIn('was rejected', str(result))
        self.assertNotIn(KEY, str(result))

    def test_422_is_not_retried_and_its_validation_list_is_shown(self):
        invalid = http_error(422, {'detail': [{'loc': ['body', 'text'], 'msg': 'field required'}]})
        result, opens, _ = self.call([invalid, Response(reply('hi'))])
        self.assertEqual(len(opens), 1)
        self.assertIn('field required', str(result))

    def test_the_code_field_wins_over_the_legacy_status_field(self):
        both = http_error(400, {'detail': {'code': 'voice_not_found', 'status': 'old', 'message': 'no voice'}})
        result, _, _ = self.call([both])
        self.assertIn('voice_not_found: no voice', str(result))


class Headers(unittest.TestCase):
    def test_request_id_and_character_cost_reach_words_json(self):
        headers = {'request-id': 'abc123', 'character-cost': '24'}
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch('urllib.request.urlopen', lambda req, timeout: Response(reply(), headers)):
            record = elevenlabs.narrate(TEXT, Path(tmp), proceed=True, env={elevenlabs.KEY_VAR: KEY},
                                        quota=lambda k: QUOTA, say=lambda s: None)
            on_disk = json.loads((Path(tmp) / 'words.json').read_text(encoding='utf-8'))
        self.assertEqual((record['request_id'], record['character_cost']), ('abc123', 24))
        self.assertEqual((on_disk['request_id'], on_disk['character_cost']), ('abc123', 24))

    def test_absent_headers_are_recorded_as_null(self):
        with mock.patch('urllib.request.urlopen', lambda req, timeout: Response(reply('hi'))):
            _, meta = elevenlabs.request('hi', elevenlabs.DEFAULT_VOICE, elevenlabs.DEFAULT_MODEL, {}, KEY)
        self.assertEqual(meta, {'request_id': None, 'character_cost': None})


class Egress(unittest.TestCase):
    def test_a_blocked_run_never_calls_the_transport(self):
        events = []
        with self.assertRaises(elevenlabs.Blocked):
            elevenlabs.narrate(TEXT, Path('unused'), proceed=True,
                               env={elevenlabs.KEY_VAR: KEY, elevenlabs.FLOOR_VAR: 'local'}, send=Recorder(events),
                               quota=lambda k: events.append('quota'), say=events.append)
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
        words = elevenlabs.word_times('ab cd', reply('ab cd'))
        self.assertEqual(words, [{'word': 'ab', 'start': 0.0, 'end': 0.2}, {'word': 'cd', 'start': 0.3, 'end': 0.5}])

    def test_multi_character_entries_take_their_entrys_times(self):
        alignment = {'characters': ['ab', ' ', 'cd'], 'character_start_times_seconds': [0.0, 0.2, 0.3],
                     'character_end_times_seconds': [0.2, 0.3, 0.5]}
        words = elevenlabs.word_times('ab cd', {'alignment': alignment})
        self.assertEqual(words, [{'word': 'ab', 'start': 0.0, 'end': 0.2}, {'word': 'cd', 'start': 0.3, 'end': 0.5}])

    def test_dictionary_shaped_entries_are_read(self):
        entries = [{'character': 'a', 'start': 0.0, 'end': 0.1}, {'character': 'b', 'start': 0.1, 'end': 0.2},
                   {'character': ' ', 'start': 0.2, 'end': 0.3}, {'character': 'c', 'start': 0.3, 'end': 0.4}]
        words = elevenlabs.word_times('ab c', {'alignment': entries})
        self.assertEqual(words, [{'word': 'ab', 'start': 0.0, 'end': 0.2}, {'word': 'c', 'start': 0.3, 'end': 0.4}])

    def test_an_alignment_that_repeats_its_text_maps_each_word_to_its_first_occurrence(self):
        words = elevenlabs.word_times('ab cd', reply('ab cd ab cd'))
        self.assertEqual([(w['start'], w['end']) for w in words], [(0.0, 0.2), (0.3, 0.5)])

    def test_normalized_alignment_is_used_when_alignment_is_absent(self):
        body = {'normalized_alignment': reply('ab cd')['alignment']}
        self.assertEqual(elevenlabs.word_times('ab cd', body)[1], {'word': 'cd', 'start': 0.3, 'end': 0.5})

    def test_a_word_missing_from_the_alignment_fails(self):
        with self.assertRaises(elevenlabs.Failed):
            elevenlabs.word_times('ab zz', reply('ab cd'))

    def test_a_truncated_timing_array_fails_instead_of_raising_index_error(self):
        body = reply('ab cd')
        body['alignment']['character_end_times_seconds'].pop()
        with self.assertRaises(elevenlabs.Failed):
            elevenlabs.word_times('ab cd', body)

    def test_an_empty_audio_payload_is_an_error_and_writes_nothing(self):
        for audio in ('', None):
            with self.subTest(audio=audio), tempfile.TemporaryDirectory() as tmp:
                with self.assertRaisesRegex(elevenlabs.Failed, 'empty audio payload'):
                    elevenlabs.narrate(TEXT, Path(tmp), proceed=True, env={elevenlabs.KEY_VAR: KEY},
                                       send=Recorder([], {**reply(), 'audio_base64': audio}),
                                       quota=lambda k: QUOTA, say=lambda s: None)
                self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_malformed_audio_writes_nothing(self):
        bad = {'junk': '!!!!', 'odd': base64.b64encode(b'\x00\x01\x02').decode()}
        for name, audio in bad.items():
            with self.subTest(name), tempfile.TemporaryDirectory() as tmp:
                with self.assertRaises(elevenlabs.Failed):
                    elevenlabs.narrate(TEXT, Path(tmp), proceed=True, env={elevenlabs.KEY_VAR: KEY},
                                       send=Recorder([], {**reply(), 'audio_base64': audio}),
                                       quota=lambda k: QUOTA, say=lambda s: None)
                self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_a_failed_second_write_leaves_the_previous_pair_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            (out / 'narration.wav').write_bytes(b'old audio')
            (out / 'words.json').write_text('old words', encoding='utf-8')
            with mock.patch.object(Path, 'write_text', side_effect=OSError('disk full')):
                with self.assertRaises(OSError):
                    run(out)
            self.assertEqual((out / 'narration.wav').read_bytes(), b'old audio')
            self.assertEqual((out / 'words.json').read_text(encoding='utf-8'), 'old words')
            self.assertEqual(sorted(p.name for p in out.iterdir()), ['narration.wav', 'words.json'])

    def test_a_script_over_the_model_limit_is_refused_before_any_statement(self):
        events = []
        with self.assertRaises(ValueError):
            elevenlabs.narrate('x ' * 6000, Path('unused'), model='eleven_v3', env={elevenlabs.KEY_VAR: KEY},
                               send=Recorder(events), quota=lambda k: QUOTA, say=events.append)
        self.assertEqual(events, [])

    def test_an_unexpected_response_is_a_failure_not_a_traceback(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(elevenlabs.Failed):
                elevenlabs.narrate(TEXT, Path(tmp), proceed=True, env={elevenlabs.KEY_VAR: KEY},
                                   send=lambda *a: ({'oops': 1}, {}), quota=lambda k: QUOTA, say=lambda s: None)

    def test_voice_settings_reach_the_request_body(self):
        seen = []

        def fake(req, timeout):
            seen.append(json.loads(req.data))
            return Response(reply('hi'))
        with mock.patch('urllib.request.urlopen', fake):
            elevenlabs.request('hi', elevenlabs.DEFAULT_VOICE, 'eleven_v3', {'stability': 0.5}, KEY)
        self.assertEqual(seen[0]['voice_settings'], {'stability': 0.5})

    def test_an_unknown_or_non_numeric_setting_is_refused(self):
        for pair in ('loudness=1', 'stability=high', 'stability'):
            with self.subTest(pair), self.assertRaises(ValueError):
                elevenlabs.parse_settings([pair], elevenlabs.DEFAULT_MODEL)


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
            return Response(reply())

        with mock.patch('urllib.request.urlopen', fake):
            elevenlabs.request('hi', elevenlabs.DEFAULT_VOICE, elevenlabs.DEFAULT_MODEL, {}, KEY)
        (req,) = seen
        self.assertEqual(req.get_header('Xi-api-key'), KEY)
        self.assertNotIn(KEY, req.full_url)
        self.assertNotIn(KEY, req.data.decode())
        self.assertTrue(req.full_url.startswith(f'https://{elevenlabs.HOST}/'))

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
