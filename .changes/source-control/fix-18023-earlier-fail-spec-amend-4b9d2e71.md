---
bump: patch
---

### Fixed

- The babysit merge gate clears `verify:earlier-fail` for a pass at a head of the same change when a trusted person recorded an owner decision on a linked issue after the FAIL's run and before the pass's run was created: a new spec comment, or an issue body edit, that links an owner-decisions row and quotes the owner after `verbatim:`. A FAIL against a done-when item the owner later amended no longer blocks the pull request forever. An amendment without that link, an untrusted edit or comment, a pass judged before the amendment, and any failed read keep the refusal ([#18023](https://github.com/melodic-software/claude-code-plugins/pull/18023)).
