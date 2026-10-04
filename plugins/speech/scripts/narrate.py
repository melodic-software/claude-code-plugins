#!/usr/bin/env python3
"""Text to speech with the kokoro backend: a script in, narration.wav and words.json out.

usage: pydeps.py run --data-dir DIR -- narrate.py --data-dir DIR [--model-dir DIR] --script FILE [--out DIR]
       [--voice NAME] [--speed X]

Every whitespace-separated token of the script is a word in words.json, with a start and end in seconds. The timings
come from the model itself: the Kokoro-82M export in kokoro-assets.json reports how many frames each input token
lasts, and a word spans its own tokens. espeak-ng, installed by the user, turns each word into the phonemes Kokoro
reads; the plugin never ships it.

exit codes: 0 written; 2 a prerequisite is missing (espeak-ng, the model files, the Python packages), named with
its remedy; 1 any other failure.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import wave
from pathlib import Path

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
                      'Install it yourself (it is GPL-3.0; this plugin never ships it): run /speech:check for the '
                      'install line for this system.')
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
        match = re.fullmatch(r'(\W*)(.*?)(\W*)', token)
        lead, body, trail = match.groups()
        if not body:   # all punctuation, such as an em dash
            lead, trail = token, ''
        pre = [vocab[c] for c in lead if c in vocab]
        core = [vocab[c] for c in (phonemize(body) if body else '') if c in vocab]
        post = [vocab[c] for c in trail if c in vocab]
        ids = pre + core + post
        span = (len(pre), len(pre) + len(core)) if core else (0, len(ids))
        words.append({'word': token, 'ids': ids, 'span': span, 'ends_sentence': bool(set(token[-1:]) & SENTENCE_END)})
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
    if voice not in assets.voices():
        raise ValueError(f'unknown voice {voice!r}; choose one of {", ".join(assets.voices())}')
    if not 0.5 <= speed <= 2.0:
        raise ValueError(f'speed must be between 0.5 and 2.0, got {speed}')
    gaps = assets.missing(data, model_dir=model_dir)
    if gaps:
        raise Missing(f'the Kokoro model files are not downloaded ({len(gaps)} missing, first {gaps[0]}). '
                      'Run /speech:setup apply install-model, which downloads them from the pinned revision.')
    try:
        import numpy as np
        import onnxruntime as rt
    except ImportError as e:
        raise Missing(f'the Python packages do not import ({e}); start a new session, whose SessionStart hook '
                      'installs them, or run the repair line from /speech:check.') from e
    root = assets.assets_dir(data, model_dir=model_dir)
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


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--script', type=Path, required=True, help='UTF-8 text file holding the words to speak')
    ap.add_argument('--out', type=Path, help='folder for narration.wav and words.json (default: the script\'s folder)')
    ap.add_argument('--voice', default=DEFAULT_VOICE)
    ap.add_argument('--speed', type=float, default=1.0)
    ap.add_argument('--data-dir')
    ap.add_argument('--model-dir', help='the model_dir option: the folder holding the kokoro-<revision> set')
    a = ap.parse_args(argv)
    try:
        data = pydeps.data_dir(a.data_dir)
        record = narrate(a.script.read_text(encoding='utf-8'), a.out or a.script.parent, data, a.voice, a.speed,
                         model_dir=a.model_dir)
    except (Missing, pydeps.Broken) as e:
        sys.stderr.write(f'speech: {e}\n')
        return 2
    except (ValueError, OSError, subprocess.CalledProcessError) as e:
        sys.stderr.write(f'speech: {e}\n')
        return 1
    out = a.out or a.script.parent
    print(f'{out / "narration.wav"}  {record["duration"]} s, {len(record["words"])} words')
    print(out / 'words.json')
    return 0


if __name__ == '__main__':
    sys.exit(main())
