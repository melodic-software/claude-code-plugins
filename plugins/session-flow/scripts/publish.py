# GENERATED from lib/publish.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
"""The publish redactor a transcript-mining script's published output passes through, failing closed.

    publisher(sources_file, identifiers="", *, rules=redact.RULES_FILE, sources=None) -> redact.PublishRedactor
    PublishError                       nothing may be published; str() is safe to print

    publish.py [--sources-file F] [--redact-identifiers LIST] < text
                                       print stdin redacted, for a skill body's published text;
                                       when the redactor fails closed, print nothing, the reason
                                       on stderr, and exit 2

`sources_file` is the `transcript_sources_file` option ("" reads this host's sources) and
`identifiers` the `redact_identifiers` option, comma-separated; `sources`, when the caller already
loaded that file, is used in place of loading it again. A named sources file that is
missing, unusable or warns, or secret rules that fail to load, raise `PublishError`: the caller
publishes nothing and exits 2 with the error line. That line names no sources path, source or host
name as written: it passes through this host's default publish redactor. What the redactor
replaces is listed in `redact.py`.

Callers put this directory on `sys.path` beside `redact.py` and `transcript_sources.py`. Stdlib
only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

import redact
import transcript_sources

_QUOTED = re.compile(r"'[^']*'|\"[^\"]*\"")
_HOST_PATH = re.compile(r"\bhosts\.\S+")


class PublishError(Exception):
    pass


def _safe(reason: str, extra: list[str]) -> str:
    default = transcript_sources.resolve(None, os.environ)
    masked = _HOST_PATH.sub("hosts.<value>", _QUOTED.sub("<value>", reason))
    return redact.publish_redactor(default, extra=extra).redact(masked)


def publisher(
    sources_file: str, identifiers: str = "", *, rules: Path = redact.RULES_FILE,
    sources: transcript_sources.Sources | None = None,
) -> redact.PublishRedactor:
    extra = [item for item in identifiers.split(",") if item.strip()]
    try:
        sources = transcript_sources.load(sources_file) if sources is None else sources
    except transcript_sources.SourcesError as error:
        reason = str(error).replace(error.file, "the sources file", 1)
        raise PublishError(_safe(f"nothing published: {reason}", extra)) from None
    if sources.warnings:
        raise PublishError(_safe("nothing published: the sources file was not found", extra))
    result = redact.publish_redactor(sources, extra=extra, path=rules)
    if result.fail_closed:
        raise PublishError("nothing published: the secret redaction rules did not load")
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="publish.py", description="print stdin through the publish redactor")
    parser.add_argument("--sources-file", default="", help="the transcript_sources_file option")
    parser.add_argument("--redact-identifiers", default="", help="the redact_identifiers option")
    args = parser.parse_args(argv)
    try:
        redactor = publisher(args.sources_file, args.redact_identifiers)
    except PublishError as error:
        print(f"publish: {error}", file=sys.stderr)
        return 2
    sys.stdout.write(redactor.redact(sys.stdin.read()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
