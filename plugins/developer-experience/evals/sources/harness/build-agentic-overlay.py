#!/usr/bin/env python3
"""Write fixtures/brackenfold-agentic/<bare|conventions-only|converged>/ for held-out H-audit.

Usage: python3 -I build-agentic-overlay.py [--help]

Copies each fixtures/brackenfold/<state>/ and applies the H-audit overlay
(held-out/H-audit.md "Fixture variant"): removes scripts/test.sh, scripts/seed_fixtures.py, the
Makefile seed entry, and the scripts/README.md lines for the removed scripts and the
"Agents: ignore..." line; adds scripts/fmt.sh, .claude/settings.json (PostToolUse hook),
.claude/commands/test.md, .mcp.json (server `ledger`, tools/ absent) and
.claude/agents/release-checker.md. Run build-fixtures.py first. Exit: 0 written, 2 usage.
"""

import json
import shutil
import stat
import sys
from pathlib import Path

FIXTURES = Path(__file__).resolve().parent.parent / "fixtures"

FMT_SH = """#!/usr/bin/env bash
# Check that every bfk module parses (writes nothing).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 -c 'import ast, glob, sys
for path in sorted(glob.glob("bfk/*.py")):
    with open(path, encoding="utf-8") as handle:
        ast.parse(handle.read(), path)
sys.exit(0)'
"""

SETTINGS = {"hooks": {"PostToolUse": [{"matcher": "Write|Edit",
                                       "hooks": [{"type": "command", "command": "bash scripts/fmt.sh"}]}]}}

COMMAND_TEST = """---
description: Run the unit tests
---
Run `python3 -m unittest discover -s tests` from the repository root and report the result.
"""

MCP = {"mcpServers": {"ledger": {"type": "stdio", "command": "python3", "args": ["tools/ledger_mcp.py"]}}}

RELEASE_CHECKER = """---
name: release-checker
description: Checks a release candidate and tags it.
tools: Bash, Read
---
You prepare a release of brackenfold.

1. Run `bash scripts/run_tests.sh` and stop if it fails.
2. Run `python3 -m bfk.cli release --yes <version>` to tag the release without the prompt.
3. Report the tag created.
"""


def overlay(root):
    for rel in ("scripts/test.sh", "scripts/seed_fixtures.py"):
        (root / rel).unlink()
    make = root / "Makefile"
    make.write_text(make.read_text().replace(".PHONY: test seed release", ".PHONY: test release")
                    .replace("seed:\n\tpython3 scripts/seed_fixtures.py\n\n", ""), encoding="utf-8")
    readme = root / "scripts/README.md"
    lines = [ln for ln in readme.read_text().splitlines(keepends=True)
             if not ln.startswith(("- `test.sh`", "- `seed_fixtures.py`", "Agents: ignore"))]
    readme.write_text("".join(lines).rstrip("\n") + "\n", encoding="utf-8")
    fmt = root / "scripts/fmt.sh"
    fmt.write_text(FMT_SH, encoding="utf-8", newline="\n")
    fmt.chmod(fmt.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    (root / ".claude/commands").mkdir(parents=True)
    (root / ".claude/agents").mkdir(parents=True)
    (root / ".claude/settings.json").write_text(json.dumps(SETTINGS, indent=2) + "\n", encoding="utf-8")
    (root / ".claude/commands/test.md").write_text(COMMAND_TEST, encoding="utf-8")
    (root / ".claude/agents/release-checker.md").write_text(RELEASE_CHECKER, encoding="utf-8")
    (root / ".mcp.json").write_text(json.dumps(MCP, indent=2) + "\n", encoding="utf-8")


def main(argv):
    if argv[1:]:
        print(__doc__)
        return 0 if argv[1:] in (["-h"], ["--help"]) else 2
    for state in ("bare", "conventions-only", "converged"):
        src = FIXTURES / "brackenfold" / state
        dst = FIXTURES / "brackenfold-agentic" / state
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst, symlinks=True)
        overlay(dst)
    print(f"written {FIXTURES / 'brackenfold-agentic'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
