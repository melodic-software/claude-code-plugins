"""Checks for embed.py and gallery.py."""
import json
import pathlib
import struct
import sys
import tempfile
import unittest
import wave

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import embed  # noqa: E402
import gallery  # noqa: E402


class ToolsTest(unittest.TestCase):
    def test_embed_inlines_json_relative_to_template(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = pathlib.Path(tmp)
            (d / "a.json").write_text(json.dumps({"k": [1, 2]}))
            (d / "t.html").write_text("<script>const A = /*EMBED:a.json*/null; const B = /*EMBED: a.json */null;</script>")
            self.assertEqual(embed.embed(d / "t.html", d / "out" / "s.html"), 2)
            self.assertIn('const A = {"k":[1,2]};', (d / "out" / "s.html").read_text())

    def test_embed_cannot_close_the_script(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = pathlib.Path(tmp)
            (d / "a.json").write_text(json.dumps({"k": "</script><b>"}))
            (d / "t.html").write_text("<script>const A = /*EMBED:a.json*/null;</script>")
            embed.embed(d / "t.html", d / "s.html")
            self.assertEqual((d / "s.html").read_text().count("</script>"), 1)

    def test_gallery_lists_media_and_skips_engine_sheet(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = pathlib.Path(tmp)
            for name in ("sheet.png", "preview.png", "walk.gif", "scene.html", "sheet.json"):
                (d / name).write_text("")
            page = gallery.build(d).read_text()
            for name in ("preview.png", "walk.gif", "scene.html"):
                self.assertIn(name, page)
            self.assertNotIn('src="sheet.png"', page)
            self.assertNotIn("sheet.json", page)


class WavEmbedTest(unittest.TestCase):
    def test_embed_inlines_wav_as_data_url(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = pathlib.Path(tmp)
            with wave.open(str(directory / "a.wav"), "w") as handle:
                handle.setnchannels(1)
                handle.setsampwidth(2)
                handle.setframerate(8000)
                handle.writeframes(struct.pack("<h", 1000))
            (directory / "t.html").write_text("<script>const A = /*WAV:a.wav*/null;</script>")
            self.assertEqual(embed.embed(directory / "t.html", directory / "s.html"), 1)
            text = (directory / "s.html").read_text()
            self.assertIn('"data:audio/wav;base64,', text)
            self.assertNotIn("/*WAV:", text)

    def test_campfire_wav_is_a_riff_file(self):
        wav = pathlib.Path(__file__).resolve().parents[1] / "examples" / "campfire" / "campfire.wav"
        data = wav.read_bytes()
        self.assertEqual(data[:4], b"RIFF")
        self.assertEqual(data[8:12], b"WAVE")
        scene = (wav.parent / "scene.html").read_text()
        self.assertIn("/*WAV:campfire.wav*/null", scene)
        self.assertIn("campfire.wav", (wav.parent / "AUDIO.txt").read_text())


if __name__ == "__main__":
    unittest.main()
