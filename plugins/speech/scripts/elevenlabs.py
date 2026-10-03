#!/usr/bin/env python3
"""Text to speech with the ElevenLabs backend: a script in, narration.wav and words.json out.

usage: elevenlabs.py --script FILE [--out DIR] [--voice VOICE_ID] [--model MODEL_ID] [--proceed]

The text leaves this machine for api.elevenlabs.io, a third-party service that bills per character. Every run first
prints the character count, the host and the estimated cost. Without --proceed it stops there (exit 3) and sends
nothing; the caller shows that statement to the user and runs again with --proceed once the user agrees.

The key is read from the ELEVENLABS_API_KEY environment variable only. It is never taken from a command line, stored,
printed or logged. SPEECH_EGRESS_FLOOR=local, which an organization sets in managed settings, forbids this backend.

exit codes: 0 written; 1 any other failure; 2 the key is missing; 3 estimate shown, waiting for --proceed; 4 the
organization's egress floor forbids the backend.
"""
import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.request
import wave
from pathlib import Path

HOST = 'api.elevenlabs.io'
KEY_VAR = 'ELEVENLABS_API_KEY'
FLOOR_VAR = 'SPEECH_EGRESS_FLOOR'
SAMPLE_RATE = 24000          # output_format pcm_24000: raw 16-bit mono little-endian
DEFAULT_VOICE = '21m00Tcm4TlvDq8ikWAM'   # premade voice "Rachel"
DEFAULT_MODEL = 'eleven_multilingual_v2'
# model -> (USD per 1,000 characters, characters per request). Read live from
# https://elevenlabs.io/pricing/api and https://elevenlabs.io/docs/overview/models (as of 2026-10-03); recheck when
# either page changes a rate or a limit.
MODELS = {
    'eleven_multilingual_v2': (0.08, 10000),
    'eleven_flash_v2_5': (0.04, 40000),
    'eleven_v3': (0.08, 5000),
}


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


def estimate(chars, model):
    rate, _ = MODELS[model]
    return chars / 1000 * rate


def statement(chars, model, voice):
    return (f'ElevenLabs is a third-party service. This run would send {chars} characters of text to {HOST} '
            f'(model {model}, voice {voice}). Estimated cost: ${estimate(chars, model):.4f} at '
            f'${MODELS[model][0]:.2f} per 1,000 characters, an estimate from the public API price list; your plan '
            f'bills it as credits.')


def request(text, voice, model, key):
    """POST to the with-timestamps endpoint and return the decoded JSON. The key travels only in the header."""
    url = f'https://{HOST}/v1/text-to-speech/{voice}/with-timestamps?output_format=pcm_{SAMPLE_RATE}'
    req = urllib.request.Request(url, data=json.dumps({'text': text, 'model_id': model}).encode('utf-8'), headers={
        'xi-api-key': key, 'Content-Type': 'application/json', 'Accept': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        detail = ''
        try:
            detail = json.loads(e.read()).get('detail', '')
            detail = detail.get('message', detail) if isinstance(detail, dict) else detail
        except (ValueError, AttributeError):
            pass
        hint = f' ({KEY_VAR} was rejected)' if e.code == 401 else ''
        raise Failed(f'ElevenLabs answered HTTP {e.code}{hint}: {detail or e.reason}') from None
    except (urllib.error.URLError, TimeoutError, ValueError) as e:
        raise Failed(f'the request to {HOST} failed: {getattr(e, "reason", e)}') from None


def word_times(text, alignment):
    """One {word, start, end} per whitespace-separated token of `text`, from the per-character alignment."""
    chars = alignment['characters']
    joined = ''.join(chars)
    if len(joined) != len(chars):
        raise Failed('the alignment holds a multi-character entry, so words cannot be located')
    starts, ends = alignment['character_start_times_seconds'], alignment['character_end_times_seconds']
    if len(starts) != len(chars) or len(ends) != len(chars):
        raise Failed('the alignment timing arrays are not the same length as its characters')
    cursor, words = 0, []
    for token in text.split():
        i = joined.find(token, cursor)
        if i < 0:
            raise Failed(f'the alignment does not contain the script word {token!r}')
        cursor = i + len(token)
        words.append({'word': token, 'start': round(starts[i], 3), 'end': round(ends[cursor - 1], 3)})
    return words


def narrate(text, out, voice=DEFAULT_VOICE, model=DEFAULT_MODEL, proceed=False, env=None, send=request,
            say=print):
    env = os.environ if env is None else env
    check_floor(env)
    if model not in MODELS:
        raise ValueError(f'unknown model {model!r}; choose one of {", ".join(MODELS)}')
    if not re.fullmatch(r'[A-Za-z0-9]{1,64}', voice):
        raise ValueError(f'{voice!r} is not an ElevenLabs voice id (letters and digits only)')
    text = text.strip()
    if not text:
        raise ValueError('the script has no words')
    if len(text) > MODELS[model][1]:
        raise ValueError(f'the script is {len(text)} characters; {model} takes at most {MODELS[model][1]} per '
                         'request. Split the script, or use eleven_flash_v2_5, which takes 40000.')
    key = env.get(KEY_VAR, '').strip()
    if not key:
        raise Missing(f'{KEY_VAR} is not set. Set it in your shell environment (the plugin never stores it); the '
                      'kokoro backend needs no key.')
    say(statement(len(text), model, voice))
    if not proceed:
        return None
    reply = send(text, voice, model, key)
    try:
        pcm = base64.b64decode(reply['audio_base64'], validate=True)
        words = word_times(text, reply['alignment'])
    except (KeyError, TypeError, ValueError) as e:
        raise Failed(f'the response was not the expected audio and alignment ({type(e).__name__})') from None
    if not pcm or len(pcm) % 2:
        raise Failed('the response held no 16-bit audio')
    out.mkdir(parents=True, exist_ok=True)
    wav_tmp, json_tmp = out / 'narration.wav.tmp', out / 'words.json.tmp'
    record = {
        'audio': 'narration.wav',
        'sample_rate': SAMPLE_RATE,
        'duration': round(len(pcm) / 2 / SAMPLE_RATE, 3),
        'backend': 'elevenlabs',
        'voice': voice,
        'model': model,
        'words': words,
    }
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


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--script', type=Path, required=True, help='UTF-8 text file holding the words to speak')
    ap.add_argument('--out', type=Path, help='folder for narration.wav and words.json (default: the script\'s folder)')
    ap.add_argument('--voice', default=DEFAULT_VOICE, help='ElevenLabs voice id')
    ap.add_argument('--model', default=DEFAULT_MODEL, choices=list(MODELS))
    ap.add_argument('--proceed', action='store_true', help='the user has seen the estimate and agrees to the call')
    a = ap.parse_args(argv)
    out = a.out or a.script.parent
    try:
        record = narrate(a.script.read_text(encoding='utf-8'), out, a.voice, a.model, a.proceed)
    except Blocked as e:
        sys.stderr.write(f'speech: {e}\n')
        return 4
    except Missing as e:
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
