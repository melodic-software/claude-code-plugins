"""Captions from narrate.py's words.json: cues, their checks, and SRT and ASS text. Standard library only.

Cues follow narration paragraphs (beats): each beat's sentences split into the fewest balanced runs of at most
max_words words. The caller passes the limits (max_words, min_seconds, seconds_per_word) from its own config.
"""
import math

SENTENCE_END = set('.!?…')
CLOSERS = '"\'’”)]}»'            # may follow a sentence end: "Done." or finished.)
MARGIN_V = 0.13                   # bottom margin as a share of the height: clears GitHub's player control bar


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


def captions(record, beats, max_words, min_seconds, seconds_per_word):
    """[(start, end, text)] for record {'words', 'duration'} and beats [(first word, word count)]. A run whose time
    before the next run starts is under min_seconds joins a neighbor in its beat when the two fit in max_words. Each
    cue then stays up for min_seconds and seconds_per_word a word, as far as the next cue's start (the narration's
    end for the last) allows."""
    words = record['words']
    beat_runs = [[r for s in _sentences(words[first:first + count]) for r in _balanced(s, max_words)]
                 for first, count in beats]
    starts = [b[0][0]['start'] for b in beat_runs if b] + [record['duration']]
    for j, runs in enumerate(beat_runs):
        i = 0
        while i < len(runs):
            window = (runs[i + 1][0]['start'] if i + 1 < len(runs) else starts[j + 1]) - runs[i][0]['start']
            if window < min_seconds:
                if i > 0 and len(runs[i - 1]) + len(runs[i]) <= max_words:
                    runs[i - 1:i + 1] = [runs[i - 1] + runs[i]]
                    i -= 1
                    continue
                if i + 1 < len(runs) and len(runs[i]) + len(runs[i + 1]) <= max_words:
                    runs[i:i + 2] = [runs[i] + runs[i + 1]]
                    continue
            i += 1
    runs = [r for b in beat_runs for r in b]
    cues = []
    for i, r in enumerate(runs):
        next_start = runs[i + 1][0]['start'] if i + 1 < len(runs) else record['duration']
        end = min(max(r[-1]['end'], r[0]['start'] + max(min_seconds, seconds_per_word * len(r))), next_start)
        cues.append((r[0]['start'], round(end, 3), ' '.join(w['word'] for w in r)))
    return cues


def caption_findings(cues, min_seconds, seconds_per_word):
    """(defects, flags): a cue shorter than min_seconds is a defect; one under seconds_per_word a word is flagged,
    since narration spoken faster than that cannot be captioned slower."""
    defects, flags = [], []
    for i, (a, b, text) in enumerate(cues, 1):
        n = len(text.split())
        if b - a < min_seconds - 1e-6:
            defects.append(f'caption {i} {text!r} is on screen {b - a:.2f} s, under the {min_seconds} s minimum: '
                           'give it a longer pause after it in script.txt, or join it to the sentence beside it')
        elif b - a < seconds_per_word * n - 1e-6:
            flags.append(f'caption {i} {text!r}: {n} words in {b - a:.2f} s, {(b - a) / n:.2f} s a word, under '
                         f'{seconds_per_word} s a word')
    return defects, flags


def srt(cues):
    def stamp(t):
        ms = round(t * 1000)
        return f'{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}'
    return ''.join(f'{i}\n{stamp(a)} --> {stamp(b)}\n{text}\n\n' for i, (a, b, text) in enumerate(cues, 1))


def _ass_text(text):
    """Braces open override blocks and a backslash starts a tag: escape the braces, and keep a backslash literal by
    a word joiner after it."""
    return text.replace('\\', '\\⁠').replace('{', '\\{').replace('}', '\\}')


def ass(cues, width, height, font='DejaVu Sans'):
    """ASS script for burning: white text with a dark box, bottom center, raised above a player's control bar."""
    def stamp(t):
        cs = round(t * 100)
        return f'{cs // 360000}:{cs // 6000 % 60:02d}:{cs // 100 % 60:02d}.{cs % 100:02d}'
    size, margin_v = round(height * 0.045), round(height * MARGIN_V)
    head = ('[Script Info]\nScriptType: v4.00+\nWrapStyle: 0\nScaledBorderAndShadow: yes\n'
            f'PlayResX: {width}\nPlayResY: {height}\n\n[V4+ Styles]\n'
            'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, '
            'Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, '
            'MarginL, MarginR, MarginV, Encoding\n'
            f'Style: Default,{font},{size},&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,3,'
            f'{round(size * 0.25)},0,2,{round(width * 0.08)},{round(width * 0.08)},{margin_v},1\n\n'
            '[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n')
    return head + ''.join(f'Dialogue: 0,{stamp(a)},{stamp(b)},Default,,0,0,0,,{_ass_text(t)}\n' for a, b, t in cues)
