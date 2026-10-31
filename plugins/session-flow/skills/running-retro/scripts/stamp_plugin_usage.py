#!/usr/bin/env python3
# test-scope: plugins/session-flow/.claude-plugin/plugin.json
"""Stamp a session's plugin usage into its running-retro ledger frontmatter.

The `plugin_usage` key is a public artifact: other plugins read it from the
ledger instead of running session-flow's parser. Its value is one line of JSON,
the parser's `data.plugin_usage` for the whole session, so each stamp replaces
the last.

Exit 0 when stamped, 1 when the ledger is left as it was.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

_PARSER = Path(__file__).resolve().parents[2] / "retro" / "scripts" / "parse_transcript.py"
_FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
_PARSE_TIMEOUT_SECONDS = 300


def read_usage(session_id: str, session_data_dir: str) -> dict | None:
    """The parser's `plugin_usage` for one session, or None when it has none."""
    try:
        run = subprocess.run(
            [
                sys.executable,
                str(_PARSER),
                "--sessions",
                session_id,
                "--base",
                session_data_dir,
            ],
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            timeout=_PARSE_TIMEOUT_SECONDS,
            check=False,
        )
        usage = json.loads(run.stdout)["sessions"][0]["data"]["plugin_usage"]
    except (OSError, subprocess.SubprocessError, ValueError, LookupError, TypeError):
        return None
    return usage if isinstance(usage, dict) else None


def stamp(ledger: Path, usage: dict) -> bool:
    """Replace the ledger's `plugin_usage` frontmatter line with `usage`."""
    try:
        text = ledger.read_text(encoding="utf-8")
    except OSError:
        return False
    match = _FRONTMATTER.match(text)
    if match is None:
        return False
    lines = [
        line for line in match[1].split("\n") if not line.startswith("plugin_usage:")
    ]
    lines.append(f"plugin_usage: {json.dumps(usage, ensure_ascii=False)}")
    ledger.write_text(
        "---\n" + "\n".join(lines) + "\n---\n" + text[match.end() :], encoding="utf-8"
    )
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ledger", required=True, type=Path)
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--session-data-dir", required=True)
    args = parser.parse_args()
    usage = read_usage(args.session_id, args.session_data_dir)
    if usage is None:
        print("plugin_usage not stamped: the parser returned none", file=sys.stderr)
        return 1
    if not stamp(args.ledger, usage):
        print("plugin_usage not stamped: no ledger frontmatter", file=sys.stderr)
        return 1
    print(f"plugin_usage stamped: {len(usage.get('skills', {}))} skill(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
