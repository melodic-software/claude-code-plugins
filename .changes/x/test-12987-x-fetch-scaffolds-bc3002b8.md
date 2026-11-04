---
bump: patch
---

### Changed

- Twelve read eval cases whose graders judge a fetched body, a status or an attribution now scaffold the converter responses they judge, and their prompts say the fetch already ran, so a run no longer scores a fetch the eval sandbox blocked; the two hostile spool-path cases scaffold a spool directory whose name holds `$user`, a backtick and an apostrophe. All fourteen are tagged `no-network` ([#12987](https://github.com/melodic-software/claude-code-plugins/issues/12987)).
