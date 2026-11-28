---
bump: patch
---

### Changed

- Trimmed frontmatter `description` fields across both `wizard` skills to cut ambient listing budget by 454 chars (`1,119 -> 665`, `-40.6%`; `generate` `513 -> 315`, `unattended` `606 -> 350`) while preserving agent-never-executes / human-launches boundaries, `cutover.result/1` JSON output contract, triggers, exclusions, and full `listing-overlap` trigger-rate parity (`generate` validation FP shifts `0.00 -> 0.25`, 1 of 4 held-out negatives, due to trimming sibling competitor `unattended` `606 -> 350`).
