"""The character kit renders a 4-direction walker and keeps light on the top-left."""
import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import character_kit as kit  # noqa: E402
import render  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]
WALKER = ROOT / "examples" / "kit-walker" / "walker.py"


class CharacterKitTest(unittest.TestCase):
    def test_chibi_head_is_taller_than_tall(self):
        chibi = kit.body_layout(48, "chibi")["head_h"]
        tall = kit.body_layout(48, "tall")["head_h"]
        self.assertGreater(chibi, tall)

    def test_shade_after_mirror_keeps_highlights_on_the_left(self):
        ramps = {"cloth": ["#ffffff", "#888888", "#444444", "#000000"]}

        def counts(grid):
            rows, palette = kit.shade_rows(grid, ramps)
            key = next(char for char, color in palette.items() if color == "#ffffff")
            left = sum(row[:8].count(key) for row in rows)
            right = sum(row[8:].count(key) for row in rows)
            return left, right

        block = kit.Grid(16, 16)
        block.rect(4, 4, 8, 8, "cloth")
        left_count, right_count = counts(block)
        mirrored_left, mirrored_right = counts(block.mirrored())
        self.assertGreater(left_count, right_count)
        self.assertGreater(mirrored_left, mirrored_right)

    def test_walker_sheet_has_four_directions(self):
        sys.path.insert(0, str(WALKER.parent))
        import walker  # noqa: E402

        spec = walker.build()
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp)
            render.render(spec, out, scale=2)
            meta = json.loads((out / "sheet.json").read_text())
            self.assertEqual(meta["meta"]["size"], {"w": 144, "h": 192})
        frames = spec["frames"]
        self.assertNotEqual(frames["down0"], frames["left0"])
        self.assertNotEqual(frames["down0"], frames["up0"])
        self.assertNotEqual(frames["left0"], frames["right0"])
        for name, rows in frames.items():
            ink = sum(row.count(".") < len(row) for row in rows)
            self.assertGreater(ink, 8, name)
            self.assertTrue(any(char != "." for row in rows for char in row), name)


if __name__ == "__main__":
    unittest.main()
