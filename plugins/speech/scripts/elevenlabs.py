#!/usr/bin/env python3
"""Text to speech with the ElevenLabs backend: a script in, narration.wav and words.json out.

usage: elevenlabs.py --script FILE [--out DIR] [--voice VOICE_ID] [--model MODEL_ID] [--setting NAME=VALUE ...]
                     [--data-dir DIR] [--no-cache] [--proceed]

The text leaves this machine for api.elevenlabs.io, a third-party service that bills per character against the
user's plan. Every run that would call it first prints the character count, the host, the plan's remaining character
quota (GET /v1/user/subscription) and the pricing page. Without --proceed it stops there (exit 3) and sends nothing;
the caller shows that statement to the user and runs again with --proceed once the user agrees.

Cache: a request identical in text, voice, model, voice settings and output format to an earlier one returns the
stored audio and alignment with no API call and no key. Entries live in <data dir>/elevenlabs-cache, where the data
dir is --data-dir, else $CLAUDE_PLUGIN_DATA, else the one speech data folder under ~/.claude/plugins/data; when none
resolves, in $XDG_CACHE_HOME/claude-speech/elevenlabs (default ~/.cache). --no-cache makes a fresh call and replaces
the entry.

Key: the ELEVENLABS_API_KEY environment variable. When it is unset and vault-exec is on PATH, the script runs itself
again as `vault-exec --env ELEVENLABS_API_KEY=elevenlabs-api-key -- <python> elevenlabs.py ...`, so the key exists
only in that one child process. It is never taken from a command line, stored, printed or logged.
SPEECH_EGRESS_FLOOR=local, which an organization sets in managed settings, forbids this backend.

Transient failures (HTTP 429 and 5xx) are retried with jittered exponential backoff, honoring Retry-After; 401, 422
and other client errors are not. words.json records the call's request-id and character-cost response headers.

exit codes: 0 written; 1 any other failure; 2 the key is missing or vault-exec could not supply it; 3 statement shown,
waiting for --proceed; 4 the organization's egress floor forbids the backend.
"""
import argparse
import base64
import email.utils
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import wave
from pathlib import Path

import pydeps

HOST = 'api.elevenlabs.io'
PRICING = 'https://elevenlabs.io/pricing'
KEY_VAR = 'ELEVENLABS_API_KEY'
FLOOR_VAR = 'SPEECH_EGRESS_FLOOR'
VAULT = 'vault-exec'
VAULT_SECRET = 'elevenlabs-api-key'
CHILD_VAR = 'SPEECH_ELEVENLABS_VAULT_CHILD'   # set on the vault-exec child so it never relaunches itself
SAMPLE_RATE = 24000
OUTPUT_FORMAT = f'pcm_{SAMPLE_RATE}'   # raw 16-bit mono little-endian
DEFAULT_VOICE = '21m00Tcm4TlvDq8ikWAM'   # premade voice "Rachel"
DEFAULT_MODEL = 'eleven_v4'
# The voice_settings fields of the request body (VoiceSettingsResponseModel in https://api.elevenlabs.io/openapi.json,
# as of 2026-10-04); recheck when the spec changes that schema.
VOICE_SETTINGS = ('stability', 'similarity_boost', 'style', 'speed', 'use_speaker_boost')
# model -> characters per request, the voice settings the script may send, and whether the with-timestamps endpoint is
# confirmed for it. Limits read from https://elevenlabs.io/docs/overview/models (as of 2026-10-04). That page lists
# eleven_v4 for Text to Dialogue only, but a live with-timestamps call with eleven_v4 succeeded on 2026-10-10. Recheck
# when that page changes a limit or lists eleven_v4 under Text to Speech.
MODELS = {
    'eleven_multilingual_v2': {'limit': 10000, 'settings': VOICE_SETTINGS, 'timestamps': True},
    'eleven_flash_v2_5': {'limit': 40000, 'settings': VOICE_SETTINGS, 'timestamps': True},
    'eleven_v3': {'limit': 5000, 'settings': VOICE_SETTINGS, 'timestamps': True},
    'eleven_v4': {'limit': 10000, 'settings': VOICE_SETTINGS, 'timestamps': True},
}
MAX_ATTEMPTS = 4
BACKOFF_S = 1.0
RETRY_AFTER_CAP_S = 60.0
CACHE_VERSION = 1


