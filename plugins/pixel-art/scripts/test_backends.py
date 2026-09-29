"""End-to-end adapter tests. Paid binaries and APIs are stand-ins that speak the documented contract."""
import base64
import contextlib
import io
import json
import pathlib
import stat
import sys
import tempfile
import unittest
import unittest.mock

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import aseprite_backend  # noqa: E402
import backends  # noqa: E402
import image_pipeline  # noqa: E402
import palette as palette_mod  # noqa: E402
import render  # noqa: E402

SPEC = {
    "palette": {"k": "#000000", "r": "#ff0000"},
    "frames": {"a": ["kr", "rk"]},
    "animations": {"blink": {"frames": ["a"], "fps": 4}},
}
SCRIPTS = str(pathlib.Path(__file__).parent)


def solid_png(width, height):
    rows = []
    for y in range(height):
        color = (0, 0, 0, 255) if y < height // 2 else (255, 0, 0, 255)
        rows.append([color] * width)
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "f.png"
        render.write_png(path, width, height, rows)
        return base64.b64encode(path.read_bytes()).decode()


PNG_B64 = solid_png(32, 32)


def write_fake_aseprite(directory):
    log = directory / "aseprite.log"
    fake = directory / "aseprite"
    fake.write_text(_FAKE_BODY.format(executable=sys.executable, scripts=SCRIPTS, log=str(log)))
    fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
    return fake, log


_FAKE_BODY = r"""#!{executable}
import json, os, pathlib, sys, tempfile
sys.path.insert(0, {scripts!r})
import render
log = pathlib.Path({log!r})
argv = sys.argv[1:]
with log.open("a") as handle:
    handle.write(json.dumps(argv) + "\n")
if "--version" in argv:
    print("Aseprite 1.3.18.6")
    raise SystemExit(0)

def param(key):
    prefix = key + "="
    for i, arg in enumerate(argv):
        if arg == "--script-param" and i + 1 < len(argv) and argv[i + 1].startswith(prefix):
            return argv[i + 1].split("=", 1)[1]
    return None

if "--script" in argv:
    if "--script-param" in argv[argv.index("--script"):]:
        raise SystemExit("a --script-param after --script is unset when the script runs")
    ase = pathlib.Path(param("ase"))
    ase.write_text(json.dumps({{"spec": param("spec")}}))
    raise SystemExit(0)

def flag(name):
    return argv[argv.index(name) + 1]

ase = next(pathlib.Path(arg) for arg in argv if arg.endswith(".aseprite"))
spec = json.loads(pathlib.Path(json.loads(ase.read_text())["spec"]).read_text())
with tempfile.TemporaryDirectory() as tmp:
    out = pathlib.Path(tmp)
    render.render(spec, out, 1)
    pathlib.Path(flag("--sheet")).write_bytes((out / "sheet.png").read_bytes())
    # Like the generated Lua: one frame per sheet slot, null cells included. Like Aseprite: keys
    # follow the default filename format ("<title> <frame index>.<extension>"), not the spec names,
    # and meta.image is the absolute --sheet path.
    order = spec.get("sheet", {{}}).get("order") or list(spec["frames"])
    if os.environ.get("FAKE_ASEPRITE_DROP_FRAME"):
        order = order[:-1]
    index = {{name: i for i, name in enumerate(order) if name}}
    tags = []
    for name, anim in spec.get("animations", {{}}).items():
        slots = [index[frame] for frame in anim["frames"] if frame in index]
        if slots:
            tags.append({{"name": name, "from": min(slots), "to": max(slots), "direction": "forward"}})
    meta = {{
        "frames": {{
            "source %d.aseprite" % i: {{"frame": {{"x": 0, "y": 0, "w": 2, "h": 2}}, "duration": 250}}
            for i in range(len(order))
        }},
        "meta": {{
            "app": "http://www.aseprite.org/",
            "version": "1.3.18.6",
            "image": str(pathlib.Path(flag("--sheet")).resolve()),
            "format": "RGBA8888",
            "size": {{"w": 2, "h": 2}},
            "scale": "1",
            "frameTags": tags,
            "layers": [{{"name": "Layer 1"}}],
            "slices": [],
        }},
    }}
    pathlib.Path(flag("--data")).write_text(json.dumps(meta))
"""


