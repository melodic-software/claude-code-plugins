---
bump: patch
---

### Fixed

- At the address-feedback round cap, a finding from a review bot listed in
  `review-threads.reviewer-ids` (such as `chatgpt-codex-connector[bot]`) is a bot finding: it goes
  to the fresh fixer round instead of a person. It still goes to a person when a trusted person
  directed it, or when the security-review lane held its head as `CRITICAL`.
- A security-review finding rated `IMPORTANT` at the round cap is a code fix first: it gets the
  fresh fixer round, and goes to a person only when that round was given it and left it open. A
  `CRITICAL` or unrated security finding still goes to a person at once.
- The fresh fixer round's thread file carries a fixed `retry.brief` (fix each finding in code;
  never weaken a test or check to close one), which the read runner adds to the skill's preamble.
