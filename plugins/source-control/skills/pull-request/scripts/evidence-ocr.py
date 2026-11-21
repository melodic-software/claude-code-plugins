"""Read each evidence capture's text with OCR and leak-scan it before the comment posts.

  python3 evidence-ocr.py [--mpdecimate-hi <n>] [--mask-stdin] <capture>...

The step that runs this is ../reference/evidence.md step 5. An image, or each frame ffmpeg's
mpdecimate keeps from a video or GIF, is upscaled and read by tesseract twice: as captured and
inverted, so dark-theme text also reaches tesseract as dark text on a light background. The text
goes through the evidence step's leak scan: the credential pattern, and with --mask-stdin the mask
values read from stdin, one per line, held in memory only. A hit names its capture and kind, never
the matched text. Everything runs on this machine; no image leaves it.

Exit: 0 every capture read and scanned clean, with the image and pass counts and the seconds taken;
1 ffmpeg or tesseract failed on a capture; 2 usage; 5 the leak scan found something; 6 a capture
yielded no text; 7 tesseract or ffmpeg is not installed.
A refusal writes one `evidence-ocr: refused <code>: <detail>` line to stderr.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DEFAULT_HI = 256
MAX_HI = 9999
MOVING = {".mp4", ".mov", ".webm", ".gif"}
STILL = {".png", ".jpg", ".jpeg", ".webp"}
UPSCALE = "scale=iw*2:ih*2:flags=lanczos,format=gray"
BOX_DRAWING = re.compile("[─-╿]")
LINE_WRAP = re.compile(r"\s*\n\s*")
SECRET_KEY = r"(?:token|secret|password|apikey|api_key)\w*[\"']?"
# The evidence step's body-scan shape, applied to each OCR line as read.
SECRET_STRICT = re.compile(SECRET_KEY + r"[=:][\"']?[^\s*•]{8,}", re.I)
# OCR spaces around the separator, or a key and value tesseract's sparse mode put on separate
# lines, match only a value that holds a digit: a label beside a plain word is no secret.
SECRET_LOOSE = re.compile(
    SECRET_KEY + r"[ \t]*[=:][ \t]*[\"']?(?=[^\s*•]*\d)[^\s*•]{8,}", re.I
)
CREDENTIAL = (
    ("email address", re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")),
    ("bearer token", re.compile(r"bearer \S{8,}", re.I)),
    ("private key", re.compile(r"-----BEGIN.*?PRIVATE KEY-----", re.I)),
)


class Refusal(Exception):
    def __init__(self, exit_code: int, code: str, detail: str):
        super().__init__(detail)
        self.exit_code, self.code, self.detail = exit_code, code, detail


def squeeze(text: str) -> str:
    return re.sub(r"[\s|]", "", text).lower()


def findings(text: str, masks: list[str]) -> list[str]:
    """The kinds of leak in `text`; `masks` are mask values already squeezed."""
    flat = BOX_DRAWING.sub("", text)
    joined = LINE_WRAP.sub("", flat)
    views = (flat, joined)
    kinds = {kind for kind, shape in CREDENTIAL for view in views if shape.search(view)}
    if SECRET_STRICT.search(flat) or any(SECRET_LOOSE.search(view) for view in views):
        kinds.add("secret assignment")
    squeezed = squeeze(flat)
    if any(mask in squeezed for mask in masks):
        kinds.add("mask value")
    return sorted(kinds)


def tool(name: str) -> str:
    found = shutil.which(name)
    if not found:
        raise Refusal(
            7,
            name,
            f"{name} is not installed, so the captures' text cannot be read and scanned;"
            " nothing was posted",
        )
    return found


def run(command: list[str], what: str) -> str:
    name = Path(command[0]).name
    try:
        done = subprocess.run(
            command,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            timeout=600,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Refusal(
            1, "tool", f"{name} did not run on {what} ({type(exc).__name__})"
        ) from None
    if done.returncode != 0:
        raise Refusal(1, "tool", f"{name} exited {done.returncode} on {what}")
    return done.stdout


def frames(ffmpeg: str, capture: Path, into: Path, hi: int) -> list[Path]:
    pattern = str(into / "frame-%06d.png")
    filters = f"mpdecimate=hi={hi}"
    run(
        [ffmpeg, "-v", "error", "-y", "-i", str(capture), "-vf", filters]
        + ["-fps_mode", "vfr", pattern],
        capture.name,
    )
    return sorted(into.glob("frame-*.png"))


def read_text(
    ffmpeg: str, tesseract: str, image: Path, into: Path, what: str
) -> list[str]:
    texts = []
    for name, chain in (("plain", UPSCALE), ("inverted", f"{UPSCALE},negate")):
        variant = into / f"{image.stem}-{name}.png"
        run(
            [ffmpeg, "-v", "error", "-y", "-i", str(image), "-vf", chain]
            + ["-frames:v", "1", "-update", "1", str(variant)],
            what,
        )
        texts.append(run([tesseract, str(variant), "stdout", "--psm", "11"], what))
    return texts


def scan(captures: list[Path], hi: int, masks: list[str]) -> str:
    tesseract, ffmpeg = tool("tesseract"), tool("ffmpeg")
    started = time.monotonic()
    hits, empty, images_read, passes = [], [], 0, 0
    with tempfile.TemporaryDirectory(prefix="evidence-ocr-") as tmp:
        for index, capture in enumerate(captures, 1):
            into = Path(tmp) / str(index)
            into.mkdir()
            moving = capture.suffix.lower() in MOVING
            images = frames(ffmpeg, capture, into, hi) if moving else [capture]
            texts = [
                text
                for image in images
                for text in read_text(ffmpeg, tesseract, image, into, capture.name)
            ]
            images_read, passes = images_read + len(images), passes + len(texts)
            if not any(text.strip() for text in texts):
                empty.append(capture.name)
            kinds = {kind for text in texts for kind in findings(text, masks)}
            hits += [f"{capture.name}: {kind}" for kind in sorted(kinds)]
    if hits:
        raise Refusal(5, "scan", "; ".join(hits))
    if empty:
        raise Refusal(
            6,
            "no-text",
            f"OCR read no text from {', '.join(empty)}, so it cannot be scanned",
        )
    seconds = time.monotonic() - started
    return (
        f"evidence-ocr: clean: {len(captures)} captures, {images_read} images,"
        f" {passes} OCR passes in {seconds:.1f}s"
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="evidence-ocr.py", description=(__doc__ or "").split("\n\n")[0]
    )
    parser.add_argument("--mpdecimate-hi", type=int, default=DEFAULT_HI)
    parser.add_argument("--mask-stdin", action="store_true")
    parser.add_argument("captures", nargs="+")
    a = parser.parse_args(argv)
    try:
        if not 1 <= a.mpdecimate_hi <= MAX_HI:
            raise Refusal(
                2, "usage", f"--mpdecimate-hi must be a whole number from 1 to {MAX_HI}"
            )
        captures = [Path(c).resolve() for c in a.captures]
        for capture in captures:
            if not capture.is_file() or capture.suffix.lower() not in MOVING | STILL:
                raise Refusal(2, "usage", f"{capture.name} is not an image or video file")
        masks = []
        if a.mask_stdin:
            masks = [m for m in map(squeeze, sys.stdin.read().splitlines()) if m]
        print(scan(captures, a.mpdecimate_hi, masks))
        return 0
    except Refusal as refusal:
        print(f"evidence-ocr: refused {refusal.code}: {refusal.detail}", file=sys.stderr)
        return refusal.exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
