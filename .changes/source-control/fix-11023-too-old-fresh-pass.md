---
bump: patch
---

### Fixed

- The pr-merge verdict reader no longer refuses an old pull request (`verify:too-old`) when every counted PASS at its head comes from a pr-verify run created after the pull request turned too old: that fresh judgment clears the refusal, and the other verdict rules then decide. It clears it only while the pull request is younger than a FAIL's 90-day retention less two days (`judged_until`), since past that its first FAILs may have expired ([#11023](https://github.com/melodic-software/claude-code-plugins/issues/11023)).
