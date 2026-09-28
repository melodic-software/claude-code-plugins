"""The character kit renders a 4-direction walker and keeps presets apart."""
import json
import pathlib
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import kit  # noqa: E402
import render  # noqa: E402

WALKER = pathlib.Path(__file__).resolve().parents[1] / "examples" / "walker" / "blacksmith.py"


def rows_of(spec, name):
    return spec["frames"][name]


def material_span(canvas, names):
    ys = [y for y, row in enumerate(canvas.m) if any(cell in names for cell in row)]
    return (ys[-1] - ys[0] + 1) if ys else 0


def read_png_size(path):
    data = path.read_bytes()
    if data[12:16] != b"IHDR":
        raise AssertionError("not a png")
    return struct.unpack(">II", data[16:24])


class KitTest(unittest.TestCase):
    def test_blacksmith_sheet_renders_four_directions(self):
        sys.path.insert(0, str(WALKER.parent))
        import blacksmith  # noqa: E402

        spec = blacksmith.build()
        self.assertEqual(spec["sheet"]["columns"], 3)
        self.assertEqual(len(spec["frames"]), 12)
        self.assertEqual(set(spec["animations"]), {"walk_down", "walk_left", "walk_right", "walk_up"})
        walker = kit.Walker(size=48, preset="standard", ramps=blacksmith.RAMPS, hair="short", extra=blacksmith.apron)
        left = walker.materials("left", 0).m
        right = walker.materials("right", 0).m
        self.assertEqual(right, [row[::-1] for row in left])
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp)
            render.render(spec, out, scale=2)
            width, height = read_png_size(out / "sheet.png")
            self.assertEqual((width, height), (48 * 3, 48 * 4))
            meta = json.loads((out / "sheet.json").read_text())
            self.assertEqual(len(meta["frames"]), 12)
            self.assertTrue((out / "walk_down.gif").is_file())

    def test_presets_change_head_and_leg_span(self):
        heads, legs = {}, {}
        for name in ("chibi", "standard", "tall"):
            walker = kit.Walker(size=48, preset=name, hair="bangs")
            grid = walker.materials("down", 0)
            heads[name] = material_span(grid, {"skin", "hair"})
            legs[name] = material_span(grid, {"pants", "boot"})
        self.assertGreater(heads["chibi"], heads["standard"])
        self.assertGreater(heads["standard"], heads["tall"])
        self.assertGreater(legs["tall"], legs["chibi"])

    def test_selective_outline_uses_line_colors(self):
        walker = kit.Walker(size=32, preset="standard", hair="bald", head="square")
        spec = walker.spec()
        line_hexes = {ramp[3] for ramp in walker.ramps.values()}
        line_chars = {key for key, color in spec["palette"].items() if color in line_hexes}
        used = set("".join(spec["frames"]["down1"]))
        self.assertTrue(used & line_chars)
        self.assertNotIn(".", spec["palette"])
        render.validate(spec)

    def test_unknown_preset_is_rejected(self):
        with self.assertRaises(ValueError):
            kit.Walker(preset="giant")


if __name__ == "__main__":
    unittest.main()
