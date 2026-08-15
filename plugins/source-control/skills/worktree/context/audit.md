# Worktree `audit` — configuration health checks and findings presentation

Full detail for the `/source-control:worktree audit` action. SKILL.md carries the headline plus Step 1 (run `status` internally); this file carries the Step 2 configuration-health checklist and the Step 3 findings presentation.

Periodic health check for worktree infrastructure. Suitable as a recurring item in your work-item tracker.

## Step 2: Check configuration health

| Check | How | Expected |
|-------|-----|----------|
| `delete_branch_on_merge` | `gh api repos/{owner}/{repo} --jq '.delete_branch_on_merge'` | `true` recommended — remote branches auto-delete on merge, so cleanup only handles local branches |
| Worktree root convention | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-root-doctor.sh" --repo-dir <repo>` | Exit 0 — the doctor makes the `melodic.worktreeroot` / `includeIf` silent-failure classes loud (misfiring conditions, missing include files, parse-order shadowing, a root inside a repository) and names which rule supplied this repository's root; report each `warn:`/`error:` line as a finding. Convention: `reference/worktree-root-convention.md` |
| Gitignored-file propagation | Check whether a `.worktreeinclude` file exists at the repo root | Optional — suggest when the project keeps local secrets/config in gitignored files (e.g. `.claude/settings.local.json`); Claude Code copies matching gitignored files into new worktrees |
| Project worktree hooks | If the project registers `WorktreeCreate` / SessionStart setup hooks in its settings, confirm they are present as its docs expect | Per project convention — skip when the project has none |
| Stale metadata | `git worktree list --porcelain` shows no `prunable` entries | Clean — otherwise suggest `git worktree prune` via `/source-control:worktree cleanup` |

## Step 3: Present findings

```markdown
## Worktree Audit

### Infrastructure
| Check | Status |
|-------|--------|
| delete_branch_on_merge | OK (enabled) |
| Worktree root convention | OK (melodic.worktreeroot supplied by includeIf "gitdir/i:~/work/") |
| .worktreeinclude | SUGGEST — gitignored local settings exist but no .worktreeinclude |
| Stale metadata | OK (none prunable) |

### Worktree Health
- 3 worktrees total
- 1 stranded (4 commits at risk) — push before any cleanup
- 0 unproven (Work axis unavailable)
- 0 in-progress — cleanup refuses (sequencer / conflict state dies with the directory)
- 0 dirty — cleanup refuses (uncommitted edits, or status unreadable)
- 1 stale (> 14 days, no PR) — consider `/source-control:worktree cleanup`
- 0 prunable

### Recommendations
- Push the stranded worktree's branch: `git -C <path> push -u origin HEAD`
- Create `.worktreeinclude` with your local-settings pattern for automatic propagation
- Run `/source-control:worktree cleanup` to remove the stale worktree
```

Stranded and unproven counts lead the health list and are reported even when zero — a class that only appears when non-zero cannot be distinguished from one that was never measured, and "the Work axis could not be computed" is exactly the answer an audit must not swallow. `in-progress` and `dirty` follow them for the same reason: both are classes `/worktree cleanup` refuses to act on, and `in-progress` is invisible to `git status --porcelain`, so nothing else in the audit surfaces it unless named here.
