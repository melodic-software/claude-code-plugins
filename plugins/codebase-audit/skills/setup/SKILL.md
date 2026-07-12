---
name: setup
description: "Configure the codebase-audit plugin for this repository: interview the user, infer audit targets from the repo layout, and write the tracked .claude/codebase-audit.md config file. Use when: 'set up codebase-audit', 'configure the audit', 'codebase-audit setup', the audit skill reports missing or thin config, or audit dimensions need tuning. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Write (or update) the consuming repo's tracked audit-dimension config at `.claude/codebase-audit.md`
so `/codebase-audit:codebase-audit` runs deterministically instead of re-inferring targets every run.
Idempotent: re-running reads the existing config and offers updates rather than overwriting blind.

## Task

1. **Read existing config first.** If `.claude/codebase-audit.md` exists, load it and present a
   short summary (dimensions present, glob counts, example-claim counts). The interview then
   proposes changes against that baseline; nothing is dropped without the user confirming.
2. **Explore the repo to draft defaults.** Before asking anything, infer candidates:
   - **documentation** primary-sources: doc directories (`docs/`, `README.md`), agent-instruction
     files (`AGENTS.md`, `CLAUDE.md`), ADR directories, convention docs.
   - **configuration** primary-sources: build config, lint config, CI workflows, git-hook config —
     detected from what actually exists (e.g. `Directory.Build.props`, `pyproject.toml`,
     `package.json`, `.github/workflows/`, `lefthook.yml`, `.editorconfig`).
   - **code-quality** primary-sources: source roots; verification-sources: test roots **plus the
     same source roots** — a cross-file DRY/SOLID claim is validated by reading peer source files,
     which a discovery agent can only read when they are in `verification-sources` (the fence forbids
     the other primary-source files). Omitting them makes cross-file findings unreachable.
   - **architecture** primary-sources: dependency manifests + architecture docs;
     verification-sources: analyzers / architecture tests where present **plus the dependency
     manifests and source roots** — dependency-direction and boundary claims need peer manifests
     readable, for the same fence reason.
3. **Interview, one decision at a time.** Present each dimension's drafted globs with a
   recommendation; let the user accept, edit, or remove the dimension. Offer custom dimensions
   last ("anything else this repo should audit as its own lane?").
4. **Draft example-claims.** For each accepted dimension, read one or two representative
   primary-source files and propose 2–4 concrete `{ claim, verify-via }` rows drawn from real
   sentences in them. Concrete rows teach the discovery pass what drift looks like in THIS repo —
   the highest-value part of the config. The user approves or edits each row.
5. **Write the config.** Materialize `.claude/codebase-audit.md` following the structure in
   [`${CLAUDE_PLUGIN_ROOT}/skills/setup/templates/config-template.md`](templates/config-template.md) (replace every placeholder comment
   with real values; drop unused placeholder rows). Confirm the file is tracked, not ignored.
6. **Offer the overlay convention.** Personal overrides go in `.claude/codebase-audit.local.md`;
   recommend the consumer add `.claude/*.local.*` to `.gitignore` if not already covered. A
   user-global base at `~/.claude/codebase-audit.md` is also honored. Layers resolve
   user-global → team → local overlay, additively.

## Output

A tracked `.claude/codebase-audit.md` in the consuming repo, plus a one-paragraph summary of what
was written and how to re-run this setup to reconfigure.

## What this skill does NOT do

- Run an audit — that is `/codebase-audit:codebase-audit`.
- Write machine-local state — configuration lives in the consumer's tracked file, never in the
  plugin directory or the plugin data directory.
