"""Checks for embed.py and gallery.py."""
import json
import pathlib
import sys
import tempfile
import unittest

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


if __name__ == "__main__":
    unittest.main()
