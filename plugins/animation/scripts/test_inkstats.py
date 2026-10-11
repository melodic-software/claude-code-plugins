# test-scope: plugins/animation/requirements.in
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
class ShotsJsonCuts(unittest.TestCase):
    def test_shots_json_t0_values_are_the_cut_list(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = write_work(Path(tmp) / 'work', [0.0, 1.0, 2.0], 3.0, (16, 200, 80))
            shots = Path(tmp) / 'shots.json'
            shots.write_text(json.dumps({'shots': [
                {'t0': 0}, {'t0': 1.5},
            ]}), encoding='utf-8')
            cuts = inkstats.parse_cuts(str(shots))
            self.assertEqual(cuts, [0.0, 1.5])
            rows = inkstats.measure(work)
            segments = inkstats.summary(rows, cuts)['segments']
            self.assertEqual([round(g['t0'], 3) for g in segments], [0.0, 1.5])
            self.assertEqual(inkstats.parse_cuts('0,1.5'), [0.0, 1.5])


if __name__ == '__main__':
    unittest.main()
