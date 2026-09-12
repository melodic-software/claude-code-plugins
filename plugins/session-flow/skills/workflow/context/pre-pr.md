# Pre-PR Sequence

Ordered checklist for code changes heading to a pull request. Complete in order; each step gates the
next. Use the consuming repo's own commands and review criteria at each gate.

The **order** below is owned by the marketplace's `pre-pr-ordering` convention, not by this file.
More than one plugin routes into this sequence, so the order lives where every routing surface can
cite the same one. This file owns what each step *does*. When this repo's
`docs/conventions/pre-pr-ordering/README.md` is available, it is the authority on the ordering and
on why outcome verification sits after the simplify pass.

1. **Test thoroughly.** Run all affected tests, smoke test new functionality, verify edge cases.
   No PR without evidence the changes work
2. **Review.** Self-review the full diff (`git diff HEAD` catches staged + unstaged) against the
   repo's conventions, or dispatch a fresh-context reviewer. Resolve blocking findings before
   proceeding
3. **Stage surgically.** `git add <path>` for specific files, never `git add -A` or `git add .`
   (risk of including secrets, build artifacts, or unrelated changes)
4. **Simplify.** Pass over the changed code for reuse, clarity, and unnecessary complexity
5. **Review the simplify diff.** Inspect what changed; approve or revert each edit individually
6. **Re-test after simplify.** Cleanup edits can introduce issues; run the tests again
7. **Verify outcome.** Confirm the result matches the original intent with evidence (see
   `steps.md` stage 7). Never claim improvement without measurements
8. **Open the PR**, only after steps 1–7 pass

## Reviewing incoming findings (CI + bot review)

- **Research before fixing CI failures.** Diagnose the root cause from logs; never guess-fix and
  re-push in a loop
- **Evaluate review comments before acting.** Verify each claim against the code; classify
  VALID / INCORRECT / UNCERTAIN with evidence, and fix only the valid ones

## Scope tips

- Docs/config-only changes may skip steps 4–6 when there is no code to simplify
- Keep the PR small and cohesive. Split unrelated changes into separate PRs
- **Override boundary.** This sequence, its steps and their order, including the simplify pass
  (4–6), is not consumer config; the plugin exposes no setting that reorders it or swaps in a
  different checklist. The order is **fleet identity rather than this plugin's identity**: it is
  owned by the `pre-pr-ordering` convention, which binds every plugin that routes into this
  sequence, so a sibling plugin prescribing a different order at a handoff is a defect against that
  convention rather than a permitted local variation. The fixed part is the skeleton, not the gates: a
  consumer's own commands, review criteria, and any mandatory gates (e.g. security review or
  approval) are still honored, applied at the matching step (the intro above) and independently
  enforced by the consumer's own CI and branch protection, which this advisory map never overrides.
  What is not configurable is the sequence structure itself. A consumer whose required ordering
  genuinely differs runs that structure as its own documented workflow, separately from this skill.
