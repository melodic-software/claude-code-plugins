# Linters

- A pull request that bumps a linter or formatter version, adds a rule, or changes its
  configuration fixes every finding it raises across the whole tree, so the default branch stays
  clean when it merges. A finding it cannot fix gets a suppression with its reason, in the same PR.
- When a new rule's findings are too many to fix in one reviewable PR, the PR follows
  [`/toolchain:ratchet`'s lint rollout rule](../../plugins/toolchain/skills/ratchet/SKILL.md#2-the-lint-rollout-rule)
  instead, which makes it a **baselined rule**. Its baseline is the record that it is one; this page
  keeps no list.
- A baselined rule's violations are fixed by any PR, in any file, and each fix lowers the baseline
  to match. At zero, clear the baseline.
- The PR that baselines the first rule also builds `/toolchain:fix-baseline`, a loop that fixes a
  baselined rule's violations one PR at a time. It never edits a file an open pull request changes,
  labels each PR it opens so the next run sees it, and stops while 5 of its PRs are open.
