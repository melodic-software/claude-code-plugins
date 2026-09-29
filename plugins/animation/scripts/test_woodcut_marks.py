"""The woodcut residuals that are authoring, not a retuned check."""
import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

try:
    import inkstats
    import woodcut_marks
except ImportError as e:
    MISSING = str(e)
else:
    MISSING = None

PACK = HERE.parent / 'styles' / 'woodcut-ink' / 'style.json'


def band(name):
    return json.loads(PACK.read_text(encoding='utf-8'))['bands'][name]


@unittest.skipUnless(not MISSING, f'numpy/opencv missing: {MISSING}')
class WoodcutMarks(unittest.TestCase):
    def test_short_slits_sit_between_the_chunky_cut_and_the_cream_strip(self):
        lo, hi = band('sliver_caption')
        got = inkstats.one(woodcut_marks.caption_panel())['sliver_caption']
        self.assertGreaterEqual(got, lo)
        self.assertLessEqual(got, hi)
        chunky = inkstats.one(woodcut_marks.caption_panel(length=4))['sliver_caption']
        strip = inkstats.one(woodcut_marks.caption_panel(length=8))['sliver_caption']
        self.assertLess(chunky, lo)
        self.assertGreater(strip, hi)

    def test_four_pixel_tail_boils_inside_the_band(self):
        lo, hi = band('boil')

        def boil(mode):
            a, b = woodcut_marks.frame_pair(mode)
            return inkstats.boil(inkstats.one(a), inkstats.one(b))

        got = boil('tail')
        self.assertGreaterEqual(got, lo)
        self.assertLessEqual(got, hi)
        self.assertLess(boil('one'), lo)
        self.assertGreater(boil('two'), hi)


if __name__ == '__main__':
    unittest.main()
