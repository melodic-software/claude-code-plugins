"""Worked sheets for tileset, ui, and vfx match the engine grids they target."""
import importlib.util
import contextlib
import io
import json
import pathlib
import struct
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import backends  # noqa: E402
import render  # noqa: E402
from test_render import read_png  # noqa: E402


def load(name, relative):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def png_size(path):
    data = path.read_bytes()
    return struct.unpack(">II", data[16:24])


def rgb_of(hex_color):
    return tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))


class ExampleSheetTest(unittest.TestCase):
    def test_a2_ground_is_768_by_576(self):
        module = load("a2_ground", "examples/tileset/a2_ground.py")
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp)
            render.render(module.build(), out, scale=1)
            self.assertEqual(png_size(out / "sheet.png"), (768, 576))
            sheet = read_png(out / "sheet.png")
            self.assertNotEqual(sheet[0][0][3], 0)
            meta = json.loads((out / "sheet.json").read_text())
            self.assertEqual(meta["meta"]["size"], {"w": 768, "h": 576})
            self.assertEqual(meta["frames"]["b00"]["frame"], {"x": 0, "y": 0, "w": 96, "h": 144})
            self.assertEqual(meta["frames"]["b08"]["frame"], {"x": 0, "y": 144, "w": 96, "h": 144})
            self.assertEqual(len(meta["frames"]), 32)
            # quarter source, block b00: every quarter of the edge region carries its own edge
            lip = {rgb_of("#c2a15a"), rgb_of("#9a7a3a")}
            for x, y in ((2, 100), (93, 100), (48, 50), (48, 141)):  # left, right, top, bottom edges
                self.assertIn(sheet[y][x][:3], lip, (x, y))
            self.assertNotIn(sheet[96][48][:3], lip)  # edge-region interior is grass
            self.assertIn(sheet[24][72][:3], lip)  # inner corners meet at the tile center
            self.assertNotIn(sheet[2][50][:3], lip)  # inner-corner tile rim stays grass
            self.assertNotIn(sheet[24][24][:3], lip)  # preview tile is plain terrain

    def test_window_png_is_192_and_regions_differ(self):
        module = load("window_mz", "examples/ui/window_mz.py")
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp)
            render.render(module.build(), out, scale=1)
            self.assertEqual(png_size(out / "sheet.png"), (192, 192))
            sheet = read_png(out / "sheet.png")
            background = sheet[0][0]
            frame = sheet[0][96]
            pattern = sheet[100][10]
            self.assertEqual(background[3], 255)
            self.assertNotEqual(background, frame)
            self.assertNotEqual(background, pattern)
            self.assertEqual(sheet[96][144][3], 255)  # pause sign
            self.assertEqual(sheet[24][132][:3], rgb_of("#f8f0c0"))  # up arrow
            self.assertEqual(sheet[150][102][:3], rgb_of(module.text_hex(0)))
            self.assertEqual(sheet[186][186][:3], rgb_of(module.text_hex(31)))
            meta = json.loads((out / "sheet.json").read_text())
            self.assertEqual(meta["frames"]["window"]["frame"], {"x": 0, "y": 0, "w": 192, "h": 192})
            self.assertEqual(meta["meta"]["size"], {"w": 192, "h": 192})

    def test_spark_sheet_is_five_columns(self):
        module = load("spark_mz", "examples/vfx/spark_mz.py")
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp)
            render.render(module.build(), out, scale=1)
            self.assertEqual(png_size(out / "sheet.png"), (960, 192))
            sheet = read_png(out / "sheet.png")
            # frame 0 center is the core; 20px right of that center is outside the small radius
            self.assertEqual(sheet[96][96][3], 255)
            self.assertEqual(sheet[96][116][3], 0)
            # frame 2 (column index 2) is the wide burst
            self.assertEqual(sheet[96][384 + 116][3], 255)
            # it fades by palette step: frame 3's core is the darker ramp color, frame 4 is empty
            self.assertEqual(sheet[96][576 + 96][:3], rgb_of("#e05020"))
            self.assertTrue(all(sheet[y][x][3] == 0 for y in range(192) for x in range(768, 960)))
            self.assertTrue((out / "spark.gif").exists())
            meta = json.loads((out / "sheet.json").read_text())
            self.assertEqual(meta["meta"]["size"], {"w": 960, "h": 192})
            self.assertEqual(meta["frames"]["fx0"]["frame"], {"x": 0, "y": 0, "w": 192, "h": 192})
            self.assertEqual(meta["frames"]["fx2"]["frame"], {"x": 384, "y": 0, "w": 192, "h": 192})
            self.assertEqual(meta["meta"]["frameTags"][0]["name"], "spark")


ROUTED = (
    ("a2_ground", "examples/tileset/a2_ground.py", 4),
    ("window_mz", "examples/ui/window_mz.py", 4),
    ("spark_mz", "examples/vfx/spark_mz.py", 2),
)


class BackendRoutingTest(unittest.TestCase):
    def test_native_backend_matches_render_for_tileset_ui_vfx(self):
        for name, relative, scale in ROUTED:
            with self.subTest(example=name), tempfile.TemporaryDirectory() as tmp:
                module = load(name, relative)
                direct, routed = pathlib.Path(tmp) / "direct", pathlib.Path(tmp) / "routed"
                expected = render.render(module.build(), direct, scale)
                with contextlib.redirect_stdout(io.StringIO()):
                    written = backends.run(module.build(), routed, "native", scale, None, {}, False)
                self.assertEqual(sorted(written), sorted(expected))
                self.assertEqual((routed / "sheet.png").read_bytes(), (direct / "sheet.png").read_bytes())

    def test_missing_aseprite_notice_then_native_artifact_for_tileset(self):
        module = load("a2_ground", "examples/tileset/a2_ground.py")
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "out"
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                backends.run(module.build(), out, "aseprite", 1, None, {"PATH": tmp}, False)
            self.assertEqual(buf.getvalue().strip(), backends.NOTICES["aseprite-missing"])
            self.assertTrue((out / "sheet.png").is_file())
            self.assertFalse((out / "source.aseprite").exists())


if __name__ == "__main__":
    unittest.main()
