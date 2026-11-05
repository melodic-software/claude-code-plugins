#!/usr/bin/env bash
# The scene behind the defect the prompt quotes: two labels at one position.
set -euo pipefail
mkdir -p video
cat >video/scene.py <<'PY'
from manim import FadeIn, Scene, Text


class Steps(Scene):
    def construct(self):
        first = Text('Step one', font_size=40)
        second = Text('Step two', font_size=40)
        self.play(FadeIn(first, second))
PY
