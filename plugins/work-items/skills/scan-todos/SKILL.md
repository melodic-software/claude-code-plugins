---
description: "Sweep source comments, not tracker items, for TODO/FIXME/HACK/XXX markers and resolve or file each one. Use when: 'scan TODOs', 'scan for FIXME', 'sweep the codebase for markers', 'find TODO comments', 'resolve TODO/FIXME/HACK', 'scan for tech-debt comments', 'clean up markers'. Not the workflow for new work: durable work belongs in the tracker when it is written. Tracker items go to /work-items:track."
argument-hint: "[--path <dir>] [--work] [--repo <repo> ...]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Sweep source comments for TODO and FIXME markers, resolve or file each
---

## Variables

Arguments: `$ARGUMENTS`, parsed as the flags below.

## Shared tracker context

The seam, operation routing, label taxonomy, canonical-role remapping, recurring schedule, and
memory-tier write rule that every work-items skill relies on live in
[`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
(and the references it links). Read it at the start of an invocation. Item creation goes through the
seam via the `/work-items:track add` path; the core inlines no provider commands.

## Purpose

Resolve or file each actionable comment marker. To catch new markers as they land, prefer a commit-time hygiene gate (linter or git hook) in the consuming repo.

## Flags

- `--path <dir>`: limit the scan to one directory (default: repo root).
- `--work`: after presenting groups, auto-select the smallest group and start resolving.
- `--repo`, `--repos-from`, `--owner`, `--fleet`, `--skip`, or the same request in words: scan
  several repositories. With none of them, the scan covers the current repository as below.

## Several repositories

The target forms resolve, count, fan out and merge as
[`${CLAUDE_PLUGIN_ROOT}/reference/target-scope.md`](${CLAUDE_PLUGIN_ROOT}/reference/target-scope.md)
"Target forms", "Resolving repositories", "Fan-out" and "Merging findings" say. Each repository's
subagent runs Scan and Group only, with `<project root>` set to its own root and `--path` applied
inside it, and returns its groups. Outside the session's own checkout, Detection greps
`origin/HEAD` (`git -C <root> grep -nE '<pattern>' origin/HEAD -- ...`) and drops the
`origin/HEAD:` prefix from each hit. The parent keys groups by repository and parent folder,
presents one table of them all by count, and takes the selection; `--work` picks the smallest
group across every repository. The selected group's markers are resolved under "Writes stay per
repository", in a worktree of that group's repository, and each significant marker is filed with
`/work-items:track add --repo <owner/name>` so it lands in that repository's tracker.

## Detection

If the consuming repo has its own comment-hygiene tooling (a shared pattern library, a lint lane), detect with it. Otherwise scan tracked files directly:

```bash
# -C roots the scan at the repo top — a bare git grep from a subdirectory searches only that subtree.
# With --path <dir>, thread it in as a root-relative pathspec: ... -- '<dir>'
# Thread the consuming repo's documented exclusion paths in the same way, as ':!<path>' pathspecs after --.
git -C "<project root>" grep -nE '\b(TODO|FIXME|HACK|XXX)\b' | tr -d '\r'
```

`<project root>` is the literal path [`tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md) "Project root" resolves, in its own Bash call before this snippet.

- **Actionable (in scope):** bare `TODO`/`FIXME`/`HACK`/`XXX` markers describing work to do; internal tracker provenance comments (e.g. `item #N` breadcrumbs left in code)
- **Not actionable (skip):** external upstream citations (`org/repo#issue`), structured task-list grammar in working-notes files (e.g. `[TODO]` phase tags), test fixtures that assert on the literal marker text, and the consuming repo's documented exclusion paths

## Next

`/work-items:triage` for the raw items it filed.

## Workflow

1. **Scan** using the detection command above (or the repo's own tooling). Avoid per-file grep loops over large trees, one `git grep` pass scales; per-file spawning is unusable on Windows.

1. **Group** by parent folder. Count items per group.

1. **Present** summary table sorted by count (smallest first).

1. **User selects a group** (by `#`) or use `--work` to auto-select the smallest.

1. **For each marker**, read 10 lines of context before and after, then classify:

- **Resolve now**: small fix; do the work, remove the marker
- **File a work item + remove marker**: significant work; create it by invoking `/work-items:track add` via the Skill tool following the shared self-observation contract ([`${CLAUDE_PLUGIN_ROOT}/reference/dogfood-filing.md`](${CLAUDE_PLUGIN_ROOT}/reference/dogfood-filing.md): dedupe → categorize → fixed shape → `needs-triage`; per-user `ai_disclaimer`: `${user_config.ai_disclaimer}`), remove the inline marker (do not leave `TODO` as a stand-in for the item). In a run the user invoked, their group choice or `--work` is the filing authorization ([`../track/actions/add.md`](../track/actions/add.md) "Authorization gate")
- **Remove (already done)**: work completed; delete the comment
- **False positive**: structured grammar or external upstream citation misclassified; fix the exclusion if systemic, otherwise note it in the PR

**Never** "Keep (intentional)" for actionable `TODO`/`FIXME`/`HACK`/`XXX` in merged production code.

1. **After processing a group**, present a results table: file, line, action, detail.

1. **Verify**: run the consuming repo's build/test/lint commands if any source file changed.
