"""storyboard.json v1 (ADR 0102): parse it, write its narration script, and lay its moments out as held frames.

parse(data) -> board, or StoryboardError naming the moment and the rule it breaks.
script(board) -> narration script: one paragraph per narrated moment, for speech's narrate.py.
timeline(board, words, hold, cue) -> {'holds', 'chapters', 'audio', 'words', 'beats', 'duration'}:
  holds    [{'id', 'start', 'end'}] in video time, one per moment;
  audio    the narration rebuilt in video time: ('narration', from_s, to_s) slices of narration.wav and
           ('silence', seconds) for a moment with no narration, or [] with no narration at all;
  words    words.json re-timed to video time (synthetic with no narration, so captions still show);
  beats    [(first word, count)] per narrated moment, for media_captions.captions.
With no narration (words None) every moment holds max(min_seconds, words * seconds_per_word + extra_seconds), longer
when cue (the caption limits: max_words, min_seconds) gives each caption run its minimum time on screen.
Standard library plus media_templates and media_captions beside this file.
"""
import math
from pathlib import PurePosixPath, PureWindowsPath

import media_captions
from media_templates import TEMPLATES


class StoryboardError(ValueError):
    pass


def _inside(path):
    """A relative path with no parent step, read as POSIX and as Windows (a storyboard may come from either)."""
    if not isinstance(path, str) or not path:
        return False
    return not any(p.is_absolute() or p.drive or '..' in p.parts
                   for p in (PurePosixPath(path), PureWindowsPath(path)))


def parse(data):
    if data.get('version') != 1:
        raise StoryboardError(f'storyboard version {data.get("version")!r} is not supported; this reader takes 1')
    chapters = data.get('chapters') or []
    for n, c in enumerate(chapters, 1):
        if not isinstance(c, dict) or not all(isinstance(c.get(k), str) and c[k] for k in ('id', 'title')):
            raise StoryboardError(f'chapter {n}: every chapter needs a string id and title')
    declared = {c['id'] for c in chapters}
    moments = data.get('moments') or []
    if not moments:
        raise StoryboardError('the storyboard has no moments')
    seen = set()
    for m in moments:
        mid = m.get('id')
        where = f'moment {mid!r}'
        if not mid or mid in seen:
            raise StoryboardError(f'{where}: every moment needs a unique id')
        seen.add(mid)
        if m.get('template') not in TEMPLATES:
            raise StoryboardError(f'{where}: unknown template {m.get("template")!r}; use one of {", ".join(TEMPLATES)}')
        if m.get('chapter') not in declared:
            raise StoryboardError(f'{where}: chapter {m.get("chapter")!r} is not declared in chapters')
        if not isinstance(m.get('data', {}), dict):
            raise StoryboardError(f'{where}: data must be an object')
        m.setdefault('narration', '')
        if not isinstance(m['narration'], str):
            raise StoryboardError(f'{where}: narration must be a string')
        if m['template'] != 'title' and not m['narration'].strip():
            raise StoryboardError(f'{where}: narration is empty; only a title moment may be silent')
        if m['template'] == 'also-changed' and not m.get('covers'):
            raise StoryboardError(f'{where}: an also-changed moment must list what it covers')
        if m['template'] == 'screenshot':
            if not m.get('data', {}).get('sidecar'):
                raise StoryboardError(f'{where}: a screenshot needs a frame-text sidecar (data.sidecar) for the scan')
            for key in ('image', 'sidecar'):
                if not _inside(m['data'].get(key)):
                    raise StoryboardError(f'{where}: data.{key} must be a relative path inside the storyboard folder')
    return {**data, 'chapters': chapters, 'moments': moments}


def script(board):
    return '\n\n'.join(' '.join(m['narration'].split()) for m in board['moments'] if m.get('narration', '').strip()) + '\n'


def _chapters(board, holds):
    titles = {c['id']: c['title'] for c in board['chapters']}
    out, last = [], None
    for m, h in zip(board['moments'], holds):
        if m['chapter'] != last:
            out.append({'title': titles[m['chapter']], 'start_s': h['start']})
            last = m['chapter']
    return out


def _synthetic(para, t, cue, per_word):
    """Made-up word timings from t: each caption run stays up for at least cue['min_seconds']."""
    out = []
    for run in media_captions.cue_runs([{'word': w} for w in para], cue['max_words']) if cue else [para]:
        step = max(per_word, math.ceil(cue['min_seconds'] / len(run) * 1000) / 1000) if cue else per_word
        for w in run:
            out.append({'word': w['word'] if cue else w, 'start': round(t, 3), 'end': round(t + step, 3)})
            t += step
    return out, t


def timeline(board, words, hold=None, cue=None):
    hold = hold or {'min_seconds': 3.0, 'seconds_per_word': 0.3, 'extra_seconds': 1.0}
    moments = board['moments']
    paras = [m.get('narration', '').split() for m in moments]
    narrated = [i for i, p in enumerate(paras) if p]
    holds, audio, out_words, beats, t = [], [], [], [], 0.0
    firsts, bounds = [], []
    if words is not None:
        tokens = [w for i in narrated for w in paras[i]]
        if tokens != [w['word'] for w in words['words']]:
            raise StoryboardError('words.json does not hold the storyboard narration word for word: narrate the '
                                  'script this storyboard wrote')
        k = 0
        for i in narrated:
            firsts.append(k)
            k += len(paras[i])
        bounds = [0.0] + [float(words['words'][f]['start']) for f in firsts[1:]] + [float(words['duration'])]
    for i, m in enumerate(moments):
        if words is not None and paras[i]:
            j = narrated.index(i)
            a0, a1 = bounds[j], bounds[j + 1]
            audio.append(('narration', round(a0, 3), round(a1, 3)))
            beats.append((len(out_words), len(paras[i])))
            for w in words['words'][firsts[j]:firsts[j] + len(paras[i])]:
                out_words.append({'word': w['word'], 'start': round(t + float(w['start']) - a0, 3),
                                  'end': round(t + float(w['end']) - a0, 3)})
            length = a1 - a0
        else:
            length = max(hold['min_seconds'], len(paras[i]) * hold['seconds_per_word'] + hold['extra_seconds'])
            if words is not None:
                audio.append(('silence', round(length, 3)))
            elif paras[i]:
                beats.append((len(out_words), len(paras[i])))
                made, end = _synthetic(paras[i], t, cue, hold['seconds_per_word'])
                out_words += made
                length = max(length, end - t + hold['extra_seconds'])
        holds.append({'id': m['id'], 'start': round(t, 3), 'end': round(t + length, 3)})
        t += length
    duration = round(t, 3)
    return {'holds': holds, 'chapters': _chapters(board, holds), 'audio': audio,
            'words': {'words': out_words, 'duration': duration}, 'beats': beats, 'duration': duration}
