# /pull-request Checklist

Copy into your project's working-notes location (or track inline). Tick each box as the corresponding action completes.

## Lifecycle

- [ ] Phase 0: Parse action + detect state — live `gh pr view` lookup, branch check, route to appropriate phase
- [ ] Phase 1: Prep — review (agents/skill when available); verify findings; simplify; run the project's build+test+lint gate
- [ ] Phase 2: Create — branch-name conformance check; `git push -u`; `gh pr create` with `Closes #N` if the branch carries an issue number
- [ ] Phase 3: Monitor — push channel (when available) OR Monitor watch fallback; CI watch + comment response loop; research before any fix
- [ ] Phase 3.5: Comments — evaluate/respond to PR comments only (sub-phase of monitor)
- [ ] Phase 4: Merge — `gh pr merge --squash --delete-branch`; worktree cleanup; verify

## Skip criteria

- Phase 1 sub-steps may use `prep quick` / `prep review-only` / `prep simplify-only` variants for partial coverage
- Phase 3.5 SKIPPED when no review comments received
- Phase 4 NEVER skipped (merge + cleanup non-negotiable)

## Non-negotiable gates

1. Finding verification before user presentation (Phase 1)
2. Research-gated CI fixes (Phase 3) — no fix without researched multi-source consensus

## How to use

Copy + tick + survive `/clear`.
