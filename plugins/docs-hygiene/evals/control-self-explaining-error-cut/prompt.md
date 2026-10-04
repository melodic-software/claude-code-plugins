---
description: "Control: an error row whose message already names its cause and fix is derivable, so a trim drops it; guards against keeping every symptom row by reflex"
tags: [pocock-34, symptom-rows, control]
runs: 3
max_turns: 8
allowed_tools: [Skill]
expected_outcome: "The trimmed file drops the Python-version troubleshooting row, whose error message already states the required version, and keeps the staging-database rule, which nothing in the repo states"
---

Every agent session in our repo loads this AGENTS.md. The layout is visible from the tree and the commands are in the Makefile. Trim it to 8 lines or fewer, keeping only what an agent could not work out on its own. Reply with the trimmed file in full inside one ```markdown fenced block, then one line per cut saying why.

```markdown
# AGENTS.md

## Overview

Brightwater is a Python 3.12 job scheduler. Dependencies are managed with uv.

## Layout

- `brightwater/`: application package
- `tests/`: pytest suite

## Commands

- `make test` runs the tests.
- `make lint` runs ruff.

## Database

- Run migrations with `make migrate-local` only. `make migrate` targets the shared staging database, which other teams use; never run it from an agent session.

## Troubleshooting

- `uv sync` fails with `error: The current Python version (3.11.9) does not satisfy Python>=3.12`: the installed Python is too old. Install Python 3.12 or later and rerun `uv sync`.
```
