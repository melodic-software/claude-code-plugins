---
description: 'Legacy check 2. With valid rule globs and no index block yet, check passes the gate, reports the missing index as a recommendation that names what the index buys, keeps it apart from a drifted index, and names the file it resolved as the target. index-recommended reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [check, rules-index, missing-index]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply resolves the root AGENTS.md as the index target and names it. render-index.sh check exit 3 means nothing to compare, not broken, so the absent index is a recommendation rather than a gate failure, and the verdict comes from the glob checks alone: all three rules are valid, so the gate passes. It explains what the index buys (no deferred surface announces that it exists, and the always-loaded index names each one so an ordinary Read can fetch it first) and names what generates it (render-index.sh write, run by /instruction-placement:realign or offered by /instruction-placement:setup). A repository that has an index and let it drift is a different case and does fail.'
---

/instruction-placement:check: we have rules but we've never generated an index.

The repository has a root `AGENTS.md`, a root `CLAUDE.md` that is the single line `@AGENTS.md`, and three rules in `.claude/rules/`. `glob-tools.sh rules` prints:

```text
PATTERN  .claude/rules/api.md  packages/api/**/*.ts  1  88  valid
PATTERN  .claude/rules/sql.md  db/**/*.sql  1  37  valid
PATTERN  .claude/rules/docs.md  docs/**/*.md  1  54  valid
SUMMARY  412  3  0  0  PASS
```

`render-index.sh check AGENTS.md` exits 3 and prints `no index block in AGENTS.md`.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
