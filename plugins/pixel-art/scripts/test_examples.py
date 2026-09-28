"""Worked sheets for tileset, ui, and vfx match the engine grids they target."""
import importlib.util
import pathlib
import struct
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(pathlib.Path(__file__).parent))
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


class ExampleSheetTest(unittest.TestCase):
    def test_a2_ground_is_768_by_576(self):
        module = load("a2_ground", "examples/tileset/a2_ground.py")
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp)
            render.render(module.build(), out, scale=1)
            self.assertEqual(png_size(out / "sheet.png"), (768, 576))
            sheet = read_png(out / "sheet.png")
            self.assertNotEqual(sheet[0][0][3], 0)

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
            self.assertTrue((out / "spark.gif").exists())


if __name__ == "__main__":
    unittest.main()
