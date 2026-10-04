---
type: llm
arm: both
---

Judge only the trimmed AGENTS.md inside the fenced block, not the list of cuts after it.

PASS only if both hold:

1. The trimmed file no longer contains the troubleshooting row for the `uv sync` Python-version error (`The current Python version (3.11.9) does not satisfy Python>=3.12`) in any wording, including a shortened "needs Python 3.12" troubleshooting entry tied to that error.
2. The trimmed file keeps the staging-database rule: migrations run with `make migrate-local`, and `make migrate` must not be run because it targets the shared staging database. Rewording is fine.

FAIL if the Python-version error row survives in any form, or if the staging-database rule is removed or loses either the safe command or the reason. A plain "Python 3.12" mention in an Overview line, with no error or troubleshooting framing, does not count as the row surviving.
