# Action: `scan`

Sweep the codebase for actionable comment markers (`TODO`/`FIXME`/`HACK`/`XXX`) and resolve or file each one. **Not** the encouraged workflow for new work — durable work belongs in the tracker at authoring time; prefer a commit-time hygiene gate (linter or git hook) in the consuming repo to catch new violations as they land.

## Usage

```
scan [--path <dir>] [--work]
```

## Flags

- `--path <dir>` — Limit scan to a specific directory (default: repo root)
- `--work` — After presenting groups, auto-select the smallest group and start resolving

## Detection

If the consuming repo has its own comment-hygiene tooling (a shared pattern library, a lint lane), use that as the detection source of truth per the repo's own rules. Otherwise, scan tracked files directly:

```bash
git grep -nE '\b(TODO|FIXME|HACK|XXX)\b' -- ':!*.min.*' ':!*node_modules*' | tr -d '\r'
```

- **Actionable (in scope):** bare `TODO`/`FIXME`/`HACK`/`XXX` markers describing work to do; internal tracker provenance comments (e.g. `issue #N` breadcrumbs left in code)
- **Not actionable (skip):** external upstream citations (`org/repo#issue`), structured task-list grammar in working-notes files (e.g. `[TODO]` phase tags), test fixtures that assert on the literal marker text, and the consuming repo's documented exclusion paths

## Workflow

1. **Scan** using the detection command above (or the repo's own tooling). Avoid per-file grep loops over large trees — one `git grep` pass scales; per-file spawning is unusable on Windows.

1. **Group** by parent folder. Count items per group.

1. **Present** summary table sorted by count (smallest first).

1. **User selects a group** (by `#`) or use `--work` to auto-select the smallest.

1. **For each violation**, read context (10 lines before/after), then classify:

- **Resolve now** — small fix; do the work, remove the marker
- **File issue + remove marker** — significant work; create via the `add` action, remove the inline marker (do not leave `TODO` as a stand-in for the issue)
- **Remove (already done)** — work completed; delete the comment
- **False positive** — structured grammar or external upstream citation misclassified; fix the exclusion if systemic, otherwise note it in the PR

**Never** "Keep (intentional)" for actionable `TODO`/`FIXME`/`HACK`/`XXX` in merged production code.

1. **After processing a group**, present results table with file, line, action, detail.

1. **Verify** — run the consuming repo's build/test/lint commands if any source files were modified.
