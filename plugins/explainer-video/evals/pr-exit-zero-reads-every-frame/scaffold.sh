#!/usr/bin/env bash
# A finished low-quality render: the scene, its video, the frames render.py lists, and its report.
set -euo pipefail
mkdir -p video/low/frames
cat >video/scene.py <<'PY'
from manim import WHITE, FadeIn, Scene, Square, VGroup


class OddSquares(Scene):
    def construct(self):
        for n in (1, 2, 3):
            tiles = VGroup(*[Square(0.6, color=WHITE, fill_opacity=1) for _ in range(n * n)])
            self.play(FadeIn(tiles.arrange_in_grid(n, n)), run_time=2)
PY
cat >video/low/report.json <<'JSON'
{
  "scene": "OddSquares",
  "quality": "l",
  "video": "video/low/OddSquares.mp4",
  "duration": {"timeline": 6.0, "ffprobe": 6.0},
  "animations": 3,
  "frames": [
    {"t": 2.0, "path": "video/low/frames/f0000.png", "elements": 0},
    {"t": 4.0, "path": "video/low/frames/f0001.png", "elements": 0},
    {"t": 6.0, "path": "video/low/frames/f0002.png", "elements": 0}
  ],
  "narration": null,
  "stills": [],
  "defects": [],
  "status": "pass"
}
JSON
ffmpeg -y -loglevel error -f lavfi -i color=c=black:s=854x480:d=6:r=15 -pix_fmt yuv420p video/low/OddSquares.mp4
for k in 0 1 2; do
  boxes=""
  for ((row = 0; row <= k; row++)); do
    for ((col = 0; col <= k; col++)); do
      boxes+="drawbox=x=$((col * 90 + 300)):y=$((row * 90 + 100)):w=80:h=80:color=white:t=fill,"
    done
  done
  ffmpeg -y -loglevel error -f lavfi -i color=c=black:s=854x480 -frames:v 1 -vf "${boxes%,}" "video/low/frames/f000$k.png"
done
