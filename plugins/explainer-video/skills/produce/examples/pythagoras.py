"""A short explainer scene: the shape of a ManimCE script this skill renders and checks."""
from manim import (BLUE, DOWN, GREEN, LEFT, RIGHT, UP, Create, FadeIn, FadeOut, MathTypst, Polygon, Scene, Text,
                   Transform, Write)


class Pythagoras(Scene):
    def construct(self):
        title = Text('Right triangles', font_size=44).to_edge(UP)
        self.play(Write(title))

        triangle = Polygon([-2, -1, 0], [1, -1, 0], [-2, 1, 0], color=BLUE).shift(LEFT * 2)
        a = Text('a', font_size=32).next_to(triangle, LEFT, buff=0.2)
        b = Text('b', font_size=32).next_to(triangle, DOWN, buff=0.2)
        self.play(Create(triangle), FadeIn(a, b))

        claim = Text('The square on the long side', font_size=30).shift(RIGHT * 3 + UP * 0.6)
        formula = MathTypst('a^2 + b^2 = c^2', font_size=48, color=GREEN).next_to(claim, DOWN, buff=0.5)
        self.play(FadeIn(claim))
        self.play(Write(formula))
        self.wait(1)

        restated = Text('equals the other two squares', font_size=30).move_to(claim)
        self.play(Transform(claim, restated))
        self.wait(1)
        self.play(FadeOut(title, triangle, a, b, claim, formula))
