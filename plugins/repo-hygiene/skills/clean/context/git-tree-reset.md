# The `tree` action — working-tree realignment

Full detail for the destructive `tree` action. SKILL.md §6 carries the headline; this file carries gates and script contract.

## Scope

**In:** single checkout realignment — `git fetch origin`, `git reset --hard <upstream>`, `git clean -fdx` with default-preserve excludes, plus a reparse-point restore guard.

**Out:** git worktree directory removal (a worktree-management tool); branch deletion (the `git` action); dependency reinstall (the project's own bootstrap/setup — post-step only); stopping live processes. A live session's own tooling (MCP servers, telemetry collectors, build/test watchers) recreates ignored dirs and holds file locks — a clean run cannot fully zero the tree while they run, and locked files surface as `Unremovable:`. For a truly pristine tree, close dev tooling first.

## Script

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-tree-reset.sh \
  [--dry-run] [--apply] [--force-default-branch] \
  [--include-deps] [--include-secrets] [--allow-unpushed]
```

Default: `--dry-run`. Output labels documented in script `--help`.

### Default-preserve + opt-in flags

`tree` preserves three protected classes by default (SSOT: `CLEAN_TREE_PRESERVE_*` in `scripts/lib/cleanup-paths.sh`). Detail + the junction-proofing rationale: `reference/cleanup-config.md` "tree".

| Flag | Effect |
| --- | --- |
| *(none)* | preserve secrets + runtime deps + skill data |
| `--include-deps` | also remove `node_modules/` / `.venv/` / `vendor/` (rebuildable) |
| `--include-secrets` | also remove `.env*` / `*.local.*` / IDE + cloud + codex config (**UNRECOVERABLE**) |
| `--allow-unpushed` | proceed when HEAD is ahead of upstream (discards unpushed commits) |

Skill data (`.claude/skills/*/data/`) is preserved unconditionally — no flag removes it.

### Gates (script-enforced)

- Upstream tracking branch required (`@{u}`); a configured-but-unresolvable upstream — remote-tracking ref absent (e.g. a squash-merged branch whose remote was deleted and pruned), where `@{u}` degrades to the literal token — is a first-class gate: skip the repo with `Blocked: upstream-unresolved (<remote>/<branch>)` before any destructive op, so a literal `@{u}` can never reach `reset --hard` (exit 6).
- Blocks on default branch (`main`/`master`/resolved default) unless `--force-default-branch` (exit 3).
- Aborts when HEAD is ahead of upstream unless `--allow-unpushed` (exit 4) — prevents silent loss of unpushed commits.
- Aborts the apply if `reset --hard` fails (exit 5) — `clean` and the restore guard never run, so a failed reset can never leave the tree cleaned but not reset (the reset itself may have partially modified tracked files, since `reset --hard` is not atomic).
- Aborts the apply if `git clean -fdx` genuinely fails (exit 7) — a non-zero clean exit whose cause is NOT locked/in-use files. The reset succeeded (its `AppliedReset:` line is still emitted); `clean` prints `AppliedClean: failed` instead of a success line, so the report can never claim a clean that errored. Locked/in-use files are the expected non-fatal case (see `Unremovable:` below) and are not a failure.
- Post-clean restore guard: any tracked file deleted via reparse-point traversal is restored from the index (`RestoredTracked:` count; safe because `reset --hard` ran first).
- Locked / in-use files git could not delete are reported (`Unremovable:`), not silently left.

### Agent gates (never script-bypassed)

- Always run `--dry-run` first; show preview to user (surface `PreserveDeps` / `PreserveSecrets` / `AheadCount`).
- `AskUserQuestion` before `--apply` (interactive only); `--include-secrets` and `--allow-unpushed` each need their own explicit confirmation.
- Autonomous mode: abort; user re-invokes interactively.

## Relationship to the `git` action

| | `git` action | `tree` action |
| --- | --- | --- |
| Safety class | Write-safe metadata | Destructive working tree |
| `git clean` | No | Yes (`-fdx`) |
| `git reset --hard` | No | Yes |
| In `all` | Yes | **No** |

## Hook interaction

The session-scoped destructive guard (`scripts/destructive-guard.sh`) blocks bare `git clean -f` / `git reset --hard` while this skill is active. The wrapper script runs those as subprocesses — invoke via `bash git-tree-reset.sh`, not inline git commands.