def quiet_env(**extra):
    env = {"PATH": "/usr/bin:/bin"}
    env.update(extra)
    return env


class BackendTest(unittest.TestCase):
    def test_downscale_samples_cell_center(self):
        red, black = (255, 0, 0, 255), (0, 0, 0, 255)
        rows = [
            [red, red, black, black],
            [red, red, black, black],
            [black, black, red, red],
            [black, black, red, red],
        ]
        scaled = image_pipeline.cell_downscale(rows, 2, 2)
        self.assertEqual(scaled, [[red, black], [black, red]])

    def test_partial_alpha_becomes_transparent(self):
        rows = [[(255, 0, 0, 10), (255, 0, 0, 255)]]
        frame = image_pipeline.frame_from_rgba(rows, SPEC["palette"], 2, 1)
        self.assertEqual(frame, [".r"])

    def test_lua_uses_the_documented_api(self):
        lua = aseprite_backend.build_lua(SPEC)
        for needle in ("json.decode", "Sprite(", "ColorMode.RGB", "app.pixelColor.rgba",
                       "image:drawPixel", "sprite:newTag", "sprite:saveAs", "app.params"):
            self.assertIn(needle, lua)
        argv = aseprite_backend.export_argv("aseprite", "a.aseprite", "sheet.png", "sheet.json", 1)
        self.assertIn("--batch", argv)
        self.assertIn("json-hash", argv)
        self.assertIn("--list-tags", argv)

    def test_unknown_backend_falls_back_to_native(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "out"
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                files = backends.run(SPEC, out, "pixellab", 1, None, quiet_env())
            self.assertIn("Unknown backend pixellab", buf.getvalue())
            self.assertIn("sheet.png", files)

    def test_stale_backend_flag_falls_back_through_main(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            spec = root / "spec.json"
            spec.write_text(json.dumps(SPEC))
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                code = backends.main([str(spec), "--out", str(root / "out"), "--backend", "pixellab"])
            self.assertEqual(code, 0)
            self.assertIn("Unknown backend pixellab", buf.getvalue())

    def test_removed_service_keys_stay_out_of_aseprite(self):
        seen = {}

        def fake(spec, out_dir, scale, spec_path, env):
            seen.update(env)

        env = quiet_env(PIXELLAB_API_TOKEN="x", RD_API_KEY="y")
        with unittest.mock.patch.object(backends, "_run_aseprite", fake):
            backends.run(SPEC, "out", "aseprite", 1, None, env)
        self.assertNotIn("PIXELLAB_API_TOKEN", seen)
        self.assertNotIn("RD_API_KEY", seen)
        self.assertEqual(seen["PATH"], "/usr/bin:/bin")

    def test_native_and_missing_aseprite(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "out"
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                files = backends.run(SPEC, out, "native", 2, None, quiet_env())
            self.assertIn("sheet.png", files)
            self.assertTrue((out / "blink.gif").is_file())
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                backends.run(SPEC, out, "aseprite", 2, None, quiet_env(PATH=tmp))
            self.assertIn("Aseprite not found on PATH", buf.getvalue())
            self.assertFalse((out / "source.aseprite").exists())

    def test_aseprite_stand_in_exports_real_json_shape(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            fake, log = write_fake_aseprite(root)
            out = root / "out"
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                files = backends.run(SPEC, out, "aseprite", 2, None, quiet_env(ASEPRITE=str(fake), PATH=tmp))
            self.assertIn("source.aseprite", files)
            sheet = json.loads((out / "sheet.json").read_text())
            self.assertEqual(sheet["meta"]["frameTags"][0]["from"], 0)
            self.assertIn("layers", sheet["meta"])
            self.assertEqual(list(sheet["frames"]), ["a"])
            self.assertEqual(sheet["meta"]["image"], "sheet.png")
            self.assertEqual(sheet["meta"]["frameTags"][0]["name"], "blink")
            self.assertTrue((out / "preview.png").is_file())
            self.assertTrue((out / "blink.gif").is_file())
            _w, _h, rows = palette_mod.read_png(out / "sheet.png")
            self.assertEqual(image_pipeline.palette_violations(rows, SPEC["palette"]), 0)
            logged = log.read_text()
            self.assertIn("--script", logged)
            self.assertIn("--batch", logged)
            self.assertIn("json-hash", logged)
            self.assertIn("Aseprite", buf.getvalue())

    def test_aseprite_falls_back_when_a_tag_is_split(self):
        spec = {
            "palette": SPEC["palette"],
            "frames": {"a": ["kr", "rk"], "b": ["rr", "kk"], "c": ["kk", "rr"]},
            "animations": {"hop": {"frames": ["a", "c"], "fps": 4}},
        }
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            fake, _log = write_fake_aseprite(root)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                backends.run(spec, root / "out", "aseprite", 1, None, quiet_env(ASEPRITE=str(fake), PATH=tmp))
            self.assertIn("contiguous", buf.getvalue())
            self.assertFalse((root / "out" / "source.aseprite").exists())

    def test_aseprite_frames_map_to_spec_names_across_null_cells(self):
        spec = {
            "palette": SPEC["palette"],
            "frames": {"a": ["kr", "rk"], "b": ["rr", "kk"]},
            "sheet": {"columns": 2, "order": ["a", None, "b"]},
            "animations": {"hop": {"frames": ["a"], "fps": 4}, "land": {"frames": ["b"], "fps": 4}},
        }
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            fake, _log = write_fake_aseprite(root)
            out = root / "out"
            with contextlib.redirect_stdout(io.StringIO()):
                backends.run(spec, out, "aseprite", 1, None, quiet_env(ASEPRITE=str(fake), PATH=tmp))
            sheet = json.loads((out / "sheet.json").read_text())
            self.assertEqual(list(sheet["frames"]), ["a", "b"])
            self.assertEqual(sheet["meta"]["image"], "sheet.png")
            tags = {tag["name"]: (tag["from"], tag["to"]) for tag in sheet["meta"]["frameTags"]}
            self.assertEqual(tags, {"hop": (0, 0), "land": (1, 1)})

    def test_aseprite_frame_count_mismatch_falls_back_without_a_partial_sheet(self):
        spec = dict(SPEC, frames={"a": ["kr", "rk"], "b": ["rr", "kk"]})
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            fake, _log = write_fake_aseprite(root)
            out = root / "out"
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                backends.run(spec, out, "aseprite", 1, None,
                             quiet_env(ASEPRITE=str(fake), PATH=tmp, FAKE_ASEPRITE_DROP_FRAME="1"))
            self.assertIn("1 frames for 2 sheet cells", buf.getvalue())
            self.assertFalse((out / "source.aseprite").exists())
            sheet = json.loads((out / "sheet.json").read_text())
            self.assertEqual(sheet["meta"]["app"], "pixel-art render.py")
            self.assertEqual(list(sheet["frames"]), ["a", "b"])

    def test_aseprite_rerender_drops_gifs_of_removed_animations(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            fake, _log = write_fake_aseprite(root)
            out = root / "out"
            env = quiet_env(ASEPRITE=str(fake), PATH=tmp)
            with contextlib.redirect_stdout(io.StringIO()):
                backends.run(SPEC, out, "aseprite", 1, None, env)
                renamed = dict(SPEC, animations={"wink": {"frames": ["a"], "fps": 4}})
                backends.run(renamed, out, "aseprite", 1, None, env)
            self.assertFalse((out / "blink.gif").exists())
            self.assertTrue((out / "wink.gif").is_file())

    def test_cli_ingest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            png = root / "in.png"
            blob = base64.b64decode(PNG_B64)
            png.write_bytes(blob)
            code = backends.main([
                "--ingest", str(png), "--palette", json.dumps(SPEC["palette"]),
                "--out", str(root / "out"), "--width", "32", "--height", "32", "--scale", "1",
            ])
            self.assertEqual(code, 0)
            self.assertTrue((root / "out" / "sheet.png").is_file())
            self.assertTrue((root / "out" / "all.gif").is_file())


if __name__ == "__main__":
    unittest.main()
