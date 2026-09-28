#!/usr/bin/env python3
"""Serve a scene and, when a browser is present, save timeline shots and an optional WebM.

The scene exposes window.__pixelScene.seek(seconds) and frameDataURL(scale)
(see reference/scene-canvas.md). This command is the scene review loop:

  capture.py <scene.html> --at 0,1.5,6 --record 4 --out <dir>

Exit 0 writes shot-<n>.png, optional scene.webm, and manifest.json.
Exit 3 means no browser tool was found. The scene is visually unreviewed.
"""
import argparse
import base64
import json
import os
import shutil
import signal
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

UNREVIEWED = (
    "visually unreviewed: no browser tool is present, so the scene was not captured"
)
BROWSERS = (
    "google-chrome",
    "google-chrome-stable",
    "chromium",
    "chromium-browser",
    "chrome",
)

RECORD_JS = r"""
(async () => {
  const scene = window.__pixelScene;
  if (!scene || typeof scene.seek !== "function" || typeof scene.frameDataURL !== "function") {
    return { error: "missing window.__pixelScene.seek or frameDataURL" };
  }
  const times = __TIMES__;
  const recordSeconds = __RECORD__;
  const scale = __SCALE__;
  const shots = [];
  for (const t of times) {
    scene.seek(t);
    shots.push({ t, png: scene.frameDataURL(scale) });
  }
  let webm = null;
  if (recordSeconds > 0) {
    const canvas = document.getElementById("screen");
    if (!canvas || !canvas.captureStream) return { error: "canvas captureStream is unavailable", shots };
    const fps = 30;
    const manual = canvas.captureStream(0).getVideoTracks()[0];
    const stream = new MediaStream([manual]);
    if (scene.audioStream && typeof scene.audioStream.getAudioTracks === "function") {
      for (const track of scene.audioStream.getAudioTracks()) stream.addTrack(track);
    }
    const mime = (typeof MediaRecorder !== "undefined" &&
      MediaRecorder.isTypeSupported("video/webm;codecs=vp8"))
      ? "video/webm;codecs=vp8" : "video/webm";
    const rec = new MediaRecorder(stream, { mimeType: mime });
    const chunks = [];
    rec.ondataavailable = (e) => { if (e.data && e.data.size) chunks.push(e.data); };
    const stopped = new Promise((resolve) => { rec.onstop = resolve; });
    rec.start(100);
    const frameCount = Math.round(recordSeconds * fps);
    for (let i = 0; i < frameCount; i++) {
      scene.seek(i / fps);
      if (typeof manual.requestFrame === "function") manual.requestFrame();
      await new Promise((resolve) => setTimeout(resolve, 1000 / fps));
    }
    if (typeof rec.requestData === "function") rec.requestData();
    rec.stop();
    await stopped;
    const bytes = new Uint8Array(await new Blob(chunks, { type: rec.mimeType }).arrayBuffer());
    let binary = "";
    for (let i = 0; i < bytes.length; i += 4096) {
      binary += String.fromCharCode.apply(null, Array.from(bytes.subarray(i, i + 4096)));
    }
    webm = { mime: rec.mimeType, b64: btoa(binary), frames: frameCount };
  }
  return { shots, webm };
})()
"""


def find_browser():
    override = os.environ.get("CAPTURE_BROWSER")
    if override:
        if os.path.isfile(override) or shutil.which(override):
            return override if os.path.isfile(override) else shutil.which(override)
        return None
    for name in BROWSERS:
        found = shutil.which(name)
        if found:
            return found
    return None


def parse_at(text):
    times = []
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        value = float(part)
        if value < 0:
            raise ValueError(f"timeline point {part} is negative")
        times.append(value)
    if not times:
        raise ValueError("--at needs at least one time in seconds")
    return times


def _read_exact(sock, buf, n):
    while len(buf) < n:
        chunk = sock.recv(max(65536, n - len(buf)))
        if not chunk:
            raise ConnectionError("browser socket closed")
        buf.extend(chunk)
    out = bytes(buf[:n])
    del buf[:n]
    return out


