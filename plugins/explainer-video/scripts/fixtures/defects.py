"""Test fixture: two overlapping labels and a label cut off by the right edge, which render.py must fail."""
from manim import LEFT, RIGHT, FadeIn, Scene, Text


class Defects(Scene):
    def construct(self):
        first = Text('first label', font_size=40)
        second = Text('second label', font_size=40).shift(RIGHT * 0.5)
        allowed = Text('stacked on purpose', font_size=40).move_to(first)
        allowed.allow_overlap = True
        edge = Text('cut off at the edge', font_size=40).move_to(RIGHT * 6, aligned_edge=LEFT)
        self.play(FadeIn(first, second, allowed, edge))
