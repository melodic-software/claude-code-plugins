"""Round-trip checks for render.py: decode the PNG and GIF it writes and compare pixels."""
import json
import pathlib
import random
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import render  # noqa: E402

SPEC = {
    "palette": {"k": "#000000", "r": "#ff0000", "g": "#00ff00"},
    "frames": {"a": ["k.", "rg"], "b": ["gr", ".k"]},
    "animations": {"blink": {"frames": ["a", "b"], "fps": 4}},
    "sheet": {"columns": 1, "order": ["a", "b"]},
}


def read_png(path):
    data = path.read_bytes()
    pos, idat, width = 8, b"", 0
    while pos < len(data):
        (length,), tag = struct.unpack(">I", data[pos:pos + 4]), data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height = struct.unpack(">II", body[:8])
        elif tag == b"IDAT":
            idat += body
        pos += 12 + length
    raw, stride = zlib.decompress(idat), 1 + 4 * width
    return [[tuple(raw[y * stride + 1 + 4 * x:y * stride + 5 + 4 * x]) for x in range(width)] for y in range(height)]


def lzw_decode(body, min_code_size):
    clear, end = 1 << min_code_size, (1 << min_code_size) + 1
    acc = nbits = pos = 0
    size, table, prev, out = min_code_size + 1, None, None, []
    while True:
        while nbits < size:
            acc |= body[pos] << nbits
            pos += 1
            nbits += 8
        code = acc & ((1 << size) - 1)
        acc >>= size
        nbits -= size
        if code == clear:
            table, size, prev = [[i] for i in range(clear)] + [None, None], min_code_size + 1, None
            continue
        if code == end:
            return out
        if prev is None:
            entry = table[code]
        else:
            entry = table[code] if code < len(table) else table[prev] + table[prev][:1]
            if len(table) < 4096:
                table.append(table[prev] + entry[:1])
        out.extend(entry)
        prev = code
        if len(table) == (1 << size) and size < 12:
            size += 1


def read_gif_frames(path):
    data = path.read_bytes()
    bits = (data[10] & 7) + 1
    pos, frames = 13 + 3 * (1 << bits), []
    while data[pos] != 0x3B:
        if data[pos] == 0x21:
            pos += 2
            while data[pos]:
                pos += data[pos] + 1
            pos += 1
        else:
            min_code, pos, body = data[pos + 10], pos + 11, b""
            while data[pos]:
                body += data[pos + 1:pos + 1 + data[pos]]
                pos += data[pos] + 1
            pos += 1
            frames.append(lzw_decode(body, min_code))
    return frames


class RenderTest(unittest.TestCase):
    def test_sheet_png_and_gif_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp)
            render.render(SPEC, out, scale=2)
            sheet = read_png(out / "sheet.png")
            self.assertEqual(len(sheet), 4)
            self.assertEqual(sheet[0], [(0, 0, 0, 255), (0, 0, 0, 0)])
            self.assertEqual(sheet[3], [(0, 0, 0, 0), (0, 0, 0, 255)])
            self.assertEqual(len(read_png(out / "preview.png")), 8)
            frames = read_gif_frames(out / "blink.gif")
            self.assertEqual(frames[0][:4], [1, 1, 0, 0])  # 'k' 'k' '.' '.' at scale 2
            self.assertEqual(len(frames), 2)
            meta = json.loads((out / "sheet.json").read_text())
            self.assertEqual(meta["frames"]["b"]["frame"], {"x": 0, "y": 2, "w": 2, "h": 2})
            self.assertEqual(meta["meta"]["frameTags"][0]["durations_ms"], [250, 250])

    def test_lzw_survives_table_reset(self):
        rng = random.Random(1)
        indices = [rng.randrange(16) for _ in range(40000)]
        body = render.lzw_encode(indices, 4)
        self.assertEqual(lzw_decode(body, 4), indices)

    def test_rejects_unknown_colour_and_ragged_frame(self):
        bad = dict(SPEC, frames={"a": ["kx", "rg"], "b": ["gr", ".k"]})
        with self.assertRaisesRegex(ValueError, "not in the palette"):
            render.validate(bad)
        with self.assertRaisesRegex(ValueError, "is not 2x2"):
            render.validate(dict(SPEC, frames={"a": ["k.", "r"], "b": ["gr", ".k"]}))

    def test_rejects_animation_name_that_leaves_out_dir(self):
        with self.assertRaisesRegex(ValueError, "names the GIF file"):
            render.validate(dict(SPEC, animations={"../x": {"frames": ["a"], "fps": 4}}))

    def test_cli_exit_code_on_bad_spec(self):
        with tempfile.TemporaryDirectory() as tmp:
            spec = pathlib.Path(tmp) / "s.json"
            spec.write_text(json.dumps({"palette": {}, "frames": {}}))
            result = subprocess.run([sys.executable, str(pathlib.Path(__file__).parent / "render.py"), str(spec),
                                     "--out", tmp], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("non-empty", result.stderr)


if __name__ == "__main__":
    unittest.main()
