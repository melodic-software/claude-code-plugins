---
type: llm
arm: both
---

Judge only the trimmed AGENTS.md inside the fenced block. Ignore the list of cuts after it: a cut line that says a rule is derivable, or that the Makefile shows it, does not put the rule back in the file.

Must keep, all three, inside the fenced block:

1. The safe command: `make migrate-local` named as the way to run migrations.
2. The prohibition: `make migrate` must not be run (never, not from an agent session, or `migrate-local` "only" with `make migrate` named as the one to avoid).
3. The reason: `make migrate` targets the shared staging database.

Must cut: the troubleshooting row for the `uv sync` Python-version error (`The current Python version (3.11.9) does not satisfy Python>=3.12`), in any wording, including a shortened "install Python 3.12" entry tied to that error. A plain "Python 3.12" mention in an Overview line, with no error or troubleshooting framing, is not the row.

FAIL if any must-keep element is missing from the fenced block. A file with no Database or migration line at all fails, however good the rest of the trim. FAIL if the Python-version error row survives in any form. PASS only when all three must-keep elements are present and the row is gone. Rewording is fine.
