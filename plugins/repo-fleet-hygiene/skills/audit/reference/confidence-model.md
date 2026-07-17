# Confidence and disposition model

Confidence describes evidence strength; disposition describes whether the evidence is sufficient to
send a target into another tool's own dry-run/confirmation workflow. They are intentionally separate.

| Kind | Evidence | Confidence | Disposition |
|---|---|---|---|
| `merged-local-branch` | GitHub `MERGED` PR for this repository + branch and `headRefOid` equals local tip; branch is not current/default/worktree-attached | `HIGH` | Candidate handoff to `/repo-hygiene:clean git` |
| `merged-worktree` | Same merged-PR/tip evidence, branch is attached to a non-main registered worktree | `HIGH` | Candidate handoff to `/source-control:worktree cleanup --dry-run` first |
| `merged-pr-tip-drift` | GitHub merged PR exists, but local tip differs from every returned `headRefOid` | `MEDIUM` | Manual review; never delete from this evidence |
| `local-ancestry-only` | Local tip is an ancestor of the remote-tracking default branch, with no matching GitHub merged PR evidence | `LOW` | Informational only |
| `prunable-worktree` | Git porcelain marks the registration `prunable` | `HIGH` | Candidate dry-run handoff; no inline prune |
| `missing-worktree` | Registered path is absent but Git has not marked it prunable under its current expiry policy | `MEDIUM` | Manual review/dry-run handoff |
| `locked-worktree` | Git porcelain marks a non-main registration locked | `HIGH` | Manual review of the lock reason before cleanup |
| `worktree-admin-mismatch` | Registered directory exists and resolves to a different common Git directory, or cannot resolve as the registered repository | `HIGH` | Manual admin-directory decision; never automatic repair/removal |
| `github-remote-moved` | GitHub REST resolves requested `owner/repo` to a different canonical `full_name` | `HIGH` | Human-reviewed remote update |
| Canonical identity unavailable/conflicting | Override target cannot prove it is the discovered GitHub repository | `UNKNOWN` | Stop that repository; never combine evidence |
| Worktree inventory command fails | Attachment/protection membership cannot be established | `UNKNOWN` | Stop local branch/worktree classification for that repository |
| GitHub unavailable/404/403 | Required GitHub evidence could not be obtained or is access-ambiguous | `UNKNOWN` | Investigate; no negative or cleanup inference |

Priority rules:

1. A protection condition wins over a branch candidate classification.
2. A merged worktree routes through worktree cleanup before branch cleanup.
3. Administrative mismatch wins over ordinary worktree status because the path cannot be trusted.
4. A stronger confidence tier never authorizes mutation inside this plugin.
