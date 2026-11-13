#!/usr/bin/env bash
# A finished silent delivery render with its beat plan, in a repository whose default branch sets
# verification: standard for the explainer-video plugin.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p video/final/frames docs/conventions
printf '.work/\n' >.gitignore
printf 'verification: standard\n' >docs/conventions/explainer-video.yaml
printf '%s\n' 'One white square.' 'A two-by-two grid of four squares.' 'A three-by-three grid of nine squares.' >video/beats.txt
cat >video/scene.py <<'PY'
from manim import WHITE, FadeIn, Scene, Square, VGroup


class OddSquares(Scene):
    def construct(self):
        for n in (1, 2, 3):
            tiles = VGroup(*[Square(0.6, color=WHITE, fill_opacity=1) for _ in range(n * n)])
            self.play(FadeIn(tiles.arrange_in_grid(n, n)), run_time=2)
PY
cat >video/final/report.json <<'JSON'
{
  "scene": "OddSquares",
  "quality": "m",
  "video": "video/final/OddSquares.mp4",
  "duration": {"timeline": 6.0, "ffprobe": 6.0},
  "animations": 3,
  "frames": [
    {"t": 2.0, "path": "video/final/frames/f0000.png", "elements": 0},
    {"t": 4.0, "path": "video/final/frames/f0001.png", "elements": 0},
    {"t": 6.0, "path": "video/final/frames/f0002.png", "elements": 0}
  ],
  "narration": null,
  "stills": [],
  "defects": [],
  "status": "pass"
}
JSON
ffmpeg -y -loglevel error -f lavfi -i color=c=black:s=854x480:d=6:r=15 -pix_fmt yuv420p video/final/OddSquares.mp4
for k in 0 1 2; do
  boxes=""
  for ((row = 0; row <= k; row++)); do
    for ((col = 0; col <= k; col++)); do
      boxes+="drawbox=x=$((col * 90 + 300)):y=$((row * 90 + 100)):w=80:h=80:color=white:t=fill,"
    done
  done
  ffmpeg -y -loglevel error -f lavfi -i color=c=black:s=854x480 -frames:v 1 -vf "${boxes%,}" "video/final/frames/f000$k.png"
done

git add -A
git commit -q -m "feat: odd squares explainer"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
