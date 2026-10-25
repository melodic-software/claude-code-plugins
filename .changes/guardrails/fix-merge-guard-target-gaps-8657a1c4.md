---
bump: patch
---

### Fixed

- `block-unresolved-pr-merge` closes four target-resolution gaps (#8657). A quote-split `gh pr mer"ge" 5` is parsed, and a `gh pr` subcommand or a `-X` method taken from a variable on a merge route is blocked as unresolvable. A `gh pr merge` with no `-R` is blocked when the command runs `cd`, `pushd` or `popd` or names `GH_REPO`. A `-R HOST/OWNER/REPO` is read without its host, and a 404 on a repo the command wrote is blocked instead of run unchecked. A branch name is percent-encoded into the pulls `head=` query (`plugins/guardrails/hooks/block-unresolved-pr-merge.sh`).
