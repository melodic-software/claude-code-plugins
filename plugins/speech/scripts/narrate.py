#!/usr/bin/env python3
"""Text to speech: a script in, narration.wav and words.json out, from kokoro or from a chain of voice backends.

usage: pydeps.py run --data-dir DIR -- narrate.py --data-dir DIR [--model-dir DIR] --script FILE [--out DIR]
       [--voice NAME] [--speed X]
       pydeps.py run --data-dir DIR -- narrate.py ... --backend-chain NAME[,NAME...] [--voice BACKEND:VOICE]...
       [--command TEMPLATE] [--timeout S] [--allow-paid-voice]

Every whitespace-separated token of the script is a word in words.json, with a start and end in seconds.

Without --backend-chain the kokoro backend runs alone, as it always has. Its timings come from the model itself: the
Kokoro-82M export in kokoro-assets.json reports how many frames each input token lasts, and a word spans its own
tokens. espeak-ng, installed by the user, turns each word into the phonemes Kokoro reads; the plugin never ships it.
exit codes: 0 written; 2 a prerequisite is missing (espeak-ng, the model files, the Python packages), named with
its remedy; 1 any other failure.

With --backend-chain the backends are tried in order and one of them voices the whole script, so a video never mixes
voices. A failed call (a non-zero exit, a network error) is retried after 1, 2 and 4 seconds, then the whole script
goes to the next backend. A call that passes its hard timeout (--timeout), or a backend that cannot run at all (a
missing package, model or key), goes to the next backend at once. voice.json records {backend, voice, attempts[]}; backend and voice are null when nothing was voiced.
  edge-tts    online, free; Microsoft's read-aloud endpoint; default voice en-US-AndrewNeural; needs ffmpeg
  kokoro      local; the backend above, with --speed, --data-dir and --model-dir
  openai      online, paid; OPENAI_API_KEY; default voice marin; word times estimated
  elevenlabs  online, paid; ELEVENLABS_API_KEY in the environment (no vault-exec relaunch in a chain)
  command     --command TEMPLATE run without a shell, {script} the script file, {out} the WAV to write; its egress
              is unknown, so it counts as online; word times estimated
Before the first online backend the script passes the secret and machine-data floor (media_scan.py); nothing lowers it.
SPEECH_EGRESS_FLOOR=local skips every online backend. A paid backend runs only with --allow-paid-voice, which the
caller passes for an attended run the user approved or when allow_unattended_paid_voice is set.
exit codes: 0 written; 1 a usage error; 3 the chain reached a paid backend without --allow-paid-voice, nothing sent;
4 the scan found a secret or machine data, nothing sent; 5 no backend produced audio.
"""
import argparse
import asyncio
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import assets
import pydeps

SAMPLE_RATE = 24000
# fp32: on a 32-thread x86 CPU it ran at 0.37 x real time, the int8 export at 2.62 and fp16 at 0.46 (2026-10-02)
MODEL = 'onnx/model.onnx'
MAX_TOKENS = 500             # the model reads 512 ids, two of them pads; each voice holds 510 style rows
DEFAULT_VOICE = 'af_heart'
LANGS = {'a': 'en-us', 'b': 'en-gb'}   # a voice name's first letter is its accent
SENTENCE_END = set('.!?…')
SPACE = ' '


class Missing(Exception):
    """A prerequisite is absent: exit 2 with the remedy."""


def espeak_phonemizer(lang):
    """A cached word -> IPA function backed by the user's espeak-ng. One process per distinct word, so each word's
    phonemes are known exactly; phonemizing a whole sentence would merge function words ('of the' -> one token)."""
    exe = shutil.which('espeak-ng')
    if not exe:
        raise Missing('espeak-ng was not found on PATH, so the kokoro backend cannot phonemize the script. '
                      'Install it yourself (it is GPL-3.0; this plugin never ships it): run '
                      f'python3 "{Path(__file__).with_name("check.py")}" for the install line for this system.')
    cache = {}

    def phonemize(word):
        if word not in cache:
            r = subprocess.run([exe, '-q', '--ipa', '-v', lang], input=word, capture_output=True, text=True,
                               encoding='utf-8', check=True)
            cache[word] = ' '.join(r.stdout.split())
        return cache[word]
    return phonemize