class BrowserSocket:
    """Tiny WebSocket client for Chrome's DevTools socket. Text frames only."""

    def __init__(self, sock, leftover):
        self.sock = sock
        self.buf = bytearray(leftover)

    def send_text(self, text):
        payload = text.encode()
        header = bytearray([0x81])
        mask = os.urandom(4)
        n = len(payload)
        if n < 126:
            header.append(0x80 | n)
        elif n < 65536:
            header.append(0x80 | 126)
            header.extend(struct.pack(">H", n))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack(">Q", n))
        header.extend(mask)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + masked)

    def _frame(self):
        header = _read_exact(self.sock, self.buf, 2)
        fin = header[0] & 0x80
        opcode = header[0] & 0x0F
        masked = header[1] & 0x80
        length = header[1] & 0x7F
        if length == 126:
            length = struct.unpack(">H", _read_exact(self.sock, self.buf, 2))[0]
        elif length == 127:
            length = struct.unpack(">Q", _read_exact(self.sock, self.buf, 8))[0]
        mask = _read_exact(self.sock, self.buf, 4) if masked else None
        payload = _read_exact(self.sock, self.buf, length)
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        return fin, opcode, payload

    def recv_text(self):
        parts = []
        while True:
            fin, opcode, payload = self._frame()
            if opcode == 9:
                self._pong(payload)
                continue
            if opcode == 8:
                raise ConnectionError("browser closed the debugger socket")
            if opcode == 10:
                continue
            if opcode in (0, 1):
                parts.append(payload)
                if fin:
                    return b"".join(parts).decode()

    def _pong(self, payload):
        header = bytearray([0x8A, 0x80 | len(payload)])
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + mask + masked)


def _ws_connect(ws_url):
    parsed = urllib.parse.urlparse(ws_url)
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query
    sock = socket.create_connection((parsed.hostname, parsed.port), timeout=20)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    key = base64.b64encode(os.urandom(16)).decode()
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {parsed.hostname}:{parsed.port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    )
    sock.sendall(request.encode())
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("debugger handshake failed")
        data += chunk
    head, rest = data.split(b"\r\n\r\n", 1)
    if b" 101 " not in head.split(b"\r\n", 1)[0]:
        raise ConnectionError(head.split(b"\r\n", 1)[0].decode(errors="replace"))
    return BrowserSocket(sock, rest)


class DevTools:
    def __init__(self, ws):
        self.ws = ws
        self.next_id = 0

    def call(self, method, params=None, timeout=30):
        self.next_id += 1
        mid = self.next_id
        self.ws.sock.settimeout(timeout)
        self.ws.send_text(json.dumps({"id": mid, "method": method, "params": params or {}}))
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.ws.sock.settimeout(max(0.1, deadline - time.time()))
            message = json.loads(self.ws.recv_text())
            if message.get("id") != mid:
                continue
            if "error" in message:
                raise RuntimeError(f"{method}: {message['error']}")
            return message.get("result", {})
        raise TimeoutError(method)


def _http_json(url, method="GET"):
    request = urllib.request.Request(url, data=b"" if method != "GET" else None, method=method)
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read().decode())


def _devtools_port(profile, proc):
    port_file = profile / "DevToolsActivePort"
    deadline = time.time() + 20
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"browser exited {proc.returncode} before the debugger opened")
        if port_file.is_file():
            line = port_file.read_text().splitlines()
            if line and line[0].isdigit():
                return int(line[0])
        time.sleep(0.1)
    raise TimeoutError("browser did not open a debugger port")


def _open_page(port, url):
    quoted = urllib.parse.quote(url, safe="")
    try:
        return _http_json(f"http://127.0.0.1:{port}/json/new?{quoted}", method="PUT")
    except urllib.error.HTTPError:
        return _http_json(f"http://127.0.0.1:{port}/json/new?{quoted}", method="GET")


def _serve(directory):
    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(directory), **kwargs)

        def log_message(self, fmt, *args):
            return

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


def _decode_data_url(value):
    header, encoded = value.split(",", 1)
    if "base64" not in header:
        raise ValueError("screenshot was not base64")
    return base64.b64decode(encoded)


