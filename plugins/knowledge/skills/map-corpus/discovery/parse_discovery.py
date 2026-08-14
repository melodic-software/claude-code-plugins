#!/usr/bin/env python3
"""Deterministic URL extraction from a discovery snapshot (ladder rungs 1-2).

Input: an immutable discovery snapshot (llms.txt, sitemap.xml, or sitemap.md)
plus the base URL it was fetched from. Output: discovery-output/v1 JSON — the
normalized, deduplicated, sorted URL set with rung provenance. See
link-map-format.md for the contract.

Same denominator discipline as the node extractor: the set of URLs that must
be classified comes from this script over snapshot bytes, never from an
agent's recall.

Exit codes:
  0  output written
  2  input error (missing/empty/unreadable snapshot, bad base URL, bad XML)
  3  internal invariant violation

Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from typing import NoReturn
from urllib.parse import urljoin, urlsplit, urlunsplit, parse_qsl, urlencode

SCHEMA = "discovery-output/v1"
RUNGS = ("llms-txt", "sitemap-xml", "sitemap-md")

TRACKING_PARAMS_RE = re.compile(r"^(utm_.*|gclid|fbclid)$")

# markdown link targets: [text](target) and <https://...> autolinks
MD_LINK_RE = re.compile(r"\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
MD_AUTOLINK_RE = re.compile(r"<(https?://[^>\s]+)>", re.IGNORECASE)
# leading backtick allowed (inline-code URLs still count as discovered);
# backtick excluded from the URL chars so the closing fence never rides along
BARE_URL_RE = re.compile(r"(?<![(<\"'])(https?://[^\s)\]>\"'`]+)", re.IGNORECASE)


def fail(code: int, message: str) -> NoReturn:
    sys.stderr.write(f"parse_discovery: ERROR: {message}\n")
    sys.exit(code)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def normalize_url(url: str, strip_punct: bool = False) -> str | None:
    """Normalize per link-map-format.md; None for non-http(s) or unusable.

    strip_punct trims trailing sentence punctuation and is for BARE-text
    captures only — an explicit markdown target or XML <loc> keeps its exact
    spelling (a legit URL may end in '.').
    """
    url = url.strip()
    if strip_punct:
        url = url.rstrip(".,;")
    parts = urlsplit(url)
    if parts.scheme.lower() not in ("http", "https"):
        return None
    if not parts.netloc:
        return None
    scheme = parts.scheme.lower()
    netloc = parts.netloc
    if "@" in netloc:  # lowercase host only; userinfo is case-significant
        userinfo, host = netloc.rsplit("@", 1)
        netloc = userinfo + "@" + host.lower()
    else:
        netloc = netloc.lower()
    path = parts.path
    if path == "/":
        path = ""  # bare root: one spelling, so root-with-slash dedupes
    elif path.endswith("/"):
        path = path.rstrip("/")
    kept = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True)
            if not TRACKING_PARAMS_RE.match(k)]
    query = urlencode(kept)
    return urlunsplit((scheme, netloc, path, query, ""))  # fragment dropped


def extract_markdown_urls(text: str, base_url: str) -> list:
    """Link targets from markdown: [](), <autolink>, and bare URLs."""
    found = []  # (target, is_bare_text_capture)
    for m in MD_LINK_RE.finditer(text):
        found.append((m.group(1), False))
    for m in MD_AUTOLINK_RE.finditer(text):
        found.append((m.group(1), False))
    for m in BARE_URL_RE.finditer(text):
        found.append((m.group(1), True))
    urls = []
    for target, bare in found:
        if target.startswith(("#",)):
            continue
        absolute = urljoin(base_url, target)
        normalized = normalize_url(absolute, strip_punct=bare)
        if normalized:
            urls.append(normalized)
    return urls


def extract_sitemap_xml_urls(data: bytes) -> list:
    """<loc> values from a urlset or sitemapindex. Malformed XML fails loudly.

    XXE/billion-laughs hardening without a third-party parser: a legitimate
    sitemap never carries a DTD, so any <!DOCTYPE/<!ENTITY declaration is
    rejected before the parser sees it. (Stdlib ElementTree additionally never
    fetches external entities, and bundled libexpat >= 2.4 caps entity
    amplification — this check makes the refusal explicit and loud.)
    """
    # scan the WHOLE input, not a prefix window: a prefix scan is bypassable
    # by padding the prolog, and the full scan is memchr-cheap next to the
    # XML parse that reads every byte anyway
    for marker in (b"<!DOCTYPE", b"<!ENTITY"):
        if marker in data:
            fail(2, f"sitemap XML contains {marker.decode()} -- DTDs are not "
                    f"valid in sitemaps and are refused (XXE/entity-expansion "
                    f"hardening).")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        fail(2, f"sitemap XML does not parse: {exc}. An unparsable sitemap "
                f"is a failed discovery, not an empty one.")
    urls = []
    for element in root.iter():
        tag = element.tag.rsplit("}", 1)[-1]  # strip namespace
        if tag == "loc" and element.text:
            normalized = normalize_url(element.text)
            if normalized:
                urls.append(normalized)
    if not urls:
        fail(2, "sitemap XML parsed but yielded no usable http(s) <loc> URLs; "
                "wrong file, wrong rung, or non-http locs only.")
    return urls


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="parse_discovery.py",
        description="Extract the URL set from a discovery snapshot.")
    parser.add_argument("snapshot", nargs="?",
                        help="path to the discovery snapshot")
    parser.add_argument("--rung", choices=RUNGS)
    parser.add_argument("--base-url",
                        help="URL the snapshot was fetched from")
    parser.add_argument("--out", default="-")
    parser.add_argument("--normalize-url", metavar="URL",
                        help="print the normalized form of one URL and exit; "
                             "seeds and hand-added rows must pass through "
                             "this so URL identity has one owner")
    args = parser.parse_args(argv)

    if args.normalize_url is not None:
        normalized = normalize_url(args.normalize_url)
        if normalized is None:
            fail(2, f"{args.normalize_url!r} is not a normalizable http(s) URL.")
        sys.stdout.buffer.write((normalized + "\n").encode("utf-8"))
        return 0

    if not args.snapshot or not args.rung or not args.base_url:
        fail(2, "snapshot, --rung, and --base-url are required "
                "(unless using --normalize-url).")

    base = normalize_url(args.base_url)
    if base is None:
        fail(2, f"--base-url {args.base_url!r} is not a valid http(s) URL.")

    try:
        with open(args.snapshot, "rb") as fh:
            data = fh.read()
    except OSError as exc:
        fail(2, f"cannot read snapshot {args.snapshot!r}: {exc}")
    if not data.strip():
        fail(2, f"snapshot {args.snapshot!r} is empty; an empty discovery "
                f"artifact is a failed fetch, not an empty site.")

    if args.rung == "sitemap-xml":
        urls = extract_sitemap_xml_urls(data)
    else:  # llms-txt, sitemap-md: both are markdown-ish text
        if data.startswith(b"\xef\xbb\xbf"):
            data_text = data[3:]
        else:
            data_text = data
        try:
            text = data_text.decode("utf-8")
        except UnicodeDecodeError as exc:
            fail(2, f"snapshot {args.snapshot!r} is not UTF-8 text: {exc}.")
        urls = extract_markdown_urls(text, args.base_url)
        if not urls:
            fail(2, f"no http(s) URLs found in {args.snapshot!r}; an empty "
                    f"rung result must be visible, not silently classified "
                    f"as nothing-to-do.")

    unique = sorted(set(urls))
    output = {
        "schema": SCHEMA,
        "rung": args.rung,
        "snapshot": {
            "basename": os.path.basename(args.snapshot),
            "sha256": sha256_hex(data),
            "byte_length": len(data),
        },
        "base_url": args.base_url,
        "url_count": len(unique),
        "urls": unique,
    }
    payload = (json.dumps(output, indent=2, sort_keys=True) + "\n").encode("utf-8")
    if args.out == "-":
        sys.stdout.buffer.write(payload)
    else:
        try:
            with open(args.out, "wb") as fh:
                fh.write(payload)
        except OSError as exc:
            fail(2, f"cannot write output {args.out!r}: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