def plan(text, phonemize, vocab):
    """Each script token with the model ids it contributes: leading punctuation, its phonemes, trailing punctuation.
    `core` is the slice of `ids` the word's timing covers: its phonemes, or its punctuation when it has none."""
    words = []
    for token in text.split():
        lead, body, trail = re.fullmatch(r'(\W*)(.*?)(\W*)', token).groups()
        if not body:   # all punctuation, such as an em dash
            lead, trail = token, ''
        pre = [vocab[c] for c in lead if c in vocab]
        core = [vocab[c] for c in (phonemize(body) if body else '') if c in vocab]
        post = [vocab[c] for c in trail if c in vocab]
        ids = pre + core + post
        span = (len(pre), len(pre) + len(core)) if core else (0, len(ids))
        words.append({'word': token, 'ids': ids, 'span': span, 'ends_sentence': token[-1] in SENTENCE_END})
    return words


def chunks(words, limit=MAX_TOKENS):
    """Pack words into model calls of at most `limit` ids, breaking after a sentence when the next would not fit,
    and between words inside a sentence too long for one call."""
    sentences, current = [], []
    for w in words:
        current.append(w)
        if w['ends_sentence']:
            sentences.append(current)
            current = []
    if current:
        sentences.append(current)

    def cost(ws):
        return sum(len(w['ids']) for w in ws) + max(len(ws) - 1, 0)

    out, batch = [], []
    for sentence in sentences:
        if batch and cost(batch + sentence) > limit:
            out.append(batch)
            batch = []
        for w in sentence:
            if batch and cost(batch + [w]) > limit:
                out.append(batch)
                batch = []
            if len(w['ids']) > limit:
                raise ValueError(f'the word {w["word"]!r} alone is longer than one model call ({limit} phonemes)')
            batch.append(w)
    if batch:
        out.append(batch)
    return out


def token_edges(durations, samples):
    """Sample offset of every token boundary, the leading pad included, scaled so the last edge is the audio's end."""
    import numpy as np
    frames = np.concatenate([[0.0], np.cumsum(np.asarray(durations, dtype=np.float64))])
    return np.round(frames * (samples / frames[-1])).astype(np.int64)


def synthesize(batches, session, style_rows, speed, space_id):
    """Run the model per batch. Returns the float32 audio and, per word, its (start, end) sample offsets."""
    import numpy as np
    audio, spans, offset = [], [], 0
    for batch in batches:
        ids, starts = [], []
        for i, w in enumerate(batch):
            if i:
                ids.append(space_id)
            starts.append(len(ids))
            ids.extend(w['ids'])
        style = style_rows[min(len(ids), len(style_rows) - 1)]
        waveform, durations = session.run(None, {
            'input_ids': np.array([[0, *ids, 0]], dtype=np.int64),
            'style': np.asarray(style, dtype=np.float32).reshape(1, -1),
            'speed': np.array([speed], dtype=np.float32),
        })
        waveform = np.asarray(waveform, dtype=np.float32).ravel()
        edges = token_edges(np.asarray(durations).ravel(), len(waveform))
        for w, start in zip(batch, starts):
            a, b = w['span']
            # +1 skips the leading pad: id position p spans edges[p + 1] .. edges[p + 2]
            spans.append((offset + int(edges[start + a + 1]), offset + int(edges[start + b + 1])))
        audio.append(waveform)
        offset += len(waveform)
    return (np.concatenate(audio) if audio else np.zeros(0, dtype=np.float32)), spans


def write_wav(path, audio):
    import numpy as np
    pcm = (np.clip(audio, -1.0, 1.0) * 32767).astype('<i2')
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm.tobytes())


