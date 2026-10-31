---
bump: patch
---

### Fixed

- `charge-words.json` stops counting a measured pass run on the subscription as a charge: that
  phrase is model usage, which its description already said is no charge. A real use such as a
  subscription upgrade still matches.
- A backslash-escaped backtick no longer opens a code span in the `code` pattern, so a word between
  escaped backticks counts as prose and `rule-admit.sh` refuses it.

### Changed

- `charge-words.json` gains `work_headings`, the section headings intake admission reads as stating
  work. Its `description` records that `rule-admit.sh` still reads the whole title and body.