def capture_scene(scene, times, out_dir, record, scale, browser):
    scene = Path(scene).resolve()
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    server = _serve(scene.parent)
    profile = out_dir / ".chrome-profile"
    if profile.exists():
        shutil.rmtree(profile)
    profile.mkdir()
    log_path = out_dir / "browser.log"
    proc = None
    log = None
    devtools = None
    try:
        port = server.server_address[1]
        page = f"http://127.0.0.1:{port}/{urllib.parse.quote(scene.name)}"
        log = log_path.open("w")
        proc = subprocess.Popen(
            [
                browser,
                "--headless=new",
                "--no-sandbox",
                "--disable-gpu",
                "--disable-dev-shm-usage",
                "--no-first-run",
                "--disable-extensions",
                "--autoplay-policy=no-user-gesture-required",
                "--disable-background-timer-throttling",
                "--disable-renderer-backgrounding",
                "--window-size=960,640",
                f"--user-data-dir={profile}",
                "--remote-debugging-port=0",
                "about:blank",
            ],
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        debug_port = _devtools_port(profile, proc)
        target = _open_page(debug_port, page)
        devtools = DevTools(_ws_connect(target["webSocketDebuggerUrl"]))
        deadline = time.time() + 15
        ready = False
        while time.time() < deadline:
            probed = devtools.call(
                "Runtime.evaluate",
                {"expression": "!!(window.__pixelScene && window.__pixelScene.seek)", "returnByValue": True},
            )
            if probed.get("result", {}).get("value"):
                ready = True
                break
            time.sleep(0.1)
        if not ready:
            raise RuntimeError("scene did not expose window.__pixelScene.seek")
        expression = (
            RECORD_JS.replace("__TIMES__", json.dumps(times))
            .replace("__RECORD__", json.dumps(record))
            .replace("__SCALE__", json.dumps(scale))
        )
        timeout = max(30, record + 20)
        evaluated = devtools.call(
            "Runtime.evaluate",
            {"expression": expression, "awaitPromise": True, "returnByValue": True},
            timeout=timeout,
        )
        if "exceptionDetails" in evaluated:
            detail = evaluated["exceptionDetails"].get("text", "scene capture failed")
            raise RuntimeError(detail)
        payload = evaluated.get("result", {}).get("value")
        if not isinstance(payload, dict):
            raise RuntimeError("capture script returned nothing")
        if payload.get("error"):
            raise RuntimeError(payload["error"])
        shots = []
        for index, shot in enumerate(payload["shots"]):
            name = f"shot-{index}.png"
            (out_dir / name).write_bytes(_decode_data_url(shot["png"]))
            shots.append({"t": shot["t"], "file": name})
        video = None
        if payload.get("webm"):
            (out_dir / "scene.webm").write_bytes(base64.b64decode(payload["webm"]["b64"]))
            video = "scene.webm"
        manifest = {
            "scene": scene.name,
            "browser": Path(browser).name,
            "shots": shots,
            "video": video,
        }
        (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        return manifest
    finally:
        if devtools is not None:
            devtools.ws.sock.close()
        if log is not None:
            log.close()
        server.shutdown()
        server.server_close()
        if proc and proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
        shutil.rmtree(profile, ignore_errors=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scene", help="self-contained scene HTML")
    parser.add_argument("--at", default="0,1.5,6", help="comma-separated timeline seconds")
    parser.add_argument("--record", type=float, default=0, help="WebM length in seconds; 0 skips video")
    parser.add_argument("--scale", type=int, default=3, help="nearest-neighbor scale of each shot")
    parser.add_argument("--out", required=True, help="directory for shots, video, and manifest.json")
    args = parser.parse_args(argv)
    scene = Path(args.scene)
    if not scene.is_file():
        print(f"capture.py: scene not found: {scene}", file=sys.stderr)
        return 2
    try:
        times = parse_at(args.at)
    except ValueError as exc:
        print(f"capture.py: {exc}", file=sys.stderr)
        return 2
    if args.record < 0:
        print("capture.py: --record must be >= 0", file=sys.stderr)
        return 2
    browser = find_browser()
    if browser is None:
        print(UNREVIEWED, file=sys.stderr)
        return 3
    try:
        manifest = capture_scene(scene, times, args.out, args.record, args.scale, browser)
    except (OSError, RuntimeError, TimeoutError, urllib.error.URLError, json.JSONDecodeError, ValueError) as exc:
        print(f"capture.py: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(manifest))
    return 0


if __name__ == "__main__":
    sys.exit(main())
