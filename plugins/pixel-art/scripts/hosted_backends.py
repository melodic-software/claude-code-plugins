"""PixelLab and Retro Diffusion HTTP adapters.

Both return raw pixels. Callers run `image_pipeline.frame_from_rgba` and then
the native renderer. Neither module imports a third-party HTTP library.
"""
import base64
import json
import pathlib
import tempfile
import time
import uuid
import urllib.error
import urllib.request

import palette as palette_mod

PIXELLAB_BASE = "https://api.pixellab.ai/v1"
PIXELLAB_MIN_AREA = 32 * 32
RETRO_BASE = "https://api.retrodiffusion.ai/v2"
RETRO_STYLE = "rd_plus__default"


class HostedError(Exception):
    """The remote call did not return a usable image. The caller falls back."""


def pixellab_size_ok(width, height):
    return width >= 1 and height >= 1 and width * height >= PIXELLAB_MIN_AREA and width <= 400 and height <= 400


def _request_json(url, method, headers, body, timeout):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")[:300]
        raise HostedError(f"HTTP {exc.code} from {url}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise HostedError(f"request to {url} failed: {exc.reason}") from exc
    except json.JSONDecodeError as exc:
        raise HostedError(f"response from {url} was not JSON") from exc


def decode_png_bytes(payload):
    """Accept raw base64 or a data:image/png;base64 URL."""
    if not isinstance(payload, str) or not payload:
        raise HostedError("image payload was empty")
    text = payload.strip()
    if text.startswith("data:"):
        marker = "base64,"
        if marker not in text:
            raise HostedError("data URL image had no base64 payload")
        text = text.split(marker, 1)[1]
    try:
        return base64.b64decode(text, validate=False)
    except (ValueError, TypeError) as exc:
        raise HostedError("image payload was not base64") from exc


def png_bytes_to_rows(blob):
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "frame.png"
        path.write_bytes(blob)
        try:
            _width, _height, rows = palette_mod.read_png(path)
        except ValueError as exc:
            raise HostedError(f"generated image was not a readable PNG: {exc}") from exc
    return rows


def pixellab_image(token, prompt, width, height, base_url=PIXELLAB_BASE, timeout=120):
    """POST /generate-image-pixflux. Returns RGBA rows."""
    if not pixellab_size_ok(width, height):
        raise HostedError(
            f"PixelLab image area must be between {PIXELLAB_MIN_AREA} and 400x400 pixels; got {width}x{height}"
        )
    body = {
        "description": prompt,
        "image_size": {"width": width, "height": height},
        "no_background": True,
    }
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    payload = _request_json(
        base_url.rstrip("/") + "/generate-image-pixflux", "POST", headers, body, timeout)
    image = payload.get("image") if isinstance(payload, dict) else None
    encoded = image.get("base64") if isinstance(image, dict) else None
    return png_bytes_to_rows(decode_png_bytes(encoded)), payload.get("usage")


def retrodiffusion_image(token, prompt, width, height, base_url=RETRO_BASE, timeout=120, polls=30, pause=2):
    """POST /v2/inferences and poll the task. Returns RGBA rows and the result object."""
    headers = {
        "X-RD-Token": token,
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Idempotency-Key": str(uuid.uuid4()),
    }
    body = {
        "prompt": prompt,
        "prompt_style": RETRO_STYLE,
        "width": width,
        "height": height,
        "num_images": 1,
    }
    root = base_url.rstrip("/")
    accepted = _request_json(root + "/inferences", "POST", headers, body, timeout)
    if isinstance(accepted, dict) and accepted.get("base64_images"):
        blob = decode_png_bytes(accepted["base64_images"][0])
        return png_bytes_to_rows(blob), accepted
    task_id = accepted.get("task_id") if isinstance(accepted, dict) else None
    if not task_id:
        raise HostedError("Retro Diffusion did not return a task_id")
    poll_headers = {"X-RD-Token": token, "Accept": "application/json"}
    task = None
    for _ in range(polls):
        task = _request_json(f"{root}/inferences/tasks/{task_id}", "GET", poll_headers, None, timeout)
        status = task.get("status") if isinstance(task, dict) else None
        if status in ("pending", "running", "accepted"):
            time.sleep(pause)
            continue
        if status == "failed":
            raise HostedError(f"Retro Diffusion task failed: {task.get('error', 'unknown')}")
        if status == "succeeded":
            result = task.get("result") or {}
            images = result.get("base64_images") or []
            if not images:
                raise HostedError("Retro Diffusion task succeeded with no image")
            return png_bytes_to_rows(decode_png_bytes(images[0])), result
        raise HostedError(f"Retro Diffusion task status {status!r} is not a terminal state")
    raise HostedError("Retro Diffusion task did not finish")
