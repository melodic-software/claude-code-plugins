---
description: 'Legacy setup 5. With an index in AGENTS.md and no CLAUDE.md anywhere, setup reports NATIVE, not UNREACHABLE and not loaded, proposes no import or symlink, says what a static check cannot see, and names verify-load.sh as the proof. reports-native and names-verify-load read the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [setup, reachability, native]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply reports the NATIVE verdict rather than UNREACHABLE: none of the three CLAUDE.md names sits on the target''s path, so nothing in the repository blocks it and Claude Code reads the AGENTS.md directly. It proposes no @AGENTS.md import or symlink, since there is no root CLAUDE.md to put one in. It stops short of saying the index loaded: that also turns on the CLI version and session kind, which no static check sees, and on a CLAUDE.md above the repository root, which this check cannot see either. It names verify-load.sh as the only proof of an actual load, and keeps UNREACHABLE for a root CLAUDE.md read instead of the target.'
---

/instruction-placement:setup this repo has an AGENTS.md with the index in it and no CLAUDE.md anywhere, not at the root, not a .claude/CLAUDE.md, not a CLAUDE.local.md. Is the index reaching Claude?

The root `AGENTS.md` is 60 lines and carries an index block that matches the four rules in `.claude/rules/`. Every rule glob resolves. `git`, `jq` and the Claude Code CLI are on `PATH`, and there is no plugin configuration.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
