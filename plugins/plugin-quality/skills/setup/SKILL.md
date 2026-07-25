---
name: setup
description: "Verify the plugin-quality plugin's prerequisites on this machine — gh presence and the ACTING account, the context-guard snapshot seam, config layers and the effective sink with per-layer provenance — and optionally write the tracked .claude/plugin-quality.md config. Use when: 'set up plugin-quality', 'which sink will audits use', 'is the audit context-gate live', before a first audit in a repo, or after changing config layers. Actions: check (read-only), apply (writes ONLY the tracked config file, on explicit request)."
argument-hint: "check | apply [sink=<gh-issues|markdown-dir|local-fallback>] [markdown_dir=<path>]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Setup for the `audit` skill's two external seams (`gh`, `context-guard`) and its config cascade.
`check` inspects and reports PASS/FAIL/INFO with one remediation line per FAIL; `apply`
writes/converges exactly ONE file — the tracked team-layer config
`${CLAUDE_PROJECT_DIR}/.claude/plugin-quality.md` — and nothing else.

The key reference is `${CLAUDE_PLUGIN_ROOT}/reference/config.md` (keys, layers, merge semantics,
sink ladder, item schema). Read it first; this skill reports against that contract rather than
restating it.

## `check` (read-only)

1. **`gh` + acting identity** — `command -v gh`, then `gh auth status`. Report the ACTING account
   and host explicitly: machines can hold multiple GitHub identity domains, and the audit's emit
   gate surfaces this same account before any `gh issue create` — a surprise here is a
   cross-pollination incident later, so surface it at setup time too. `gh` absent → INFO, not
   FAIL: the sink ladder ends in the local markdown fallback, so audits still work.
2. **Context-guard seam** — probe this session's snapshot
   (`~/.claude/context-guard/context/${CLAUDE_SESSION_ID}.json`, staleness and null rules per the
   context-guard reader contract) and report the dispatch mode the audit will run in:
   - Fresh, trustworthy snapshot → **zone-informed dispatch** (report the zone too).
   - Absent / stale / null fields / jq missing / substitution unexpanded → **conservative
     dispatch** (the audit's unknown row + visible notice). This is a working state, not a
     defect; recommend the `context-guard` plugin's setup only as an optional upgrade.
3. **Config layers + effective sink with provenance** — read every cascade layer
   (user-global `~/.claude/plugin-quality.md`, tracked `.claude/plugin-quality.md`, gitignored
   `.claude/plugin-quality.local.md`), apply per-key override, and report:
   - which layers exist,
   - the effective value of each key (`sink`, `markdown_dir`, `zone_behavior`, `repo_map`
     entries), and **which layer supplied it** (the provenance line is the point — a surprising
     effective sink should be traceable in one glance),
   - all layers absent → INFO: sink resolves at audit time via inference/ask (ladder rungs 2–3).
4. **Sink reachability** — for the effective sink: `gh-issues` → covered by step 1;
   `markdown-dir` → the directory exists and is writable; `local-fallback` → nothing to check.

## `apply` (writes ONLY the tracked config, on explicit request)

Write or converge `${CLAUDE_PROJECT_DIR}/.claude/plugin-quality.md`:

1. Source values from the arguments (`sink=…`, `markdown_dir=…`) or, absent arguments, a short
   interview (which sink, and for `markdown-dir` the directory). Validate against the key
   reference before writing.
2. **Converge, don't clobber:** update only the keys being set; preserve every other existing
   key and any surrounding prose byte-for-byte. Idempotent — a second identical `apply` produces
   no diff, and says so.
3. Report exactly what changed (old → new per key).
4. **Gitignore reminder (surface only, never write):** recommend the consuming repo carry the
   recursive overlay line `.claude/**/*.local.*` in its `.gitignore` so the local overlay layer
   stays untracked — this skill NEVER edits the consumer's `.gitignore`; the line is the
   operator's to add.

`apply` never touches the user-global or `.local` layers (those are the operator's), never edits
`settings.json`, and never creates the overlay file.

## What this skill does NOT do

- Run an audit (that is `/plugin-quality:audit`).
- Install `gh` or `jq`, or wire the context-guard statusline (that plugin's own setup owns it).
- Write anything except the tracked `.claude/plugin-quality.md` in `apply`.
