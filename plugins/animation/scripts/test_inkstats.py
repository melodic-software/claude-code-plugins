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


def _jagged_frame(invade):
    """A connected square-wave frame line. invade fills the top ring with a straight bar."""
    h, w = 240, 360
    img = np.empty((h, w, 3), np.uint8)
    img[:] = (243, 234, 215)
    ink = (20, 17, 14)

    def jog(i):
        return 1 if (i // 10) % 2 == 0 else 3

    for x in range(w):
        y0 = jog(x)
        img[y0:y0 + 3, x] = ink
        y1 = h - 4 - jog(x)
        img[y1:y1 + 3, x] = ink
    for y in range(h):
        x0 = jog(y)
        img[y, x0:x0 + 3] = ink
        x1 = w - 4 - jog(y)
        img[y, x1:x1 + 3] = ink
    if invade:
        e = max(1, round(inkstats.BORDER * min(h, w)))
        img[0:e + 2, 40:w - 40] = ink
    return img


@unittest.skipUnless(not MISSING, f'numpy/opencv missing: {MISSING}')
class StraightBorderContact(unittest.TestCase):
    def test_subject_in_the_ring_does_not_pull_straight_border(self):
        clean = inkstats.one(_jagged_frame(False))
        invaded = inkstats.one(_jagged_frame(True))
        self.assertTrue(inkstats.clear_sides(clean['mask']).all())
        self.assertFalse(inkstats.clear_sides(invaded['mask'])[0])
        real = inkstats.clear_sides
        inkstats.clear_sides = lambda ink: np.ones(4, bool)
        try:
            raw = inkstats.one(_jagged_frame(True))['straight_border']
        finally:
            inkstats.clear_sides = real
        self.assertGreater(abs(raw - clean['straight_border']), 0.1)
        self.assertLess(abs(invaded['straight_border'] - clean['straight_border']), 0.03)


if __name__ == '__main__':
    unittest.main()
