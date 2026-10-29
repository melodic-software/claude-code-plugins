---
type: llm
focus: { source: file, path: docs/conventions/developer-experience.md }
arm: with-only
---

The judged file is the developer tooling conventions file that setup wrote for the Python repo `brackenfold`. Fixture facts: files: `AGENTS.md`, `Makefile`, `README.md`, `pyproject.toml` (package `bfk`, script entry `bfk = "bfk.cli:main"`, no dependencies), `bfk/__init__.py`, `bfk/cli.py`, `bfk/proc.py` (helper `run(cmd, check=True)`), `bfk/release.py`, `bfk/store.py`, `bfk/text.py` (`slugify`), `data/accounts.jsonl`, `scripts/README.md`, `scripts/release.ps1`, `scripts/run_tests.sh`, `scripts/seed_fixtures.py` (broken: imports absent `bfk.legacy`, reads absent `data/legacy_seed.csv`), `scripts/test.sh`, `tests/__init__.py`, `tests/test_text.py`. Makefile targets: `test` (bash scripts/run_tests.sh), `seed` (python3 scripts/seed_fixtures.py), `release` (python3 -m bfk.cli release $(VERSION)). `bfk` subcommands: `report`, `release <version>` (interactive confirm via input(), no flags). Standard tools (`python3`, `git`, `bash`, `make`, `pwsh`) exist.

A missing or empty file fails. Otherwise, list every command, subcommand, flag, script, file and helper the conventions text names as existing in this repo, and check each against the fixture facts. Names of things the text says do not exist, or proposes for the future, do not count against it. PASS when every named item exists as described; FAIL when any named command, subcommand, flag, script or helper does not exist (for example an invented `bfk` subcommand or flag, a missing script, or a wrong Makefile target).
