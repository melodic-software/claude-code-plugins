---
bump: patch
---

### Fixed

- The babysit merge gate clears `verify:earlier-fail` for a pass at a head of the same change when a trusted person amended a linked issue's spec (a body edit or a new spec comment) after the FAIL's run and before the pass's run was created, so a FAIL against a done-when item that was later amended no longer blocks the pull request forever. Untrusted edits or comments, a pass judged before the amendment, and any failed read keep the refusal ([#18023](https://github.com/melodic-software/claude-code-plugins/pull/18023)).
