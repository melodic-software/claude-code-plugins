#!/usr/bin/env python3
"""Deterministic URL extraction from a discovery snapshot.

Input: an immutable discovery snapshot (llms.txt, sitemap.xml, or sitemap.md)
plus the base URL it was fetched from, or a forge's tree listing plus a
repository seed and include/exclude globs (rung repo-tree). Output:
discovery-output/v1 JSON — the normalized, deduplicated, sorted URL set with
rung provenance. See link-map-format.md for the contract.

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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from repo_tree_adapters import ADAPTERS  # noqa: E402

SCHEMA = "discovery-output/v1"
RUNGS = ("llms-txt", "sitemap-xml", "sitemap-md", "repo-tree")

REPO_NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")
PINNED_SHA_RE = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")

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
    scheme = parts.scheme.lower()
    if scheme not in ("http", "https") or not parts.netloc:
        return None
    # lowercase host only; userinfo is case-significant
    userinfo, at, host = parts.netloc.rpartition("@")
    netloc = userinfo + at + host.lower()
    # trailing slashes dropped, bare root included: one spelling per
    # resource, so root-with-slash dedupes against the bare origin
    path = parts.path.rstrip("/")
    query = urlencode(
        [
            (k, v)
            for k, v in parse_qsl(parts.query, keep_blank_values=True)
            if not TRACKING_PARAMS_RE.match(k)
        ]
    )
    return urlunsplit((scheme, netloc, path, query, ""))  # fragment dropped


def extract_markdown_urls(text: str, base_url: str) -> list:
    """Link targets from markdown: [](), <autolink>, and bare URLs."""
    urls = []
    for regex, bare_text_capture in (
        (MD_LINK_RE, False),
        (MD_AUTOLINK_RE, False),
        (BARE_URL_RE, True),
    ):
        for match in regex.finditer(text):
            target = match.group(1)
            if target.startswith("#"):
                continue
            normalized = normalize_url(
                urljoin(base_url, target), strip_punct=bare_text_capture
            )
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
    # scan the WHOLE input: a prefix window is bypassable by padding the prolog,
    # and the full scan is cheap next to the XML parse that reads every byte
    for marker in (b"<!DOCTYPE", b"<!ENTITY"):
        if marker in data:
            fail(
                2,
                f"sitemap XML contains {marker.decode()} -- DTDs are not "
                f"valid in sitemaps and are refused (XXE/entity-expansion "
                f"hardening).",
            )
    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        fail(
            2,
            f"sitemap XML does not parse: {exc}. An unparsable sitemap "
            f"is a failed discovery, not an empty one.",
        )
    urls = []
    for element in root.iter():
        tag = element.tag.rsplit("}", 1)[-1]  # strip namespace
        if tag == "loc" and element.text:
            normalized = normalize_url(element.text)
            if normalized:
                urls.append(normalized)
    if not urls:
        fail(
            2,
            "sitemap XML parsed but yielded no usable http(s) <loc> URLs; "
            "wrong file, wrong rung, or non-http locs only.",
        )
    return urls


def glob_regex(pattern: str):
    """Path glob: '**' spans directories, '*' and '?' stay inside one segment."""
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("".join(out) + r"\Z")


def extract_repo_tree_urls(data: bytes, args) -> tuple:
    """Raw URLs for the listed blobs the globs keep, plus the repository record."""
    adapter = ADAPTERS[args.forge]
    for flag, value in (("--owner", args.owner), ("--repo", args.repo)):
        if not value or not REPO_NAME_RE.match(value) or value in (".", ".."):
            fail(2, f"{flag} {value!r} is not a repository name.")
    if not args.ref or not PINNED_SHA_RE.match(args.ref):
        fail(
            2,
            f"--ref {args.ref!r} is not a full commit SHA; a repository "
            f"seed is pinned so the listing and every fetch read one revision.",
        )
    if not args.include:
        fail(2, "repo-tree needs at least one --include glob.")
    try:
        listing = json.loads(data)
        paths = adapter.blob_paths(listing)
    except ValueError as exc:  # json.JSONDecodeError and ListingError
        fail(2, f"tree listing {args.snapshot!r} is unusable: {exc}")
    includes = [glob_regex(g) for g in args.include]
    excludes = [glob_regex(g) for g in args.exclude]
    kept = [
        p
        for p in paths
        if any(r.match(p) for r in includes) and not any(r.match(p) for r in excludes)
    ]
    for glob, regex in zip(args.include, includes):
        if not any(regex.match(p) for p in kept):
            fail(
                2,
                f"--include {glob!r} matched no blob in {args.snapshot!r} "
                f"(after excludes {args.exclude}); a glob that selects "
                f"nothing under-discovers behind a clean gate.",
            )
    urls = []
    for path in kept:
        normalized = normalize_url(
            adapter.resource_url(args.owner, args.repo, args.ref, path)
        )
        if normalized is None:
            fail(3, f"adapter {args.forge!r} built no http(s) URL for {path!r}.")
        urls.append(normalized)
    seed = normalize_url(adapter.seed_url(args.owner, args.repo, args.ref))
    repository = {
        "forge": args.forge,
        "owner": args.owner,
        "repo": args.repo,
        "ref": args.ref,
        "seed_url": seed,
        "include": list(args.include),
        "exclude": list(args.exclude),
    }
    return urls, adapter.base_url(args.owner, args.repo, args.ref), repository


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="parse_discovery.py",
        description="Extract the URL set from a discovery snapshot.",
    )
    parser.add_argument("snapshot", nargs="?", help="path to the discovery snapshot")
    parser.add_argument("--rung", choices=RUNGS)
    parser.add_argument("--base-url", help="URL the snapshot was fetched from")
    repo_tree = parser.add_argument_group("repo-tree rung")
    repo_tree.add_argument("--forge", choices=sorted(ADAPTERS), default="github")
    repo_tree.add_argument("--owner")
    repo_tree.add_argument("--repo")
    repo_tree.add_argument("--ref", help="full commit SHA the listing was read at")
    repo_tree.add_argument("--include", action="append", default=[], metavar="GLOB")
    repo_tree.add_argument("--exclude", action="append", default=[], metavar="GLOB")
    parser.add_argument("--out", default="-")
    parser.add_argument(
        "--normalize-url",
        metavar="URL",
        help="print the normalized form of one URL and exit; "
        "seeds and hand-added rows must pass through "
        "this so URL identity has one owner",
    )
    args = parser.parse_args(argv)

    if args.normalize_url is not None:
        normalized = normalize_url(args.normalize_url)
        if normalized is None:
            fail(2, f"{args.normalize_url!r} is not a normalizable http(s) URL.")
        sys.stdout.buffer.write((normalized + "\n").encode("utf-8"))
        return 0

    repo_rung = args.rung == "repo-tree"
    if not args.snapshot or not args.rung or not (args.base_url or repo_rung):
        fail(
            2,
            "snapshot, --rung, and --base-url are required "
            "(unless using --normalize-url; repo-tree takes --owner, --repo, "
            "--ref and --include instead of --base-url).",
        )
    if repo_rung and args.base_url:
        fail(2, "repo-tree builds its base URL from the repository seed; drop --base-url.")

    if not repo_rung and (
        args.owner or args.repo or args.ref or args.include or args.exclude
    ):
        fail(2, f"--owner/--repo/--ref/--include/--exclude apply to repo-tree, not {args.rung}.")
    if not repo_rung and normalize_url(args.base_url) is None:
        fail(2, f"--base-url {args.base_url!r} is not a valid http(s) URL.")

    try:
        with open(args.snapshot, "rb") as fh:
            data = fh.read()
    except OSError as exc:
        fail(2, f"cannot read snapshot {args.snapshot!r}: {exc}")
    if not data.strip():
        fail(
            2,
            f"snapshot {args.snapshot!r} is empty; an empty discovery "
            f"artifact is a failed fetch, not an empty site.",
        )

    base_url, repository = args.base_url, None
    if repo_rung:
        urls, base_url, repository = extract_repo_tree_urls(data, args)
    elif args.rung == "sitemap-xml":
        urls = extract_sitemap_xml_urls(data)
    else:  # llms-txt, sitemap-md: both are markdown-ish text
        try:
            text = data.removeprefix(b"\xef\xbb\xbf").decode("utf-8")
        except UnicodeDecodeError as exc:
            fail(2, f"snapshot {args.snapshot!r} is not UTF-8 text: {exc}.")
        urls = extract_markdown_urls(text, args.base_url)
        if not urls:
            fail(
                2,
                f"no http(s) URLs found in {args.snapshot!r}; an empty "
                f"rung result must be visible, not silently classified "
                f"as nothing-to-do.",
            )

    unique = sorted(set(urls))
    output = {
        "schema": SCHEMA,
        "rung": args.rung,
        "snapshot": {
            "basename": os.path.basename(args.snapshot),
            "sha256": sha256_hex(data),
            "byte_length": len(data),
        },
        "base_url": base_url,
        "url_count": len(unique),
        "urls": unique,
    }
    if repository is not None:
        output["repository"] = repository
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
