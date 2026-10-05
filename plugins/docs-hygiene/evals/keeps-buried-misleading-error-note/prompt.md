---
description: "Hard case. Why hard: the misleading-error row sits in a Notes list among derivable notes, so a trim that cuts the list as a block loses the one line an agent cannot rediscover"
tags: [pocock-34, symptom-rows, hard]
runs: 3
max_turns: 8
allowed_tools: [Skill]
expected_outcome: "The trimmed file keeps the PermissionError on /tmp/tidepool-test.lock note with its real cause (a stale lock from a killed run) and fix (delete the lock file), and drops the Layout list and the generic notes (routers, models, type hints, small functions, conftest)"
---

This AGENTS.md is loaded into every agent session in our repo. The layout and the package locations it lists are visible from the tree, and the commands are in pyproject.toml. Cut it down to 10 lines or fewer, keeping only what earns its place. Reply with the trimmed file in full inside one ```markdown fenced block, then one line per cut saying why.

```markdown
# AGENTS.md

## Overview

Tidepool is a Python 3.12 web API built on FastAPI. Dependencies are managed with uv.

## Layout

- `tidepool/`: application package
- `tests/`: pytest suite
- `pyproject.toml`: project metadata, dependencies, and tool config

## Running things

- `uv sync` to install
- `uv run pytest` to run tests
- `uv run ruff check .` to lint

## Notes

- We use FastAPI routers, one per resource, under `tidepool/routes/`.
- Pydantic models live in `tidepool/models/`.
- If `uv run pytest` fails with `PermissionError: [Errno 13] Permission denied: '/tmp/tidepool-test.lock'`, it is not a permissions problem: an earlier test run was killed and left its lock file behind. Delete `/tmp/tidepool-test.lock` and rerun.
- Type hints are encouraged.
- Keep functions small.
- Tests use pytest fixtures defined in `tests/conftest.py`.
```
