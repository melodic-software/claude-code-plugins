---
bump: patch
---

### Changed

- The songwriting eval suite is ready for the next measured pass. `mp-chorus-stress-count` / `raw-count-not-balance` is now an LLM-judged grader that reads any wording saying the raw 8/9/9/8 count is not the measure of balance, in place of a regex that failed such replies. The rhyme case's `no-single-winner` no longer flags a "How I'd choose:" guide keyed to feelings. Three new slash-invoked cases bring diagnose, meter-prosody and rhyme to two cases each: `dg-audit-identity-rhyme`, `mp-sung-line-template` and `rh-release-identity-menu`.
