# Linters

- A pull request that bumps a linter or formatter version, adds a rule, or changes its
  configuration fixes every finding it raises across the whole tree, so the default branch stays
  clean when it merges. A finding it cannot fix gets a suppression with its reason, in the same PR.
- When a rule's findings are too many to fix in one reviewable PR, baseline the rule instead: add
  its count of existing violations as a ceiling with `/toolchain:ratchet`. A rule with a ceiling
  entry is a **baselined rule**: CI fails it only when its count rises, and every other rule fails
  on any violation. The ceiling file is the one record of which rules are baselined; this page
  keeps no list of them.
- A baselined rule's old violations go down three ways, all allowed at once: a whole-tree fix PR
  at any time, the pre-commit hook making whoever touches a file fix that file, and the fix-one
  loop (a `toolchain` skill named `fix-baseline`, built when the first rule is baselined). Each PR
  that lowers the count lowers the ceiling to match; at zero, **clearing the baseline** deletes
  the rule's ceiling entry.
- The fix-one loop never edits a file an open pull request changes, labels each PR it opens so the
  next run sees it, and stops while 5 of its PRs are open.
