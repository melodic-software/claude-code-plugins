# Pre-PR Sequence

Ordered checklist for code changes heading to a pull request. Complete in order; each step gates the
next. Use the consuming repo's own commands and review criteria at each gate.

1. **Test thoroughly** — run all affected tests, smoke test new functionality, verify edge cases.
   No PR without evidence the changes work
2. **Review** — self-review the full diff (`git diff HEAD` catches staged + unstaged) against the
   repo's conventions, or dispatch a fresh-context reviewer. Resolve blocking findings before
   proceeding
3. **Stage surgically** — `git add <path>` for specific files, never `git add -A` or `git add .`
   (risk of including secrets, build artifacts, or unrelated changes)
4. **Simplify** — pass over the changed code for reuse, clarity, and unnecessary complexity
5. **Review the simplify diff** — inspect what changed; approve or revert each edit individually
6. **Re-test after simplify** — cleanup edits can introduce issues; run the tests again
7. **Verify outcome** — confirm the result matches the original intent with evidence (see
   `steps.md` stage 7). Never claim improvement without measurements
8. **Open the PR** — only after steps 1–7 pass

## Reviewing incoming findings (CI + bot review)

- **Research before fixing CI failures** — diagnose the root cause from logs; never guess-fix and
  re-push in a loop
- **Evaluate review comments before acting** — verify each claim against the code; classify
  VALID / INCORRECT / UNCERTAIN with evidence, and fix only the valid ones

## Scope tips

- Docs/config-only changes may skip steps 4–6 when there is no code to simplify
- Keep the PR small and cohesive — split unrelated changes into separate PRs
- **Override boundary.** This sequence — its steps and their order, including the simplify pass
  (4–6) — is fixed plugin identity, not consumer config; there is no seam to reorder it or swap in
  a different checklist by editing the plugin. The fixed part is the skeleton, not the gates: a
  consumer's own commands, review criteria, and any mandatory gates (e.g. security review or
  approval) are still honored — applied at the matching step (the intro above) and independently
  enforced by the consumer's own CI and branch protection, which this advisory map never overrides.
  What has no seam is the sequence structure itself; a consumer whose required ordering genuinely
  differs runs that structure as its own documented workflow, separately from this skill.
