# Confidence and disposition model

Confidence describes evidence strength; disposition describes whether the evidence is sufficient to
send a target into another tool's own dry-run/confirmation workflow. They are intentionally separate.

## Axes

`HIGH`, `MEDIUM`, `LOW`, and `UNKNOWN` are the confidence values — how strong the evidence is.

`ACKNOWLEDGED` is **not** a fifth confidence value. It is a prominence demotion applied to an
`UNKNOWN` `github-identity-unavailable` finding whose identity is listed in `fleet.ackUnavailable`:
the evidence is exactly as weak, and the finding is still reported, but the operator has recorded
that this identity is known-inaccessible so it stops competing for attention. It never suppresses a
finding, never touches a non-404/403 failure, and never affects evidence from a successful API
response. The report gives it its own group for that reason.

## Every emitted finding kind

The collector emits exactly the kinds below. `scripts/audit-fleet.test.sh` asserts that this table's
kind set and the collector's emitted kind set are equal, so a new kind cannot ship without a
documented disposition — the drift that made this table cover half the finding set is now a test
failure rather than a discovery.

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
| `github-remote-moved` | GitHub REST resolves the requested `owner/repo` to a different canonical `full_name` | `HIGH` | Human-reviewed remote update |
| `duplicate-checkout` | Two or more distinct checkouts resolve to one normalized GitHub identity | `LOW` | Informational only; same-identity clones legitimately diverge |
| `canonical-override-invalid` | An override target has a missing, ambiguous, credential-only, or non-`github.com` remote | `UNKNOWN` | Stop that repository; never combine evidence |
| `canonical-identity-unverified` | An override target's GitHub identity could not be resolved for comparison against the discovered one | `UNKNOWN` | Stop that repository; never combine evidence |
| `canonical-identity-conflict` | An override target resolves to a different GitHub identity than the discovered checkout | `UNKNOWN` | Stop that repository; never combine evidence |
| `github-identity-unavailable` | `GET /repos/{owner}/{repo}` returned 404/403, failed, or timed out | `UNKNOWN`, demoted to `ACKNOWLEDGED` when the identity is listed in `fleet.ackUnavailable` and the failure was 404/403 | Investigate; never infer "deleted" or "moved" |
| `github-pr-evidence-unavailable` | The repository-scoped merged-PR query failed | `UNKNOWN` | Do not infer branch merge state |
| `merged-pr-window-truncated` | The merged-PR query returned a full window of rows, so older merged PRs fall outside it | `UNKNOWN` | Absent merged findings in this repository are unproven; verify a branch on GitHub before cleanup |
| `merge-evidence-privacy-gated` | The exact per-branch merged-PR lookup was skipped because the branch is absent from the local remote-tracking inventory, so its name must not be sent to GitHub | `UNKNOWN` | Merged state unverified; restore remote evidence or verify manually |
| `worktree-inventory-unavailable` | `git worktree list --porcelain -z` failed | `UNKNOWN` | Stop local branch/worktree classification for that repository |
| `worktree-common-dir-unavailable` | A registered worktree path exists but its `--git-common-dir` could not be resolved | `UNKNOWN` | Manual inspection; the registration cannot be trusted either way |
| `branch-inventory-unavailable` | `git for-each-ref` over `refs/heads/` failed or emitted malformed/partial output | `UNKNOWN` | Discard partial records, stop branch classification, exclude from the audited count |
| `remote-branch-inventory-unavailable` | `git for-each-ref` over `refs/remotes/<remote>/` failed | `UNKNOWN` | Exact per-branch GitHub lookups are skipped for the whole repository |
| `current-branch-unavailable` | `git branch --show-current` failed, so branch-protection membership is unknown | `UNKNOWN` | Emit no standalone branch cleanup candidate for that repository |
| `git-common-dir-unavailable` | The canonical checkout's own `--git-common-dir` could not be resolved | `UNKNOWN` | Stop that repository; registration comparison is impossible |
| `local-ancestry-unavailable` | `git merge-base --is-ancestor` failed with an error status | `UNKNOWN` | Do not infer local ancestry |
| `stale-config-entry` | A config-sourced `fleet.root`/`fleet.repo` path is missing or not a Git working tree | `UNKNOWN` | Entry skipped, rest of the fleet still audited; correct or remove the entry |

## What the tiers depend on

Two dependencies change what these tiers can prove. Neither is a defect, and neither is visible from
a single report, so they are stated here rather than left to be rediscovered.

**Merge strategy.** `local-ancestry-only` tests whether a branch tip is an ancestor of the
remote-tracking default branch. A squash merge rewrites the branch's commits into one new commit, so
the original tip is not an ancestor and the predicate is near-inert on a squash-merging fleet —
observed holding for 27 of 506 branches on one such fleet. Related consequences of the same cause:
`git rev-list --count <tip> --not --remotes` reads non-zero for a squashed-and-pruned branch even
though it merged, and `git cherry` is one-directional, since `ALL-UPSTREAM` proves content landed
while `NONE-UPSTREAM` proves nothing when a squash has collapsed N commits so no individual patch-id
survives. On such a fleet the GitHub merged-PR evidence is the load-bearing signal and the `LOW`
ancestry tier adds little.

**`gc.worktreePruneExpire`.** `missing-worktree` (`MEDIUM`) and `prunable-worktree` (`HIGH`) describe
the same physical situation — a registered path that is absent. What separates them is only whether
Git's own expiry window has elapsed and marked the registration prunable, and that window is a
user-tunable config value. The tier difference is therefore a difference in Git's willingness to act,
not a difference in evidence strength.

## Priority rules

1. A protection condition wins over a branch candidate classification.
2. A merged worktree routes through worktree cleanup before branch cleanup.
3. Administrative mismatch wins over ordinary worktree status because the path cannot be trusted.
4. A stronger confidence tier never authorizes mutation inside this plugin.