class Missing(Exception):
    """The API key is absent: exit 2."""


class Blocked(Exception):
    """The organization's egress floor forbids this backend: exit 4."""


class Failed(Exception):
    """The request or its response was unusable: exit 1."""


def check_floor(env):
    value = env.get(FLOOR_VAR, '').strip().lower()
    if value in ('', 'any'):
        return
    why = 'is "local"' if value == 'local' else f'has the unrecognized value "{value}", which is treated as "local"'
    raise Blocked(f'the ElevenLabs backend is forbidden: {FLOOR_VAR} {why}, so no text may leave this machine for a '
                  f'third-party service. Use the kokoro backend, or ask whoever manages the organization settings '
                  f'to change {FLOOR_VAR}.')


def parse_settings(pairs, model):
    """NAME=VALUE pairs into a voice_settings dict; VALUE is a JSON number or boolean."""
    settings = {}
    for pair in pairs or ():
        name, sep, raw = pair.partition('=')
        if not sep or name not in MODELS[model]['settings']:
            raise ValueError(f'{pair!r} is not NAME=VALUE with NAME one of {", ".join(MODELS[model]["settings"])}')
        try:
            value = json.loads(raw)
        except ValueError:
            value = None
        if isinstance(value, str) or value is None or isinstance(value, (list, dict)):
            raise ValueError(f'{pair!r}: the value must be a number, true or false')
        settings[name] = value
    return settings


def cache_key(text, voice, model, settings):
    """sha256 over every parameter that changes the audio. The key is not one of them."""
    request = {'v': CACHE_VERSION, 'endpoint': 'with-timestamps', 'text': text, 'voice': voice, 'model': model,
               'voice_settings': settings, 'output_format': OUTPUT_FORMAT}
    return hashlib.sha256(json.dumps(request, sort_keys=True, ensure_ascii=False).encode('utf-8')).hexdigest()


def cache_dir(data_flag=None, env=None):
    env = os.environ if env is None else env
    try:
        return pydeps.data_dir(data_flag) / 'elevenlabs-cache'
    except pydeps.Broken:
        return Path(env.get('XDG_CACHE_HOME') or Path.home() / '.cache') / 'claude-speech' / 'elevenlabs'


def error_detail(e):
    """The API's message, from detail.code or the older detail.status plus detail.message, or a validation list."""
    try:
        body = json.loads(e.read())
    except (ValueError, OSError, TypeError):
        return ''
    detail = body.get('detail', body) if isinstance(body, dict) else body
    if isinstance(detail, dict):
        code = detail.get('code') or detail.get('status') or ''
        message = detail.get('message') or ''
        return f'{code}: {message}' if code and message else str(code or message)
    if isinstance(detail, list):
        return '; '.join(str(d.get('msg', d)) if isinstance(d, dict) else str(d) for d in detail)
    return str(detail or '')


def retry_delay(headers, attempt):
    """Retry-After (seconds or an HTTP date) when the API sends one, capped; otherwise exponential with jitter."""
    after = headers.get('Retry-After') if headers else None
    if after:
        try:
            return min(max(float(after), 0.0), RETRY_AFTER_CAP_S)
        except ValueError:
            try:
                return min(max(email.utils.parsedate_to_datetime(after).timestamp() - time.time(), 0.0),
                           RETRY_AFTER_CAP_S)
            except (TypeError, ValueError):
                pass
    step = BACKOFF_S * 2 ** (attempt - 1)
    return step / 2 + random.uniform(0, step / 2)


