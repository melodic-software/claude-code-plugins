# test-scope: plugins/pixel-art/palettes/*.json
"""Preset resolution and palette snapping."""
import json
import pathlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import palette  # noqa: E402
import render  # noqa: E402
from test_render import read_png  # noqa: E402


def png_chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def raw_png(width, height, bit_depth, color_type, interlace, rows_bytes, extra=b""):
    ihdr = struct.pack(">IIBBBBB", width, height, bit_depth, color_type, 0, 0, interlace)
    raw = b"".join(rows_bytes)
    return b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + extra + png_chunk(b"IDAT", zlib.compress(raw)) + png_chunk(b"IEND", b"")


class PaletteTest(unittest.TestCase):
    def test_preset_and_project_file_render(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp)
            spec_path = out / "icon.json"
            spec_path.write_text(json.dumps({
                "palette": "pico-8",
                "frames": {"icon": ["8."]},
            }))
            render.render(json.loads(spec_path.read_text()), out / "pico", spec_path=spec_path)
            sheet = read_png(out / "pico" / "sheet.png")
            self.assertEqual(sheet[0][0], (255, 0, 77, 255))
            self.assertEqual(sheet[0][1], (0, 0, 0, 0))

            project = out / "mine.json"
            project.write_text(json.dumps({"colors": [{"hex": "#112233"}, {"hex": "#abcdef"}]}))
            spec_path.write_text(json.dumps({
                "palette": "mine.json",
                "frames": {"icon": ["01"]},
            }))
            render.render(json.loads(spec_path.read_text()), out / "proj", spec_path=spec_path)
            sheet = read_png(out / "proj" / "sheet.png")
            self.assertEqual(sheet[0][0], (0x11, 0x22, 0x33, 255))
            self.assertEqual(sheet[0][1], (0xAB, 0xCD, 0xEF, 255))

    def test_unknown_preset_names_the_available_list(self):
        with self.assertRaisesRegex(ValueError, "available: cosmic-space, deep-sea, game-boy, nes, pico-8, retro-8-bit"):
            palette.resolve_palette("nope", pathlib.Path("."))

    def test_inline_object_is_unchanged(self):
        spec = {"palette": {"k": "#000000", "r": "#ff0000"}, "frames": {"a": ["k."]}}
        self.assertIs(palette.prepare_spec(spec), spec)

    def test_snap_alpha_threshold_and_dither(self):
        black_white = {"k": "#000000", "w": "#ffffff"}
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp)
            source = out / "src.png"
            render.write_png(source, 2, 1, [[(200, 200, 200, 127), (200, 200, 200, 128)]])
            render.snap_image(source, json.dumps(black_white), out / "snap.png")
            snapped = read_png(out / "snap.png")
            self.assertEqual(snapped[0][0], (0, 0, 0, 0))
            self.assertEqual(snapped[0][1], (255, 255, 255, 255))

            gray = [[(128, 128, 128, 255) for _ in range(4)] for _ in range(4)]
            render.write_png(out / "gray.png", 4, 4, gray)
            render.snap_image(out / "gray.png", json.dumps(black_white), out / "flat.png")
            flat = read_png(out / "flat.png")
            self.assertTrue(all(px == (255, 255, 255, 255) for row in flat for px in row))
            render.snap_image(out / "gray.png", json.dumps(black_white), out / "dither.png", dither=True)
            dithered = read_png(out / "dither.png")
            black, white = (0, 0, 0, 255), (255, 255, 255, 255)
            expect = [
                [black, white, black, white],
                [white, black, white, black],
                [black, white, black, white],
                [white, black, white, black],
            ]
            self.assertEqual(dithered, expect)

            # alpha below 128 stays transparent even where the dither offset is nonzero
            render.write_png(out / "fade.png", 1, 1, [[(128, 128, 128, 127)]])
            render.snap_image(out / "fade.png", json.dumps(black_white), out / "fade-out.png", dither=True)
            self.assertEqual(read_png(out / "fade-out.png")[0][0], (0, 0, 0, 0))

    def test_reads_sub_filtered_rgb_and_rejects_other_pngs(self):
        # one RGB pixel, filter Sub: stored byte is the sample itself because left is 0
        raw = raw_png(1, 1, 8, 2, 0, [bytes([1, 10, 20, 30])])
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "rgb.png"
            path.write_bytes(raw)
            width, height, rows = palette.read_png(path)
            self.assertEqual((width, height), (1, 1))
            self.assertEqual(rows[0][0], (10, 20, 30, 255))

            path.write_bytes(raw_png(1, 1, 8, 3, 0, [b"\x00\x01"]))
            with self.assertRaisesRegex(ValueError, "color type 3"):
                palette.read_png(path)
            path.write_bytes(raw_png(1, 1, 8, 6, 1, [b"\x00\x00\x00\x00\x00"]))
            with self.assertRaisesRegex(ValueError, "interlaced"):
                palette.read_png(path)
            path.write_bytes(raw_png(1, 1, 4, 2, 0, [b"\x00\x00"]))
            with self.assertRaisesRegex(ValueError, "bit depth 4"):
                palette.read_png(path)
            path.write_bytes(raw_png(1, 1, 8, 2, 0, [bytes([0, 1, 2, 3])], extra=png_chunk(b"tRNS", b"\x00\x00\x00")))
            with self.assertRaisesRegex(ValueError, "tRNS"):
                palette.read_png(path)

    def test_cli_unknown_preset_and_emit_frames(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp)
            source = out / "src.png"
            render.write_png(source, 1, 1, [[(255, 0, 77, 255)]])
            script = pathlib.Path(__file__).parent / "render.py"
            bad = subprocess.run([sys.executable, str(script), "--snap", str(source), "--palette", "nope",
                                  "--out", str(out / "x.png")], capture_output=True, text=True)
            self.assertEqual(bad.returncode, 2)
            self.assertIn("pico-8", bad.stderr)
            self.assertIn("available:", bad.stderr)
            good = subprocess.run([sys.executable, str(script), "--snap", str(source), "--palette", "pico-8",
                                   "--out", str(out / "frames.json"), "--emit-frames"], capture_output=True, text=True)
            self.assertEqual(good.returncode, 0, good.stderr)
            spec = json.loads((out / "frames.json").read_text())
            self.assertEqual(spec["frames"]["snap"], ["8"])
            self.assertEqual(spec["palette"]["8"], "#ff004d")

    def test_bundled_presets_have_source_and_license(self):
        for path in palette.preset_dir().glob("*.json"):
            data = json.loads(path.read_text())
            self.assertTrue(data.get("source"), path.name)
            self.assertTrue(data.get("license"), path.name)
            self.assertGreaterEqual(len(data["colors"]), 4)
        nes = palette.resolve_palette("nes", pathlib.Path("."))
        self.assertEqual(len(nes), 64)
        self.assertEqual(nes["0"], "#525252")
        game_boy = palette.resolve_palette("game-boy", pathlib.Path("."))
        self.assertEqual(list(game_boy), ["0", "1", "2", "3"])
        self.assertEqual(game_boy["0"], "#8ca54a")
        self.assertEqual(game_boy["3"], "#182908")


if __name__ == "__main__":
    unittest.main()
