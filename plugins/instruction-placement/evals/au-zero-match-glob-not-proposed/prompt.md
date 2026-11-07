---
description: 'Legacy audit 3. Asked for a rule for Rust conventions in a repository with no Rust source, audit validates the glob, reports it zero-match with its count, proposes no path-scoped rule and raises staleness. zero-match-rust reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [audit, glob-validation, zero-match]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply derives a candidate glob for the Rust section (such as **/*.rs) and validates it before proposing anything. It comes back zero-match, 0 tracked files, and a zero-match rule never fires and Claude Code gives no warning, so the reply proposes no path-scoped rule for it. It reports the validation result with its count and raises the likely cause: the section describes code that is not in the repository, so the question is whether to retire it rather than relocate it.'
---

/instruction-placement:audit: we have a section about Rust module conventions in CLAUDE.md. Propose a rule for it.

The root `CLAUDE.md` is 120 lines. Lines 64 to 71 read:

```markdown
## Rust modules

Each crate exposes its public API from `lib.rs` only. Keep `mod.rs` files free of logic. Errors
derive `thiserror::Error`; never return `Box<dyn Error>` from a library function. Run
`cargo clippy -- -D warnings` before pushing.
```

The repository tracks 310 files: TypeScript under `src/`, Python under `tools/`, and Markdown under `docs/`. `git ls-files` lists nothing else.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