def narrate(text, out, data, voice=DEFAULT_VOICE, speed=1.0, phonemize=None, model_dir=None):
    m = assets.manifest()
    known = assets.voices(m)
    if voice not in known:
        raise ValueError(f'unknown voice {voice!r}; choose one of {", ".join(known)}')
    if not 0.5 <= speed <= 2.0:
        raise ValueError(f'speed must be between 0.5 and 2.0, got {speed}')
    gaps = assets.missing(data, m, model_dir)
    if gaps:
        raise Missing(f'the Kokoro model files are not downloaded ({len(gaps)} missing, first {gaps[0]}). '
                      'Run /speech:setup apply install-model, which downloads them from the pinned revision.')
    try:
        import numpy as np
        import onnxruntime as rt
    except ImportError as e:
        raise Missing(f'the Python packages do not import ({e}); start a new session, whose SessionStart hook '
                      f'installs them, or run the repair line that python3 "{Path(__file__).with_name("check.py")}" prints.') from e
    root = assets.assets_dir(data, m, model_dir)
    vocab = json.loads((root / 'tokenizer.json').read_text(encoding='utf-8'))['model']['vocab']
    phonemize = phonemize or espeak_phonemizer(LANGS[voice[0]])
    words = plan(text, phonemize, vocab)
    if not words:
        raise ValueError('the script has no words')
    rt.set_default_logger_severity(3)
    session = rt.InferenceSession(str(root / MODEL), providers=['CPUExecutionProvider'])
    style_rows = np.fromfile(root / 'voices' / f'{voice}.bin', dtype=np.float32).reshape(-1, 256)
    audio, spans = synthesize(chunks(words), session, style_rows, speed, vocab[SPACE])

    out.mkdir(parents=True, exist_ok=True)
    write_wav(out / 'narration.wav', audio)
    record = {
        'audio': 'narration.wav',
        'sample_rate': SAMPLE_RATE,
        'duration': round(len(audio) / SAMPLE_RATE, 3),
        'backend': 'kokoro',
        'voice': voice,
        'speed': speed,
        'words': [{'word': w['word'], 'start': round(a / SAMPLE_RATE, 3), 'end': round(b / SAMPLE_RATE, 3)}
                  for w, (a, b) in zip(words, spans)],
    }
    (out / 'words.json').write_text(json.dumps(record, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    return record


RETRY_DELAYS_S = (1, 2, 4)
DEFAULT_TIMEOUT_S = 120.0
TIMEOUT_GRACE_S = 1.0        # the adapter's own timeout reports first; the thread join is the backstop
FLOOR_VAR = 'SPEECH_EGRESS_FLOOR'
EDGE_VOICE = 'en-US-AndrewNeural'
OPENAI_HOST, OPENAI_MODEL, OPENAI_VOICE = 'api.openai.com', 'gpt-4o-mini-tts', 'marin'
ERROR_CHARS = 300
EXIT_PAID, EXIT_FLOOR, EXIT_NO_AUDIO = 3, 4, 5


class Unavailable(Exception):
    """The backend cannot run here at all (package, model, key, voice); retrying cannot help."""


class CallTimeout(Exception):
    """The call passed its timeout."""


@dataclass(frozen=True)
class Backend:
    name: str
    voice: Callable    # (script, out_dir, voice, timeout) -> (wav path, [{word, start, end}])
    default_voice: str = ''
    online: bool = True
    paid: bool = False
    timed: bool = False   # the words come from the voice itself, not an estimate


def estimate_words(text, duration):
    """Word times for a voice that reports none: the duration shared out by each token's length plus one."""
    tokens = text.split()
    total = sum(len(t) + 1 for t in tokens) or 1
    words, at = [], 0
    for t in tokens:
        start = at
        at += len(t) + 1
        words.append({'word': t, 'start': round(duration * start / total, 3), 'end': round(duration * at / total, 3)})
    return words


def align_boundaries(text, marks):
    """One {word, start, end} per whitespace token of `text` from (spoken text, start, end) marks in speaking order.
    A token spans the marks found inside it; a token with none, such as a dash, sits at the previous token's end."""
    lower, placed, cursor = text.lower(), [], 0
    for said, start, end in marks:
        said = said.strip().lower()
        i = lower.find(said, cursor) if said else -1
        if i >= 0:
            placed.append((i, i + len(said), start, end))
            cursor = i + len(said)
    if not placed:
        raise RuntimeError('none of the word timings the voice returned match the script')
    words, prev = [], 0.0
    for m in re.finditer(r'\S+', text):
        hit = [(s, e) for i, j, s, e in placed if i < m.end() and j > m.start()]
        start, end = (min(h[0] for h in hit), max(h[1] for h in hit)) if hit else (prev, prev)
        words.append({'word': m.group(), 'start': round(start, 3), 'end': round(end, 3)})
        prev = end
    return words


def bounded(fn, timeout):
    """fn() on a daemon thread, abandoned after the timeout: an in-process call that hangs cannot hold the chain."""
    box = {}

    def run():
        try:
            box['value'] = fn()
        except BaseException as e:   # re-raised on the caller's thread below
            box['error'] = e
    t = threading.Thread(target=run, daemon=True)
    t.start()
    t.join(timeout + TIMEOUT_GRACE_S)
    if t.is_alive():
        raise CallTimeout(f'no answer within {timeout:g} s')
    if 'error' in box:
        raise box['error']
    return box['value']


def run_command(argv, timeout):
    """Run argv with no shell; on timeout kill its whole process group, so a child it started cannot hold it open."""
    posix = os.name == 'posix'
    try:
        p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                             start_new_session=posix)
    except OSError as e:
        raise Unavailable(f'{argv[0]} could not be started ({e})') from None
    try:
        _, err = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        if posix:
            os.killpg(p.pid, signal.SIGKILL)
        else:
            p.kill()
        p.communicate()
        raise CallTimeout(f'{Path(argv[0]).name} passed {timeout:g} s and was stopped') from None
    if p.returncode:
        tail = err.decode('utf-8', 'replace').strip()[-ERROR_CHARS:]
        raise RuntimeError(f'{Path(argv[0]).name} exited {p.returncode}' + (f': {tail}' if tail else ''))


def wav_info(path):
    with wave.open(str(path), 'rb') as w:
        frames, rate = w.getnframes(), w.getframerate()
    if not frames:
        raise RuntimeError('the voice wrote an empty WAV')
    return rate, round(frames / rate, 3)


def write_pcm_wav(path, pcm, rate=SAMPLE_RATE):
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm)
    return path


