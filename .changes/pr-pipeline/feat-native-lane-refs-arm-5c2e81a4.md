---
bump: minor
---

### Changed

- The `enable-auto-merge` activity arms a lanes App pull request whose issue link the merge gate takes, a plain `Refs: #<n>` issue included, instead of only one whose body opens with `Closes #<issue>`. The link is read with the verdict, through the gate's own rule (`babysit_verify_evidence.py evidence --lane-link`, which runs `babysit_merge_policy._linked_issue`), on the scheduled and hand-started runs only: two or more `Refs:` issues, a `Refs:` line in any other form, a number that is no issue, two closing issues, a closing issue in another repository, and a failed read all leave the pull request unarmed, or disarm it. An event run reads no link, so it never disarms on one.
