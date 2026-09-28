"""inkstats hold timing: a rotoscope work dir's last drawing uses d/index.json t1, not one frame.

Standard library only at module level so collection works without numpy; the tests skip, naming what is
missing, when numpy or opencv is absent.
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

try:
    import cv2
    import numpy as np
    import inkstats
    import workdir
except ImportError as e:
    MISSING = str(e)
else:
    MISSING = None

FPS = 24


def holds_of(film, fps=FPS):
    times = [t for _, t in inkstats.drawings(film, fps)]
    return [b - a for a, b in zip(times, times[1:])]


def write_png(path, gray):
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(path), np.full((48, 64, 3), gray, np.uint8))


def write_work(root, starts, duration, grays):
    """A work dir whose drawings start at `starts` and whose last t1 is `duration`."""
    t1s = list(starts[1:]) + [duration]
    drawings = []
    for k, (t, t1, g) in enumerate(zip(starts, t1s, grays)):
        write_png(workdir.source(root, k), g)
        drawings.append([k, t, t1])
    workdir.traces_dir(root).mkdir(parents=True, exist_ok=True)
    json.dump({'w': 64, 'h': 48, 'duration': duration, 'drawings': drawings},
              open(workdir.index(root), 'w', encoding='utf-8'))
    return root


@unittest.skipUnless(not MISSING, f'numpy/opencv missing: {MISSING}')
class WorkDirFinalHold(unittest.TestCase):
    def test_last_drawing_uses_index_t1_not_one_frame(self):
        # 3, 2, then 4 frames at 24 fps: extract.py stores the 4-frame tail as the last t1.
        starts = [0.0, 3 / FPS, 5 / FPS]
        duration = 9 / FPS
        want = [3 / FPS, 2 / FPS, 4 / FPS]
        with tempfile.TemporaryDirectory() as tmp:
            work = write_work(Path(tmp) / 'work', starts, duration, (16, 200, 80))
            got = holds_of(work)
            self.assertEqual(len(got), 3)
            for h, w in zip(got, want):
                self.assertAlmostEqual(h, w, places=6)
            self.assertNotAlmostEqual(got[-1], 1 / FPS, places=6)
            self.assertEqual(list(inkstats.hold_frames([{'hold': h} for h in got], FPS)), [3, 2, 4])
            self.assertAlmostEqual(inkstats.film_end(work, starts[-1], FPS), duration)

    def test_lone_drawing_holds_until_index_duration(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = write_work(Path(tmp) / 'work', [0.0], 1.0, (16,))
            got = holds_of(work)
            self.assertEqual(len(got), 1)
            self.assertAlmostEqual(got[0], 1.0, places=6)

    def test_frame_folder_last_hold_is_still_one_frame(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / 'frames'
            for i, g in enumerate((16, 200, 80)):
                write_png(folder / f'f{i:04d}.png', g)
            got = holds_of(folder)
            self.assertEqual(len(got), 3)
            for h in got:
                self.assertAlmostEqual(h, 1 / FPS, places=6)

    def test_t_window_clips_the_final_hold(self):
        starts = [0.0, 3 / FPS, 5 / FPS]
        duration = 9 / FPS
        with tempfile.TemporaryDirectory() as tmp:
            work = write_work(Path(tmp) / 'work', starts, duration, (16, 200, 80))
            times = [t for _, t in inkstats.drawings(work, FPS, window=(0.0, 6 / FPS))]
            self.assertAlmostEqual(times[-1], 6 / FPS, places=6)
            self.assertAlmostEqual(times[-1] - times[-2], 1 / FPS, places=6)


@unittest.skipUnless(not MISSING, f'numpy/opencv missing: {MISSING}')
class WoodcutResiduals(unittest.TestCase):
    """#4507: straight_border ignores a subject-contact side; short slits and a
    one-third 2 px recut land sliver_caption and boil in the woodcut bands."""

    @classmethod
    def setUpClass(cls):
        import sys as _sys
        styles = HERE.parent / 'styles' / 'woodcut-ink'
        if str(styles) not in _sys.path:
            _sys.path.insert(0, str(styles))
        import marks
        cls.marks = marks
        cls.pack = json.loads((styles / 'style.json').read_text(encoding='utf-8'))

    def _border(self, touch):
        h, w = 240, 360
        e = max(1, round(inkstats.BORDER * min(h, w)))
        ink = np.zeros((h, w), bool)
        for x in range(10, w - 10):
            y = 2 + int(2 * np.sin(x / 2.5))
            ink[y:y + 2, x] = True
            yb = h - 4 + int(2 * np.sin(x / 2.5))
            ink[yb:yb + 2, x] = True
        for y in range(10, h - 10):
            x = 2 + int(2 * np.sin(y / 2.5))
            ink[y, x:x + 2] = True
            xr = w - 4 + int(2 * np.sin(y / 2.5))
            ink[y, xr:xr + 2] = True
        if touch == 'ring':
            ink[h - e + 1:h - 2, 40:w - 40] = True
        elif touch == 'cross':
            ink[h - e - 4:h - 2, 40:w - 40] = True
        rgb = np.full((h, w, 3), 230, np.uint8)
        rgb[ink] = 8
        return inkstats.one(rgb)['straight_border'], inkstats.closed_border_sides(ink)[1]

    def test_subject_contact_side_is_left_out_of_straight_border(self):
        wobble, open_sides = self._border(None)
        in_ring, ring_sides = self._border('ring')
        cross, cross_sides = self._border('cross')
        self.assertNotIn(1, open_sides)
        self.assertNotIn(1, ring_sides)
        self.assertIn(1, cross_sides)
        self.assertGreater(in_ring, wobble + 0.15)
        self.assertLess(abs(cross - wobble), 0.05)

    def test_short_slits_land_in_the_sliver_caption_band(self):
        lo, hi = self.pack['bands']['sliver_caption']
        short = inkstats.one(self.marks.caption_short_slits())['sliver_caption']
        thin = inkstats.one(self.marks.caption_thin_strip())['sliver_caption']
        self.assertIsNotNone(short)
        self.assertGreaterEqual(short, lo)
        self.assertLessEqual(short, hi)
        self.assertGreater(thin, hi)

    def test_partial_recut_lands_in_the_boil_band(self):
        lo, hi = self.pack['bands']['boil']
        a, b = self.marks.boil_pair(0.35)
        boil = inkstats.boil(inkstats.one(a), inkstats.one(b))
        self.assertGreaterEqual(boil, lo)
        self.assertLessEqual(boil, hi)
        full_a, full_b = self.marks.boil_pair(1.0)
        over = inkstats.boil(inkstats.one(full_a), inkstats.one(full_b))
        self.assertGreater(over, hi)
        under_a, under_b = self.marks.boil_pair(0.0)
        under = inkstats.boil(inkstats.one(under_a), inkstats.one(under_b))
        self.assertLess(under, lo)


if __name__ == '__main__':
    unittest.main()
