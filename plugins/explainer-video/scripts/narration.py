"""Narration timing for a scene, and the captions and beat checks render.py runs with it. Standard library only.

A scene imports `beat` and calls `beat(self, k)` where beat k starts, then `beat(self, n)` after the last beat,
where n is the number of beats. Rendered with `render.py --narration DIR`, `beat` holds the scene until the first
word of narration paragraph k is spoken (the narration's end for k == n), so the video follows the audio. Without
narration it holds `hold` seconds, so the same scene renders silent.

The beats are the narration script's paragraphs: script.txt split on blank lines, in order. narrate.py makes one
words.json entry per whitespace-separated token of the script, so paragraph k owns the next len(paragraph.split())
entries.

Caption limits (most words per cue, shortest cue, reading time per word) are defaults.json "captions".
"""
import json
import math
import os
import re
from pathlib import Path

ENV = 'EXPLAINER_TIMING'
CAPTIONS = json.loads(Path(__file__).with_name('defaults.json').read_text(encoding='utf-8'))['captions']
SENTENCE_END = set('.!?…')
CLOSERS = '"\'’”)]}»'            # may follow a sentence end: "Done." or finished.)


def paragraphs(script):
    return [p.split() for p in re.split(r'\n\s*\n', script) if p.split()]


def timing(script, record):
    """{'starts': start of each beat, then the narration's end, 'beats': [(first word, word count)]} from the
    script text and narrate.py's words.json record. Raises ValueError when they do not describe the same words."""
    words = record['words']
    paras = paragraphs(script)
    tokens = [t for p in paras for t in p]
    if tokens != [w['word'] for w in words]:
        raise ValueError(f'script.txt has {len(tokens)} words and words.json {len(words)}, or they differ: '
                         'narrate the script again so both describe the same words')
    starts, beats, first = [], [], 0
    for p in paras:
        starts.append(float(words[first]['start']))
        beats.append((first, len(p)))
        first += len(p)
    return {'starts': starts + [float(record['duration'])], 'beats': beats}


def beat(scene, k, hold=0.0):
    """Hold the scene until beat k's narration starts; record when it was cued. Silent: hold `hold` seconds."""
    path = os.environ.get(ENV)
    if not path:
        if hold > 0:
            scene.wait(hold)
        return
    starts = json.loads(Path(path).read_text(encoding='utf-8'))['starts']
    if k >= len(starts):
        raise ValueError(f'beat {k} does not exist: the narration has {len(starts) - 1} paragraphs, '
                         f'so beats run 0 to {len(starts) - 1} (the last one is the end)')
    gap = starts[k] - scene.renderer.time
    if gap > 1e-6:
        scene.wait(gap)
    scene.__dict__.setdefault('beat_marks', []).append((k, float(scene.renderer.time)))


def beat_defects(marks, starts, fps):
    """Each beat cued once, in order, within one frame of its narration start."""
    cued = [k for k, _ in marks]
    if cued != list(range(len(starts))):
        return [f'the scene cued beats {cued}; it must call beat(self, k) once for each k from 0 to '
                f'{len(starts) - 1}, in order (the last one after the final beat)']
    defects = []
    for k, t in marks:
        if abs(t - starts[k]) > 1 / fps:
            what = 'the narration ends' if k == len(starts) - 1 else f'beat {k} narration starts'
            defects.append(f'{what} at {starts[k]:.2f} s but the scene reaches it at {t:.2f} s: the animations '
                           f'before it run {t - starts[k]:.2f} s too long')
    return defects


def _sentences(run):
    out, current = [], []
    for w in run:
        current.append(w)
        if set(w['word'].rstrip(CLOSERS)[-1:]) & SENTENCE_END:
            out.append(current)
            current = []
    return out + [current] if current else out


def _balanced(sentence, limit):
    """The fewest runs of at most limit words, their lengths as even as possible, so no run is a short orphan."""
    k = math.ceil(len(sentence) / limit)
    size, extra = divmod(len(sentence), k)
    runs, at = [], 0
    for i in range(k):
        n = size + (i < extra)
        runs.append(sentence[at:at + n])
        at += n
    return runs


def captions(record, beats, limit=None, min_seconds=None, per_word=None):
    """[(start, end, text)]: each beat's sentences split into the fewest balanced runs of at most `limit` words.
    A run whose time before the next run starts is under min_seconds joins a neighbor in its beat when the two fit
    in `limit` words. Each cue then stays up for min_seconds and per_word seconds a word, as far as the next cue's
    start (the narration's end for the last) allows."""
    limit = limit or CAPTIONS['max_words']
    min_seconds = CAPTIONS['min_seconds'] if min_seconds is None else min_seconds
    per_word = CAPTIONS['seconds_per_word'] if per_word is None else per_word
    words = record['words']
    beat_runs = [[r for s in _sentences(words[first:first + count]) for r in _balanced(s, limit)]
                 for first, count in beats]
    starts = [b[0][0]['start'] for b in beat_runs if b] + [record['duration']]
    for j, runs in enumerate(beat_runs):
        i = 0
        while i < len(runs):
            window = (runs[i + 1][0]['start'] if i + 1 < len(runs) else starts[j + 1]) - runs[i][0]['start']
            if window < min_seconds:
                if i > 0 and len(runs[i - 1]) + len(runs[i]) <= limit:
                    runs[i - 1:i + 1] = [runs[i - 1] + runs[i]]
                    i -= 1
                    continue
                if i + 1 < len(runs) and len(runs[i]) + len(runs[i + 1]) <= limit:
                    runs[i:i + 2] = [runs[i] + runs[i + 1]]
                    continue
            i += 1
    runs = [r for b in beat_runs for r in b]
    cues = []
    for i, r in enumerate(runs):
        next_start = runs[i + 1][0]['start'] if i + 1 < len(runs) else record['duration']
        end = min(max(r[-1]['end'], r[0]['start'] + max(min_seconds, per_word * len(r))), next_start)
        cues.append((r[0]['start'], round(end, 3), ' '.join(w['word'] for w in r)))
    return cues


def caption_findings(cues, min_seconds=None, per_word=None):
    """(defects, flags): a cue shorter than min_seconds is a defect; one under per_word seconds a word is flagged,
    since narration spoken faster than that cannot be captioned slower."""
    min_seconds = CAPTIONS['min_seconds'] if min_seconds is None else min_seconds
    per_word = CAPTIONS['seconds_per_word'] if per_word is None else per_word
    defects, flags = [], []
    for i, (a, b, text) in enumerate(cues, 1):
        n = len(text.split())
        if b - a < min_seconds - 1e-6:
            defects.append(f'caption {i} {text!r} is on screen {b - a:.2f} s, under the {min_seconds} s minimum: '
                           'give it a longer pause after it in script.txt, or join it to the sentence beside it')
        elif b - a < per_word * n - 1e-6:
            flags.append(f'caption {i} {text!r}: {n} words in {b - a:.2f} s, {(b - a) / n:.2f} s a word, under '
                         f'{per_word} s a word')
    return defects, flags


def srt(cues):
    def stamp(t):
        ms = round(t * 1000)
        return f'{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}'
    return ''.join(f'{i}\n{stamp(a)} --> {stamp(b)}\n{text}\n\n' for i, (a, b, text) in enumerate(cues, 1))
