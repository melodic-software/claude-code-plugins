---
bump: patch
---

### Changed

- Trimmed frontmatter `description` fields across 5 `user-interface` skills to cut ambient listing budget by 1,077 chars (`2,647 -> 1,570`, `-40.7%`; `audit` `615 -> 342`, `design` `976 -> 416`, `glossary` `418 -> 340`, `setup` `191 -> 144`, `write-css` `447 -> 328`; `write-animation` unchanged at `342`) while keeping `disable-model-invocation: true` trigger-free on `setup` and retaining action, safety, and neighbor-exclusion boundaries; accepts lexical `listing-overlap` recall drops on `audit` (`0.625/0.80 -> 0.25/0.60`, train FP `0.20 -> 0.00`) and `design` (`0.737/0.80 -> 0.474/0.40`, FP `0.417/0.333 -> 0.167/0.00`) under the shorter listing cap while `glossary` holds parity and `write-css` gains on both splits.
