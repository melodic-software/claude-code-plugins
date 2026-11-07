---
description: 'Legacy migrate 5. Asked for a short answer on dropping the shims, migrate cutover-check prints each graded condition with its evidence, treats UNREACH as not a pass, names the outstanding conditions, and removes nothing. ci-unreach-outstanding reads the reply. Read-only tools, graded on the reply.'
tags: [migrate, cutover-check, unreach]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply reports each graded condition with the evidence behind it, not a bare yes or no: condition 1 met on the bundle''s code default, condition 2 UNREACH because the claude-code-action@v1.2.0 pin is outside the release map, condition 3 met on both canary cwds, condition 4 unmet on the unacknowledged tests/conftest.py row. It treats UNREACH as not a pass, so the answer is no: conditions 2 and 4 are outstanding. It deletes no CLAUDE.md and writes nothing.'
---

/instruction-placement:migrate cutover-check: are we clear to drop the CLAUDE.md shims yet? Short answer is fine.

`cutover-check.sh --repo .` prints:

```text
[MET]     1 remote flag: code default true in the installed 2.1.319 bundle
[UNREACH] 2 CI: anthropics/claude-code-action@v1.2.0 in .github/workflows/claude.yml is not in the release map
[MET]     3 local canary: token returned from ~/src/scratch and /mnt/d/scratch
[UNMET]   4 path detection: tests/conftest.py: ROOT = next(p for p in here.parents if (p / "CLAUDE.md").exists())
```

and exits 1. `.claude/cutover-pathdet-ack.txt` does not exist.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
