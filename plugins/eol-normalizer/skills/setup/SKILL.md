---
name: setup
description: "Verify the eol-normalizer hook's runtime prerequisites and configuration for this repository. Use when: 'set up eol-normalizer', 'configure eol-normalizer', 'is eol-normalizer working', line endings silently aren't normalizing, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — the normalization policy is
the repository's own `.gitattributes`, and the only tunable is the native `userConfig`
toggle. Every prerequisite is a system tool (Bash, jq, git), so `apply` is pure guidance and
writes nothing.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
points at each remediation. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

The hook is the single source of truth for what it requires and how it resolves things.
**Read it first** — the entry script (`${CLAUDE_PLUGIN_ROOT}/hooks/eol-normalizer.sh`) sources
`${CLAUDE_PLUGIN_ROOT}/hooks/normalize-eol.sh`, and that sourced library is where the real
resolution lives (the `git check-attr` calls, the repo-root anchoring, and the NUL-byte
binary guard). Read both, probe what they actually do, don't recite this file. Then run each
probe via Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not
modify anything.

1. **Bash version** — check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (for example telemetry's `EPOCHREALTIME`,
   Bash 5.0+).
2. **`jq`** — `command -v jq`. FAIL if absent: the hook then skips with a visible
   once-per-session notice instead of normalizing.
3. **`git`** — `command -v git`. FAIL if absent: unlike jq, the hook emits NO visible notice
   when git is missing — `git check-attr` and repo-root resolution silently fail and the
   hook no-ops, so this probe is the only visibility. Distinguish the two non-failure cases
   the hook treats differently: git present but the path is not inside a git repository →
   INFO (not applicable — nothing to normalize against, per the README), and git present
   inside a repo but no `eol=` rule governs any path → INFO (inert by design, the opt-in
   analog: resolution is entirely `.gitattributes`-driven).
4. **Consumer `.gitattributes` `eol=` policy** — using the hook's own resolver
   (`git check-attr eol` anchored at the repo root), confirm whether any `eol=lf`/`eol=crlf`
   rule governs paths the hook would touch. `check-attr` answers for ANY candidate path,
   tracked or not — the hook normalizes a first write to a brand-new file the same as an
   edit to a tracked one — so probe representative candidate paths (or report the declared
   patterns), never a tracked-files listing that would miss untracked matches. Report what
   governs, or INFO that none does — absence is the opt-out by design, so the plugin is
   inert (INFO, not FAIL), matching the README's "ships no policy of its own" stance.
5. **Hook toggle** — report the effective `eol_normalizer_enabled` value:
   `${user_config.eol_normalizer_enabled}` (unexpanded or empty means default `true`).
6. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution. Every prerequisite here is a system
tool, so `apply` installs nothing and writes nothing — it only points:

- missing `jq` / Bash / git: platform install instructions from the README Requirements
  section; this skill never installs system packages.
- toggle off: direct to `/plugin configure eol-normalizer` or
  `claude plugin install eol-normalizer@<marketplace> --config eol_normalizer_enabled=true`;
  this skill never writes user settings or `pluginConfigs`.
- no `eol=` policy: this is the opt-out, not a defect. Point at the repository's own
  `.gitattributes` as the place to declare policy; this skill never writes `.gitattributes`,
  because that would impose a repo-wide line-ending policy the plugin has no mandate to
  choose.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Normalize any file — editing a file exercises the hook end-to-end.
- Write `.gitattributes`, the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install any tool, during either `check` or `apply` — all prerequisites are system tools
  resolved with guidance only.
