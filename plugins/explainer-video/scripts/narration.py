"""Narration timing for a scene, and the captions and beat checks render.py runs with it. Standard library only.

A scene imports `beat` and calls `beat(self, k)` where beat k starts, then `beat(self, n)` after the last beat,
where n is the number of beats. Rendered with `render.py --narration DIR`, `beat` holds the scene until the first
word of narration paragraph k is spoken (the narration's end for k == n), so the video follows the audio. Without
narration it holds `hold` seconds, so the same scene renders silent.

The beats are the narration script's paragraphs: script.txt split on blank lines, in order. narrate.py makes one
words.json entry per whitespace-separated token of the script, so paragraph k owns the next len(paragraph.split())
entries.
"""
import json
import os
import re
from pathlib import Path

ENV = 'EXPLAINER_TIMING'
CAPTION_WORDS = 8           # most words in one caption
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


def captions(record, beats, limit=CAPTION_WORDS):
    """[(start, end, text)]: each beat's words in runs of at most `limit`, broken after a sentence end."""
    words = record['words']
    cues = []
    for first, count in beats:
        run = []
        for w in words[first:first + count]:
            run.append(w)
            if len(run) == limit or set(w['word'].rstrip(CLOSERS)[-1:]) & SENTENCE_END:
                cues.append(run)
                run = []
        if run:
            cues.append(run)
    return [(r[0]['start'], r[-1]['end'], ' '.join(w['word'] for w in r)) for r in cues]


def srt(cues):
    def stamp(t):
        ms = round(t * 1000)
        return f'{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}'
    return ''.join(f'{i}\n{stamp(a)} --> {stamp(b)}\n{text}\n\n' for i, (a, b, text) in enumerate(cues, 1))
