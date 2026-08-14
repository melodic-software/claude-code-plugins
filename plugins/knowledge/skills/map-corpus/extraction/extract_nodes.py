#!/usr/bin/env python3
"""Deterministic node extractor: immutable snapshot in, node manifest out.

Decomposes a snapshot file into a NON-OVERLAPPING byte partition of outline
nodes. Every byte of the snapshot belongs to exactly one node, so a coverage
claim over the manifest is a coverage claim over the whole snapshot — the
denominator is this script's output, never an agent's.

Manifest contract: see node-manifest-format.md beside this script.

Determinism contract: running this script twice over one snapshot produces
byte-identical manifests. Nothing time-, locale-, machine-, or path-dependent
enters the output (snapshot is recorded by basename only).

Exit codes:
  0  manifest written
  2  input error (missing/empty/unreadable snapshot, unknown format)
  3  internal invariant violation (partition self-check failed)

Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from typing import NoReturn

SCHEMA = "node-manifest/v1"
EXTRACTOR_NAME = "extract_nodes.py"
EXTRACTOR_VERSION = "1.0.0"

UTF8_BOM = b"\xef\xbb\xbf"
# UTF-32 BOMs listed before their UTF-16 prefixes: \xff\xfe\x00\x00 starts
# with \xff\xfe, so order decides which one matches.
NON_UTF8_BOMS = [
    (b"\xff\xfe\x00\x00", "UTF-32 LE"),
    (b"\x00\x00\xfe\xff", "UTF-32 BE"),
    (b"\xff\xfe", "UTF-16 LE"),
    (b"\xfe\xff", "UTF-16 BE"),
]


def fail(code: int, message: str) -> NoReturn:
    sys.stderr.write(f"extract_nodes: ERROR: {message}\n")
    sys.exit(code)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------------------
# Line model (byte-offset preserving)
# ---------------------------------------------------------------------------

class Line:
    __slots__ = ("start", "end", "text")

    def __init__(self, start: int, end: int, raw: bytes):
        self.start = start          # byte offset of line start
        self.end = end              # byte offset just past the newline (or EOF)
        # matching text: newline and trailing \r stripped; offsets stay raw
        self.text = raw.rstrip(b"\r\n")


def split_lines(data: bytes, base: int = 0) -> list:
    """Split into lines; offsets are raw-snapshot offsets starting at `base`."""
    lines = []
    pos = base
    n = len(data)
    while pos < n:
        nl = data.find(b"\n", pos)
        if nl == -1:
            lines.append(Line(pos, n, data[pos:n]))
            break
        lines.append(Line(pos, nl + 1, data[pos:nl + 1]))
        pos = nl + 1
    return lines


# ---------------------------------------------------------------------------
# Markdown handler
# ---------------------------------------------------------------------------

ATX_RE = re.compile(rb"^ {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*$")
ATX_TRAIL_RE = re.compile(rb"[ \t]+#+[ \t]*$")
FENCE_OPEN_RE = re.compile(rb"^( {0,3})(`{3,}|~{3,})(.*)$")
SETEXT_RE = re.compile(rb"^ {0,3}(=+|-+)[ \t]*$")


def decode_title(raw: bytes) -> str:
    return raw.decode("utf-8", errors="replace").strip()


def markdown_boundaries(data: bytes):
    """Return (frontmatter_end, [(offset, level, title), ...]) for a markdown snapshot.

    Deterministic simplifications, documented in node-manifest-format.md:
    - a setext heading claims only its immediately preceding line as heading
      text (CommonMark would claim the whole paragraph);
    - setext-vs-thematic-break ambiguity for `---` resolves to setext whenever
      the previous line is non-blank and not itself a boundary.
    """
    # A UTF-8 BOM is not content structure: scan lines after it, keeping raw
    # offsets, so the BOM bytes land in the first node's span. CR-only line
    # endings would collapse the file to one "line" and silently lose every
    # heading — fail loudly instead.
    base = len(UTF8_BOM) if data.startswith(UTF8_BOM) else 0
    if b"\n" not in data[base:] and b"\r" in data[base:]:
        fail(2, "snapshot uses CR-only (classic Mac) line endings; "
                "normalize to LF or CRLF before extraction.")
    lines = split_lines(data, base)
    frontmatter_end = 0

    idx = 0
    if lines and lines[0].text == b"---":
        for j in range(1, len(lines)):
            if lines[j].text in (b"---", b"..."):
                frontmatter_end = lines[j].end
                idx = j + 1
                break
        # no closing marker: not frontmatter; idx stays 0

    boundaries = []  # (byte offset, level, title)
    in_fence = False
    fence_char = b""
    fence_len = 0
    consumed = set()  # line indexes already used as heading/underline/fence

    i = idx
    while i < len(lines):
        line = lines[i]
        text = line.text

        if in_fence:
            m = FENCE_OPEN_RE.match(text)
            if m and m.group(2)[0:1] == fence_char and len(m.group(2)) >= fence_len \
                    and m.group(3).strip() == b"":
                in_fence = False
            consumed.add(i)
            i += 1
            continue

        m = FENCE_OPEN_RE.match(text)
        if m:
            in_fence = True
            fence_char = m.group(2)[0:1]
            fence_len = len(m.group(2))
            consumed.add(i)
            i += 1
            continue

        m = ATX_RE.match(text)
        if m:
            level = len(m.group(1))
            title_raw = m.group(2) or b""
            title_raw = ATX_TRAIL_RE.sub(b"", title_raw)
            boundaries.append((line.start, level, decode_title(title_raw)))
            consumed.add(i)
            i += 1
            continue

        m = SETEXT_RE.match(text)
        if m and i > idx:
            prev = lines[i - 1]
            prev_usable = (
                prev.text.strip() != b""
                and (i - 1) not in consumed
                and prev.start >= frontmatter_end
            )
            if prev_usable:
                level = 1 if m.group(1)[0:1] == b"=" else 2
                boundaries.append((prev.start, level, decode_title(prev.text)))
                consumed.add(i - 1)
                consumed.add(i)
                i += 1
                continue

        i += 1

    # A fence left open runs to EOF; everything after its opener was consumed
    # as fence interior — that is deterministic, so no error.
    return frontmatter_end, boundaries


# ---------------------------------------------------------------------------
# HTML handler
# ---------------------------------------------------------------------------

HTML_MASK_RES = [
    re.compile(rb"<!--.*?-->", re.DOTALL),
    re.compile(rb"<script\b.*?</script\s*>", re.DOTALL | re.IGNORECASE),
    re.compile(rb"<style\b.*?</style\s*>", re.DOTALL | re.IGNORECASE),
    re.compile(rb"<pre\b.*?</pre\s*>", re.DOTALL | re.IGNORECASE),
    re.compile(rb"<textarea\b.*?</textarea\s*>", re.DOTALL | re.IGNORECASE),
]
HTML_HEADING_RE = re.compile(rb"<h([1-6])(\s[^>]*)?>", re.IGNORECASE)
HTML_TAG_RE = re.compile(rb"<[^>]+>")
WS_RUN_RE = re.compile(r"\s+")


def html_boundaries(data: bytes):
    """Return [(offset, level, title), ...] for an HTML snapshot.

    Byte-regex based, not a DOM parse: heading open tags found after masking
    comments, script, style, pre, and textarea regions (masking preserves
    length, so offsets are raw-snapshot offsets). An unclosed masked region
    masks through EOF. Limitation stated in node-manifest-format.md.
    """
    masked = data
    for rx in HTML_MASK_RES:
        masked = rx.sub(lambda m: b" " * (m.end() - m.start()), masked)
    # unclosed comment: mask opener..EOF (closed ones were masked above)
    m = masked.find(b"<!--")
    if m != -1 and masked.find(b"-->", m) == -1:
        masked = masked[:m] + b" " * (len(masked) - m)
    # unclosed script/style/pre/textarea: mask opener..EOF
    for name in (b"script", b"style", b"pre", b"textarea"):
        rx = re.compile(rb"<" + name + rb"\b", re.IGNORECASE)
        m = rx.search(masked)
        if m:
            close = re.compile(rb"</" + name + rb"\s*>", re.IGNORECASE)
            if not close.search(masked, m.end()):
                masked = masked[: m.start()] + b" " * (len(masked) - m.start())

    boundaries = []
    for m in HTML_HEADING_RE.finditer(masked):
        level = int(m.group(1))
        close_re = re.compile(rb"</h" + m.group(1) + rb"\s*>", re.IGNORECASE)
        cm = close_re.search(masked, m.end())
        inner = masked[m.end(): cm.start()] if cm else b""
        title = WS_RUN_RE.sub(" ", decode_title(HTML_TAG_RE.sub(b" ", inner)))
        boundaries.append((m.start(), level, title.strip()))
    return boundaries


# ---------------------------------------------------------------------------
# Partition assembly (shared)
# ---------------------------------------------------------------------------

def build_nodes(data: bytes, frontmatter_end: int, boundaries, whole_kind: str):
    """Assemble the non-overlapping node partition covering [0, len(data))."""
    n = len(data)
    spans = []  # (start, end, kind, level, title)

    if not boundaries and frontmatter_end == 0:
        spans.append((0, n, whole_kind, 0, ""))
    else:
        cursor = 0
        if frontmatter_end > 0:
            spans.append((0, frontmatter_end, "frontmatter", 0, ""))
            cursor = frontmatter_end
        first = boundaries[0][0] if boundaries else n
        if first > cursor:
            spans.append((cursor, first, "preamble", 0, ""))
        for k, (off, level, title) in enumerate(boundaries):
            end = boundaries[k + 1][0] if k + 1 < len(boundaries) else n
            spans.append((off, end, "section", level, title))

    nodes = []
    parent_stack = []  # (level, id) of open section ancestors
    for index, (start, end, kind, level, title) in enumerate(spans):
        content = data[start:end]
        digest = sha256_hex(content)
        node_id = f"n{index:04d}-{digest[:8]}"
        if kind == "section":
            while parent_stack and parent_stack[-1][0] >= level:
                parent_stack.pop()
            parent_id = parent_stack[-1][1] if parent_stack else None
            parent_stack.append((level, node_id))
        else:
            parent_id = None
        nodes.append({
            "id": node_id,
            "index": index,
            "kind": kind,
            "level": level,
            "title": title,
            "parent_id": parent_id,
            "start_byte": start,
            "end_byte": end,
            "byte_length": end - start,
            "content_sha256": digest,
        })
    return nodes


def self_check(nodes, data: bytes) -> "None":
    """Partition invariants; violation is a bug, fail loudly."""
    n = len(data)
    if not nodes:
        fail(3, "self-check: empty node list")
    cursor = 0
    for node in nodes:
        if node["start_byte"] != cursor:
            fail(3, f"self-check: gap/overlap at node {node['id']}: "
                    f"expected start {cursor}, got {node['start_byte']}")
        if node["end_byte"] <= node["start_byte"]:
            fail(3, f"self-check: empty/negative span at node {node['id']}")
        if sha256_hex(data[node["start_byte"]:node["end_byte"]]) != node["content_sha256"]:
            fail(3, f"self-check: hash mismatch at node {node['id']}")
        cursor = node["end_byte"]
    if cursor != n:
        fail(3, f"self-check: partition ends at {cursor}, snapshot is {n} bytes")


# ---------------------------------------------------------------------------
# Format registry — THE extension seam.
# ---------------------------------------------------------------------------
# To support a new snapshot format: add a handler returning
# (frontmatter_end, boundaries, whole_kind) and register its extensions here.
# Unregistered extensions fail loudly unless --format overrides.

def handle_markdown(data: bytes):
    fm_end, bounds = markdown_boundaries(data)
    return fm_end, bounds, "document"


def handle_html(data: bytes):
    return 0, html_boundaries(data), "document"


def handle_opaque(data: bytes):
    return 0, [], "document"


FORMAT_HANDLERS = {
    "markdown": handle_markdown,
    "html": handle_html,
    "opaque": handle_opaque,
}

EXTENSION_FORMATS = {
    ".md": "markdown",
    ".markdown": "markdown",
    ".mdx": "markdown",
    ".html": "html",
    ".htm": "html",
    ".txt": "opaque",
    ".json": "opaque",
    ".pdf": None,  # extract from source.txt, never the binary
}


def resolve_format(path: str, override: str) -> str:
    if override != "auto":
        return override
    ext = os.path.splitext(path)[1].lower()
    if ext not in EXTENSION_FORMATS:
        fail(2, f"unknown snapshot extension '{ext}' for {path!r}; "
                f"known: {', '.join(sorted(k for k in EXTENSION_FORMATS))}. "
                f"Pass --format to override.")
    fmt = EXTENSION_FORMATS[ext]
    if fmt is None:
        fail(2, f"binary format '{ext}' is not node-extractable; "
                f"run against its text extraction (e.g. source.txt) instead.")
    return fmt


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="extract_nodes.py",
        description="Emit a deterministic node manifest for an immutable snapshot.",
    )
    parser.add_argument("snapshot", help="path to the immutable snapshot file")
    parser.add_argument("--format", default="auto",
                        choices=["auto"] + sorted(FORMAT_HANDLERS),
                        help="snapshot format (default: by extension)")
    parser.add_argument("--out", default="-",
                        help="manifest output path (default: stdout)")
    args = parser.parse_args(argv)

    try:
        with open(args.snapshot, "rb") as fh:
            data = fh.read()
    except OSError as exc:
        fail(2, f"cannot read snapshot {args.snapshot!r}: {exc}")

    if len(data) == 0:
        fail(2, f"snapshot {args.snapshot!r} is empty (0 bytes); an empty "
                f"snapshot is a broken fetch, not an empty corpus resource.")

    for bom, encoding in NON_UTF8_BOMS:
        if data.startswith(bom):
            fail(2, f"snapshot {args.snapshot!r} carries a {encoding} BOM; "
                    f"the byte-level scanners would silently miss every "
                    f"heading. Re-fetch or transcode the snapshot to UTF-8.")

    fmt = resolve_format(args.snapshot, args.format)
    frontmatter_end, boundaries, whole_kind = FORMAT_HANDLERS[fmt](data)
    boundaries = sorted(boundaries, key=lambda b: b[0])
    nodes = build_nodes(data, frontmatter_end, boundaries, whole_kind)
    self_check(nodes, data)

    manifest = {
        "schema": SCHEMA,
        "extractor": {"name": EXTRACTOR_NAME, "version": EXTRACTOR_VERSION},
        "snapshot": {
            "basename": os.path.basename(args.snapshot),
            "format": fmt,
            "byte_length": len(data),
            "sha256": sha256_hex(data),
        },
        "node_count": len(nodes),
        "nodes": nodes,
    }
    payload = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")

    if args.out == "-":
        sys.stdout.buffer.write(payload)
    else:
        try:
            with open(args.out, "wb") as fh:
                fh.write(payload)
        except OSError as exc:
            fail(2, f"cannot write manifest {args.out!r}: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
