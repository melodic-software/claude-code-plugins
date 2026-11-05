---
bump: minor
---

### Changed

- The interview's emoji anchors are now on by default: `use_emoji_question_markers` defaults to `true`, so each round question leads with ❓ and its recommendation with ➡️ in the terminal and on the page ([#6233](https://github.com/melodic-software/claude-code-plugins/issues/6233)). Set the option to `false` for plain text; a user instruction against emoji still wins, and the ledger, register and Brief stay plain. On the page, `round.sh ensure-running --emoji-markers` now reads only `false`, `0`, `no` and `off` as off, so an empty value or an unexpanded `user_config` token means on; a new data dir records `true`, and a `questions.json` without `meta.emojiMarkers` shows the anchors.