def command_backend(template):
    def voice(script, out_dir, _voice, timeout):
        if not template:
            raise Unavailable('the command backend needs --command TEMPLATE')
        src, wav = out_dir / 'script.txt', out_dir / 'narration.wav'
        src.write_text(script, encoding='utf-8')
        argv = [a.replace('{script}', str(src)).replace('{out}', str(wav)) for a in shlex.split(template)]
        run_command(argv, timeout)
        if not wav.is_file():
            raise RuntimeError('the command exited 0 but wrote no WAV at {out}')
        return wav, estimate_words(script, wav_info(wav)[1])
    return Backend('command', voice)


def kokoro_backend(data_flag, model_dir, speed):
    def voice(script, out_dir, name, _timeout):
        try:
            record = narrate(script, out_dir, pydeps.data_dir(data_flag), name, speed, model_dir=model_dir)
        except (Missing, pydeps.Broken, ValueError) as e:
            raise Unavailable(str(e)) from None
        return out_dir / 'narration.wav', record['words']
    return Backend('kokoro', voice, DEFAULT_VOICE, online=False, timed=True)


def edge_backend():
    def voice(script, out_dir, name, timeout):
        try:
            import edge_tts
        except ImportError as e:
            raise Unavailable(f'the edge-tts package does not import ({e}); start a new session, whose SessionStart '
                              'hook installs it') from None
        ffmpeg = shutil.which('ffmpeg')
        if not ffmpeg:
            raise Unavailable('ffmpeg is not on PATH; edge-tts sends MP3, which ffmpeg turns into narration.wav')
        try:
            talk = edge_tts.Communicate(script, name, boundary='WordBoundary', receive_timeout=max(int(timeout), 1))
        except ValueError as e:
            raise Unavailable(f'edge-tts refused the voice {name!r}: {e}') from None

        async def collect():
            audio, marks = bytearray(), []
            async for chunk in talk.stream():
                if chunk['type'] == 'audio':
                    audio += chunk['data']
                elif chunk['type'] == 'WordBoundary':   # offsets in 100 ns ticks
                    marks.append((chunk['text'], chunk['offset'] / 1e7, (chunk['offset'] + chunk['duration']) / 1e7))
            return bytes(audio), marks
        try:
            audio, marks = asyncio.run(asyncio.wait_for(collect(), timeout))
        except TimeoutError:
            raise CallTimeout(f'edge-tts passed {timeout:g} s') from None
        if not audio:
            raise RuntimeError('edge-tts returned no audio')
        mp3, wav = out_dir / 'edge.mp3', out_dir / 'narration.wav'
        mp3.write_bytes(audio)
        run_command([ffmpeg, '-v', 'error', '-y', '-i', str(mp3), '-ac', '1', '-ar', str(SAMPLE_RATE),
                     '-c:a', 'pcm_s16le', str(wav)], timeout)
        duration = wav_info(wav)[1]
        words = [{**w, 'start': min(w['start'], duration), 'end': min(w['end'], duration)}
                 for w in align_boundaries(script, marks)]
        return wav, words
    return Backend('edge-tts', voice, EDGE_VOICE, timed=True)


