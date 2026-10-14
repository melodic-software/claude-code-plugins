#!/usr/bin/env bash
# A production whose pack review failed the rough row, with a copy of the woodcut-ink pack in the workspace.
set -euo pipefail
mkdir -p packs/woodcut-ink
cp "$(dirname "${BASH_SOURCE[0]}")/../../styles/woodcut-ink/style.json" packs/woodcut-ink/style.json
mkdir -p film
cat >film/brief.md <<'MD'
# Brief

Subject: a lighthouse keeper relights the lamp in a storm
Length: 24 s
Audience: festival short, general audience
Packs: woodcut-ink
Delivery: mp4, 768x576, silent
MD
cat >film/shots.json <<'JSON'
{"fps": 12, "size": [768, 576], "shots": [
  {"id": "s1", "t0": 0, "t1": 8, "scene": "scenes/s1.js", "pack": "woodcut-ink"},
  {"id": "s2", "t0": 8, "t1": 16, "scene": "scenes/s2.js", "pack": "woodcut-ink"},
  {"id": "s3", "t0": 16, "t1": 24, "scene": "scenes/s3.js", "pack": "woodcut-ink"}
]}
JSON
cat >film/review.txt <<'TXT'
$ inkstats.py film/frames --cuts film/shots.json --pack packs/woodcut-ink
film/frames: 196 drawings, 24 s, 768x576

check against woodcut-ink

| check | film | band | distance | pass |
|---|---|---|---|---|
| straight_border | 0.8291 | 0.8179-0.8406 | 0.42 | yes |
| straight_caption | 0.5102 | 0.4284-0.6264 | 0.31 | yes |
| rough | 0.0941 | 0.0591-0.0757 | 3.11 | NO |
| offstep | 0.0712 | 0.0308-0.1406 | 0.37 | yes |
| sliver_border | 3.512 | 3.17-4.125 | 0.28 | yes |
| sliver_caption | 2.611 | 2.02-3.278 | 0.19 | yes |
| flat | 0.4012 | 0.1305-0.7958 | 0.22 | yes |
| holes | 0.0221 | 0.0127-0.0344 | 0.35 | yes |
| boil | 1.402 | 1.298-1.476 | 0.48 | yes |
| per_second | 7.91 | 7.784-8.04 | 0.33 | yes |

9/10 pass, 0 n/a; distance to source 3.11, margin +2.11 (rough)
TXT
