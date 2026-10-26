---
bump: minor
---

### Changed

- `use_emoji_question_markers` now defaults to `true`: an interview round leads each `Q<N>:` line with ❓ and each `My recommendation:` line with ➡️, in the terminal and on the page, unless the option is set to `false` or the user asks for no emoji. Saved files (ledger, register, Brief) stay plain. `--emoji-markers` records false only for `false`, `0`, `no` or `off` (any case); any other value, an empty or unexpanded token included, records true, and a new file records true. The interview eval graders that find the first question accept a ❓ before `Q1`.
