# Worktree `audit` — configuration health checks and findings presentation

Full detail for the `/worktree audit` action. SKILL.md carries the headline plus Step 1 (run `status` internally); this file carries the Step 2 configuration-health checklist and the Step 3 findings presentation.

Periodic health check for worktree infrastructure. Suitable as a recurring item in your work-item tracker.

## Step 2: Check configuration health

| Check | How | Expected |
|-------|-----|----------|
| `delete_branch_on_merge` | `gh api repos/{owner}/{repo} --jq '.delete_branch_on_merge'` | `true` recommended — remote branches auto-delete on merge, so cleanup only handles local branches |
| Gitignored-file propagation | Check whether a `.worktreeinclude` file exists at the repo root | Optional — suggest when the project keeps local secrets/config in gitignored files (e.g. `.claude/settings.local.json`); Claude Code copies matching gitignored files into new worktrees |
| Project worktree hooks | If the project registers `WorktreeCreate` / SessionStart setup hooks in its settings, confirm they are present as its docs expect | Per project convention — skip when the project has none |
| Stale metadata | `git worktree list --porcelain` shows no `prunable` entries | Clean — otherwise suggest `git worktree prune` via `/worktree cleanup` |

## Step 3: Present findings

```markdown
## Worktree Audit

### Infrastructure
| Check | Status |
|-------|--------|
| delete_branch_on_merge | OK (enabled) |
| .worktreeinclude | SUGGEST — gitignored local settings exist but no .worktreeinclude |
| Stale metadata | OK (none prunable) |

### Worktree Health
- 3 worktrees total
- 1 stale (> 14 days, no PR) — consider `/worktree cleanup`
- 0 prunable

### Recommendations
- Create `.worktreeinclude` with your local-settings pattern for automatic propagation
- Run `/worktree cleanup` to remove the stale worktree
```
