# Linters

- A pull request that bumps a linter or formatter version, or changes its configuration, also fixes
  every finding the new version or configuration raises across the whole tree, so the default
  branch stays clean when it merges. A finding the PR cannot fix gets a suppression with its reason,
  in the same PR; never a follow-up lint-fix PR.
