---
bump: minor
---

### Added

- `block-unresolved-pr-merge` now refuses a merge, auto-merge or merge-queue request of a pull request that pr-verify judges until a PASS or PASS-NOTES verdict exists at the PR's head commit. It reads the verdict the way `/source-control:pull-request merge` does, with the same artifact names. A repository without `.github/workflows/pr-verify.yml` on its base branch, a fork or non-default-base PR, a dependency-manager bot's PR, and an author `merge.verify-authors` does not cover are never held. A failed read fails open with a notice.
- `block-unresolved-pr-merge` now refuses removing the `pr-verify-failed` label through `gh pr edit` or `gh issue edit --remove-label`, a REST `DELETE issues/{n}/labels/pr-verify-failed`, or a GraphQL `removeLabelsFromLabelable` whose label ids name it. Only a PASS verdict at a newer head clears that label.
- Both new checks follow `block_unresolved_pr_merge_enabled`.
