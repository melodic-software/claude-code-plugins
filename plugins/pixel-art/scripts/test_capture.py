"""capture.py: unreviewed exit, and the campfire scene's timeline when a browser exists."""
import base64
import io
import json
import os
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from contextlib import contextmanager, redirect_stdout
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import capture  # noqa: E402
import embed  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]
CAMPFIRE = ROOT / "examples" / "campfire"


def png_rgba(path):
    data = pathlib.Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a png")
    pos = 8
    width = height = None
    channels = None
    idat = b""
    while pos < len(data):
        length, tag = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
            if bit_depth != 8 or color_type not in (2, 6):
                raise ValueError(f"unsupported png {bit_depth} {color_type}")
            channels = 4 if color_type == 6 else 3
        elif tag == b"IDAT":
            idat += chunk
        elif tag == b"IEND":
            break
    raw = zlib.decompress(idat)
    stride = width * channels
    rows = []
    index = 0
    prev = bytearray(stride)

    def paeth(left, up, up_left):  # identifier, not prose # spellchecker:disable-line
        estimate = left + up - up_left
        if abs(estimate - left) <= abs(estimate - up) and abs(estimate - left) <= abs(estimate - up_left):
            return left
        if abs(estimate - up) <= abs(estimate - up_left):
            return up
        return up_left

    for _ in range(height):
        filt = raw[index]
        index += 1
        row = bytearray(raw[index:index + stride])
        index += stride
        for x in range(stride):
            left = row[x - channels] if x >= channels else 0
            up = prev[x]
            up_left = prev[x - channels] if x >= channels else 0
            if filt == 1:
                row[x] = (row[x] + left) & 255
            elif filt == 2:
                row[x] = (row[x] + up) & 255
            elif filt == 3:
                row[x] = (row[x] + ((left + up) // 2)) & 255
            elif filt == 4:
                row[x] = (row[x] + paeth(left, up, up_left)) & 255  # identifier, not prose # spellchecker:disable-line
        prev = row
        if channels == 3:
            expanded = bytearray()
            for x in range(0, stride, 3):
                expanded.extend(row[x:x + 3])
                expanded.append(255)
            row = expanded
        rows.append(row)
    return width, height, rows


def count_tunic(rows):
    """VP8 shifts exact palette colors, so match the tunic's blue cluster."""
    found = 0
    for row in rows:
        for x in range(0, len(row), 4):
            red, green, blue, alpha = row[x:x + 4]
            if alpha and blue > 140 and blue > red + 40 and blue > green:
                found += 1
    return found


PNG_URL = "data:image/png;base64," + base64.b64encode(b"\x89PNG fake").decode()


class FakeDevTools:
    """Answers the readiness probe, then returns the canned capture payload."""

    def __init__(self, payload):
        self.payload = payload
        self.ws = SimpleNamespace(sock=SimpleNamespace(close=lambda: None))

    def call(self, method, params=None, timeout=None):
        if (params or {}).get("expression", "").startswith("!!("):
            return {"result": {"value": True}}
        return {"result": {"value": self.payload}}


@contextmanager
def fake_browser(payload=None, setup_error=None):
    """Patch every browser touchpoint of capture_scene; yield what the fakes saw."""
    seen = {}

    def serve(directory):
        seen["served"] = pathlib.Path(directory)
        seen["served_files"] = sorted(p.name for p in seen["served"].iterdir())
        return SimpleNamespace(server_address=("127.0.0.1", 1), shutdown=lambda: None, server_close=lambda: None)

    def devtools_port(profile, proc):
        if setup_error:
            raise setup_error
        return 1

    proc = SimpleNamespace(poll=lambda: 0, pid=0)
    with mock.patch.object(capture, "find_browser", return_value="chrome"), \
            mock.patch.object(capture, "_serve", serve), \
            mock.patch.object(capture.subprocess, "Popen", return_value=proc), \
            mock.patch.object(capture, "_devtools_port", devtools_port), \
            mock.patch.object(capture, "_open_page", return_value={"webSocketDebuggerUrl": "ws://x"}), \
            mock.patch.object(capture, "_ws_connect", return_value=None), \
            mock.patch.object(capture, "DevTools", lambda ws: FakeDevTools(payload)):
        yield seen


class CaptureTest(unittest.TestCase):
    def scene_and_out(self, tmp):
        scene = pathlib.Path(tmp) / "src" / "scene.html"
        scene.parent.mkdir()
        scene.write_text("<!doctype html>")
        (scene.parent / "sibling.txt").write_text("private")
        return scene, pathlib.Path(tmp) / "out"

    def test_parse_at(self):
        self.assertEqual(capture.parse_at("0, 1.5, 6"), [0.0, 1.5, 6.0])
        for bad in ("inf", "nan", "-1"):
            with self.assertRaises(ValueError):
                capture.parse_at(bad)

    def test_non_finite_record_is_rejected_before_any_capture(self):
        with tempfile.TemporaryDirectory() as tmp:
            scene, out = self.scene_and_out(tmp)
            for bad in ("inf", "-inf", "nan", "-1"):
                with mock.patch.object(capture, "find_browser", side_effect=AssertionError("browser looked up")), \
                        mock.patch.object(capture, "capture_scene", side_effect=AssertionError("capture ran")):
                    code = capture.main([str(scene), f"--record={bad}", "--out", str(out)])
                self.assertEqual(code, 2, bad)

    def test_setup_failure_cleans_stale_artifacts_and_temp_dirs(self):
        with tempfile.TemporaryDirectory() as tmp:
            scene, out = self.scene_and_out(tmp)
            out.mkdir()
            stale = ["shot-0.png", "shot-7.png", "scene.webm", "manifest.json"]
            for name in stale:
                (out / name).write_bytes(b"old")
            with fake_browser(setup_error=RuntimeError("no devtools")) as seen:
                with self.assertRaisesRegex(RuntimeError, "no devtools"):
                    capture.capture_scene(scene, [0], out, 0, 1, "chrome")
            for name in stale:
                self.assertFalse((out / name).exists(), name)
            self.assertFalse((out / ".chrome-profile").exists())
            self.assertFalse(seen["served"].exists())

    def test_default_record_skips_video(self):
        payload = {"shots": [{"t": 0, "png": PNG_URL}]}
        with tempfile.TemporaryDirectory() as tmp:
            scene, out = self.scene_and_out(tmp)
            with fake_browser(payload), redirect_stdout(io.StringIO()):
                self.assertEqual(capture.main([str(scene), "--at", "0", "--out", str(out)]), 0)
            manifest = json.loads((out / "manifest.json").read_text())
            self.assertIsNone(manifest["video"])
            self.assertEqual([s["file"] for s in manifest["shots"]], ["shot-0.png"])
            self.assertFalse((out / "scene.webm").exists())

    def test_recording_failure_keeps_shots_and_fails_the_run(self):
        payload = {"shots": [{"t": 0, "png": PNG_URL}, {"t": 1, "png": PNG_URL}], "error": "recorder died"}
        with tempfile.TemporaryDirectory() as tmp:
            scene, out = self.scene_and_out(tmp)
            with fake_browser(payload):
                with self.assertRaisesRegex(RuntimeError, r"recorder died \(2 shots written\)"):
                    capture.capture_scene(scene, [0, 1], out, 2, 1, "chrome")
                self.assertEqual(capture.main([str(scene), "--at", "0,1", "--record", "2", "--out", str(out)]), 1)
            self.assertEqual(sorted(p.name for p in out.glob("shot-*.png")), ["shot-0.png", "shot-1.png"])
            self.assertFalse((out / "manifest.json").exists())

    def test_scene_is_served_from_a_temp_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            scene, out = self.scene_and_out(tmp)
            with fake_browser({"shots": [{"t": 0, "png": PNG_URL}]}) as seen:
                capture.capture_scene(scene, [0], out, 0, 1, "chrome")
            self.assertNotEqual(seen["served"], scene.parent)
            self.assertEqual(seen["served_files"], ["scene.html"])

    def test_example_exposes_capture_contract(self):
        text = (CAMPFIRE / "scene.html").read_text()
        self.assertIn("window.__pixelScene", text)
        self.assertIn("seek(seconds)", text)
        self.assertIn("frameDataURL", text)

    def test_missing_browser_is_visually_unreviewed(self):
        with tempfile.TemporaryDirectory() as tmp:
            scene = pathlib.Path(tmp) / "scene.html"
            scene.write_text("<!doctype html><canvas id='screen'></canvas>")
            saved = os.environ.get("PATH")
            override = os.environ.pop("CAPTURE_BROWSER", None)
            os.environ["PATH"] = str(pathlib.Path(tmp) / "empty")
            try:
                code = capture.main([str(scene), "--at", "0", "--out", str(pathlib.Path(tmp) / "out")])
            finally:
                os.environ["PATH"] = saved
                if override is not None:
                    os.environ["CAPTURE_BROWSER"] = override
            self.assertEqual(code, 3)

    @unittest.skipUnless(capture.find_browser(), "no local browser")
    def test_campfire_shots_and_video_timing(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = pathlib.Path(tmp)
            shutil.copy(CAMPFIRE / "hero_mz.py", work / "hero_mz.py")
            shutil.copy(CAMPFIRE / "scene.html", work / "scene.html")
            shutil.copy(CAMPFIRE / "campfire.wav", work / "campfire.wav")
            subprocess.check_call([sys.executable, str(work / "hero_mz.py")], cwd=work)
            embed.embed(work / "scene.html", work / "campfire.html")
            out = work / "capture"
            code = capture.main([
                str(work / "campfire.html"),
                "--at", "0,3",
                "--record", "4",
                "--scale", "2",
                "--out", str(out),
            ])
            self.assertEqual(code, 0, (out / "browser.log").read_text() if (out / "browser.log").is_file() else "")
            early = count_tunic(png_rgba(out / "shot-0.png")[2])
            later = count_tunic(png_rgba(out / "shot-1.png")[2])
            self.assertEqual(early, 0)
            self.assertGreater(later, 20)
            webm = out / "scene.webm"
            self.assertGreater(webm.stat().st_size, 1000)
            if not (shutil.which("ffprobe") and shutil.which("ffmpeg")):
                self.skipTest("shots checked; ffprobe/ffmpeg absent, so video timing is unchecked")
            probe = subprocess.run(
                [
                    "ffprobe", "-v", "error", "-select_streams", "v:0",
                    "-show_entries", "frame=best_effort_timestamp_time",
                    "-of", "csv=p=0", str(webm),
                ],
                check=True, capture_output=True, text=True,
            )
            stamps = [float(line) for line in probe.stdout.splitlines() if line.strip()]
            self.assertGreater(len(stamps), 30)
            self.assertGreater(stamps[-1], 3.0)
            self.assertLess(stamps[-1], 5.5)
            for stamp, name in (("0.3", "frame-early.png"), ("3.0", "frame-late.png")):
                subprocess.check_call([
                    "ffmpeg", "-y", "-i", str(webm), "-ss", stamp, "-frames:v", "1", str(out / name),
                ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            video_early = count_tunic(png_rgba(out / "frame-early.png")[2])
            video_late = count_tunic(png_rgba(out / "frame-late.png")[2])
            self.assertEqual(video_early, 0)
            self.assertGreater(video_late, 10)


if __name__ == "__main__":
    unittest.main()
