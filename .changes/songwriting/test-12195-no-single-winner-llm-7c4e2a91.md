---
bump: patch
---

### Changed

- The three menu cases' `no-single-winner` grader is now LLM-judged in place of a regex: a reply passes when it leaves the choice to the writer and fails on a lone pick, with or without its option number.
- The two rhyme menu cases' `eight-plus-candidates` grader is now LLM-judged in place of a regex: it counts distinct candidates however they are laid out (list lines, table rows with several per row, or inline), not lines or rows, and does not count a candidate named only to rule it out.
- `tier-labels-span` and `mosaic-entry` in `rh-window-menu-no-winner`, and `identity-flagged` in `rh-release-identity-menu` and `dg-audit-identity-rhyme`, are now LLM-judged in place of regexes, so a tier, a multi-word candidate or an identity verdict counts in any wording ("drops the d", "same vowels, different consonants", "two-word rhyme", "both are **identities**"). Their samples add the replies from the measured runs.
