---
bump: patch
---

### Fixed

- The pr-merge verifier evidence gate clears a verifier FAIL at an earlier head of the same change, such as a head the branch later only merged main into, when a pass at the current head was created after a trusted person edited the pull request body or changed its linked issues. These are the trust conditions a FAIL's own head already applies. Before this fix, such a FAIL kept `verify:earlier-fail`, because the verifier never runs again at the FAILed head. A FAIL with no such edit, with an untrusted edit, or with no counted pass after the edit still reports `verify:earlier-fail` ([#16367](https://github.com/melodic-software/claude-code-plugins/issues/16367)).