def openai_backend(env):
    def voice(script, out_dir, name, timeout):
        key = env.get('OPENAI_API_KEY', '').strip()
        if not key:
            raise Unavailable('OPENAI_API_KEY is not set')
        body = json.dumps({'model': OPENAI_MODEL, 'input': script, 'voice': name, 'response_format': 'pcm'})
        req = urllib.request.Request(f'https://{OPENAI_HOST}/v1/audio/speech', data=body.encode('utf-8'),
                                     method='POST', headers={'Authorization': f'Bearer {key}',
                                                             'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                pcm = r.read()
        except urllib.error.HTTPError as e:
            e.close()
            if e.code == 429 or e.code >= 500:
                raise RuntimeError(f'{OPENAI_HOST} answered HTTP {e.code}') from None
            raise Unavailable(f'{OPENAI_HOST} answered HTTP {e.code}') from None
        except (urllib.error.URLError, OSError) as e:
            reason = getattr(e, 'reason', e)
            if isinstance(reason, TimeoutError):   # a read timeout, or one while connecting (URLError)
                raise CallTimeout(f'{OPENAI_HOST} passed {timeout:g} s') from None
            raise RuntimeError(f'the request to {OPENAI_HOST} failed: {reason}') from None
        if not pcm or len(pcm) % 2:
            raise RuntimeError(f'{OPENAI_HOST} returned no 16-bit PCM audio')
        wav = write_pcm_wav(out_dir / 'narration.wav', pcm)
        return wav, estimate_words(script, wav_info(wav)[1])
    return Backend('openai', voice, OPENAI_VOICE, paid=True)


def elevenlabs_backend(env, data_flag):
    def voice(script, out_dir, name, timeout):
        import elevenlabs
        try:
            record = elevenlabs.narrate(script, out_dir, name, proceed=True, env=env, say=lambda *_: None,
                                        cache=elevenlabs.cache_dir(data_flag), timeout=timeout)
        except elevenlabs.TimedOut as e:
            raise CallTimeout(str(e)) from None
        except (elevenlabs.Missing, elevenlabs.Blocked, elevenlabs.Failed, ValueError) as e:
            raise Unavailable(str(e)) from None   # elevenlabs.py already retries 429 and 5xx itself
        return out_dir / 'narration.wav', record['words']
    import elevenlabs
    return Backend('elevenlabs', voice, elevenlabs.DEFAULT_VOICE, paid=True, timed=True)


def registry(command='', data_flag=None, model_dir=None, speed=1.0, env=None):
    env = os.environ if env is None else env
    found = (edge_backend(), kokoro_backend(data_flag, model_dir, speed), openai_backend(env),
             elevenlabs_backend(env, data_flag), command_backend(command))
    return {b.name: b for b in found}


def scan_script(text):
    """The finding kinds media_scan reports for the script, or why it could not run; [] when the text may leave."""
    try:
        import media_scan
        result = media_scan.scan({'narration': text})
    except Exception as e:   # the floor fails closed on any error
        return [f'scan-error: {type(e).__name__}']
    return (['rules-failed-to-load'] if result.fail_closed else []) + sorted({f['kind'] for f in result.findings})


def run_chain(text, out, chain, backends, voices=None, timeout=DEFAULT_TIMEOUT_S, allow_paid=False, env=None,
              sleep=time.sleep, scan=None):
    """Voice the whole script with the first backend in `chain` that can; returns the exit code."""
    env = os.environ if env is None else env
    voices, scan = voices or {}, scan or scan_script
    tokens = text.split()
    if not tokens:
        raise ValueError('the script has no words')
    local_only = env.get(FLOOR_VAR, '').strip().lower() not in ('', 'any')
    out.mkdir(parents=True, exist_ok=True)
    attempts, winner, code, scanned = [], None, EXIT_NO_AUDIO, False

    def note(name, voice, status, error='', seconds=0.0):
        attempts.append({'backend': name, 'voice': voice, 'status': status, 'seconds': round(seconds, 3),
                         **({'error': str(error)[:ERROR_CHARS]} if error else {})})

    for name in chain:
        b = backends[name]
        v = voices.get(name, b.default_voice)
        if b.online and local_only:
            note(name, v, 'forbidden', f'{FLOOR_VAR} allows no online backend')
            continue
        if b.paid and not allow_paid:
            note(name, v, 'paid-gate', 'a paid backend needs --allow-paid-voice')
            code = EXIT_PAID
            break
        if b.online and not scanned:
            kinds = scan(text)
            if kinds:
                note(name, v, 'scan', 'the secret and machine-data floor found: ' + ', '.join(kinds))
                code = EXIT_FLOOR
                break
            scanned = True
        for delay in (0, *RETRY_DELAYS_S):
            if delay:
                sleep(delay)
            work = Path(tempfile.mkdtemp(prefix=f'.voice-{name}-', dir=out))
            began = time.monotonic()
            try:
                wav, words = bounded(lambda: b.voice(text, work, v, timeout), timeout)
                if [w['word'] for w in words] != tokens:
                    raise RuntimeError('the word timings do not cover every word of the script')
                rate, duration = wav_info(wav)
            except Unavailable as e:
                note(name, v, 'unavailable', e, time.monotonic() - began)
                shutil.rmtree(work, ignore_errors=True)
                break
            except CallTimeout as e:
                note(name, v, 'timeout', e, time.monotonic() - began)
                shutil.rmtree(work, ignore_errors=True)
                break
            except Exception as e:   # any other failure of a voice is retried
                note(name, v, 'failed', str(e) or type(e).__name__, time.monotonic() - began)
            else:
                note(name, v, 'ok', '', time.monotonic() - began)
                winner = (b, v, wav, words, rate, duration, work)
                break
            shutil.rmtree(work, ignore_errors=True)
        if winner:
            break

    if winner:
        b, v, wav, words, rate, duration, work = winner
        os.replace(wav, out / 'narration.wav')
        record = {'audio': 'narration.wav', 'sample_rate': rate, 'duration': duration, 'backend': b.name,
                  'voice': v, 'timing': 'measured' if b.timed else 'estimated',
                  'words': [{**w, 'start': min(w['start'], duration), 'end': min(w['end'], duration)} for w in words]}
        (out / 'words.json').write_text(json.dumps(record, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        shutil.rmtree(work, ignore_errors=True)
        code = 0
    (out / 'voice.json').write_text(json.dumps({'backend': winner[0].name if winner else None,
                                                'voice': winner[1] if winner else None,
                                                'attempts': attempts}, indent=2, ensure_ascii=False) + '\n',
                                    encoding='utf-8')
    return code


def chain_main(a, out):
    chain = [n.strip() for n in a.backend_chain.split(',') if n.strip()]
    backends = registry(a.command, a.data_dir, a.model_dir, a.speed)
    unknown = [n for n in chain if n not in backends]
    if not chain or unknown:
        sys.stderr.write(f'speech: unknown backend {", ".join(unknown) or "(none)"}; choose from '
                         f'{", ".join(backends)}\n')
        return 1
    voices = {}
    for spec in a.voice or ():
        name, sep, value = spec.partition(':')
        if not sep or name not in backends or not value:
            sys.stderr.write(f'speech: --voice {spec!r} is not BACKEND:VOICE with BACKEND one of '
                             f'{", ".join(backends)}\n')
            return 1
        voices[name] = value
    try:
        code = run_chain(a.script.read_text(encoding='utf-8'), out, chain, backends, voices, a.timeout,
                         a.allow_paid_voice)
    except (ValueError, OSError) as e:
        sys.stderr.write(f'speech: {e}\n')
        return 1
    voice = json.loads((out / 'voice.json').read_text(encoding='utf-8'))
    if code:
        why = {EXIT_PAID: 'the chain reached a paid backend without --allow-paid-voice; nothing was sent',
               EXIT_FLOOR: 'the script failed the secret and machine-data floor; nothing was sent',
               EXIT_NO_AUDIO: 'no backend produced audio'}[code]
        sys.stderr.write(f'speech: {why}. Attempts are in {out / "voice.json"}\n')
        return code
    record = json.loads((out / 'words.json').read_text(encoding='utf-8'))
    print(f'{out / "narration.wav"}  {record["duration"]} s, {len(record["words"])} words, '
          f'{voice["backend"]} {voice["voice"]}')
    print(out / 'words.json')
    print(out / 'voice.json')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--script', type=Path, required=True, help='UTF-8 text file holding the words to speak')
    ap.add_argument('--out', type=Path, help='folder for narration.wav and words.json (default: the script\'s folder)')
    ap.add_argument('--voice', action='append', help=f'kokoro voice (default {DEFAULT_VOICE}); with --backend-chain, '
                    'BACKEND:VOICE, repeatable')
    ap.add_argument('--speed', type=float, default=1.0)
    ap.add_argument('--data-dir')
    ap.add_argument('--model-dir', help='the model_dir option: the folder holding the kokoro-<revision> set')
    ap.add_argument('--backend-chain', help='backends to try in order, comma-separated')
    ap.add_argument('--command', default='', help='the command backend\'s template: {script} in, {out} WAV out')
    ap.add_argument('--timeout', type=float, default=DEFAULT_TIMEOUT_S, help='seconds per backend call')
    ap.add_argument('--allow-paid-voice', action='store_true', help='let the chain call a paid backend')
    a = ap.parse_args(argv)
    out = a.out or a.script.parent
    if a.backend_chain is not None:
        return chain_main(a, out)
    try:
        data = pydeps.data_dir(a.data_dir)
        record = narrate(a.script.read_text(encoding='utf-8'), out, data, (a.voice or [DEFAULT_VOICE])[-1], a.speed,
                         model_dir=a.model_dir)
    except (Missing, pydeps.Broken) as e:
        sys.stderr.write(f'speech: {e}\n')
        return 2
    except (ValueError, OSError, subprocess.CalledProcessError) as e:
        sys.stderr.write(f'speech: {e}\n')
        return 1
    print(f'{out / "narration.wav"}  {record["duration"]} s, {len(record["words"])} words')
    print(out / 'words.json')
    return 0


if __name__ == '__main__':
    sys.exit(main())
