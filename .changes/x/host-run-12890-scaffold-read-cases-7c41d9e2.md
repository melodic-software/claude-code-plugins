---
bump: patch
---

### Changed

- Four read eval cases now scaffold the condition they test (a bot-challenge body behind a 200, a 4.4 MB article past the read budget, an article longer than one Read slice, and a missing `curl`) and grade it deterministically; two cases that other scaffolded cases already cover are removed ([#12890](https://github.com/melodic-software/claude-code-plugins/issues/12890)).
