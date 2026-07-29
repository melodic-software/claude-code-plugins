---
name: scan-todos
description: "Sweep the codebase's source comments — not tracker items — for actionable markers (TODO/FIXME/HACK/XXX) and resolve or file each one. Use when: 'scan TODOs', 'scan for FIXME', 'sweep the codebase for markers', 'find TODO comments', 'resolve TODO/FIXME/HACK', 'scan for tech-debt comments', 'clean up markers'. NOT the encouraged workflow for new work — durable work belongs in the tracker at authoring time; prefer a commit-time hygiene gate. Sibling skills: /work-items:track (backlog CRUD), /work-items:work (auto-select + execute), /work-items:triage (raw intake), /work-items:decompose (plan → tickets)."
argument-hint: "[--path <dir>] [--work] — sweep TODO/FIXME/HACK/XXX markers"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Sweep source comments for TODO and FIXME markers, resolve or file each
---

## Variables

Arguments: `$ARGUMENTS`

## Shared tracker context

The seam, operation routing, label taxonomy, canonical-role remapping, recurring schedule, and
topic-docs binding that every work-items skill relies on live in
[`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
(and the references it links). Read it at the start of an invocation. Item creation goes through the
seam via the `/work-items:track add` path; the core inlines no provider commands.

## Purpose

Sweep the codebase for actionable comment markers (`TODO`/`FIXME`/`HACK`/`XXX`) and resolve or file each one. **Not** the encouraged workflow for new work — durable work belongs in the tracker at authoring time; prefer a commit-time hygiene gate (linter or git hook) in the consuming repo to catch new violations as they land.

## Usage

```
/work-items:scan-todos [--path <dir>] [--work]
```

## Flags

- `--path <dir>` — Limit scan to a specific directory (default: repo root)
- `--work` — After presenting groups, auto-select the smallest group and start resolving

## Detection

If the consuming repo has its own comment-hygiene tooling (a shared pattern library, a lint lane), use that as the detection source of truth per the repo's own rules. Otherwise, scan tracked files directly:

```bash
# -C roots the scan at the repo top — a bare git grep from a subdirectory searches only that subtree.
# With --path <dir>, thread it in as a root-relative pathspec (keep the exclusions): ... -- '<dir>' ':!*.min.*' ':!*node_modules*'
git -C "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}" grep -nE '\b(TODO|FIXME|HACK|XXX)\b' -- ':!*.min.*' ':!*node_modules*' | tr -d '\r'
```

- **Actionable (in scope):** bare `TODO`/`FIXME`/`HACK`/`XXX` markers describing work to do; internal tracker provenance comments (e.g. `item #N` breadcrumbs left in code)
- **Not actionable (skip):** external upstream citations (`org/repo#issue`), structured task-list grammar in working-notes files (e.g. `[TODO]` phase tags), test fixtures that assert on the literal marker text, and the consuming repo's documented exclusion paths

## Workflow

1. **Scan** using the detection command above (or the repo's own tooling). Avoid per-file grep loops over large trees — one `git grep` pass scales; per-file spawning is unusable on Windows.

1. **Group** by parent folder. Count items per group.

1. **Present** summary table sorted by count (smallest first).

1. **User selects a group** (by `#`) or use `--work` to auto-select the smallest.

1. **For each marker**, read context (10 lines before/after), then classify:

- **Resolve now** — small fix; do the work, remove the marker
- **File a work item + remove marker** — significant work; create via `/work-items:track add` following the shared self-observation contract ([`${CLAUDE_PLUGIN_ROOT}/reference/dogfood-filing.md`](${CLAUDE_PLUGIN_ROOT}/reference/dogfood-filing.md): dedupe → categorize → fixed shape → `needs-triage`), remove the inline marker (do not leave `TODO` as a stand-in for the item)
- **Remove (already done)** — work completed; delete the comment
- **False positive** — structured grammar or external upstream citation misclassified; fix the exclusion if systemic, otherwise note it in the PR

**Never** "Keep (intentional)" for actionable `TODO`/`FIXME`/`HACK`/`XXX` in merged production code.

1. **After processing a group**, present results table with file, line, action, detail.

1. **Verify** — run the consuming repo's build/test/lint commands if any source files were modified.
