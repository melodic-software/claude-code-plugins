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
| `merged-protected-branch` | Same merged-PR/tip evidence as `merged-local-branch`, but the branch is attached to the main worktree or is the canonical checkout's current branch (the default branch never reaches this classification — it is excluded from merge-evidence collection) | `HIGH` | Informational only; protected branches are never branch-cleanup candidates. `HIGH` is the evidence tier, not a cleanup signal — the disposition carries the protection. Reported so exact-OID merge evidence is never computed and then silently discarded: absent this kind, a protected branch's strongest evidence produced no finding while the weaker `merged-pr-tip-drift` still emitted, so silence read as "nothing merged" |
| `merged-pr-tip-drift` | GitHub merged PR exists, but local tip differs from every returned `headRefOid` | `MEDIUM` | Manual review; never delete from this evidence |
| `merged-remote-branch` | GitHub `MERGED` PR for this repository + branch and `headRefOid` equals the last-fetched remote-tracking tip, **and** `git ls-remote --heads` confirms the same tip still exists on the remote (so `delete_branch_on_merge` was not enabled or was blocked). When ls-remote fails, the same cached match is reported at `MEDIUM` as an unverified local remote-tracking observation. Empty ls-remote (head already deleted upstream) emits no finding. | `HIGH` when ls-remote confirms; `MEDIUM` when ls-remote fails | Optional `git push --delete --dry-run` preview handoff; separate from local cleanup. Enabling GitHub `delete_branch_on_merge` is complementary (stops the class accruing), not a substitute for this finding — never changed by this audit |
| `local-ancestry-only` | Local tip is an ancestor of the remote-tracking default branch, with no matching GitHub merged PR evidence | `LOW` | Informational only |
| `prunable-worktree` | Git porcelain marks the registration `prunable` | `HIGH` | Candidate dry-run handoff; no inline prune |
| `missing-worktree` | Registered path is absent but Git has not marked it prunable under its current expiry policy | `MEDIUM` | Manual review/dry-run handoff |
| `locked-worktree` | Git porcelain marks a non-main registration locked | `HIGH` | Manual review of the lock reason before cleanup |
| `worktree-admin-mismatch` | Registered directory exists and resolves to a different common Git directory, or cannot resolve as the registered repository | `HIGH` | Manual admin-directory decision; never automatic repair/removal |
| `worktree-not-a-root` | Registered path exists but `git rev-parse --show-prefix` is non-empty, so it is a subdirectory of a work tree rather than its root — `git -C` answers for the CONTAINING repository at exit 0, which is indistinguishable from a healthy clean worktree | `HIGH` | Manual review; never read a `git -C` probe of the path as this worktree's own state |
| `worktree-root-unverifiable` | `git rev-parse --show-prefix` failed at the registered path, so root-ness is unproven | `UNKNOWN` | Stop worktree classification for that registration; do not infer either way |
| `worktree-nested-in-repository` | A non-main registration's root is inside the canonical checkout's own working tree, rather than at an external root outside every repository | `MEDIUM` | Manual placement decision; never auto-move or auto-remove |
| `worktree-outside-configured-root` | A linked worktree is outside the configured worktree root (`melodic.worktreeroot` or source-control `worktree_root`); evidence names the expected `<root>/<owner>-<repo>-<slug>` location and the config origin | `MEDIUM` | Manual placement decision; never auto-move |
| `worktree-wrong-layout` | A linked worktree is under the configured root but not at the expected `<owner>-<repo>-<slug>` (or `<repo>-<slug>` without origin) path; create-shaped basenames stay conforming after branch rename/detach | `MEDIUM` | Manual placement decision; never auto-move |
| `worktree-tool-owned` | A linked worktree sits under a Codex (`~/.codex/worktrees`) or Cursor (`~/.cursor/worktrees`) tool-owned root; exempt from misplaced-fleet classification | `LOW` | Informational; leave to the owning tool or migrate deliberately |
| `worktree-root-conformance` | Per-repository rollup of conforming / outside-or-wrong-layout / tool-owned linked worktree counts against the configured root | `LOW` | Informational rollup; per-worktree findings carry expected paths |
| `worktree-root-conformance-summary` | Fleet-wide rollup of the same counts; emitted even when every linked worktree conforms so the headline is never missing | `LOW` | Fleet migration signal toward the configured root |
| `worktree-root-unconfigured` | No `melodic.worktreeroot` and no source-control `worktree_root`; linked worktree placement is listed without asserting a convention | `LOW` | Descriptive only; configure a root then rerun for conformance |
| `worktree-root-pluginconfigs-unreadable` | `melodic.worktreeroot` unset and the source-control `pluginConfigs` fallback could not be read because `jq` is missing from PATH | `UNKNOWN` | Do not treat as unconfigured; install `jq` or set `melodic.worktreeroot` |
| `worktree-status-handoff` | One or more linked, unlocked registrations with reliable admin exist; disposability is owned by `/source-control:worktree status` (stranded / unknown / safe), not by fleet `git status` | `MEDIUM` | Delegate stranded-work classification; never treat porcelain emptiness as reclaimable; cleanup `--dry-run` only after Work is safe |
| `worktree-placement-unverifiable` | A non-bare canonical checkout gave no working-tree root, so no registration under it could be placement-checked. A BARE hub is not this finding — it has no working tree for a worktree to be nested inside, so the check is legitimately skipped rather than unanswered | `UNKNOWN` | Do not infer that this repository's worktrees are correctly placed |
| `bare-repo-with-working-tree` | `core.bare=true` coincides with populated working-tree content and/or registered linked worktrees, so the path is a Git repository but not a work tree | `MEDIUM` | Manual review only; prefer `git config --local core.bare false` (linked worktrees are unaffected); never auto-rewrite |
| `github-remote-moved` | GitHub REST resolves the requested `owner/repo` to a different canonical `full_name`. Branch and worktree analysis continues against the resolved identity; this finding does not stop local classification | `HIGH` | Human-reviewed remote update; local classification is not deferred |
| `duplicate-checkout` | Two or more distinct checkouts resolve to one normalized GitHub identity | `LOW` | Informational only; same-identity clones legitimately diverge |
| `canonical-override-invalid` | An override target has a missing, ambiguous, credential-only, or non-`github.com` remote | `UNKNOWN` | Stop that repository; never combine evidence |
| `canonical-identity-unverified` | An override target's GitHub identity could not be resolved for comparison against the discovered one | `UNKNOWN` | Stop that repository; never combine evidence |
| `canonical-identity-conflict` | An override target resolves to a different GitHub identity than the discovered checkout | `UNKNOWN` | Stop that repository; never combine evidence |
| `github-identity-unavailable` | `GET /repos/{owner}/{repo}` returned 404/403, failed, or timed out | `UNKNOWN`, demoted to `ACKNOWLEDGED` when the identity is listed in `fleet.ackUnavailable` and the failure was 404/403 | Investigate; never infer "deleted" or "moved" |
| `github-pr-evidence-unavailable` | The repository-scoped merged-PR query failed | `UNKNOWN` | Do not infer branch merge state |
| `worktree-inventory-unavailable` | `git worktree list --porcelain -z` failed | `UNKNOWN` | Stop local branch/worktree classification for that repository |
| `worktree-common-dir-unavailable` | A registered worktree path exists but its `--git-common-dir` could not be resolved | `UNKNOWN` | Manual inspection; the registration cannot be trusted either way |
| `branch-inventory-unavailable` | `git for-each-ref` over `refs/heads/` failed or emitted malformed/partial output | `UNKNOWN` | Discard partial records, stop branch classification, exclude from the audited count |
| `remote-branch-inventory-unavailable` | `git for-each-ref` over `refs/remotes/<remote>/` failed | `UNKNOWN` | Remote-tracking tip comparison for `merged-pr-tip-drift` is unavailable; GraphQL merge evidence still runs |
| `current-branch-unavailable` | `git branch --show-current` failed, so branch-protection membership is unknown | `UNKNOWN` | Emit no standalone branch cleanup candidate for that repository |
| `git-common-dir-unavailable` | The canonical checkout's own `--git-common-dir` could not be resolved | `UNKNOWN` | Stop that repository; registration comparison is impossible |
| `local-ancestry-unavailable` | `git merge-base --is-ancestor` failed with an error status | `UNKNOWN` | Do not infer local ancestry |
| `stale-config-entry` | A config-sourced `fleet.root`/`fleet.repo` path is missing or not a Git working tree | `UNKNOWN` | Entry skipped, rest of the fleet still audited; correct or remove the entry |
| `discovery-skip` | A path discovered under `--root` is unreadable or not a Git working tree despite a `.git` marker | `UNKNOWN` | Path skipped, rest of the fleet still audited; inspect unexpected `.git` markers |

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
3. `merged-remote-branch` is independent of local attachment: it describes the remote ref.
4. Administrative mismatch wins over ordinary worktree status because the path cannot be trusted.
5. A stronger confidence tier never authorizes mutation inside this plugin.

## Presentation rollup

Default report output aggregates per repository (kind counts + verdict). Detail mode collapses
multiple findings that share a target into one entry. Across the fleet action plan, branch skill
invocations are listed before worktree skill invocations so an approved batch never prunes a
worktree before the branch that still anchors its reflog. The machine-readable action plan is the
interchange format for fleet-scale handoff (#2608, #2609).
