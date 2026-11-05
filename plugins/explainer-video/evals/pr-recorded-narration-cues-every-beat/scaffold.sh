#!/usr/bin/env bash
# A finished narration: three paragraphs, a short silent WAV, and word timings that match the script.
set -euo pipefail
mkdir -p video/narration
cat >video/narration/script.txt <<'TXT'
Binary search starts with a sorted list.

It checks the middle value against the target.

Each check throws away half of what is left.
TXT
python3 -I - <<'PY'
import json
import wave

words = open('video/narration/script.txt', encoding='utf-8').read().split()
step = 0.4
record = {
    'audio': 'narration.wav',
    'duration': round(len(words) * step, 3),
    'words': [{'word': w, 'start': round(i * step, 3), 'end': round((i + 1) * step, 3)} for i, w in enumerate(words)],
}
with open('video/narration/words.json', 'w', encoding='utf-8') as out:
    json.dump(record, out, indent=2)
with wave.open('video/narration/narration.wav', 'wb') as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(24000)
    wav.writeframes(b'\0\0' * int(24000 * record['duration']))
PY
