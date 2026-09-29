"""End-to-end adapter tests. Paid binaries and APIs are stand-ins that speak the documented contract."""
import base64
import contextlib
import io
import json
import pathlib
import stat
import sys
import tempfile
import threading
import unittest
import unittest.mock
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

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


class Handler(BaseHTTPRequestHandler):
    seen = []

    def _read(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        raw = self.rfile.read(length) if length else b""
        body = json.loads(raw.decode() or "{}")
        self.seen.append((self.command, self.path, body, {k.lower(): v for k, v in self.headers.items()}))
        return body

    def _send(self, payload, status=200):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        self._read()
        if self.path.endswith("/generate-image-pixflux"):
            self._send({
                "image": {"type": "base64", "base64": "data:image/png;base64," + PNG_B64},
                "usage": {"type": "usd", "usd": 0.01},
            })
            return
        if self.path.endswith("/inferences"):
            self._send({"status": "accepted", "task_id": "task-1"})
            return
        self._send({"error": "not found"}, 404)

    def do_GET(self):
        self.seen.append((self.command, self.path, None, {k.lower(): v for k, v in self.headers.items()}))
        if "/inferences/tasks/" in self.path:
            self._send({
                "status": "succeeded",
                "result": {"base64_images": [PNG_B64], "balance_cost": 0.02, "remaining_balance": 1.0},
            })
            return
        self._send({"error": "not found"}, 404)

    def log_message(self, fmt, *args):
        return


def start_server():
    Handler.seen = []
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


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
    env = {"PATH": "/usr/bin:/bin", "PIXEL_ART_BACKEND_CONFIRM": ""}
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

    def test_native_and_missing_aseprite(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "out"
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                files = backends.run(SPEC, out, "native", 2, None, quiet_env(), False)
            self.assertIn("sheet.png", files)
            self.assertTrue((out / "blink.gif").is_file())
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                backends.run(SPEC, out, "aseprite", 2, None, quiet_env(PATH=tmp), False)
            self.assertIn("Aseprite not found on PATH", buf.getvalue())
            self.assertFalse((out / "source.aseprite").exists())

    def test_aseprite_stand_in_exports_real_json_shape(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            fake, log = write_fake_aseprite(root)
            out = root / "out"
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                files = backends.run(SPEC, out, "aseprite", 2, None, quiet_env(ASEPRITE=str(fake), PATH=tmp), False)
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

    def test_confirm_comes_from_flag_or_env(self):
        self.assertTrue(backends.confirmed(True, {}))
        self.assertTrue(backends.confirmed(False, {"PIXEL_ART_BACKEND_CONFIRM": "1"}))
        self.assertFalse(backends.confirmed(False, quiet_env()))

    def test_hosted_backends_require_confirm_then_snap(self):
        server = start_server()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        port = server.server_address[1]
        pix_base = f"http://127.0.0.1:{port}/v1"
        rd_base = f"http://127.0.0.1:{port}/v2"
        generated = {
            "palette": SPEC["palette"],
            "frames": SPEC["frames"],
            "animations": SPEC["animations"],
            "generate": {
                "prompt": "a red and black mark",
                "width": 32,
                "height": 32,
                "frames": [{"name": "a", "prompt": "a red and black mark"}],
            },
        }
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "out"
            env = quiet_env(PIXELLAB_API_TOKEN="token", PIXELLAB_API_BASE=pix_base, PATH=tmp)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                backends.run(generated, out, "pixellab", 1, None, env, False)
            self.assertIn("confirmation required", buf.getvalue())
            self.assertEqual(Handler.seen, [])
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                files = backends.run(generated, out, "pixellab", 1, None, env, True)
            self.assertIn("sheet.png", files)
            self.assertIn("usage.usd=0.01", buf.getvalue())
            self.assertEqual(Handler.seen[0][0], "POST")
            self.assertTrue(Handler.seen[0][1].endswith("/generate-image-pixflux"))
            self.assertEqual(Handler.seen[0][3].get("authorization"), "Bearer token")
            _w, _h, rows = palette_mod.read_png(out / "sheet.png")
            self.assertEqual(image_pipeline.palette_violations(rows, SPEC["palette"]), 0)
            self.assertEqual(len(rows), 32)

            Handler.seen = []
            env = quiet_env(RD_API_KEY="rdpk-test", RD_API_BASE=rd_base, PATH=tmp)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                backends.run(generated, out, "retrodiffusion", 1, None, env, False)
            self.assertIn("balance_cost", buf.getvalue())
            self.assertEqual(Handler.seen, [])
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                backends.run(generated, out, "retrodiffusion", 1, None, env, True)
            self.assertIn("balance_cost=0.02", buf.getvalue())
            posts = [item for item in Handler.seen if item[0] == "POST"]
            gets = [item for item in Handler.seen if item[0] == "GET"]
            self.assertTrue(posts[0][1].endswith("/inferences"))
            self.assertEqual(posts[0][3].get("x-rd-token"), "rdpk-test")
            self.assertIn("idempotency-key", posts[0][3])
            self.assertIn("/inferences/tasks/task-1", gets[0][1])
            _w, _h, rows = palette_mod.read_png(out / "sheet.png")
            self.assertEqual(image_pipeline.palette_violations(rows, SPEC["palette"]), 0)

    def test_tiny_pixellab_falls_back_without_a_call(self):
        server = start_server()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        port = server.server_address[1]
        spec = dict(SPEC)
        spec["generate"] = {"prompt": "tiny", "width": 2, "height": 2}
        env = quiet_env(
            PIXELLAB_API_TOKEN="token",
            PIXELLAB_API_BASE=f"http://127.0.0.1:{port}/v1",
        )
        with tempfile.TemporaryDirectory() as tmp:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                backends.run(spec, pathlib.Path(tmp) / "out", "pixellab", 1, None, env, True)
            self.assertIn("PixelLab failed", buf.getvalue())
            self.assertEqual(Handler.seen, [])

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
                backends.run(spec, root / "out", "aseprite", 1, None, quiet_env(ASEPRITE=str(fake), PATH=tmp), False)
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
                backends.run(spec, out, "aseprite", 1, None, quiet_env(ASEPRITE=str(fake), PATH=tmp), False)
            sheet = json.loads((out / "sheet.json").read_text())
            self.assertEqual(list(sheet["frames"]), ["a", "b"])
            self.assertEqual(sheet["meta"]["image"], "sheet.png")
            tags = {tag["name"]: (tag["from"], tag["to"]) for tag in sheet["meta"]["frameTags"]}
            self.assertEqual(tags, {"hop": (0, 0), "land": (2, 2)})

    def test_aseprite_frame_count_mismatch_falls_back_without_a_partial_sheet(self):
        spec = dict(SPEC, frames={"a": ["kr", "rk"], "b": ["rr", "kk"]})
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            fake, _log = write_fake_aseprite(root)
            out = root / "out"
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                backends.run(spec, out, "aseprite", 1, None,
                             quiet_env(ASEPRITE=str(fake), PATH=tmp, FAKE_ASEPRITE_DROP_FRAME="1"), False)
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
                backends.run(SPEC, out, "aseprite", 1, None, env, False)
                renamed = dict(SPEC, animations={"wink": {"frames": ["a"], "fps": 4}})
                backends.run(renamed, out, "aseprite", 1, None, env, False)
            self.assertFalse((out / "blink.gif").exists())
            self.assertTrue((out / "wink.gif").is_file())

    def test_generate_without_prompt_falls_back_to_native(self):
        spec = dict(SPEC, generate={})
        with tempfile.TemporaryDirectory() as tmp:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                files = backends.run(spec, pathlib.Path(tmp) / "out", "pixellab", 1, None,
                                     quiet_env(PIXELLAB_API_TOKEN="token"), True)
            self.assertIn("needs spec.generate.prompt", buf.getvalue())
            self.assertIn("sheet.png", files)

    def test_hosted_frames_keep_the_declared_sheet_layout(self):
        spec = dict(SPEC, sheet={"columns": 1, "order": ["b", "a"]},
                    generate={"prompt": "p", "width": 2, "height": 2, "frames": [{"name": "a"}, {"name": "b"}]})

        def red(_prompt, width, height):
            return [[(255, 0, 0, 255)] * width for _ in range(height)]

        with contextlib.redirect_stdout(io.StringIO()):
            built = backends._generate_frames(spec, red, None)
        self.assertEqual(built["sheet"], {"columns": 1, "order": ["b", "a"]})

    def test_main_honors_the_env_confirmation(self):
        seen = {}

        def fake_run(*args):
            seen["confirm"] = args[-1]
            return []

        with tempfile.TemporaryDirectory() as tmp:
            spec_path = pathlib.Path(tmp) / "spec.json"
            spec_path.write_text(json.dumps(SPEC))
            with unittest.mock.patch.object(backends, "run", fake_run), \
                    unittest.mock.patch.dict(backends.os.environ, {"PIXEL_ART_BACKEND_CONFIRM": "1"}), \
                    contextlib.redirect_stdout(io.StringIO()):
                backends.main([str(spec_path), "--out", str(pathlib.Path(tmp) / "out")])
        self.assertIs(seen["confirm"], True)

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