def call(method, path, key, body=None, attempts=MAX_ATTEMPTS):
    """One API call with retries. Returns (decoded JSON, {request_id, character_cost}). The key goes in a header only."""
    data = None if body is None else json.dumps(body).encode('utf-8')
    for attempt in range(1, attempts + 1):
        req = urllib.request.Request(f'https://{HOST}{path}', data=data, method=method, headers={
            'xi-api-key': key, 'Content-Type': 'application/json', 'Accept': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                headers = getattr(r, 'headers', None) or {}
                return json.loads(r.read()), {'request_id': headers.get('request-id'),
                                              'character_cost': headers.get('character-cost')}
        except urllib.error.HTTPError as e:
            detail = error_detail(e)
            e.close()
            if (e.code == 429 or 500 <= e.code < 600) and attempt < attempts:
                time.sleep(retry_delay(e.headers, attempt))
                continue
            hint = f' ({KEY_VAR} was rejected)' if e.code == 401 else ''
            tries = f' after {attempt} attempts' if attempt > 1 else ''
            raise Failed(f'ElevenLabs answered HTTP {e.code}{hint}{tries}: {detail or e.reason}') from None
        except (urllib.error.URLError, TimeoutError, ValueError) as e:
            raise Failed(f'the request to {HOST} failed: {getattr(e, "reason", e)}') from None


def request(text, voice, model, settings, key):
    body = {'text': text, 'model_id': model}
    if settings:
        body['voice_settings'] = settings
    return call('POST', f'/v1/text-to-speech/{voice}/with-timestamps?output_format={OUTPUT_FORMAT}', key, body)


def subscription(key):
    """(characters used, character limit) for the current billing period."""
    body, _ = call('GET', '/v1/user/subscription', key)
    try:
        return int(body['character_count']), int(body['character_limit'])
    except (KeyError, TypeError, ValueError):
        raise Failed('the subscription response has no character_count and character_limit') from None


def statement(chars, model, voice, quota):
    lines = [f'ElevenLabs is a third-party service. This run would send {chars} characters of text to {HOST} '
             f'(model {model}, voice {voice}).']
    if not MODELS[model]['timestamps']:
        lines.append(f'{model} is not confirmed on the with-timestamps endpoint; ElevenLabs may refuse the call.')
    if isinstance(quota, tuple):
        used, limit = quota
        left = max(limit - used, 0)
        over = ' That is more than the plan has left.' if chars > left else ''
        lines.append(f'Your plan has {left} of {limit} characters left this period; this run counts {chars} '
                     f'characters against it.{over}')
    else:
        lines.append(f'The remaining character quota could not be read: {quota}')
    lines.append(f'ElevenLabs bills characters as credits at a rate set by the model and the plan: {PRICING}')
    return '\n'.join(lines)


def _entry_text(entry):
    return str(entry.get('character', entry.get('char', entry.get('text', '')))) if isinstance(entry, dict) \
        else str(entry)


def _alignment(reply):
    """(characters, starts, ends) from `alignment`, or `normalized_alignment` when that is all there is. Accepts the
    documented arrays-in-a-dict shape and a list of per-character dicts."""
    a = reply.get('alignment') or reply.get('normalized_alignment')
    if isinstance(a, list):
        return ([_entry_text(e) for e in a],
                [e.get('start', e.get('character_start_times_seconds')) for e in a],
                [e.get('end', e.get('character_end_times_seconds')) for e in a])
    return ([_entry_text(c) for c in a['characters']], a['character_start_times_seconds'],
            a['character_end_times_seconds'])


def word_times(text, reply):
    """One {word, start, end} per whitespace-separated token of `text`, from the per-character alignment. An entry
    may hold several characters; each character it holds takes that entry's times."""
    chars, starts, ends = _alignment(reply)
    if len(starts) != len(chars) or len(ends) != len(chars):
        raise Failed('the alignment timing arrays are not the same length as its characters')
    joined, owner = '', []
    for i, c in enumerate(chars):
        joined += c
        owner += [i] * len(c)
    cursor, words = 0, []
    for token in text.split():
        i = joined.find(token, cursor)
        if i < 0:
            raise Failed(f'the alignment does not contain the script word {token!r}')
        cursor = i + len(token)
        words.append({'word': token, 'start': round(starts[owner[i]], 3), 'end': round(ends[owner[cursor - 1]], 3)})
    return words


def write_outputs(text, out, reply, meta, voice, model, settings, cached):
    try:
        audio = reply['audio_base64']
        pcm = base64.b64decode(audio, validate=True) if audio else b''
    except (KeyError, TypeError, ValueError) as e:
        raise Failed(f'the response was not the expected audio and alignment ({type(e).__name__})') from None
    if not pcm:
        raise Failed('the response held an empty audio payload; nothing was written. Run again, or use another model.')
    if len(pcm) % 2:
        raise Failed('the response audio is not 16-bit PCM')
    try:
        words = word_times(text, reply)
    except (KeyError, TypeError, ValueError, AttributeError, IndexError) as e:
        raise Failed(f'the response alignment was unusable ({type(e).__name__})') from None
    duration = round(len(pcm) / 2 / SAMPLE_RATE, 3)
    for w in words:
        w['end'] = min(w['end'], duration)
    cost = meta.get('character_cost')
    record = {
        'audio': 'narration.wav',
        'sample_rate': SAMPLE_RATE,
        'duration': duration,
        'backend': 'elevenlabs',
        'voice': voice,
        'model': model,
        'voice_settings': settings,
        'request_id': meta.get('request_id'),
        'character_cost': int(cost) if str(cost or '').isdigit() else cost,
        'cached': cached,
        'words': words,
    }
    out.mkdir(parents=True, exist_ok=True)
    wav_tmp, json_tmp = out / 'narration.wav.tmp', out / 'words.json.tmp'
    try:
        with wave.open(str(wav_tmp), 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SAMPLE_RATE)
            w.writeframes(pcm)
        json_tmp.write_text(json.dumps(record, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        os.replace(wav_tmp, out / 'narration.wav')
        os.replace(json_tmp, out / 'words.json')
    finally:
        wav_tmp.unlink(missing_ok=True)
        json_tmp.unlink(missing_ok=True)
    return record


def read_cache(entry):
    try:
        stored = json.loads(entry.read_text(encoding='utf-8'))
        return stored['reply'], stored['meta']
    except (OSError, ValueError, KeyError, TypeError):
        return None


def write_cache(entry, reply, meta, say=print):
    """Store a paid reply. Best effort: the narration is already written, so a cache that cannot be written is a
    warning, never a failed run that invites a second paid call. Each writer gets its own temp file, so two sessions
    filling the same key never share one."""
    tmp = None
    try:
        entry.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=entry.name + '.', suffix='.tmp', dir=entry.parent)
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            json.dump({'reply': reply, 'meta': meta}, f)
        os.replace(tmp, entry)
        tmp = None
    except OSError as e:
        say(f'speech: the narration is written, but the cache could not store it ({e}); a repeat of this request '
            'will call the API again.')
    finally:
        if tmp:
            Path(tmp).unlink(missing_ok=True)


def narrate(text, out, voice=DEFAULT_VOICE, model=DEFAULT_MODEL, proceed=False, env=None, send=None, quota=None,
            say=print, settings=(), cache=None, refresh=False):
    env = os.environ if env is None else env
    send, quota = send or request, quota or subscription
    check_floor(env)
    if model not in MODELS:
        raise ValueError(f'unknown model {model!r}; choose one of {", ".join(MODELS)}')
    if not re.fullmatch(r'[A-Za-z0-9]{1,64}', voice):
        raise ValueError(f'{voice!r} is not an ElevenLabs voice id (letters and digits only)')
    settings = parse_settings(settings, model)
    text = text.strip()
    if not text:
        raise ValueError('the script has no words')
    limit = MODELS[model]['limit']
    if len(text) > limit:
        raise ValueError(f'the script is {len(text)} characters; {model} takes at most {limit} per request. Split '
                         'the script, or use eleven_flash_v2_5, which takes more.')
    entry = Path(cache) / f'{cache_key(text, voice, model, settings)}.json' if cache else None
    hit = read_cache(entry) if entry and not refresh and entry.is_file() else None
    if hit:
        say(f'Reusing the stored audio for this exact request ({entry.name}); nothing is sent to {HOST}.')
        return write_outputs(text, out, *hit, voice, model, settings, cached=True)
    key = env.get(KEY_VAR, '').strip()
    if not key:
        raise Missing(f'{KEY_VAR} is not set. Set it in your shell environment, or put {VAULT} on PATH with the '
                      f'"{VAULT_SECRET}" secret mapped (the plugin never stores the key); the kokoro backend needs '
                      'no key.')
    try:
        remaining = quota(key)
    except Failed as e:
        remaining = str(e)
    say(statement(len(text), model, voice, remaining))
    if not proceed:
        return None
    reply, meta = send(text, voice, model, settings, key)
    record = write_outputs(text, out, reply, meta, voice, model, settings, cached=False)
    if entry:
        write_cache(entry, reply, meta, say)
    return record


def via_vault(argv, exe):
    """Run this script again under vault-exec, which puts the key in the child's environment only. vault-exec exits 1
    when it cannot resolve the secret; the child's own failures carry a 'speech: ' line, so a bare 1 is vault-exec's."""
    cmd = [exe, '--env', f'{KEY_VAR}={VAULT_SECRET}', '--', sys.executable, str(Path(__file__).resolve()), *argv]
    try:
        r = subprocess.run(cmd, env={**os.environ, CHILD_VAR: '1'}, stderr=subprocess.PIPE, text=True)
    except OSError as e:
        sys.stderr.write(f'speech: {VAULT} could not be started ({e}). Fix or reinstall {VAULT}, or set {KEY_VAR} in '
                         'your shell environment; the kokoro backend needs no key.\n')
        return 2
    err = r.stderr or ''
    if r.returncode == 1 and not any(line.startswith('speech: ') for line in err.splitlines()):
        sys.stderr.write(f'speech: {VAULT} could not supply {KEY_VAR} from the vault secret "{VAULT_SECRET}" '
                         f'(exit 1). Add that secret to your vault and the {VAULT} map, or set {KEY_VAR} in your '
                         'shell environment; the kokoro backend needs no key.\n')
        if err.strip():
            sys.stderr.write(f'{VAULT}: {err.strip()}\n')
        return 2
    sys.stderr.write(err)
    return r.returncode


def main(argv=None):
    argv = sys.argv[1:] if argv is None else list(argv)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--script', type=Path, required=True, help='UTF-8 text file holding the words to speak')
    ap.add_argument('--out', type=Path, help='folder for narration.wav and words.json (default: the script\'s folder)')
    ap.add_argument('--voice', default=DEFAULT_VOICE, help='ElevenLabs voice id')
    ap.add_argument('--model', default='', help=f'one of {", ".join(MODELS)} (default {DEFAULT_MODEL}; empty or an '
                    'unsubstituted placeholder means the default)')
    ap.add_argument('--setting', action='append', default=[], help=f'voice setting NAME=VALUE, NAME one of '
                    f'{", ".join(VOICE_SETTINGS)}; repeatable')
    ap.add_argument('--data-dir', help='the plugin data directory, which holds the cache')
    ap.add_argument('--no-cache', action='store_true', help='call the API even when an identical request is stored')
    ap.add_argument('--proceed', action='store_true', help='the user has seen the statement and agrees to the call')
    a = ap.parse_args(argv)
    model = a.model.strip() if a.model.strip() and not a.model.startswith('${') else DEFAULT_MODEL
    out = a.out or a.script.parent
    try:
        record = narrate(a.script.read_text(encoding='utf-8'), out, a.voice, model, a.proceed, settings=a.setting,
                         cache=cache_dir(a.data_dir), refresh=a.no_cache)
    except Blocked as e:
        sys.stderr.write(f'speech: {e}\n')
        return 4
    except Missing as e:
        exe = shutil.which(VAULT) if os.environ.get(CHILD_VAR) != '1' else None
        if exe:
            return via_vault(argv, exe)
        sys.stderr.write(f'speech: {e}\n')
        return 2
    except (Failed, ValueError, OSError) as e:
        sys.stderr.write(f'speech: {e}\n')
        return 1
    if record is None:
        print('Nothing was sent. Run again with --proceed once the user agrees to this call.')
        return 3
    print(f'{out / "narration.wav"}  {record["duration"]} s, {len(record["words"])} words')
    print(out / 'words.json')
    return 0


if __name__ == '__main__':
    sys.exit(main())
